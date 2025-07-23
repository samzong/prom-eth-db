package timeparser

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// RelativeTimeParser Grafana风格的时间解析器
type RelativeTimeParser struct {
	baseTime time.Time
	location *time.Location
}

// NewRelativeTimeParser 创建新的相对时间解析器
func NewRelativeTimeParser(baseTime time.Time) *RelativeTimeParser {
	// 默认使用 CST 时区 (中国标准时间)
	location := time.FixedZone("CST", 8*3600) // UTC+8

	return &RelativeTimeParser{
		baseTime: baseTime,
		location: location,
	}
}

// SetLocation 设置时区
func (p *RelativeTimeParser) SetLocation(location *time.Location) {
	p.location = location
}

// Parse 解析Grafana风格的时间表达式
func (p *RelativeTimeParser) Parse(timeExpr string) (time.Time, error) {
	if timeExpr == "" {
		return p.baseTime, nil
	}

	// 转换为小写以便处理
	expr := strings.TrimSpace(strings.ToLower(timeExpr))

	// 处理特殊关键词
	switch expr {
	case "now":
		return p.baseTime.In(p.location), nil
	}

	// 处理Grafana格式的时间表达式 (如: now-1d/d, now/d, now-1h, etc.)
	return p.parseGrafanaTime(expr)
}

// parseGrafanaTime 解析Grafana风格时间表达式
// 支持格式：
// - now-1d/d (昨天开始)
// - now/d (今天开始)
// - now-1h (1小时前)
// - now-30m (30分钟前)
func (p *RelativeTimeParser) parseGrafanaTime(expr string) (time.Time, error) {
	baseTime := p.baseTime.In(p.location)

	// 处理 /d 后缀 (日期截断到当天开始)
	if strings.HasSuffix(expr, "/d") {
		// 移除 /d 后缀
		expr = strings.TrimSuffix(expr, "/d")

		// 解析基础时间
		t, err := p.parseBasicGrafanaExpr(expr, baseTime)
		if err != nil {
			return time.Time{}, err
		}

		// 截断到当天开始 (00:00:00)
		return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, p.location), nil
	}

	// 处理普通的相对时间表达式
	return p.parseBasicGrafanaExpr(expr, baseTime)
}

// parseBasicGrafanaExpr 解析基础的Grafana表达式
func (p *RelativeTimeParser) parseBasicGrafanaExpr(expr string, baseTime time.Time) (time.Time, error) {
	// 处理 "now" 关键字
	if expr == "now" {
		return baseTime, nil
	}

	// 匹配 now+1d, now-1d, now-2h, now+30m 等格式
	re := regexp.MustCompile(`^now([+-])(\d+)([smhdwMy])$`)
	matches := re.FindStringSubmatch(expr)

	if len(matches) != 4 {
		return time.Time{}, fmt.Errorf("unsupported time expression: %s", expr)
	}

	sign := matches[1]
	valueStr := matches[2]
	unit := matches[3]

	value, err := strconv.Atoi(valueStr)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid number in time expression: %s", valueStr)
	}

	// 处理符号
	if sign == "-" {
		value = -value
	}

	// 根据单位计算时间
	switch unit {
	case "s": // 秒
		return baseTime.Add(time.Duration(value) * time.Second), nil
	case "m": // 分钟
		return baseTime.Add(time.Duration(value) * time.Minute), nil
	case "h": // 小时
		return baseTime.Add(time.Duration(value) * time.Hour), nil
	case "d": // 天
		return baseTime.AddDate(0, 0, value), nil
	case "w": // 周
		return baseTime.AddDate(0, 0, value*7), nil
	case "M": // 月
		return baseTime.AddDate(0, value, 0), nil
	case "y": // 年
		return baseTime.AddDate(value, 0, 0), nil
	default:
		return time.Time{}, fmt.Errorf("unsupported time unit: %s", unit)
	}
}

// GetYesterdayRange 获取昨天的时间范围 (00:00:00 到 23:59:59)
func (p *RelativeTimeParser) GetYesterdayRange() (start, end time.Time) {
	// 使用Grafana格式
	start, _ = p.Parse("now-1d/d") // 昨天00:00:00
	end, _ = p.Parse("now/d")      // 今天00:00:00

	return start, end
}

// GetTodayRange 获取今天的时间范围 (00:00:00 到 23:59:59)
func (p *RelativeTimeParser) GetTodayRange() (start, end time.Time) {
	start, _ = p.Parse("now/d")  // 今天00:00:00
	end, _ = p.Parse("now+1d/d") // 明天00:00:00

	return start, end
}
