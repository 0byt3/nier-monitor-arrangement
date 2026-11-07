package arrangement

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

//go:embed decode.lua
var decoder string

// LuaQuote emits Lua decimal escapes, not Go's incompatible \u escapes.
func LuaQuote(value string) string {
	var out strings.Builder
	out.WriteByte('"')
	for _, b := range []byte(value) {
		if b == '"' || b == '\\' {
			out.WriteByte('\\')
			out.WriteByte(b)
		} else if b < 32 || b == 127 {
			fmt.Fprintf(&out, "\\%03d", b)
		} else {
			out.WriteByte(b)
		}
	}
	out.WriteByte('"')
	return out.String()
}

func ReadProfiles(ctx context.Context, path, lua string) (Profiles, string, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return Profiles{}, "", nil
	}
	if err != nil {
		return nil, "", err
	}
	if len(data) > 1024*1024 {
		return nil, "", errors.New("the arrangement file exceeds 1 MiB")
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	// The document is passed as data on stdin. The decoder evaluates it with an
	// empty environment and a bounded instruction budget, never with io/os access.
	cmd := exec.CommandContext(ctx, lua, "-E", "-e", "\n"+decoder)
	cmd.Stdin = bytes.NewReader(data)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, "", fmt.Errorf("cannot read %s: %s (%w)", path, strings.TrimSpace(string(output)), err)
	}
	profiles := Profiles{}
	dec := json.NewDecoder(bytes.NewReader(output))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&profiles); err != nil {
		return nil, "", fmt.Errorf("invalid arrangement data: %w", err)
	}
	if profiles == nil || len(profiles) > 256 {
		return nil, "", errors.New("the arrangement file must contain up to 256 profiles")
	}
	for key, profile := range profiles {
		if key == "" || len(key) > 65536 || len(profile) == 0 || len(profile) > MaxMonitors {
			return nil, "", errors.New("invalid profile key or monitor count")
		}
		for id, p := range profile {
			if id == "" || len(id) > 4096 || p.X < -65536 || p.X > 65536 || p.Y < -65536 || p.Y > 65536 {
				return nil, "", errors.New("invalid monitor identity or coordinates in profile")
			}
		}
	}
	return profiles, Digest(data), nil
}

func EncodeProfiles(profiles Profiles) []byte {
	var out strings.Builder
	out.WriteString("-- Managed by Nier Monitor Arrangement. Coordinates are logical pixels.\n-- Keys: sorted serials, with model= fallback and @connector for duplicates.\nreturn {\n")
	keys := make([]string, 0, len(profiles))
	for key := range profiles {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		out.WriteString("  [" + LuaQuote(key) + "] = {\n")
		ids := make([]string, 0, len(profiles[key]))
		for id := range profiles[key] {
			ids = append(ids, id)
		}
		sort.Strings(ids)
		for _, id := range ids {
			p := profiles[key][id]
			fmt.Fprintf(&out, "    [%s] = { x = %s, y = %s },\n", LuaQuote(id), strconv.Itoa(p.X), strconv.Itoa(p.Y))
		}
		out.WriteString("  },\n")
	}
	out.WriteString("}\n")
	return []byte(out.String())
}

func AtomicWrite(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".nier-arrangement-*")
	if err != nil {
		return err
	}
	temp := file.Name()
	defer os.Remove(temp)
	if _, err = file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err = file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	if err = os.Rename(temp, path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func WriteProfiles(path string, profiles Profiles) (string, error) {
	if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("the arrangement file is a symlink; choose a regular file before saving")
	}
	data := EncodeProfiles(profiles)
	if len(data) > 1024*1024 {
		return "", errors.New("the arrangement file would exceed 1 MiB")
	}
	previous, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	if bytes.Equal(previous, data) {
		return "", nil
	}
	backup := ""
	if err == nil {
		file, e := os.CreateTemp(filepath.Dir(path), "monitor-arrangement.lua.before-*")
		if e != nil {
			return "", e
		}
		backup = file.Name()
		_, writeErr := file.Write(previous)
		closeErr := file.Close()
		if writeErr != nil {
			return "", writeErr
		}
		if closeErr != nil {
			return "", closeErr
		}
	}
	return backup, AtomicWrite(path, data)
}
