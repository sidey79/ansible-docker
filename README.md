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

Der Container läuft als unprivilegierter Benutzer `ansible` (UID/GID 1000), damit Dateien,
die Ansible in das eingebundene Repository schreibt (z. B. via `fetch` importierte Assets),
auf dem Host dem aufrufenden Benutzer gehören und nicht `root`.

Der private Key wird nach `/home/ansible/.ssh/id_ed25519` gemountet und in `ansible.cfg` als Standard-Key eingetragen.

## Öffentliche SSH-Schlüssel auf Zielsystemen

Die öffentlichen Schlüssel `keys/s26.pub` und `keys/bienchen.pub` werden mit
`playbooks/ssh_authorized_keys.yml` auf den Benutzer `pi` von `pi3` sowie auf
den Benutzer `sven` von `zeus` und `thor` sowie für `root` von `sf8008` installiert. `svnfhem` ist kein Ziel
dieses Playbooks.

Vorschau und Ausführung:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/ssh_authorized_keys.yml --limit 'ssh_key_targets:!sf8008' --syntax-check --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/ssh_authorized_keys.yml --limit 'ssh_key_targets:!sf8008' --check --diff --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/ssh_authorized_keys.yml --limit 'ssh_key_targets:!sf8008' --vault-password-file .vault_pass
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
read -r -s -p "sf8008 root password: " SF8008_ROOT_PASSWORD
printf "\n"
printf "%s\n" "$SF8008_ROOT_PASSWORD" | docker compose exec -T ansible python -c "import sys; from passlib.hash import sha512_crypt; print(sha512_crypt.hash(sys.stdin.read().rstrip(chr(10))))"
unset SF8008_ROOT_PASSWORD
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


## AppArmor-Profile auf zeus

Ubuntu 24.04 schränkt unprivilegierte User-Namespaces ein
(`kernel.apparmor_restrict_unprivileged_userns = 1`). Dadurch startet
`rootlesskit` und damit rootless Docker nicht. Statt die Einschränkung
systemweit abzuschalten, erlaubt ein AppArmor-Profil genau diesem Binary die
`userns`-Capability.

Die Rolle `apparmor_profiles` rollt Profildateien aus
`roles/apparmor_profiles/files/<host>/` nach `/etc/apparmor.d/` aus. Welche
Profile ein Host bekommt, steht in seinem Manifest, z. B. in
`inventory/host_vars/zeus/apparmor_profiles.yml`:

```yaml
apparmor_profiles:
  - name: usr.local.bin.rootlesskit
```

Der Name ist zugleich der Dateiname im Repository und in `/etc/apparmor.d`.
`owner`, `group` und `mode` sind optional und fallen sonst auf `root`, `root`
und `0644` zurück. Vor dem Schreiben prüft `apparmor_parser --skip-kernel-load
--skip-cache` die Datei, danach lädt ein Handler die Profile per
`systemctl reload apparmor` neu.

`zeus` verlangt für `sudo` ein Passwort, deshalb braucht jeder Lauf
`--ask-become-pass`. Der Prompt funktioniert nur in einem echten Terminal; ohne
TTY liest `getpass` nichts ein und der Lauf scheitert mit
`Missing sudo password`:

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/apparmor.yml --limit zeus --syntax-check
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/apparmor.yml --limit zeus --check --diff --ask-become-pass --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/apparmor.yml --limit zeus --ask-become-pass --vault-password-file .vault_pass
```

Ein unmittelbar anschließender zweiter Lauf muss `changed=0` melden. Das Profil
darf auch installiert werden, bevor `/usr/local/bin/rootlesskit` existiert; es
greift erst, wenn das Binary gestartet wird. Nach einem nachträglichen Wechsel
auf rootless Docker muss der Benutzerdienst einmal neu gestartet werden
(`systemctl --user restart docker`), damit der neue Prozess unter dem Profil
läuft.

## Wöchentliche Compose-Updates auf zeus

Die Rolle `compose_update` legt pro Compose-Projekt eine systemd-Service- und
eine Timer-Unit unter `/etc/systemd/system/` an und aktiviert den Timer. Der
Service ist ein `Type=oneshot` und führt der Reihe nach `git pull --ff-only`
(optional), `docker compose pull` und `docker compose up -d` im Projektordner
aus.

Welche Projekte ein Host bekommt, steht in seinem Manifest, z. B. in
`inventory/host_vars/zeus/compose_update.yml`:

```yaml
compose_update_jobs:
  - name: docker-portainer-cfg
    directory: /home/sven/git_repos/docker-portainer-cfg
    user: sven
    git_pull: true
    on_calendar: "Sat *-*-* 03:00:00"
