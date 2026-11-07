#!/usr/bin/env bash
# Shared file manifest for pacman packaging and the standalone installer.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $# == 1 && $1 == /* ]] || { echo 'Usage: install-files.sh ABSOLUTE_DESTDIR' >&2; exit 1; }
destination=${1%/}
assets=$destination/usr/share/nier/plugins/nier.monitor-arrangement
[[ -x $root/build/nier-monitor-arrangement-backend ]] || { echo 'Build the backend before installing files.' >&2; exit 1; }
install -d "$assets/i18n" "$destination/usr/bin"
for file in shell.qml Editor.qml Theme.qml Strings.qml; do install -m644 "$root/qml/$file" "$assets/"; done
install -m644 "$root"/qml/i18n/*.json "$assets/i18n/"
install -Dm644 "$root/hypr/runtime.lua" "$destination/usr/local/nier/share/hypr/monitor-arrangement-runtime.lua"
install -Dm755 "$root/build/nier-monitor-arrangement-backend" "$destination/usr/share/nier/bin/nier-monitor-arrangement-backend"
install -Dm755 "$root/bin/nier-monitor-arrangement" "$destination/usr/share/nier/bin/nier-monitor-arrangement"
install -Dm755 "$root/bin/enable-hyprland" "$destination/usr/share/nier/bin/nier-monitor-arrangement-enable"
ln -sfn /usr/share/nier/bin/nier-monitor-arrangement "$destination/usr/bin/nier-monitor-arrangement"
ln -sfn /usr/share/nier/bin/nier-monitor-arrangement-enable "$destination/usr/bin/nier-monitor-arrangement-enable"
install -Dm644 "$root/packaging/nier-monitor-arrangement.svg" "$assets/nier-monitor-arrangement.svg"
install -d "$destination/usr/share/icons/hicolor/scalable/apps"
ln -sfn /usr/share/nier/plugins/nier.monitor-arrangement/nier-monitor-arrangement.svg \
  "$destination/usr/share/icons/hicolor/scalable/apps/nier-monitor-arrangement.svg"
install -Dm644 "$root/packaging/nier-monitor-arrangement.desktop" "$destination/usr/share/applications/nier-monitor-arrangement.desktop"
install -Dm644 "$root/LICENSE" "$destination/usr/share/licenses/nier-monitor-arrangement/LICENSE"
install -Dm644 "$root/README.md" "$destination/usr/share/doc/nier-monitor-arrangement/README.md"
