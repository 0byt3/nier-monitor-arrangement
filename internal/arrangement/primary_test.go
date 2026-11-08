package arrangement

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func evaluatePrimary(t *testing.T, code []byte, name string) {
	t.Helper()
	expected := "nil"
	if name != "" {
		expected = LuaQuote(name)
	}
	script := "NIER_PRIMARY_MONITOR='stale';hl={monitor=function() end};" + string(code) + ";assert(NIER_PRIMARY_MONITOR==" + expected + ")"
	output, err := exec.Command("lua", "-E", "-e", script).CombinedOutput()
	if err != nil {
		t.Fatalf("Lua global was incorrect: %s (%v)", output, err)
	}
}

func currentRequest(snapshot Snapshot, primary string) SaveRequest {
	req := SaveRequest{Fingerprint: snapshot.Fingerprint, Revision: snapshot.Revision, Primary: primary}
	for _, m := range snapshot.Monitors {
		req.Monitors = append(req.Monitors, Placement{Name: m.Name, X: m.X, Y: m.Y})
	}
	return req
}

func TestPrimarySelectionAndConnectorRename(t *testing.T) {
	m := prepared(t, sample())
	req := SaveRequest{Fingerprint: Fingerprint(m), Primary: "DP-6", Monitors: []Placement{{Name: "eDP-1", X: 3072, Y: 0}, {Name: "DP-6", X: 0, Y: 0}}}
	profile, err := FromRequest(m, req)
	if err != nil || !profile["EXTERNAL"].Primary || profile["LAPTOP"].Primary {
		t.Fatal(profile, err)
	}
	if PrimaryName(m, profile) != "DP-6" {
		t.Fatal("primary is not the connector name")
	}
	m[1].Name = "HDMI-A-9"
	if PrimaryName(m, profile) != "HDMI-A-9" {
		t.Fatal("primary did not follow the stable identity")
	}
	req.Primary = "not-connected"
	if _, err = FromRequest(m, req); err == nil {
		t.Fatal("accepted a disconnected primary monitor")
	}
	profile["LAPTOP"] = Position{X: 3072, Y: 0, Primary: true}
	if Validate(m, profile) == nil {
		t.Fatal("accepted two primary monitors")
	}
}

func TestLegacyProfilesAndPrimaryPersistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "arrangement.lua")
	legacy := `return { ["EXTERNAL:LAPTOP"] = { EXTERNAL={x=0,y=0}, LAPTOP={x=3072,y=0} } }`
	if err := os.WriteFile(path, []byte(legacy), 0600); err != nil {
		t.Fatal(err)
	}
	profiles, _, err := ReadProfiles(context.Background(), path, "lua")
	if err != nil || PrimaryName(prepared(t, sample()), profiles["EXTERNAL:LAPTOP"]) != "" {
		t.Fatal(profiles, err)
	}
	p := profiles["EXTERNAL:LAPTOP"]["EXTERNAL"]
	p.Primary = true
	profiles["EXTERNAL:LAPTOP"]["EXTERNAL"] = p
	backup, err := WriteProfiles(path, profiles)
	if err != nil || backup == "" {
		t.Fatal(backup, err)
	}
	loaded, _, err := ReadProfiles(context.Background(), path, "lua")
	if err != nil || !loaded["EXTERNAL:LAPTOP"]["EXTERNAL"].Primary {
		t.Fatal(loaded, err)
	}
	p = profiles["EXTERNAL:LAPTOP"]["LAPTOP"]
	p.Primary = true
	profiles["EXTERNAL:LAPTOP"]["LAPTOP"] = p
	if err = os.WriteFile(path, EncodeProfiles(profiles), 0600); err != nil {
		t.Fatal(err)
	}
	if _, _, err = ReadProfiles(context.Background(), path, "lua"); err == nil {
		t.Fatal("accepted two saved primary flags")
	}
}

func TestPrimaryOnlySaveUpdatesGlobalWithoutMovingScreens(t *testing.T) {
	a, _, dir := fixture(t)
	ctx := context.Background()
	snapshot, err := a.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	result := a.Save(ctx, currentRequest(snapshot, "DP-6"))
	if !result.OK || !result.Applied || result.Snapshot == nil || result.Snapshot.Primary != "DP-6" {
		t.Fatal(result)
	}
	code, err := os.ReadFile(filepath.Join(dir, "last-eval"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(code), "hl.monitor") {
		t.Fatal("a metadata-only change moved monitors")
	}
	evaluatePrimary(t, code, "DP-6")
	snapshot, err = a.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	result = a.Save(ctx, currentRequest(snapshot, ""))
	if !result.OK || result.Snapshot.Primary != "" {
		t.Fatal(result)
	}
	code, _ = os.ReadFile(filepath.Join(dir, "last-eval"))
	evaluatePrimary(t, code, "")
}

func TestPrimaryGlobalIsSafelyQuoted(t *testing.T) {
	a, raw, dir := fixture(t)
	name := "DP-6\";error('injected')--"
	raw[1].Name = name
	data, _ := json.Marshal(raw)
	os.WriteFile(filepath.Join(dir, "monitors.json"), data, 0600)
	snapshot, err := a.Snapshot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	result := a.Save(context.Background(), currentRequest(snapshot, name))
	if !result.OK {
		t.Fatal(result)
	}
	code, _ := os.ReadFile(filepath.Join(dir, "last-eval"))
	evaluatePrimary(t, code, name)
}

func TestDisconnectClearsPrimaryGlobal(t *testing.T) {
	a, raw, dir := fixture(t)
	ctx := context.Background()
	snapshot, err := a.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	result := a.Save(ctx, currentRequest(snapshot, "DP-6"))
	if !result.OK {
		t.Fatal(result)
	}
	raw = raw[:1]
	// The remaining laptop is already at its automatic origin, so only metadata changes.
	data, _ := json.Marshal(raw)
	os.WriteFile(filepath.Join(dir, "monitors.json"), data, 0600)
	result = a.Apply(ctx)
	if !result.OK || result.Source != "automatic" {
		t.Fatal(result)
	}
	code, _ := os.ReadFile(filepath.Join(dir, "last-eval"))
	evaluatePrimary(t, code, "")
}

func TestRuntimeClearsGlobalDuringTopologyChanges(t *testing.T) {
	path, err := filepath.Abs("../../hypr/runtime.lua")
	if err != nil {
		t.Fatal(err)
	}
	script := `local callbacks={};NIER_PRIMARY_MONITOR='stale';hl={on=function(name,fn) callbacks[name]=fn end,timer=function() end};dofile(` + LuaQuote(path) + `);assert(NIER_PRIMARY_MONITOR==nil);NIER_PRIMARY_MONITOR='DP-6';callbacks['monitor.removed']();assert(NIER_PRIMARY_MONITOR==nil);NIER_PRIMARY_MONITOR='DP-6';callbacks['monitor.added']();assert(NIER_PRIMARY_MONITOR==nil)`
	output, err := exec.Command("lua", "-E", "-e", script).CombinedOutput()
	if err != nil {
		t.Fatalf("runtime left a stale primary: %s (%v)", output, err)
	}
}
