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
docker compose --profile test up -d --build
docker compose exec ansible ansible-inventory -i inventory/test-hosts.ini --graph
docker compose exec ansible ansible-playbook -i inventory/test-hosts.ini playbooks/site.yml --check --diff --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/test-hosts.ini playbooks/site.yml --vault-password-file .vault_pass
```

Der Test-Zielhost heißt `targetpi` und ist im Compose-Netz nur intern erreichbar. SSH läuft mit dem vorhandenen Ansible-Key.

## SSH-Key im Container

Der private Key wird nach `/root/.ssh/id_ed25519` gemountet und in `ansible.cfg` als Standard-Key eingetragen.

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
docker compose exec ansible ansible -i inventory/hosts.ini -i inventory/wsl.local.ini ssh_clients -m ansible.builtin.ping
docker compose exec ansible ansible-playbook -i inventory/hosts.ini -i inventory/wsl.local.ini playbooks/ssh_clients.yml --syntax-check
docker compose exec ansible ansible-playbook -i inventory/hosts.ini -i inventory/wsl.local.ini playbooks/ssh_clients.yml --check --diff --vault-password-file .vault_pass
```

Danach kannst du die Konfiguration ausrollen. Ein unmittelbar anschließender zweiter Lauf muss `changed=0` melden:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini -i inventory/wsl.local.ini playbooks/ssh_clients.yml --vault-password-file .vault_pass
```

