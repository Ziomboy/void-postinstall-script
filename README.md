Void post-install script that:
Installs KDE
Installs SDDM
Installs MESA (+ Radeon Stuff)
Installs few apps and utilities
Installs flatpak (and flathub repo)
Enables zram via zramen
Configures audio and everything
Adds noatime and mitigations=off to fstab and grub config
Swaps dhcpcd and wpa_supplicant with NetworkManager

Run with:
curl -fsSL https://raw.githubusercontent.com/Ziomboy/void-postinstall-script/refs/heads/main/postinstaller.sh | sudo bash

(before that xbps-install -u xbps and xbps-install -S curl might be needed)
