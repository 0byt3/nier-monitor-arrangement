# Monitor arrangement editor

- Standalone Quickshell/QML GUI; Go handles monitor discovery, identity, validation,
  persistence and application. Bash handles launchers and packaging.
- Store profiles in ~/.config/hypr/monitor-arrangement.lua as a returned table.
  Keys are sorted, colon-separated escaped serial identities, falling back to
  model names and using connector names to break identity ties.
- Keep identity/matching in the Go backend; runtime.lua invokes the same backend
  on Hyprland events so GUI and runtime cannot disagree.
- Never execute shell text derived from monitor metadata. Use argument arrays,
  escape generated Lua strings, and show dynamic QML text as Text.PlainText.
- Save atomically, preserve other profiles, reject overlapping layouts and stale
  GUI snapshots, and back up changed profiles. Do not mutate live desktop config
  from tests. Tests use temporary HOME/runtime directories and fake hyprctl.
- Install read-only assets under /usr/share/nier/plugins/nier.monitor-arrangement,
  binaries under /usr/share/nier/bin, with standard-location command symlinks.
- Run go test -race ./..., go vet ./..., Bash syntax, Lua syntax, package build,
  offscreen GUI smoke tests and git diff --check before delivering changes.
