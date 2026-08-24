# ansible-docker

Ansible-Workspace, der in einem Docker-Container läuft.

## Inhalt

- `Dockerfile`: baut ein Image mit `ansible-core` und `openssh-client`
- `docker-compose.yml`: startet den Container und bindet den SSH-Key ein
- `keys/ansible_ed25519`: privater Key, lokal genutzt, nicht in Git
- `keys/ansible_ed25519.pub`: öffentlicher Key
- `inventory/hosts.ini`: Zielsysteme
- `playbooks/site.yml`: Beispiel-Playbook

## Erster Start

1. SSH-Key erzeugen:

```bash
ssh-keygen -t ed25519 -f keys/ansible_ed25519 -N ""
```

2. Container bauen und starten:

```bash
docker compose up -d --build
```

3. Ansible ausführen:

```bash
docker compose exec ansible ansible --version
docker compose exec ansible ansible-playbook playbooks/site.yml
```

## Ausrollen auf pi3

Mit dem produktiven Inventory auf `pi3` ausrollen:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/site.yml --limit pi3 --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/site.yml --check --diff --limit pi3 --vault-password-file .vault_pass
```

Der erste Befehl führt die Änderungen wirklich aus, der zweite zeigt nur den geplanten Diff. Die Datei `.vault_pass` bleibt lokal und ist in `.gitignore` eingetragen.

## Audit vor dem Upgrade

Vor einem OS-Upgrade kannst du den Ist-Zustand mit dem Audit-Playbook prüfen:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/audit.yml --check --diff --limit pi3 --vault-password-file .vault_pass
```

Das Playbook schreibt keine Änderungen und zeigt die Abweichungen der verwalteten Konfigurationen.

## Zielhost-Container testen

Für einen rudimentären Test gibt es einen zweiten Container mit SSH und Samba. Damit kannst du Login, CIFS-Mount und `ser2net` gegen einen echten Zielhost im Compose-Netz prüfen.

```bash
docker compose -f docker-compose.yml -f docker-compose.test.yml --profile test up -d --build
docker compose -f docker-compose.yml -f docker-compose.test.yml exec ansible ansible-inventory -i inventory/test-hosts.ini --graph
docker compose -f docker-compose.yml -f docker-compose.test.yml exec ansible ansible-playbook -i inventory/test-hosts.ini playbooks/site.yml --check --diff --vault-password-file .vault_pass
docker compose -f docker-compose.yml -f docker-compose.test.yml exec ansible ansible-playbook -i inventory/test-hosts.ini playbooks/site.yml --vault-password-file .vault_pass
```

Der Test-Zielhost heißt `targetpi`. Der Test-Override veröffentlicht SSH auf `127.0.0.1:2224`, damit der Ansible-Container im Host-Netzwerk ihn erreicht. SSH läuft mit dem vorhandenen Ansible-Key.

## SSH-Key im Container

Der private Key wird nach `/root/.ssh/id_ed25519` gemountet und in `ansible.cfg` als Standard-Key eingetragen.

## Öffentliche SSH-Schlüssel auf Zielsystemen

Die öffentlichen Schlüssel `keys/s26.pub` und `keys/bienchen.pub` werden mit
`playbooks/ssh_authorized_keys.yml` auf den Benutzer `pi` von `pi3` sowie auf
den Benutzer `sven` von `zeus` und `thor` sowie für `root` von `sf8008` installiert. `svnfhem` ist kein Ziel
dieses Playbooks.

Vorschau und Ausführung:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/ssh_authorized_keys.yml --syntax-check --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/ssh_authorized_keys.yml --check --diff --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/ssh_authorized_keys.yml --vault-password-file .vault_pass
```

### sf8008 vorbereiten

Wenn der Receiver ausgeschaltet ist, muss er vor dem SSH-Zugriff per Wake-on-LAN aufgeweckt werden. Der Ansible-Container verwendet dafür das Host-Netzwerk:

```bash
docker compose exec ansible ansible localhost -c local \
    -m community.general.wakeonlan \
    -a 'mac=D0:27:24:00:D0:45 broadcast=192.168.1.255'

