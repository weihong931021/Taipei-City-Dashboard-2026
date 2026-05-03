package tools

import (
	"TaipeiCityDashboardBE/app/models"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// flexFloat accepts either a JSON number or a string-encoded number.
// LLMs sometimes return "25.033" (string) instead of 25.033 (number) — this normalises both.
type flexFloat float64

func (f *flexFloat) UnmarshalJSON(data []byte) error {
	if len(data) == 0 || string(data) == "null" {
		*f = 0
		return nil
	}
	if data[0] == '"' {
		var s string
		if err := json.Unmarshal(data, &s); err != nil {
			return err
		}
		s = strings.TrimSpace(s)
		if s == "" {
			*f = 0
			return nil
		}
		v, err := strconv.ParseFloat(s, 64)
		if err != nil {
			return fmt.Errorf("flexFloat: cannot parse %q as number", s)
		}
		*f = flexFloat(v)
		return nil
	}
	var v float64
	if err := json.Unmarshal(data, &v); err != nil {
		return err
	}
	*f = flexFloat(v)
	return nil
}

// knownLandmarks: short ambiguous names that Mapbox geocoding gets wrong.
// Verified coordinates for popular Taipei landmarks. Add more as needed.
var knownLandmarks = map[string]LocPoint{
	"台北101":     {Name: "台北101", Address: "臺北市信義區信義路五段7號", Lat: 25.0330, Lng: 121.5654, Source: "landmark"},
	"臺北101":     {Name: "臺北101", Address: "臺北市信義區信義路五段7號", Lat: 25.0330, Lng: 121.5654, Source: "landmark"},
	"台北車站":     {Name: "台北車站", Address: "臺北市中正區北平西路3號", Lat: 25.0478, Lng: 121.5170, Source: "landmark"},
	"臺北車站":     {Name: "臺北車站", Address: "臺北市中正區北平西路3號", Lat: 25.0478, Lng: 121.5170, Source: "landmark"},
	"象山":       {Name: "象山", Address: "臺北市信義區象山", Lat: 25.0270, Lng: 121.5713, Source: "landmark"},
	"台北象山":     {Name: "象山", Address: "臺北市信義區象山", Lat: 25.0270, Lng: 121.5713, Source: "landmark"},
	"西門町":     {Name: "西門町", Address: "臺北市萬華區西門町", Lat: 25.0421, Lng: 121.5081, Source: "landmark"},
	"中正紀念堂":   {Name: "中正紀念堂", Address: "臺北市中正區中山南路21號", Lat: 25.0349, Lng: 121.5217, Source: "landmark"},
	"國父紀念館":   {Name: "國父紀念館", Address: "臺北市信義區仁愛路四段505號", Lat: 25.0399, Lng: 121.5605, Source: "landmark"},
	"信義威秀":   {Name: "信義威秀", Address: "臺北市信義區松壽路20號", Lat: 25.0364, Lng: 121.5664, Source: "landmark"},
	"松山機場":   {Name: "松山機場", Address: "臺北市松山區敦化北路340之9號", Lat: 25.0697, Lng: 121.5524, Source: "landmark"},
	"圓山":       {Name: "圓山", Address: "臺北市中山區圓山", Lat: 25.0719, Lng: 121.5202, Source: "landmark"},
	"龍山寺":     {Name: "龍山寺", Address: "臺北市萬華區廣州街211號", Lat: 25.0371, Lng: 121.4998, Source: "landmark"},
	"故宮博物院": {Name: "故宮博物院", Address: "臺北市士林區至善路二段221號", Lat: 25.1023, Lng: 121.5485, Source: "landmark"},
}

var mapboxToken = os.Getenv("MAPBOX_TOKEN")

// mapboxReferer makes server-side calls satisfy `pk.*` tokens that have URL allowlist.
// Defaults to the FE dev origin so the Referer matches what the browser would send.
// Override with MAPBOX_REFERER if your token allows a different origin (or unset for no header).
var mapboxReferer = func() string {
	if v, ok := os.LookupEnv("MAPBOX_REFERER"); ok {
		return v
	}
	return "http://localhost:8080/"
}()

// httpClient is shared across location tools.
var httpClient = &http.Client{Timeout: 10 * time.Second}

// ---------- resolve_location ----------

type ResolveLocationArgs struct {
	Name string `json:"name"`
}

type LocPoint struct {
	Name    string  `json:"name"`
	Address string  `json:"address"`
	Lat     float64 `json:"lat"`
	Lng     float64 `json:"lng"`
	Source  string  `json:"source"`
}

// ResolveLocation turns a place name / address into a {lat,lng}.
// Lookup order: ev_stations name match -> restaurants name match -> Mapbox geocoding.
func ResolveLocation(ctx context.Context, args string) (string, error) {
	var p ResolveLocationArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}
	if strings.TrimSpace(p.Name) == "" {
		return "", fmt.Errorf("name is required")
	}

	q := strings.TrimSpace(p.Name)

	// 1. Known landmarks (exact + contains match) — bypass Mapbox to avoid wrong matches
	//    e.g. Mapbox sends "台北101" to 屏東 because it ignores the city prefix.
	if pt, ok := knownLandmarks[q]; ok {
		b, _ := json.Marshal(pt)
		return string(b), nil
	}
	for key, pt := range knownLandmarks {
		if strings.Contains(q, key) {
			b, _ := json.Marshal(pt)
			return string(b), nil
		}
	}

	// 2. Internal POI lookup (餐廳/充電站名稱)
	if pt, ok := lookupInternalPOI(q); ok {
		b, _ := json.Marshal(pt)
		return string(b), nil
	}

	// 3. Mapbox geocoding fallback (with Taipei proximity bias)
	pt, err := geocodeMapbox(ctx, q)
	if err != nil {
		return "", fmt.Errorf("geocoding failed: %v", err)
	}
	b, _ := json.Marshal(pt)
	return string(b), nil
}

