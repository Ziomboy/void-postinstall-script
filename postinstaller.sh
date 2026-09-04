#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "==> Elevating to root..."
  exec sudo bash "$0" "$@"
fi

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  TARGET_USER="$SUDO_USER"
elif [ -n "${USER:-}" ] && [ "$USER" != "root" ]; then
  TARGET_USER="$USER"
else
  TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd || true)
fi

if [ -z "${TARGET_USER:-}" ]; then
  TARGET_USER="root"
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
echo "==> Target user: $TARGET_USER ($TARGET_HOME)"

if [ "$TARGET_USER" != "root" ]; then
  echo "==> Adding $TARGET_USER to system groups..."
  usermod -aG wheel,audio,video,input,network "$TARGET_USER" || true
fi

echo "==> 1. Updating XBPS package manager..."
xbps-install -S -u -y xbps

echo "==> 2. Installing multilib and nonfree repositories..."
xbps-install -y void-repo-multilib void-repo-nonfree

echo "==> 3. Synchronizing repositories and performing system update..."
xbps-install -S -u -y

echo "==> 4. Installing packages..."
PACKAGES=(
  # AMD Graphics & 32-bit Gaming
  mesa mesa-dri mesa-vaapi mesa-vulkan-radeon xf86-video-amdgpu
  mesa-32bit mesa-dri-32bit mesa-vulkan-radeon-32bit
  libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit
  vulkan-loader vulkan-loader-32bit linux-firmware-amd
  
  # Audio (PipeWire + WirePlumber + 32-bit ALSA bridge)
  pipewire wireplumber libjack-pipewire libjack-pipewire-32bit
  alsa-pipewire alsa-pipewire-32bit alsa-plugins alsa-utils alsa-firmware sof-firmware
  bluez libspa-bluetooth
  
  # Desktop & Plasma
  kde-plasma sddm elogind NetworkManager
  dolphin kate breeze-icons hicolor-icon-theme
  xdg-user-dirs xdg-utils
  
  # Utilities & Applications
  alacritty firefox flatpak zramen mono steam linux-mainline nano fastfetch
)

xbps-install -y "${PACKAGES[@]}"

echo "==> 5. Configuring SDDM for Wayland..."
mkdir -p /etc/sddm.conf.d
cat << 'EOF' > /etc/sddm.conf.d/10-wayland.conf
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
MinimumVT=1

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF

echo "==> 6. Configuring Alacritty dimensions..."
ALACRITTY_DIR="$TARGET_HOME/.config/alacritty"
mkdir -p "$ALACRITTY_DIR"
cat << 'EOF' > "$ALACRITTY_DIR/alacritty.toml"
[window]
dimensions = { columns = 119, lines = 31 }
EOF
chown -R "$TARGET_USER:" "$ALACRITTY_DIR"

echo "==> 7. Disabling dhcpcd and wpa_supplicant services..."
rm -f /var/service/dhcpcd /var/service/wpa_supplicant

echo "==> 8. Configuring PipeWire audio stack..."
rm -rf /etc/pipewire/pipewire.conf.d

mkdir -p /etc/alsa/conf.d
ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d/

AUTOSTART_DIR="/etc/xdg/autostart"
mkdir -p "$AUTOSTART_DIR"

cat << 'EOF' > "$AUTOSTART_DIR/pipewire.desktop"
[Desktop Entry]
Type=Application
Name=PipeWire
Exec=pipewire
Terminal=false
NoDisplay=true
X-KDE-autostart-phase=1
EOF

cat << 'EOF' > "$AUTOSTART_DIR/pipewire-pulse.desktop"
[Desktop Entry]
Type=Application
Name=PipeWire PulseAudio Emulation
Exec=pipewire-pulse
Terminal=false
NoDisplay=true
X-KDE-autostart-phase=1
EOF

cat << 'EOF' > "$AUTOSTART_DIR/wireplumber.desktop"
[Desktop Entry]
Type=Application
Name=WirePlumber Session Manager
Exec=wireplumber
Terminal=false
NoDisplay=true
X-KDE-autostart-phase=1
EOF

echo "==> 9. Enabling Flathub repository system-wide..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "==> 10. Appending noatime to /etc/fstab..."
sed -i -E '/\s+(ext4|btrfs|xfs|zfs|f2fs)\s+/ { /noatime/! s/(\s+)(defaults|rw)/\1\2,noatime/ }' /etc/fstab

echo "==> 11. Adding mitigations=off to GRUB and reconfiguring system..."
if [ -f /etc/default/grub ]; then
  if grep -q "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub; then
    if ! grep -q "mitigations=off" /etc/default/grub; then
      sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)/\1 mitigations=off/' /etc/default/grub
    fi
  fi
fi

xbps-reconfigure -fa

echo "==> 12. Enabling runit services..."
SERVICES=(dbus sddm zramen NetworkManager bluetoothd)
for svc in "${SERVICES[@]}"; do
  if [ -d "/etc/sv/$svc" ]; then
    ln -sf "/etc/sv/$svc" /var/service/
  fi
done

# Ensure everything in the target user's home folder belongs to the user
if [ "$TARGET_USER" != "root" ]; then
  echo "==> Fixing home directory ownership for $TARGET_USER..."
  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME"
fi

echo "==> Setup complete! Rebooting in 5 seconds (Press Ctrl+C to cancel)..."
sleep 5
reboot
