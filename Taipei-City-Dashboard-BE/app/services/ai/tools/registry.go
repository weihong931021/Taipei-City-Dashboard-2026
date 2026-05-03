package tools

import (
	"TaipeiCityDashboardBE/app/models"
	"TaipeiCityDashboardBE/global"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// ToolFunc defines the signature for a tool function
type ToolFunc func(ctx context.Context, args string) (string, error)

var registry = make(map[string]ToolFunc)

func init() {
	// Register demo tools
	Register("get_current_time", GetCurrentTime)
	Register("get_population_summary", GetPopulationSummary)
	Register("search_documents", SearchDocuments)
	Register("resolve_location", ResolveLocation)
	Register("search_nearby_pois", SearchNearbyPOIs)
	Register("compute_route", ComputeRoute)
	Register("compute_carbon_emission", ComputeCarbonEmission)
	Register("analyze_route_greenness", AnalyzeRouteGreenness)
}

// Register adds a tool to the registry
func Register(name string, fn ToolFunc) {
	registry[name] = fn
}

// Execute calls a registered tool with the given arguments
func Execute(ctx context.Context, name string, args string) (string, error) {
	fn, ok := registry[name]
	if !ok {
		return "", fmt.Errorf("tool %s not found", name)
	}
	return fn(ctx, args)
}

// PopulationArgs defines the arguments for the get_population_summary tool
type PopulationArgs struct {
	City string `json:"city"`
	Year int    `json:"year"`
}

// GetPopulationSummary queries the population age distribution from the dashboard database
func GetPopulationSummary(ctx context.Context, args string) (string, error) {
	var params PopulationArgs
	if err := parseArgs(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}

	// Default to Taipei if not specified or unrecognized
	tableName := "population_age_distribution_tpe"
	cityName := "台北市"
	if params.City == "new_taipei" {
		tableName = "population_age_distribution_new_tpe"
		cityName = "新北市"
	}

	// Define result structure based on database schema
	var result struct {
		Year      int `gorm:"column:year"`
		Young     int `gorm:"column:young_population"`
		Working   int `gorm:"column:working_age_population"`
		Elderly   int `gorm:"column:elderly_population"`
		DataTime  time.Time `gorm:"column:data_time"`
	}

	// Query the dashboard database
	err := models.DBDashboard.Table(tableName).
		Where("year = ?", params.Year).
		Order("data_time DESC"). // Get the latest record for that year
		First(&result).Error

	if err != nil {
		return "", fmt.Errorf("找不到 %s %d 年的人口統計資料: %v", cityName, params.Year, err)
	}

	// Format the response for the LLM
	return fmt.Sprintf(
		"【%d年 %s 人口結構概況】\n- 幼年人口 (0-14歲)：%d 人\n- 青壯年人口 (15-64歲)：%d 人\n- 老年人口 (65歲以上)：%d 人\n- 總人口： %d 人\n- 數據更新時間：%s",
		result.Year, cityName, result.Young, result.Working, result.Elderly,
		result.Young+result.Working+result.Elderly,
		result.DataTime.Format("2006-01-02"),
	), nil
}

// GetCurrentTime is a demo tool that returns the current Taipei time
func GetCurrentTime(ctx context.Context, args string) (string, error) {
	loc, err := time.LoadLocation("Asia/Taipei")
	if err != nil {
		// Fallback to UTC if timezone data is missing
		return time.Now().Format(time.RFC3339), nil
	}
	return time.Now().In(loc).Format("2006-01-02 15:04:05"), nil
}

// Helper to parse JSON arguments if needed in future tools
func parseArgs(args string, v interface{}) error {
	return json.Unmarshal([]byte(args), v)
}

// SearchDocsArgs defines the arguments for the search_documents tool
type SearchDocsArgs struct {
	Query    string  `json:"query"`
	TopK     int     `json:"top_k"`
	MinScore float64 `json:"min_score"`
}

// SearchDocuments performs semantic search over the markdown knowledge base in Qdrant.
// Returns top-K matching chunks formatted for LLM consumption (with source citations).
func SearchDocuments(ctx context.Context, args string) (string, error) {
	var p SearchDocsArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}
	if p.Query == "" {
		return "", fmt.Errorf("query is required")
	}
	if p.TopK <= 0 || p.TopK > 10 {
		p.TopK = 5
	}
	if p.MinScore <= 0 {
		p.MinScore = 0.70
	}

	vec, err := models.GenVector(p.Query)
	if err != nil {
		return "", fmt.Errorf("embed query failed: %v", err)
	}

	collection := global.Qdrant.DocCollection
	if collection == "" {
		collection = "documents"
	}

	resp, err := models.QueryQdrantCollection(collection, vec, p.TopK, p.MinScore)
	if err != nil {
		return "", fmt.Errorf("qdrant query failed: %v", err)
	}

	if len(resp.Result.Points) == 0 {
		return "知識庫中找不到與「" + p.Query + "」相關的內容。請改用其他關鍵字，或回應使用者「目前知識庫沒有相關資料」。", nil
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("找到 %d 筆相關段落 (依相關度排序):\n\n", len(resp.Result.Points)))
	for i, pt := range resp.Result.Points {
		source, _ := pt.Payload["source_file"].(string)
		heading, _ := pt.Payload["heading_path"].(string)
		text, _ := pt.Payload["text"].(string)
		// Cap chunk length to control token usage
		if len(text) > 800 {
			text = text[:800] + "..."
		}
		sb.WriteString(fmt.Sprintf(
			"[%d] 來源: %s | 章節: %s | 相關度: %.3f\n%s\n\n",
			i+1, source, heading, pt.Score, text,
		))
	}
	sb.WriteString("\n指引: 引用上述內容回答使用者時,請在句尾標註來源 [來源: 檔名]。若內容不足以回答,請誠實說明。")
	return sb.String(), nil
}
