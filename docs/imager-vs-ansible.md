# Imager vs Ansible

This repository currently splits provisioning into two phases:

1. Raspberry Pi Imager + the `ua-netinst` bootstrap config establish the base system.
2. Ansible runs afterward and configures the host from the repository.

## Configured In Raspberry Pi Imager

The image-side configuration lives in `ua-netinst/raspberrypi-ua-netinst/config/installer-config.txt` and the related boot/chroot scripts.

It sets up the initial machine state:

- host name: `pi3`
- base user: `pi` with password `raspberry`
- root password: `pi`
- SSH key import: `authorized_keys`
- SSH password login for root: disabled
- network: `eth0` via DHCP
- timezone: `Europe/Berlin`
- keyboard layout: `de`
- locale: `de_DE.UTF-8`
- domain name: `blausee.eu`
- watchdog: enabled
- boot size: `+256M`
- release: `buster`
- NTP server: `de.pool.ntp.org`

It also installs the initial package set listed in `packages=...` and passes the kernel command line in `cmdline=...`.

The installer chroot script then applies host bootstrap changes before Ansible ever runs:

- creates `/media/usb1` and `/mnt/fritznas`
- adds `/mnt/fritznas` and optional `/media/usb1` mounts to `/etc/fstab`
- sets up SMB credentials for the NAS mount
- installs Docker-related tooling when `/media/usb1/opt/docker` exists
- enables the Docker service and links `/opt/docker` to the USB-backed tree
- pulls referenced Docker images during bootstrap
- disables `serial-getty@ttyAMA0.service`
- installs and builds the Homematic UART adapter tools
- enables unattended upgrades by editing `/etc/apt/apt.conf.d/50unattended-upgrades`

## Handled By Ansible Afterwards

The Ansible entrypoint is `playbooks/site.yml`.

It now configures the host from roles and inventory variables:

- `storage_mounts`
- `firewall`
- `ser2net`

`firewall` is rendered from Ansible data instead of being copied from the USB stick. The Pi3 rules live in `inventory/host_vars/pi3.yml`, and the role writes `/etc/iptables/rules.v4` from that data.

`ser2net` is rendered from Ansible data instead of being copied from the USB stick. The Pi3-specific serial endpoints live in `inventory/host_vars/pi3.yml`, and the role writes `/etc/ser2net.yaml` from that data.

The test inventory can omit the host-specific variables; in that case the roles stay disabled and remove their config files.

## Practical Split

Use Raspberry Pi Imager for anything that must exist on first boot or during bootstrap. Use Ansible for post-boot automation once the host is reachable and managed over SSH.
