# Legacy `ua-netinst/raspberrypi-ua-netinst`

This directory is reference material only now. It documents the old `ua-netinst/raspberrypi-ua-netinst` installer layout and should not be treated as the active source of truth for provisioning changes.

## What it used to cover

- Unattended Raspberry Pi OS installation via `installer-config.txt`.
- Base system setup such as hostname, user, password, network settings, timezone, locale, keyboard layout, and package selection.
- Boot-time customization through `config/boot/custom_config.txt` and the bundled installer initramfs.
- Target-system file injection via `config/files/*.list` and `config/files/`.
- Post-install chroot customization in `config/chroot_config.sh`.
- Optional Docker enablement when a USB-backed `/media/usb1/opt/docker` tree was present.
- Local mount and service tweaks, including CIFS mounting, iptables restoration, serial console changes, unattended-upgrades, and `ser2net`.
- Homematic UART adapter preparation by cloning and building `hmcfgusb`.
- Recovery/reinstall boot assets under `reinstall/`.

## Migration note

Any current work should use the active Ansible-managed provisioning paths in this repository, not the legacy `ua-netinst` tree. Keep this directory untouched unless you are only reading it for historical context.
