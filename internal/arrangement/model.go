package arrangement

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
)

const MaxMonitors = 32

type Monitor struct {
	DPMSStatus    *bool   `json:"dpmsStatus,omitempty"`
	Name          string  `json:"name"`
	Make          string  `json:"make"`
	Model         string  `json:"model"`
	Description   string  `json:"description"`
	Serial        string  `json:"serial"`
	Width         int     `json:"width"`
	Height        int     `json:"height"`
	Scale         float64 `json:"scale"`
	Transform     int     `json:"transform"`
	X             int     `json:"x"`
	Y             int     `json:"y"`
	MirrorOf      string  `json:"mirrorOf"`
	Disabled      bool    `json:"disabled"`
	Identity      string  `json:"identity"`
	LogicalWidth  int     `json:"logicalWidth"`
	LogicalHeight int     `json:"logicalHeight"`
}

type Position struct {
	Primary bool `json:"primary,omitempty"`
	X       int  `json:"x"`
	Y       int  `json:"y"`
}

type Profile map[string]Position
type Profiles map[string]Profile

type Snapshot struct {
	Primary     string    `json:"primary"`
	Monitors    []Monitor `json:"monitors"`
	Key         string    `json:"key"`
	Fingerprint string    `json:"fingerprint"`
	Revision    string    `json:"revision"`
	Saved       bool      `json:"saved"`
	Path        string    `json:"path"`
	Profiles    int       `json:"profiles"`
	Arrangement Profile   `json:"arrangement,omitempty"`
}

type Placement struct {
	Name string `json:"name"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
}

type SaveRequest struct {
	Primary     string      `json:"primary"`
	Fingerprint string      `json:"fingerprint"`
	Revision    string      `json:"revision"`
	Monitors    []Placement `json:"monitors"`
}

func usableSerial(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "0", "unknown", "none", "n/a", "null", "(null)", "unspecified":
		return false
	}
	return true
}

// Escape delimiters before joining: a literal colon in a serial is not a separator.
func escape(value string) string {
	return strings.NewReplacer("%", "%25", ":", "%3A", "@", "%40", "=", "%3D").Replace(value)
}

func Prepare(raw []Monitor) ([]Monitor, error) {
	if len(raw) > MaxMonitors {
		return nil, fmt.Errorf("too many monitors (maximum %d)", MaxMonitors)
	}
	result := make([]Monitor, 0, len(raw))
	counts := map[string]int{}
	names := map[string]bool{}
	for _, m := range raw {
		if m.Disabled || (m.MirrorOf != "" && m.MirrorOf != "none") {
			continue
		}
		if m.Name == "" || len(m.Name) > 256 || names[m.Name] {
			return nil, errors.New("invalid or duplicate monitor connector")
		}
		if len(m.Serial) > 1024 || len(m.Model) > 1024 {
			return nil, errors.New("monitor identity is too long")
		}
		if m.Width <= 0 || m.Height <= 0 || m.Width > 32768 || m.Height > 32768 || math.IsNaN(m.Scale) || math.IsInf(m.Scale, 0) || m.Scale < 0.25 || m.Scale > 8 || m.Transform < 0 || m.Transform > 7 {
			return nil, fmt.Errorf("invalid dimensions or scale for %s", m.Name)
		}
		names[m.Name] = true
		if usableSerial(m.Serial) {
			m.Identity = escape(strings.TrimSpace(m.Serial))
		} else {
			model := strings.TrimSpace(m.Model)
			if model == "" {
				model = strings.TrimSpace(m.Description)
			}
			if model == "" {
				return nil, fmt.Errorf("%s has neither a serial nor a model", m.Name)
			}
			m.Identity = "model=" + escape(model)
		}
		width, height := m.Width, m.Height
		if m.Transform%2 == 1 {
			width, height = height, width
		}
		m.LogicalWidth = int(math.Ceil(float64(width) / m.Scale))
		m.LogicalHeight = int(math.Ceil(float64(height) / m.Scale))
		counts[m.Identity]++
		result = append(result, m)
	}
	// A connector is needed only for ambiguous identities; unique serials remain
	// portable across docks and connector renumbering.
	for i := range result {
		if counts[result[i].Identity] > 1 {
			result[i].Identity += "@" + escape(result[i].Name)
		}
	}
	if len(result) == 0 {
		return nil, errors.New("no active non-mirrored monitors were found")
	}
	return result, nil
}

func Key(monitors []Monitor) string {
	keys := make([]string, len(monitors))
	for i, m := range monitors {
		keys[i] = m.Identity
	}
	sort.Strings(keys)
	return strings.Join(keys, ":")
}

func Digest(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// Positions are deliberately excluded: layout changes must not masquerade as
// a changed monitor set, mode or scale while the user is editing.
func Fingerprint(monitors []Monitor) string {
	type item struct {
		Name, Identity           string
		Width, Height, Transform int
		Scale                    float64
	}
	items := make([]item, 0, len(monitors))
	for _, m := range monitors {
		items = append(items, item{m.Name, m.Identity, m.Width, m.Height, m.Transform, m.Scale})
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Name < items[j].Name })
	data, _ := json.Marshal(items)
	return Digest(data)
}

func Validate(monitors []Monitor, profile Profile) error {
	if len(profile) != len(monitors) {
		return errors.New("the arrangement does not include exactly the active monitor set")
	}
	primaryCount := 0
	for _, p := range profile {
		if p.Primary {
			primaryCount++
		}
	}
	if primaryCount > 1 {
		return errors.New("only one monitor can be primary")
	}
	for i, m := range monitors {
		p, ok := profile[m.Identity]
		if !ok {
			return fmt.Errorf("the arrangement is missing %s", m.Name)
		}
		if p.X < -65536 || p.X > 65536 || p.Y < -65536 || p.Y > 65536 {
			return errors.New("coordinates must be between -65536 and 65536")
		}
		for _, other := range monitors[:i] {
			q := profile[other.Identity]
			if p.X < q.X+other.LogicalWidth && p.X+m.LogicalWidth > q.X && p.Y < q.Y+other.LogicalHeight && p.Y+m.LogicalHeight > q.Y {
				return fmt.Errorf("%s overlaps %s; move the screens apart before saving", m.Name, other.Name)
			}
		}
	}
	return nil
}

func FromRequest(monitors []Monitor, req SaveRequest) (Profile, error) {
	if req.Fingerprint != Fingerprint(monitors) {
		return nil, errors.New("the connected monitors, resolutions or scales changed; reload before saving")
	}
	if len(req.Monitors) != len(monitors) {
		return nil, errors.New("the connected monitor set changed; reload before saving")
	}
	byName := map[string]Monitor{}
	for _, m := range monitors {
		byName[m.Name] = m
	}
	if req.Primary != "" {
		if _, ok := byName[req.Primary]; !ok {
			return nil, fmt.Errorf("primary monitor %s is not connected", req.Primary)
		}
	}
	result := Profile{}
	for _, p := range req.Monitors {
		m, ok := byName[p.Name]
		if !ok {
			return nil, fmt.Errorf("unknown connector %s", p.Name)
		}
		if _, exists := result[m.Identity]; exists {
			return nil, errors.New("a monitor appears more than once")
		}
		result[m.Identity] = Position{X: p.X, Y: p.Y, Primary: m.Name == req.Primary}
	}
	return result, Validate(monitors, result)
}

// The selection follows the saved identity while Lua consumers see the current connector.
func PrimaryName(monitors []Monitor, profile Profile) string {
	for _, m := range monitors {
		if profile[m.Identity].Primary {
			return m.Name
		}
	}
	return ""
}
