package timeparser

import (
	"testing"
	"time"
)

func TestGrafanaTimeParser(t *testing.T) {
	// 使用固定的基准时间: 2024-01-15 14:30:45 (Monday)
	baseTime := time.Date(2024, 1, 15, 14, 30, 45, 0, time.UTC)
	parser := NewRelativeTimeParser(baseTime)

	tests := []struct {
		name     string
		input    string
		expected func() time.Time
	}{
		{
			name:  "now",
			input: "now",
			expected: func() time.Time {
				return baseTime.In(parser.location)
			},
		},
		{
			name:  "now-1d/d (昨天开始)",
			input: "now-1d/d",
			expected: func() time.Time {
				return time.Date(2024, 1, 14, 0, 0, 0, 0, parser.location)
			},
		},
		{
			name:  "now/d (今天开始)",
			input: "now/d",
			expected: func() time.Time {
				return time.Date(2024, 1, 15, 0, 0, 0, 0, parser.location)
			},
		},
		{
			name:  "now-1h (1小时前)",
			input: "now-1h",
			expected: func() time.Time {
				return baseTime.Add(-1 * time.Hour).In(parser.location)
			},
		},
		{
			name:  "now-30m (30分钟前)",
			input: "now-30m",
			expected: func() time.Time {
				return baseTime.Add(-30 * time.Minute).In(parser.location)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := parser.Parse(tt.input)
			if err != nil {
				t.Errorf("Parse(%q) error = %v", tt.input, err)
				return
			}

			expected := tt.expected()
			if !result.Equal(expected) {
				t.Errorf("Parse(%q) = %v, expected %v", tt.input, result, expected)
			}
		})
	}
}

func TestGetYesterdayRange(t *testing.T) {
	// 使用固定的基准时间: 2024-01-15 14:30:45
	baseTime := time.Date(2024, 1, 15, 14, 30, 45, 0, time.UTC)
	parser := NewRelativeTimeParser(baseTime)

	start, end := parser.GetYesterdayRange()

	t.Logf("Yesterday range: %s to %s",
		start.Format("2006-01-02 15:04:05"),
		end.Format("2006-01-02 15:04:05"))

	// 验证start是昨天的00:00:00
	expectedStart := time.Date(2024, 1, 14, 0, 0, 0, 0, parser.location)
	if !start.Equal(expectedStart) {
		t.Errorf("Start time should be %v, got %v", expectedStart, start)
	}

	// 验证end是今天的00:00:00
	expectedEnd := time.Date(2024, 1, 15, 0, 0, 0, 0, parser.location)
	if !end.Equal(expectedEnd) {
		t.Errorf("End time should be %v, got %v", expectedEnd, end)
	}
}

func TestGrafanaTimeParserConsistency(t *testing.T) {
	// 测试在一天中的不同时间查询昨天，结果应该一致
	cst := time.FixedZone("CST", 8*3600)

	times := []time.Time{
		time.Date(2024, 1, 15, 0, 0, 0, 0, cst),    // 00:00:00 CST
		time.Date(2024, 1, 15, 12, 30, 0, 0, cst),  // 12:30:00 CST
		time.Date(2024, 1, 15, 23, 59, 59, 0, cst), // 23:59:59 CST
	}

	var expectedStart, expectedEnd time.Time

	for i, baseTime := range times {
		parser := NewRelativeTimeParser(baseTime)
		start, end := parser.GetYesterdayRange()

		if i == 0 {
			expectedStart, expectedEnd = start, end
		} else {
			if !start.Equal(expectedStart) || !end.Equal(expectedEnd) {
				t.Errorf("Yesterday range inconsistent at time %v: got (%v, %v), expected (%v, %v)",
					baseTime, start, end, expectedStart, expectedEnd)
			}
		}
	}

	t.Logf("Consistent yesterday range: %v to %v", expectedStart, expectedEnd)
}

func TestGrafanaTimeParserErrors(t *testing.T) {
	baseTime := time.Date(2024, 1, 15, 14, 30, 45, 0, time.UTC)
	parser := NewRelativeTimeParser(baseTime)

	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"valid now-1d", "now-1d", false},
		{"valid now-1h", "now-1h", false},
		{"valid now/d", "now/d", false},
		{"invalid format", "invalid", true},
		{"invalid number", "now-abc", true},
		{"invalid unit", "now-1z", true},
		{"missing now", "1d", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parser.Parse(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("Parse(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			}
		})
	}
}