```

`name`, `directory` und `user` sind Pflicht, die Rolle prüft sie per `assert`
und bricht ab, wenn `directory` auf dem Host kein Verzeichnis ist. `git_pull`,
`on_calendar` und `randomized_delay` fallen sonst auf die Werte in
`roles/compose_update/defaults/main.yml` zurück. Aus `name` entstehen die Units
`compose-update-<name>.service` und `compose-update-<name>.timer`.

Der Job läuft als `sven`. Der Benutzer ist auf zeus in der Gruppe `docker`, der
Service braucht für Docker also kein sudo. `git pull --ff-only` scheitert
absichtlich, wenn im Projektordner lokale Commits oder Änderungen liegen —
dann soll niemand ungefragt darüber hinweggehen.

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/compose_update.yml --limit zeus --syntax-check
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/compose_update.yml --limit zeus --check --diff --ask-become-pass --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/compose_update.yml --limit zeus --ask-become-pass --vault-password-file .vault_pass
```

`--ask-become-pass` braucht ein echtes Terminal. Im `--check`-Lauf wird das
Aktivieren der Timer übersprungen, weil dort keine Unit-Dateien geschrieben
werden und systemd den Timer folglich nicht auflösen kann; der Dry-Run zeigt
also nur den Diff der Units. Nach dem Rollout zeigt
`systemctl list-timers 'compose-update-*'` den nächsten Lauf, ein manueller
Test geht mit `sudo systemctl start compose-update-docker-portainer-cfg.service`
und das Ergebnis steht in
`journalctl -u compose-update-docker-portainer-cfg.service`.

## Täglicher Docker-Aufräumjob auf zeus

Die Rolle `docker_prune` legt `docker-prune.service` und `docker-prune.timer`
unter `/etc/systemd/system/` an und aktiviert den Timer. Der Service ist ein
`Type=oneshot` und räumt der Reihe nach Container, Images, Netzwerke und
Build-Cache auf — jeweils mit `--filter until=96h`, es wird also nichts
angefasst, was in den letzten 96 Stunden noch gebraucht wurde. Volumes bleiben
bewusst außen vor: dort liegen Daten, und Dockers `until`-Filter greift für sie
ohnehin nicht.

Die Einstellungen stehen in `inventory/host_vars/zeus/docker_prune.yml`:

```yaml
docker_prune_until: 96h
docker_prune_on_calendar: "*-*-* 04:00:00"
docker_prune_obsolete_cron_files:
  - /etc/cron.weekly/dockerprune
```

Alles Weitere — Unit-Name, Docker-Binary, Benutzer (`root`), `TimeoutStartSec`
und welche Ressourcentypen überhaupt aufgeräumt werden — kommt aus
`roles/docker_prune/defaults/main.yml`. `TimeoutStartSec` steht auf `30min`,
weil ein großer Prune die systemd-Voreinstellung von 90 Sekunden reißt und dann
mittendrin abgebrochen würde.

Der Job ersetzt den bisherigen Cronjob `/etc/cron.weekly/dockerprune`. Die Rolle
löscht die dort gelistete Datei, aber erst nachdem der Timer aktiv ist, damit
der Host nie ganz ohne Aufräumjob dasteht. Inhaltlich sind das drei
Unterschiede: der Lauf ist täglich statt wöchentlich, `docker image prune -a`
bekommt einen Altersfilter statt jedes ungenutzte Image sofort zu entfernen,
und die Grenze liegt bei 96h statt 72h. Beim Image-Filter zählt Docker das
Erstellungsdatum des Images, nicht den letzten Zugriff — ein frisch gezogenes,
aber altes Image fällt also beim ersten Lauf, sobald es niemand mehr verwendet.

```bash
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/docker_prune.yml --limit zeus --syntax-check
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/docker_prune.yml --limit zeus --check --diff --ask-become-pass --vault-password-file .vault_pass
docker compose exec ansible ansible-playbook -i inventory/hosts.ini playbooks/docker_prune.yml --limit zeus --ask-become-pass --vault-password-file .vault_pass
```

Wie bei `compose_update` überspringt der `--check`-Lauf das Aktivieren des
Timers, weil dort keine Unit-Dateien geschrieben werden. Nach dem Rollout zeigt
`systemctl list-timers docker-prune.timer` den nächsten Lauf, ein manueller Test
geht mit `sudo systemctl start docker-prune.service` und das Ergebnis steht in
`journalctl -u docker-prune.service`.
