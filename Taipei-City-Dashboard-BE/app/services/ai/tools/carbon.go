package tools

import (
	"context"
	"fmt"
	"strings"
)

// emissionTable maps a transport mode to (g CO2 / km, source description).
// Values derived from these CSVs in csv_files/:
//   - 機車動態能耗與碳排放係數.csv  (機車)
//   - 大客車動態能耗與碳排放係數.csv (國道客運/遊覽車 + 市區公車)
//   - 小客車動態能耗與碳排放係數.csv (檔案內容空, 改用 EPA 文獻典型值)
// Each value is the city-speed (~30km/h) coefficient. For more precise
// numbers we should interpolate by speed; for MVP a constant is enough.
var emissionTable = map[string]struct {
	GPerKm float64
	Source string
}{
	"walking":     {GPerKm: 0, Source: "步行不產生 CO2"},
	"cycling":     {GPerKm: 0, Source: "騎自行車不產生 CO2"},
	"scooter":     {GPerKm: 148.56, Source: "機車動態能耗與碳排放係數.csv (30 km/h)"},
	"driving":     {GPerKm: 187.0, Source: "EPA 典型值 (小客車動態能耗.csv 為空, 用 1500cc 汽油車估算)"},
	"car":         {GPerKm: 187.0, Source: "EPA 典型值 (小客車)"},
	"bus":         {GPerKm: 1500.0, Source: "大客車動態能耗.csv 市區公車 (30 km/h)"},
	"bus_city":    {GPerKm: 1500.0, Source: "大客車動態能耗.csv 市區公車"},
	"bus_highway": {GPerKm: 700.0, Source: "大客車動態能耗.csv 國道客運 (80 km/h)"},
	"mrt":         {GPerKm: 35.0, Source: "捷運參考值 (台電平均電力排碳 + MRT 能耗)"},
	"taxi":        {GPerKm: 187.0, Source: "計程車按小客車估算"},
}

// ComputeCarbonArgs is the input for compute_carbon_emission.
type ComputeCarbonArgs struct {
	DistanceKm flexFloat `json:"distance_km"`
	Mode       string    `json:"mode"`
	Passengers int       `json:"passengers"` // optional, for per-passenger calc on bus/mrt
}

// ComputeCarbonEmission returns CO2 emissions for a trip given distance + mode.
// If passengers > 1 (e.g. for bus), also returns per-passenger emission.
func ComputeCarbonEmission(ctx context.Context, args string) (string, error) {
	var p ComputeCarbonArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}
	dist := float64(p.DistanceKm)
	if dist <= 0 {
		return "", fmt.Errorf("distance_km must be > 0")
	}

	mode := strings.ToLower(strings.TrimSpace(p.Mode))
	row, ok := emissionTable[mode]
	if !ok {
		// Helpful list of valid modes
		valid := make([]string, 0, len(emissionTable))
		for k := range emissionTable {
			valid = append(valid, k)
		}
		return "", fmt.Errorf("mode %q unknown. Valid: %v", mode, valid)
	}

	totalG := dist * row.GPerKm
	totalKg := totalG / 1000

	out := fmt.Sprintf(
		"【碳排放估算】\n"+
			"- 距離: %.2f km\n"+
			"- 交通工具: %s\n"+
			"- 排放係數: %.2f g CO2/km\n"+
			"- 總排放: %.1f g (%.3f kg) CO2\n",
		dist, mode, row.GPerKm, totalG, totalKg,
	)

	if p.Passengers > 1 && (mode == "bus" || mode == "bus_city" || mode == "bus_highway" || mode == "mrt") {
		perPassenger := totalG / float64(p.Passengers)
		out += fmt.Sprintf("- 每位乘客分攤 (%d 人): %.1f g CO2\n", p.Passengers, perPassenger)
	}

	out += "- 來源: " + row.Source
	return out, nil
}
