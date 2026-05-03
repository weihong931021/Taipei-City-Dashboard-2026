package tools

import (
	"TaipeiCityDashboardBE/app/models"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
)

// AnalyzeRouteGreennessArgs takes a route geometry (sequence of [lng,lat] coords
// from compute_route's legs) and counts street trees + green parks within
// configurable buffer distances.
type AnalyzeRouteGreennessArgs struct {
	Coordinates [][]float64 `json:"coordinates"`     // 必填,[[lng,lat], ...]
	TreeBufferM int         `json:"tree_buffer_m"` // 預設 100
	ParkBufferM int         `json:"park_buffer_m"` // 預設 200
}

type speciesCount struct {
	Species string `gorm:"column:species"`
	N       int    `gorm:"column:n"`
}

type parkRow struct {
	Name    string  `gorm:"column:name"`
	AreaHa  float64 `gorm:"column:area_ha"`
	DistM   float64 `gorm:"column:dist_m"`
}

// AnalyzeRouteGreenness queries street_trees + green_parks for sites near a
// route. Designed to be called *after* compute_route so the LLM can append
// "this route passes 247 trees and 3 parks" to its summary.
func AnalyzeRouteGreenness(ctx context.Context, args string) (string, error) {
	var p AnalyzeRouteGreennessArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}
	if len(p.Coordinates) < 2 {
		return "", fmt.Errorf("coordinates required: at least 2 [lng,lat] points")
	}
	if p.TreeBufferM <= 0 || p.TreeBufferM > 1000 {
		p.TreeBufferM = 100
	}
	if p.ParkBufferM <= 0 || p.ParkBufferM > 2000 {
		p.ParkBufferM = 200
	}

	// Build a LineString GeoJSON from the route coordinates.
	geo := map[string]interface{}{
		"type":        "LineString",
		"coordinates": p.Coordinates,
	}
	geoBytes, err := json.Marshal(geo)
	if err != nil {
		return "", fmt.Errorf("marshal geometry: %v", err)
	}
	geoJSON := string(geoBytes)

	// 1. Tree count + top species
	var treeCount int64
	if err := models.DBDashboard.Raw(`
		SELECT COUNT(*) FROM street_trees
		WHERE ST_DWithin(
			location,
			ST_SetSRID(ST_GeomFromGeoJSON(?), 4326)::geography,
			?
		)`,
		geoJSON, p.TreeBufferM,
	).Scan(&treeCount).Error; err != nil {
		return "", fmt.Errorf("tree count query: %v", err)
	}

	var topSpecies []speciesCount
	if treeCount > 0 {
		if err := models.DBDashboard.Raw(`
			SELECT species, COUNT(*) AS n
			FROM street_trees
			WHERE species IS NOT NULL
			  AND species <> ''
			  AND ST_DWithin(
			    location,
			    ST_SetSRID(ST_GeomFromGeoJSON(?), 4326)::geography,
			    ?
			  )
			GROUP BY species
			ORDER BY n DESC
			LIMIT 5`,
			geoJSON, p.TreeBufferM,
		).Scan(&topSpecies).Error; err != nil {
			return "", fmt.Errorf("species query: %v", err)
		}
	}

	// 2. Park count + names (within parkBufferM of the route)
	var parks []parkRow
	if err := models.DBDashboard.Raw(`
		SELECT name, area_ha,
		       ST_Distance(location, ST_SetSRID(ST_GeomFromGeoJSON(?), 4326)::geography) AS dist_m
		FROM green_parks
		WHERE name IS NOT NULL
		  AND name <> ''
		  AND ST_DWithin(
		    location,
		    ST_SetSRID(ST_GeomFromGeoJSON(?), 4326)::geography,
		    ?
		  )
		ORDER BY dist_m ASC
		LIMIT 10`,
		geoJSON, geoJSON, p.ParkBufferM,
	).Scan(&parks).Error; err != nil {
		return "", fmt.Errorf("park query: %v", err)
	}

	// Format LLM-friendly summary.
	var sb strings.Builder
	sb.WriteString("【沿路綠化分析】\n")
	sb.WriteString(fmt.Sprintf("- 沿路 %dm 內: %d 棵行道樹\n", p.TreeBufferM, treeCount))
	if len(topSpecies) > 0 {
		parts := make([]string, 0, len(topSpecies))
		for _, s := range topSpecies {
			parts = append(parts, fmt.Sprintf("%s (%d)", s.Species, s.N))
		}
		sb.WriteString(fmt.Sprintf("- 主要樹種: %s\n", strings.Join(parts, ", ")))
	}
	sb.WriteString(fmt.Sprintf("- 沿路 %dm 內: %d 個公園/綠地\n", p.ParkBufferM, len(parks)))
	if len(parks) > 0 {
		names := make([]string, 0, len(parks))
		for _, k := range parks {
			names = append(names, k.Name)
		}
		sb.WriteString(fmt.Sprintf("- 公園: %s\n", strings.Join(names, ", ")))
	}

	// Lightweight greenness score: 0-10 (rough heuristic, log-scaled)
	rawScore := float64(treeCount) + float64(len(parks))*30.0
	score := 0.0
	if rawScore > 0 {
		score = math.Log10(rawScore+1) * 2.5
		if score > 10 {
			score = 10
		}
	}
	sb.WriteString(fmt.Sprintf("- 綠化評分: %.1f / 10\n", score))

	return sb.String(), nil
}
