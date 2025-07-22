package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/samzong/prom-etl-db/internal/models"
	"github.com/samzong/prom-etl-db/internal/prometheus"
	"github.com/samzong/prom-etl-db/internal/timeparser"
)

func main() {
	// 创建 Prometheus 客户端
	client, err := prometheus.NewClient("http://localhost:9090", "30s")
	if err != nil {
		log.Fatalf("Failed to create Prometheus client: %v", err)
	}
	defer client.Close()

	// 演示不同的时间表达式
	demonstrateTimeParser()

	// 演示昨天数据查询
	demonstrateYesterdayQuery(client)
}

func demonstrateTimeParser() {
	fmt.Println("=== 时间解析器示例 ===")

	// 创建时间解析器 (使用当前时间)
	parser := timeparser.NewRelativeTimeParser(time.Now())

	// 测试不同的时间表达式
	expressions := []string{
		"now",
		"yesterday",
		"昨天",
		"today",
		"-1d",
		"-2h",
		"-30m",
	}

	fmt.Printf("当前时间: %v\n\n", time.Now().Format("2006-01-02 15:04:05"))

	for _, expr := range expressions {
		result, err := parser.Parse(expr)
		if err != nil {
			fmt.Printf("解析 '%s' 失败: %v\n", expr, err)
			continue
		}
		fmt.Printf("'%s' -> %s\n", expr, result.Format("2006-01-02 15:04:05 MST"))
	}

	// 演示昨天的完整时间范围
	start, end := parser.GetYesterdayRange()
	fmt.Printf("\n昨天时间范围:\n")
	fmt.Printf("开始: %s\n", start.Format("2006-01-02 15:04:05.999999999 MST"))
	fmt.Printf("结束: %s\n", end.Format("2006-01-02 15:04:05.999999999 MST"))
}

func demonstrateYesterdayQuery(client *prometheus.Client) {
	fmt.Println("\n=== 昨天数据查询示例 ===")

	ctx := context.Background()

	// 方法1: 使用 "yesterday" 表达式的即时查询
	queryConfig1 := &models.QueryConfig{
		ID:    "gpu_utilization_yesterday_instant",
		Query: "up",
		TimeRange: &models.TimeRangeConfig{
			Type: "instant",
			Time: "yesterday", // 昨天 00:00:00
		},
	}

	fmt.Println("方法1: 使用 'yesterday' 即时查询")
	response1, err := client.QueryWithTimeRange(ctx, queryConfig1.Query, queryConfig1.TimeRange)
	if err != nil {
		fmt.Printf("查询失败: %v\n", err)
	} else {
		fmt.Printf("查询成功，结果类型: %s\n", response1.Data.ResultType)
	}

	// 方法2: 使用昨天的范围查询 (整天的数据)
	queryConfig2 := &models.QueryConfig{
		ID:    "gpu_utilization_yesterday_range",
		Query: "up",
		TimeRange: &models.TimeRangeConfig{
			Type:  "range",
			Start: "yesterday", // 昨天 00:00:00
			End:   "today",     // 今天 00:00:00 (即昨天 24:00:00)
			Step:  "1h",        // 每小时一个数据点
		},
	}

	fmt.Println("\n方法2: 使用昨天范围查询 (yesterday 到 today)")
	response2, err := client.QueryWithTimeRange(ctx, queryConfig2.Query, queryConfig2.TimeRange)
	if err != nil {
		fmt.Printf("查询失败: %v\n", err)
	} else {
		fmt.Printf("查询成功，结果类型: %s\n", response2.Data.ResultType)
	}

	// 方法3: 使用相对时间表达式的范围查询
	queryConfig3 := &models.QueryConfig{
		ID:    "gpu_utilization_relative_range",
		Query: "up",
		TimeRange: &models.TimeRangeConfig{
			Type:  "range",
			Start: "-1d", // 昨天这个时间
			End:   "now", // 现在
			Step:  "1h",  // 每小时一个数据点
		},
	}

	fmt.Println("\n方法3: 使用相对时间范围查询 (-1d 到 now)")
	response3, err := client.QueryWithTimeRange(ctx, queryConfig3.Query, queryConfig3.TimeRange)
	if err != nil {
		fmt.Printf("查询失败: %v\n", err)
	} else {
		fmt.Printf("查询成功，结果类型: %s\n", response3.Data.ResultType)
	}

	// 实际的GPU利用率查询示例
	fmt.Println("\n=== GPU利用率昨天数据查询 ===")

	gpuQuery := "count_over_time((count(kpanda_gpu_pod_utilization{cluster_name=\"sh-07-d-run\"}) by (cluster_name,UUID,node))[24h:1h])"

	gpuQueryConfig := &models.QueryConfig{
		ID:    "gpu_utilization_daily",
		Query: gpuQuery,
		TimeRange: &models.TimeRangeConfig{
			Type: "instant",
			Time: "yesterday", // 查询昨天00:00:00时刻的24小时统计
		},
	}

	fmt.Printf("查询语句: %s\n", gpuQuery)
	fmt.Printf("查询时间: yesterday (昨天 00:00:00)\n")

	gpuResponse, err := client.QueryWithTimeRange(ctx, gpuQueryConfig.Query, gpuQueryConfig.TimeRange)
	if err != nil {
		fmt.Printf("GPU查询失败: %v\n", err)
	} else {
		fmt.Printf("GPU查询成功，结果类型: %s\n", gpuResponse.Data.ResultType)

		// 尝试解析结果
		if vectorResult, err := gpuResponse.ParseVectorResult(); err == nil {
			fmt.Printf("返回 %d 个GPU利用率记录\n", len(vectorResult))

			// 显示前3条记录作为示例
			for i, sample := range vectorResult {
				if i >= 3 {
					fmt.Printf("... (还有 %d 条记录)\n", len(vectorResult)-3)
					break
				}

				fmt.Printf("记录 %d:\n", i+1)
				fmt.Printf("  指标: %v\n", sample.Metric)
				fmt.Printf("  值: %v\n", sample.Value)
			}
		}
	}
}
