# Managed by Ansible (role shell_aliases), local changes are overwritten.
# Shortcuts for the RFFHEM devcontainer and its FHEM SVN working copy.

FHEM_DEV_CONTAINER="${FHEM_DEV_CONTAINER:-devcontainer-fhem-dev-1}"
FHEM_DEV_SVN_DIR="${FHEM_DEV_SVN_DIR:-/workspace/fhem-svn/fhem}"
FHEM_DEV_REPO_DIR="${FHEM_DEV_REPO_DIR:-/workspace/RFFHEM}"

# Run a command in the devcontainer as user dev: _fhem_dev_exec <workdir> <command...>
_fhem_dev_exec() {
  local workdir="$1"
  shift
  local -a tty=(-i)
  [[ -t 0 && -t 1 ]] && tty=(-it)
  docker exec "${tty[@]}" -u dev -w "$workdir" "$FHEM_DEV_CONTAINER" "$@"
}

# svn in the SVN working copy: fsvn status | fsvn update | fsvn commit FILE CHANGED -m "..."
fsvn() {
  _fhem_dev_exec "$FHEM_DEV_SVN_DIR" svn "$@"
}

# Sync module files from RFFHEM into the SVN working copy: fsvn-sync [--dry-run]
fsvn-sync() {
  _fhem_dev_exec "$FHEM_DEV_REPO_DIR" bash .devcontainer/scripts/sync-module-to-svn.sh "$@"
}

# Shell in the SVN working copy, SVN key passphrase is asked only once
fsvn-shell() {
  _fhem_dev_exec "$FHEM_DEV_SVN_DIR" ssh-agent bash -c 'ssh-add ~/.ssh/id_svn_fhem && exec bash -i'
}
