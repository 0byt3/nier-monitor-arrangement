package arrangement

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

type App struct{ Path, StateDir, Hyprctl, Lua string }

var ErrDisplaysAsleep = errors.New("layout queued until the displays wake")

type Result struct {
	Pending  bool      `json:"pending,omitempty"`
	OK       bool      `json:"ok"`
	Saved    bool      `json:"saved"`
	Applied  bool      `json:"applied"`
	Key      string    `json:"key,omitempty"`
	Source   string    `json:"source,omitempty"`
	Backup   string    `json:"backup,omitempty"`
	Error    string    `json:"error,omitempty"`
	Snapshot *Snapshot `json:"snapshot,omitempty"`
}

func Default() (App, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return App{}, err
	}
	state := os.Getenv("XDG_RUNTIME_DIR")
	if state == "" {
		state, err = os.UserCacheDir()
		if err != nil {
			return App{}, err
		}
	}
	path := os.Getenv("NIER_MONITOR_ARRANGEMENT_FILE")
	if path == "" {
		path = filepath.Join(home, ".config/hypr/monitor-arrangement.lua")
	}
	return App{Path: path, StateDir: filepath.Join(state, "nier-monitor-arrangement"), Hyprctl: "hyprctl", Lua: "lua"}, nil
}

func (a App) command(ctx context.Context, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, a.Hyprctl, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("hyprctl %s failed: %s (%w)", args[0], strings.TrimSpace(string(output)), err)
	}
	if len(output) > 4*1024*1024 {
		return nil, errors.New("Hyprland returned too much data")
	}
	return output, nil
}

func (a App) Monitors(ctx context.Context) ([]Monitor, error) {
	output, err := a.command(ctx, "monitors", "-j")
	if err != nil {
		return nil, err
	}
	var raw []Monitor
	if err = json.Unmarshal(output, &raw); err != nil {
		return nil, fmt.Errorf("invalid monitor response: %w", err)
	}
	return Prepare(raw)
}

func (a App) Snapshot(ctx context.Context) (Snapshot, error) {
	monitors, err := a.Monitors(ctx)
	if err != nil {
		return Snapshot{}, err
	}
	profiles, revision, err := ReadProfiles(ctx, a.Path, a.Lua)
	if err != nil {
		return Snapshot{}, err
	}
	key := Key(monitors)
	_, saved := profiles[key]
	return Snapshot{Primary: PrimaryName(monitors, profiles[key]), Monitors: monitors, Key: key, Fingerprint: Fingerprint(monitors), Revision: revision, Saved: saved, Path: a.Path, Profiles: len(profiles), Arrangement: profiles[key]}, nil
}