docker compose exec ansible ansible localhost -c local \
    -m ansible.builtin.wait_for \
    -a 'host=sf8008 port=22 timeout=120 sleep=5'
```

`192.168.1.255` muss bei Bedarf durch die Broadcast-Adresse des lokalen Netzwerks ersetzt werden.

`sf8008` wird als `root` verwaltet. Die vorhandenen öffentlichen Schlüssel sowie der öffentliche Schlüssel des Ansible-Containers werden ebenfalls für `root` installiert. Das Root-Passwort wird als SHA-512-Hash in `inventory/host_vars/sf8008/vault.yml` hinterlegt und darf nicht im Klartext ins Repository gelangen:

```bash
cp inventory/host_vars/sf8008/vault.yml.example inventory/host_vars/sf8008/vault.yml
docker compose exec ansible ansible localhost -m ansible.builtin.debug \
  -a 'msg={{ "MEIN_PASSWORT" | password_hash("sha512") }}'
docker compose exec ansible ansible-vault encrypt inventory/host_vars/sf8008/vault.yml \
  --vault-password-file .vault_pass
```

Den ausgegebenen Hash trägst du anstelle des Platzhalters in `vault.yml` ein, bevor du verschlüsselst. Für den ersten Lauf muss Root bereits per SSH-Key, Konsole oder einem temporären Zugang erreichbar sein, da auf dem ausgelieferten Gerät noch kein Passwort zur SSH-Anmeldung existiert:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini \
  playbooks/ssh_authorized_keys.yml --limit sf8008 \
  --check --diff --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini \
  playbooks/ssh_authorized_keys.yml --limit sf8008 \
  --vault-password-file .vault_pass
```

## SSH-Client in WSL verwalten

Voraussetzung ist ein bereits laufender SSH-Server in WSL. Windows muss einen stabilen Port an diesen Server weiterleiten; die Weiterleitung selbst wird nicht durch dieses Repository verwaltet.

Lege zuerst das lokale, nicht versionierte Inventory an und ersetze den Beispiel-Hostnamen durch den DNS-Namen deines Windows-Rechners:

```bash
cp inventory/wsl.example.ini inventory/wsl.local.ini
```

Die Vorgabe verwendet den Inventory-Namen `wsl`, den WSL-Benutzer `sven` und den weitergeleiteten Port `2222`.

SSH-Profile werden in `inventory/host_vars/wsl/main.yml` definiert:

```yaml
ssh_client_hosts:
  - host: example
    hostname: server.example.org
    user: remote-user
    port: 22
    identity_file: ~/.ssh/id_example
    identities_only: true
    options:
      ServerAliveInterval: 60

ssh_client_private_keys:
  - name: id_example
    content: "{{ vault_ssh_client_private_keys.example_key }}"
```

Private Schlüssel gehören in `inventory/host_vars/wsl/vault.yml` und werden als komplette Datei verschlüsselt:

```yaml
---
vault_ssh_client_private_keys:
  example_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

```bash
docker compose exec ansible ansible-vault encrypt inventory/host_vars/wsl/vault.yml --vault-password-file .vault_pass
```

Die Rolle verändert vorhandene manuelle Host-Einträge nicht. Sie ergänzt am Anfang von `~/.ssh/config` ein Include und verwaltet ausschließlich `~/.ssh/config.d/ansible.conf` sowie explizit deklarierte Schlüssel. Ein Schlüssel wird nur entfernt, wenn sein Eintrag `state: absent` enthält.

Prüfe zuerst die Erreichbarkeit und danach den geplanten Diff:

```bash
docker compose exec ansible ansible -i inventory/hosts.ini -i inventory/wsl.local.ini ssh_clients -m ansible.builtin.ping --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini -i inventory/wsl.local.ini playbooks/ssh_clients.yml --syntax-check
docker compose exec ansible ansible-playbook -i inventory/hosts.ini -i inventory/wsl.local.ini playbooks/ssh_clients.yml --check --diff --vault-password-file .vault_pass
```

Danach kannst du die Konfiguration ausrollen. Ein unmittelbar anschließender zweiter Lauf muss `changed=0` melden:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini -i inventory/wsl.local.ini playbooks/ssh_clients.yml --vault-password-file .vault_pass
```

