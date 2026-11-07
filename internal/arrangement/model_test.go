package arrangement

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func sample() []Monitor {
	return []Monitor{
		{Name: "eDP-1", Model: "Panel", Serial: "LAPTOP", Width: 1920, Height: 1200, Scale: 1.25},
		{Name: "DP-6", Model: "External", Serial: "EXTERNAL", Width: 3840, Height: 2160, Scale: 1.25, X: 1536},
	}
}
func prepared(t *testing.T, raw []Monitor) []Monitor {
	t.Helper()
	m, e := Prepare(raw)
	if e != nil {
		t.Fatal(e)
	}
	return m
}

func TestIdentityAndGeometry(t *testing.T) {
	raw := sample()
	m := prepared(t, raw)
	if Key(m) != "EXTERNAL:LAPTOP" || m[1].LogicalWidth != 3072 {
		t.Fatal(m, Key(m))
	}
	reversed := []Monitor{raw[1], raw[0]}
	if Key(prepared(t, reversed)) != Key(m) {
		t.Fatal("enumeration changed key")
	}
	raw[1].Name = "HDMI-A-9"
	if Key(prepared(t, raw)) != Key(m) {
		t.Fatal("connector changed unique serial key")
	}
	raw[1].Transform = 1
	rotated := prepared(t, raw)[1]
	if rotated.LogicalWidth != 1728 || rotated.LogicalHeight != 3072 {
		t.Fatal(rotated)
	}
	raw[0].Serial = "unknown"
	raw[1].Serial = ""
	raw[1].Model = "Panel"
	dup := prepared(t, raw)
	if dup[0].Identity != "model=Panel@eDP-1" || dup[1].Identity != "model=Panel@HDMI-A-9" {
		t.Fatal(dup)
	}
	raw[0].Serial = "same"
	raw[1].Serial = "same"
	dup = prepared(t, raw)
	if dup[0].Identity != "same@eDP-1" {
		t.Fatal(dup)
	}
}
func TestKeyDelimitersCannotCollide(t *testing.T) {
	a := sample()
	a[0].Serial = "a:b"
	a[1].Serial = "c"
	b := sample()
	b[0].Serial = "a"
	b[1].Serial = "b:c"
	if Key(prepared(t, a)) == Key(prepared(t, b)) {
		t.Fatal("colliding colon-delimited key")
	}
	a[0].Serial = "model=Panel@DP-1%3A"
	if !strings.Contains(prepared(t, a)[0].Identity, "%3D") {
		t.Fatal("serial can impersonate fallback identity")
	}
}
func TestValidateAndStaleRequests(t *testing.T) {
	m := prepared(t, sample())
	p := Profile{"EXTERNAL": {0, -400}, "LAPTOP": {3072, 0}}
	if e := Validate(m, p); e != nil {
		t.Fatal(e)
	}
	p["LAPTOP"] = Position{3000, 0}
	if Validate(m, p) == nil {
		t.Fatal("accepted overlap")
	}
	p["LAPTOP"] = Position{65537, 0}
	if Validate(m, p) == nil {
		t.Fatal("accepted out-of-bounds coordinate")
	}
	req := SaveRequest{Fingerprint: Fingerprint(m), Monitors: []Placement{{"eDP-1", 3072, 0}, {"DP-6", 0, -400}}}
	if _, e := FromRequest(m, req); e != nil {
		t.Fatal(e)
	}
	changed := append([]Monitor{}, m...)
	changed[0].Scale = 2
	if _, e := FromRequest(changed, req); e == nil {
		t.Fatal("accepted stale scale")
	}
	req.Monitors[1].Name = "eDP-1"
	if _, e := FromRequest(m, req); e == nil {
		t.Fatal("accepted duplicate connector")
	}
}
func TestStoreRoundtripAndSandbox(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "monitor-arrangement.lua")
	key := "a\"\\\n<script>雪"
	profiles := Profiles{key: {key: Position{-15, 42}}}
	if _, e := WriteProfiles(path, profiles); e != nil {
		t.Fatal(e)
	}
	loaded, revision, e := ReadProfiles(context.Background(), path, "lua")
	if e != nil {
		t.Fatal(e)
	}
	if revision == "" || loaded[key][key] != profiles[key][key] {
		t.Fatal(loaded, revision)
	}
	profiles["second"] = Profile{"monitor": Position{0, 0}}
	backup, e := WriteProfiles(path, profiles)
	if e != nil || backup == "" {
		t.Fatal(backup, e)
	}
	old, _, e := ReadProfiles(context.Background(), backup, "lua")
	if e != nil || len(old) != 1 {
		t.Fatal(old, e)
	}
	for _, bad := range []string{`return os.execute("touch nope")`, `while true do end`, `return {a={b={x="invalid",y=0}}}`, `return {a={b={x=0/0,y=0}}}`} {
		if e = os.WriteFile(path, []byte(bad), 0600); e != nil {
			t.Fatal(e)
		}
		if _, _, e = ReadProfiles(context.Background(), path, "lua"); e == nil {
			t.Fatalf("accepted %s", bad)
		}
	}
}
func fixture(t *testing.T) (App, []Monitor, string) {
	t.Helper()
	dir := t.TempDir()
	raw := sample()
	data, _ := json.Marshal(raw)
	if e := os.WriteFile(filepath.Join(dir, "monitors.json"), data, 0600); e != nil {
		t.Fatal(e)
	}
	ctl := filepath.Join(dir, "hyprctl")
	script := `#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname "$0")"
if [[ $1 == monitors ]]; then cat monitors.json
elif [[ $1 == eval ]]; then
 printf '%s' "$2" > last-eval
 if [[ -e next.json ]]; then cp next.json monitors.json; fi
 printf 'ok\n'
else exit 1; fi
`
	if e := os.WriteFile(ctl, []byte(script), 0700); e != nil {
		t.Fatal(e)
	}
	app := App{Path: filepath.Join(dir, "config/monitor-arrangement.lua"), StateDir: filepath.Join(dir, "state"), Hyprctl: ctl, Lua: "lua"}
	return app, raw, dir
}
func TestSaveAndApplyProfiles(t *testing.T) {
	a, raw, dir := fixture(t)
	ctx := context.Background()
	snapshot, e := a.Snapshot(ctx)
	if e != nil {
		t.Fatal(e)
	}
	raw[0].X = 3072
	raw[1].X = 0
	raw[1].Y = -400
	next, _ := json.Marshal(raw)
	os.WriteFile(filepath.Join(dir, "next.json"), next, 0600)
	req := SaveRequest{Fingerprint: snapshot.Fingerprint, Revision: snapshot.Revision, Monitors: []Placement{{"eDP-1", 3072, 0}, {"DP-6", 0, -400}}}
	result := a.Save(ctx, req)
	if !result.OK || !result.Saved || !result.Applied {
		t.Fatal(result)
	}
	profile, _, e := ReadProfiles(ctx, a.Path, "lua")
	if e != nil || profile[snapshot.Key]["EXTERNAL"].Y != -400 {
		t.Fatal(profile, e)
	}
	result = a.Apply(ctx)
	if !result.OK || result.Source != "profile" {
		t.Fatal(result)
	}
	// A stale GUI may not overwrite the now-saved file.
	result = a.Save(ctx, req)
	if result.OK || !strings.Contains(result.Error, "another editor") {
		t.Fatal(result)
	}
	// A different connected set must preserve the previous profile.
	raw = raw[:1]
	next, _ = json.Marshal(raw)
	os.WriteFile(filepath.Join(dir, "monitors.json"), next, 0600)
	snapshot, e = a.Snapshot(ctx)
	if e != nil {
		t.Fatal(e)
	}
	os.WriteFile(filepath.Join(dir, "next.json"), next, 0600)
	req = SaveRequest{Fingerprint: snapshot.Fingerprint, Revision: snapshot.Revision, Monitors: []Placement{{"eDP-1", 3072, 0}}}
	result = a.Save(ctx, req)
	if !result.OK || result.Backup == "" {
		t.Fatal(result)
	}
	profile, _, e = ReadProfiles(ctx, a.Path, "lua")
	if e != nil || len(profile) != 2 {
		t.Fatal(profile, e)
	}
}
func TestFallbackAndReconnection(t *testing.T) {
	a, raw, _ := fixture(t)
	m := prepared(t, raw)
	profile, e := a.fallback(m)
	if e != nil {
		t.Fatal(e)
	}
	if profile["EXTERNAL"].X != 0 || profile["LAPTOP"].X != 3072 {
		t.Fatal(profile)
	}
	raw = append(raw, Monitor{Name: "DP-7", Model: "Another", Serial: "THIRD", Width: 1920, Height: 1080, Scale: 1})
	m = prepared(t, raw)
	p, e := a.fallback(m)
	if e != nil || p["THIRD"].X != 3072 || p["LAPTOP"].X != 4992 {
		t.Fatal(p, e)
	}
	// Reverse enumeration: already-discovered monitors keep their order.
	m = []Monitor{m[2], m[0], m[1]}
	p, e = a.fallback(m)
	if e != nil || p["THIRD"].X != 3072 {
		t.Fatal(p, e)
	}
}
func TestApplyFailureDoesNotPretendToSucceed(t *testing.T) {
	a, _, _ := fixture(t)
	snapshot, e := a.Snapshot(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	req := SaveRequest{Fingerprint: snapshot.Fingerprint, Monitors: []Placement{{"eDP-1", 3072, 0}, {"DP-6", 0, 0}}}
	result := a.Save(context.Background(), req)
	if result.OK || !result.Saved || result.Applied || !strings.Contains(result.Error, "did not apply") {
		t.Fatal(result)
	}
}

func TestSleepingDisplaysQueueWithoutFalseSuccess(t *testing.T) {
	a, raw, dir := fixture(t)
	asleep := false
	for i := range raw {
		raw[i].DPMSStatus = &asleep
	}
	data, _ := json.Marshal(raw)
	os.WriteFile(filepath.Join(dir, "monitors.json"), data, 0600)
	snapshot, err := a.Snapshot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	req := SaveRequest{Fingerprint: snapshot.Fingerprint, Monitors: []Placement{{"eDP-1", 3072, 0}, {"DP-6", 0, -200}}}
	result := a.Save(context.Background(), req)
	if !result.OK || !result.Saved || !result.Pending || result.Applied {
		t.Fatal(result)
	}
	result = a.Apply(context.Background())
	if !result.OK || !result.Pending || result.Source != "profile" {
		t.Fatal(result)
	}
}
