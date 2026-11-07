#!/usr/bin/env bash
# Build as the invoking user, copy installed assets, then enable their user hook.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
destination=/
enable=true
build=true
reload=true
usage() {
  cat <<'HELP'
Usage: ./install.sh [--skip-build] [--no-enable] [--no-reload] [--destdir DIRECTORY]
  --skip-build  Use an existing build/nier-monitor-arrangement-backend.
  --no-enable   Install files without changing user Hyprland configuration.
  --no-reload   Add the user hook without contacting a running compositor.
  --destdir     Stage files beneath an absolute directory; implies --no-enable.
Run as your desktop user. System file copies use sudo when needed.
HELP
}
while (( $# )); do
  case $1 in
    --skip-build) build=false ;;
    --no-enable) enable=false ;;
    --no-reload) reload=false ;;
    --destdir)
      (( $# >= 2 )) || { usage >&2; exit 1; }
      [[ $2 == /* && $2 != / ]] || { echo '--destdir requires an absolute directory other than /.' >&2; exit 1; }
      destination=$2
      enable=false
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
  shift
done
if [[ $enable == true && $EUID == 0 ]]; then
  echo 'Run as your desktop user, or use --no-enable for a system-only root install.' >&2
  exit 1
fi
if [[ $destination == / ]] && command -v pacman >/dev/null && pacman -Q nier-monitor-arrangement >/dev/null 2>&1; then
  echo 'nier-monitor-arrangement is managed by pacman; update that package instead.' >&2
  exit 1
fi
for program in bash install ln; do command -v "$program" >/dev/null || { echo "Missing required command: $program" >&2; exit 1; }; done
if [[ $destination == / ]]; then
  for program in quickshell hyprctl lua luac; do command -v "$program" >/dev/null || { echo "Missing required command: $program" >&2; exit 1; }; done
fi
if [[ $enable == true ]]; then
  [[ -f $HOME/.config/hypr/monitors.lua && ! -L $HOME/.config/hypr/monitors.lua ]] || { echo 'Expected a regular ~/.config/hypr/monitors.lua; use --no-enable for a file-only install.' >&2; exit 1; }
fi
if [[ $build == true ]]; then bash "$root/bin/build"; fi
[[ -x $root/build/nier-monitor-arrangement-backend ]] || { echo 'No built backend; run bin/build first.' >&2; exit 1; }
if [[ $destination == / && $EUID != 0 ]]; then
  sudo -- bash "$root/packaging/install-files.sh" /
else
  bash "$root/packaging/install-files.sh" "$destination"
fi
if [[ $destination == / ]]; then
  if command -v update-desktop-database >/dev/null; then
    if (( EUID == 0 )); then update-desktop-database /usr/share/applications
    else sudo -- update-desktop-database /usr/share/applications; fi
  fi
  if [[ $enable == true ]]; then
    args=()
    [[ $reload == false ]] && args+=(--no-reload)
    /bin/bash /usr/share/nier/bin/nier-monitor-arrangement-enable "${args[@]}"
  fi
fi
printf 'Installed monitor arrangement files under %s\n' "$destination"