func (a App) lock() (func(), error) {
	if err := os.MkdirAll(a.StateDir, 0700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(filepath.Join(a.StateDir, "apply.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return func() { syscall.Flock(int(f.Fd()), syscall.LOCK_UN); f.Close() }, nil
}

func (a App) apply(ctx context.Context, monitors []Monitor, profile Profile) error {
	if err := Validate(monitors, profile); err != nil {
		return err
	}
	var code strings.Builder
	primary := PrimaryName(monitors, profile)
	if primary == "" {
		code.WriteString("NIER_PRIMARY_MONITOR=nil;")
	} else {
		fmt.Fprintf(&code, "NIER_PRIMARY_MONITOR=%s;", LuaQuote(primary))
	}
	geometryChanged := false
	for _, m := range monitors {
		p := profile[m.Identity]
		if m.X != p.X || m.Y != p.Y {
			geometryChanged = true
			fmt.Fprintf(&code, "hl.monitor({output=%s,position=%s});", LuaQuote(m.Name), LuaQuote(fmt.Sprintf("%dx%d", p.X, p.Y)))
		}
	}
	output, err := a.command(ctx, "eval", code.String())
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(output)) != "ok" {
		return fmt.Errorf("Hyprland rejected the layout: %s", strings.TrimSpace(string(output)))
	}
	// The Lua global is updated even when all screen positions are already current.
	if !geometryChanged {
		return nil
	}
	allAsleep := len(monitors) > 0
	for _, m := range monitors {
		if m.DPMSStatus == nil || *m.DPMSStatus {
			allAsleep = false
			break
		}
	}
	if allAsleep {
		return ErrDisplaysAsleep
	}
	// hyprctl eval acknowledges execution before the scheduled monitor refresh.
	// Check the actual geometry rather than accepting a syntactically valid rule.
	for attempt := 0; attempt < 12; attempt++ {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
		current, err := a.Monitors(ctx)
		if err != nil {
			return err
		}
		if Fingerprint(current) != Fingerprint(monitors) {
			return errors.New("the monitor set or settings changed while applying the arrangement")
		}
		matched := true
		for _, m := range current {
			p := profile[m.Identity]
			if m.X != p.X || m.Y != p.Y {
				matched = false
				break
			}
		}
		if matched {
			return nil
		}
	}
	return errors.New("Hyprland did not apply the requested positions; another monitor rule or service may be overriding them")
}

func (a App) Save(ctx context.Context, req SaveRequest) Result {
	unlock, err := a.lock()
	if err != nil {
		return Result{Error: err.Error()}
	}
	defer unlock()
	monitors, err := a.Monitors(ctx)
	if err != nil {
		return Result{Error: err.Error()}
	}
	profile, err := FromRequest(monitors, req)
	if err != nil {
		return Result{Error: err.Error()}
	}
	profiles, revision, err := ReadProfiles(ctx, a.Path, a.Lua)
	if err != nil {
		return Result{Error: err.Error()}
	}
	if revision != req.Revision {
		return Result{Error: "the arrangement file changed in another editor; reload before saving"}
	}
	if len(profiles) >= 256 {
		if _, exists := profiles[Key(monitors)]; !exists {
			return Result{Error: "the arrangement file already contains 256 profiles"}
		}
	}
	profiles[Key(monitors)] = profile
	backup, err := WriteProfiles(a.Path, profiles)
	if err != nil {
		return Result{Error: err.Error()}
	}
	result := Result{Saved: true, Key: Key(monitors), Backup: backup, Source: "profile"}
	if err = a.apply(ctx, monitors, profile); errors.Is(err, ErrDisplaysAsleep) {
		result.OK = true
		result.Pending = true
		return result
	} else if err != nil {
		result.Error = "Saved, but could not apply: " + err.Error()
		return result
	}
	snapshot, err := a.Snapshot(ctx)
	if err != nil {
		result.Error = "Saved and applied, but could not refresh: " + err.Error()
		result.Applied = true
		return result
	}
	result.OK = true
	result.Applied = true
	result.Snapshot = &snapshot
	return result
}

func (a App) fallback(monitors []Monitor) (Profile, error) {
	path := filepath.Join(a.StateDir, "discovery.json")
	var previous []string
	if raw, err := os.ReadFile(path); err == nil {
		if len(raw) > 65536 {
			return nil, errors.New("discovery state is too large")
		}
		if err = json.Unmarshal(raw, &previous); err != nil {
			return nil, err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	active := map[string]Monitor{}
	for _, m := range monitors {
		active[m.Identity] = m
	}
	order := []string{}
	seen := map[string]bool{}
	for _, id := range previous {
		if m, ok := active[id]; ok && m.Name != "eDP-1" && !seen[id] {
			order = append(order, id)
			seen[id] = true
		}
	}
	for _, m := range monitors {
		if m.Name != "eDP-1" && !seen[m.Identity] {
			order = append(order, m.Identity)
			seen[m.Identity] = true
		}
	}
	data, _ := json.Marshal(order)
	if err := AtomicWrite(path, data); err != nil {
		return nil, err
	}
	profile := Profile{}
	x := 0
	for _, id := range order {
		profile[id] = Position{X: x, Y: 0}
		x += active[id].LogicalWidth
	}
	for _, m := range monitors {
		if m.Name == "eDP-1" {
			profile[m.Identity] = Position{X: x, Y: 0}
		}
	}
	return profile, nil
}

func (a App) Apply(ctx context.Context) Result {
	unlock, err := a.lock()
	if err != nil {
		return Result{Error: err.Error()}
	}
	defer unlock()
	monitors, err := a.Monitors(ctx)
	if err != nil {
		return Result{Error: err.Error()}
	}
	profiles, _, err := ReadProfiles(ctx, a.Path, a.Lua)
	if err != nil {
		return Result{Error: err.Error()}
	}
	key := Key(monitors)
	// Keep discovery state current even when this set has a saved profile.
	fallback, err := a.fallback(monitors)
	if err != nil {
		return Result{Error: err.Error()}
	}
	profile, exists := profiles[key]
	source := "profile"
	if !exists {
		profile = fallback
		source = "automatic"
	}
	if err = a.apply(ctx, monitors, profile); errors.Is(err, ErrDisplaysAsleep) {
		return Result{OK: true, Pending: true, Key: key, Source: source}
	} else if err != nil {
		return Result{Error: err.Error(), Key: key, Source: source}
	}
	return Result{OK: true, Applied: true, Key: key, Source: source}
}
