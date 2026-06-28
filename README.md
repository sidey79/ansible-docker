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