func lookupInternalPOI(name string) (*LocPoint, bool) {
	type row struct {
		Name    string
		Address string
		Lat     float64
		Lng     float64
	}
	pat := "%" + name + "%"

	for _, table := range []string{"ev_stations", "restaurants"} {
		var r row
		err := models.DBDashboard.Raw(
			"SELECT name, address, lat, lng FROM "+table+
				" WHERE name ILIKE ? AND lat IS NOT NULL LIMIT 1", pat,
		).Scan(&r).Error
		if err == nil && r.Name != "" {
			return &LocPoint{
				Name: r.Name, Address: r.Address,
				Lat: r.Lat, Lng: r.Lng,
				Source: "db:" + table,
			}, true
		}
	}
	return nil, false
}

func geocodeMapbox(ctx context.Context, query string) (*LocPoint, error) {
	if mapboxToken == "" {
		return nil, fmt.Errorf("MAPBOX_TOKEN not configured")
	}
	// Bias results toward Taipei area: proximity = Taipei 101, bbox = Taipei + New Taipei.
	endpoint := fmt.Sprintf(
		"https://api.mapbox.com/geocoding/v5/mapbox.places/%s.json"+
			"?access_token=%s&country=tw&language=zh-TW&limit=1"+
			"&proximity=121.5654,25.0330"+
			"&bbox=121.40,24.90,122.05,25.30",
		url.PathEscape(query), mapboxToken,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
	if mapboxReferer != "" {
		req.Header.Set("Referer", mapboxReferer)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("mapbox %d: %s", resp.StatusCode, string(body))
	}
	var out struct {
		Features []struct {
			PlaceName string    `json:"place_name"`
			Center    []float64 `json:"center"`
		} `json:"features"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Features) == 0 {
		return nil, fmt.Errorf("no results for %q", query)
	}
	f := out.Features[0]
	return &LocPoint{
		Name:    query,
		Address: f.PlaceName,
		Lng:     f.Center[0],
		Lat:     f.Center[1],
		Source:  "mapbox_geocode",
	}, nil
}

// ---------- search_nearby_pois ----------

type SearchNearbyArgs struct {
	Lat         flexFloat `json:"lat"`
	Lng         flexFloat `json:"lng"`
	Category    string    `json:"category"` // restaurant | charging_station | swap_station
	VehicleType string    `json:"vehicle_type"` // car | scooter (optional, for charging)
	RadiusM     int       `json:"radius_m"`
	Limit       int       `json:"limit"`
}

type POIResult struct {
	Name        string  `json:"name"`
	Address     string  `json:"address"`
	District    string  `json:"district"`
	DistanceM   float64 `json:"distance_m"`
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
	Operator    string  `json:"operator,omitempty"`
	PlugType    string  `json:"plug_type,omitempty"`
	VehicleType string  `json:"vehicle_type,omitempty"`
	EcoTags     string  `json:"eco_tags,omitempty"`
	Phone       string  `json:"phone,omitempty"`
}

// SearchNearbyPOIs searches restaurants or EV stations within a radius, ordered by distance.
func SearchNearbyPOIs(ctx context.Context, args string) (string, error) {
	var p SearchNearbyArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}
	lat, lng := float64(p.Lat), float64(p.Lng)
	if lat == 0 && lng == 0 {
		return "", fmt.Errorf("lat/lng required (use resolve_location first if you only have a name)")
	}
	if p.RadiusM <= 0 || p.RadiusM > 20000 {
		p.RadiusM = 1500
	}
	if p.Limit <= 0 || p.Limit > 30 {
		p.Limit = 10
	}

	results := []POIResult{}

	switch p.Category {
	case "restaurant", "餐廳":
		err := models.DBDashboard.Raw(`
			SELECT name, address, district, phone,
			       COALESCE(array_to_string(eco_tags, ','), '') AS eco_tags,
			       lat, lng,
			       ST_Distance(location, ST_MakePoint(?, ?)::geography) AS distance_m
			FROM restaurants
			WHERE location IS NOT NULL
			  AND ST_DWithin(location, ST_MakePoint(?, ?)::geography, ?)
			ORDER BY distance_m ASC
			LIMIT ?`,
			lng, lat, lng, lat, p.RadiusM, p.Limit,
		).Scan(&results).Error
		if err != nil {
			return "", fmt.Errorf("db query failed: %v", err)
		}

	case "charging_station", "充電站", "swap_station", "換電站":
		serviceType := "charging"
		if p.Category == "swap_station" || p.Category == "換電站" {
			serviceType = "swap"
		}
		extraWhere := ""
		argv := []interface{}{lng, lat, lng, lat, p.RadiusM, serviceType}
		if p.VehicleType != "" {
			extraWhere = "AND vehicle_type = ?"
			argv = append(argv, p.VehicleType)
		}
		argv = append(argv, p.Limit)
		query := `
			SELECT name, address, district, operator, plug_type, vehicle_type,
			       lat, lng,
			       ST_Distance(location, ST_MakePoint(?, ?)::geography) AS distance_m
			FROM ev_stations
			WHERE location IS NOT NULL
			  AND ST_DWithin(location, ST_MakePoint(?, ?)::geography, ?)
			  AND service_type = ?
			  ` + extraWhere + `
			ORDER BY distance_m ASC
			LIMIT ?`
		err := models.DBDashboard.Raw(query, argv...).Scan(&results).Error
		if err != nil {
			return "", fmt.Errorf("db query failed: %v", err)
		}

	default:
		return "", fmt.Errorf("category must be one of: restaurant, charging_station, swap_station")
	}

	if len(results) == 0 {
		return fmt.Sprintf("在半徑 %d 公尺內找不到符合條件的「%s」。請考慮放大搜尋半徑或改變類別。", p.RadiusM, p.Category), nil
	}

	// Format for LLM (concise, with structured JSON for FE rendering)
	out := map[string]interface{}{
		"category":  p.Category,
		"radius_m":  p.RadiusM,
		"count":     len(results),
		"results":   results,
	}
	b, _ := json.MarshalIndent(out, "", "  ")
	return string(b), nil
}

// ---------- compute_route ----------

// WaypointArg is a single intermediate stop. Accepts either {lat,lng} object
// or [lng,lat] array; the LLM has been observed to emit both shapes.
type WaypointArg struct {
	Lat flexFloat `json:"lat"`
	Lng flexFloat `json:"lng"`
}

type ComputeRouteArgs struct {
	OriginLat flexFloat     `json:"origin_lat"`
	OriginLng flexFloat     `json:"origin_lng"`
	DestLat   flexFloat     `json:"dest_lat"`
	DestLng   flexFloat     `json:"dest_lng"`
	Mode      string        `json:"mode"` // walking | driving | cycling
	Waypoints []WaypointArg `json:"waypoints"` // optional intermediate stops, in visit order
}

// ComputeRoute calls Mapbox Directions API and returns the geometry + summary.
func ComputeRoute(ctx context.Context, args string) (string, error) {
	var p ComputeRouteArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}
	if p.Mode == "" {
		p.Mode = "driving"
	}
	mode := map[string]string{
		"walking": "walking", "driving": "driving",
		"driving-traffic": "driving-traffic", "cycling": "cycling",
	}[p.Mode]
	if mode == "" {
		return "", fmt.Errorf("mode must be walking|driving|cycling")
	}
	if mapboxToken == "" {
		return "", fmt.Errorf("MAPBOX_TOKEN not configured")
	}

	oLat, oLng := float64(p.OriginLat), float64(p.OriginLng)
	dLat, dLng := float64(p.DestLat), float64(p.DestLng)
	if oLat == 0 || oLng == 0 || dLat == 0 || dLng == 0 {
		return "", fmt.Errorf("origin/destination coordinates required (call resolve_location first)")
	}

	// Build the path: origin;wp1;wp2;...;destination
	// Mapbox Directions API allows up to 25 coordinates per request (v5).
	var sb strings.Builder
	fmt.Fprintf(&sb, "%f,%f", oLng, oLat)
	wpOut := make([][]float64, 0, len(p.Waypoints))
	for _, w := range p.Waypoints {
		wLat, wLng := float64(w.Lat), float64(w.Lng)
		if wLat == 0 || wLng == 0 {
			continue // skip malformed entries silently
		}
		fmt.Fprintf(&sb, ";%f,%f", wLng, wLat)
		wpOut = append(wpOut, []float64{wLng, wLat})
	}
	fmt.Fprintf(&sb, ";%f,%f", dLng, dLat)

	// steps=true → per-step geometries + maneuver text. We rebuild each leg
	// (segment between two consecutive coords) by concatenating its steps so
	// the FE can colour each leg independently.
	endpoint := fmt.Sprintf(
		"https://api.mapbox.com/directions/v5/mapbox/%s/%s?geometries=geojson&overview=full&steps=true&language=zh-TW&access_token=%s",
		mode, sb.String(), mapboxToken,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", endpoint, nil)
	if mapboxReferer != "" {
		req.Header.Set("Referer", mapboxReferer)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("mapbox directions %d: %s", resp.StatusCode, string(body))
	}

	var raw struct {
		Routes []struct {
			Distance float64         `json:"distance"`
			Duration float64         `json:"duration"`
			Geometry json.RawMessage `json:"geometry"`
			Legs     []struct {
				Distance float64 `json:"distance"`
				Duration float64 `json:"duration"`
				Summary  string  `json:"summary"`
				Steps    []struct {
					Distance float64 `json:"distance"`
					Duration float64 `json:"duration"`
					Name     string  `json:"name"`
					Geometry struct {
						Coordinates [][]float64 `json:"coordinates"`
					} `json:"geometry"`
					Maneuver struct {
						Instruction string `json:"instruction"`
						Type        string `json:"type"`
					} `json:"maneuver"`
				} `json:"steps"`
			} `json:"legs"`
		} `json:"routes"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return "", err
	}
	if len(raw.Routes) == 0 {
		return "找不到路徑。請確認起點/終點座標。", nil
	}
	r := raw.Routes[0]

	type stepOut struct {
		Instruction string `json:"instruction"`
		DistanceM   int    `json:"distance_m"`
		Name        string `json:"name,omitempty"`
		Type        string `json:"type,omitempty"`
	}
	type legOut struct {
		DistanceKm  string      `json:"distance_km"`
		DistanceM   int         `json:"distance_m"`
		DurationMin int         `json:"duration_min"`
		Summary     string      `json:"summary"`
		Coordinates [][]float64 `json:"coordinates"`
		Steps       []stepOut   `json:"steps"`
	}

	legsOut := make([]legOut, 0, len(r.Legs))
	for _, leg := range r.Legs {
		coords := make([][]float64, 0)
		steps := make([]stepOut, 0, len(leg.Steps))
		for _, s := range leg.Steps {
			coords = append(coords, s.Geometry.Coordinates...)
			steps = append(steps, stepOut{
				Instruction: s.Maneuver.Instruction,
				DistanceM:   int(s.Distance),
				Name:        s.Name,
				Type:        s.Maneuver.Type,
			})
		}
		legsOut = append(legsOut, legOut{
			DistanceKm:  fmt.Sprintf("%.2f", leg.Distance/1000),
			DistanceM:   int(leg.Distance),
			DurationMin: int(leg.Duration / 60),
			Summary:     leg.Summary,
			Coordinates: coords,
			Steps:       steps,
		})
	}

	out := map[string]interface{}{
		"mode":         p.Mode,
		"distance_m":   int(r.Distance),
		"distance_km":  fmt.Sprintf("%.2f", r.Distance/1000),
		"duration_s":   int(r.Duration),
		"duration_min": int(r.Duration / 60),
		"geometry":     json.RawMessage(r.Geometry), // kept for backward compat
		"origin":       []float64{oLng, oLat},
		"destination":  []float64{dLng, dLat},
		"waypoints":    wpOut,
		"legs":         legsOut,
	}
	b, _ := json.MarshalIndent(out, "", "  ")
	return string(b), nil
}
