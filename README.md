Void post-install script that:

1. Installs KDE
2. Installs SDDM
3. Installs MESA (+ Radeon Stuff)
4. Installs few apps and utilities
5. Installs flatpak (and flathub repo)
6. Enables zram via zramen
7. Configures audio and everything
8. Adds noatime and mitigations=off to fstab and grub config
9. Swaps dhcpcd and wpa_supplicant with NetworkManager

Run with:

curl -fsSL https://raw.githubusercontent.com/Ziomboy/void-postinstall-script/refs/heads/main/postinstaller.sh | sudo bash

(before that xbps-install -u xbps and xbps-install -S curl might be needed)
