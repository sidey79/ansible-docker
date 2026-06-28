#!/usr/bin/env bash
set -euo pipefail

PUBLIC_KEY_PATH="${PUBLIC_KEY_PATH:-/tmp/ansible_ed25519.pub}"
SSH_USER="${SSH_USER:-pi}"
SMB_USER="${SMB_USER:-ftpuser}"
SMB_PASSWORD="${SMB_PASSWORD:-xxxxxx}"
SMB_SHARE="${SMB_SHARE:-/srv/fritz.nas}"
BIND_SOURCE="${BIND_SOURCE:-/srv/fritz.nas-source}"

mkdir -p /run/sshd /var/log/samba /etc/sudoers.d "${SMB_SHARE}" "${BIND_SOURCE}"
ssh-keygen -A

if ! getent group "${SSH_USER}" >/dev/null 2>&1; then
    groupadd "${SSH_USER}"
fi

if ! id -u "${SSH_USER}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --gid "${SSH_USER}" "${SSH_USER}"
fi

install -d -m 0700 -o "${SSH_USER}" -g "${SSH_USER}" "/home/${SSH_USER}/.ssh"
if [ -f "${PUBLIC_KEY_PATH}" ]; then
    install -m 0600 -o "${SSH_USER}" -g "${SSH_USER}" "${PUBLIC_KEY_PATH}" "/home/${SSH_USER}/.ssh/authorized_keys"
fi

printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${SSH_USER}" >/etc/sudoers.d/"${SSH_USER}"
chmod 0440 /etc/sudoers.d/"${SSH_USER}"

if ! id -u "${SMB_USER}" >/dev/null 2>&1; then
    useradd --no-create-home --shell /usr/sbin/nologin "${SMB_USER}"
fi

printf '%s\n%s\n' "${SMB_PASSWORD}" "${SMB_PASSWORD}" | smbpasswd -a -s "${SMB_USER}" >/dev/null

cat >/etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   server role = standalone server
   map to guest = Bad User
   logging = file
   log file = /var/log/samba/log.%m
   max log size = 50
   smb ports = 445
   disable netbios = yes
   server min protocol = NT1

[fritz.nas]
   path = ${SMB_SHARE}
   read only = no
   browsable = yes
   guest ok = no
   valid users = ${SMB_USER}
   force user = ${SMB_USER}
EOF

chown -R "${SMB_USER}:${SMB_USER}" "${SMB_SHARE}" || true

/usr/sbin/sshd
smbd -D --no-process-group
exec tail -f /dev/null
