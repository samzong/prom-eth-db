package timeparser

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

// RelativeTimeParser parses relative time expressions
type RelativeTimeParser struct {
	now time.Time
}

// NewRelativeTimeParser creates a new time parser with the given reference time
func NewRelativeTimeParser(now time.Time) *RelativeTimeParser {
	return &RelativeTimeParser{now: now}
}

// Parse parses a relative time expression and returns the absolute time
func (p *RelativeTimeParser) Parse(expr string) (time.Time, error) {
	if expr == "" {
		return p.now, nil
	}

	expr = strings.TrimSpace(expr)

	// Handle "now"
	if expr == "now" {
		return p.now, nil
	}

	// Handle "yesterday" expressions
	if strings.HasPrefix(expr, "yesterday") {
		return p.parseYesterday(expr)
	}

	// Handle "today" expressions
	if strings.HasPrefix(expr, "today") {
		return p.parseToday(expr)
	}

	// Handle relative time expressions like "-1d", "-2h", etc.
	if strings.HasPrefix(expr, "-") || strings.HasPrefix(expr, "+") {
		return p.parseRelative(expr)
	}

	return time.Time{}, fmt.Errorf("unsupported time expression: %s", expr)
}

// parseYesterday handles yesterday expressions
func (p *RelativeTimeParser) parseYesterday(expr string) (time.Time, error) {
	// Calculate yesterday's date
	yesterday := p.now.AddDate(0, 0, -1)

	// Extract time part if specified
	timePart := strings.TrimPrefix(expr, "yesterday")

	if timePart == "" {
		// Default to yesterday 00:00:00
		return time.Date(yesterday.Year(), yesterday.Month(), yesterday.Day(), 0, 0, 0, 0, p.now.Location()), nil
	}

	// Handle @time format: yesterday@00:00, yesterday@23:59:59
	if strings.HasPrefix(timePart, "@") {
		timeStr := strings.TrimPrefix(timePart, "@")
		return p.parseTimeWithDate(yesterday, timeStr)
	}

	return time.Time{}, fmt.Errorf("invalid yesterday expression: %s", expr)
}

// parseToday handles today expressions
func (p *RelativeTimeParser) parseToday(expr string) (time.Time, error) {
	// Extract time part if specified
	timePart := strings.TrimPrefix(expr, "today")

	if timePart == "" {
		// Default to today 00:00:00
		return time.Date(p.now.Year(), p.now.Month(), p.now.Day(), 0, 0, 0, 0, p.now.Location()), nil
	}

	// Handle @time format: today@00:00, today@23:59:59
	if strings.HasPrefix(timePart, "@") {
		timeStr := strings.TrimPrefix(timePart, "@")
		return p.parseTimeWithDate(p.now, timeStr)
	}

	return time.Time{}, fmt.Errorf("invalid today expression: %s", expr)
}

// parseTimeWithDate parses time string and applies it to a given date
func (p *RelativeTimeParser) parseTimeWithDate(date time.Time, timeStr string) (time.Time, error) {
	// Support formats: "00:00", "23:59:59", "12:30"
	parts := strings.Split(timeStr, ":")
	if len(parts) < 2 || len(parts) > 3 {
		return time.Time{}, fmt.Errorf("invalid time format: %s", timeStr)
	}

	hour := 0
	minute := 0
	second := 0

	if len(parts) >= 1 {
		if h, err := parseInt(parts[0]); err == nil {
			hour = h
		} else {
			return time.Time{}, fmt.Errorf("invalid hour: %s", parts[0])
		}
	}

	if len(parts) >= 2 {
		if m, err := parseInt(parts[1]); err == nil {
			minute = m
		} else {
			return time.Time{}, fmt.Errorf("invalid minute: %s", parts[1])
		}
	}

	if len(parts) >= 3 {
		if s, err := parseInt(parts[2]); err == nil {
			second = s
		} else {
			return time.Time{}, fmt.Errorf("invalid second: %s", parts[2])
		}
	}

	return time.Date(date.Year(), date.Month(), date.Day(), hour, minute, second, 0, p.now.Location()), nil
}

// parseRelative handles relative time expressions
func (p *RelativeTimeParser) parseRelative(expr string) (time.Time, error) {
	// Parse expressions like "-1d", "+2h", "-30m", etc.
	re := regexp.MustCompile(`^([+-])(\d+)([dhms])$`)
	matches := re.FindStringSubmatch(expr)

	if len(matches) != 4 {
		return time.Time{}, fmt.Errorf("invalid relative time expression: %s", expr)
	}

	sign := matches[1]
	value := matches[2]
	unit := matches[3]

	// Parse the numeric value
	val, err := parseInt(value)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid number in expression: %s", value)
	}

	// Calculate the duration
	var duration time.Duration
	switch unit {
	case "d":
		duration = time.Duration(val) * 24 * time.Hour
	case "h":
		duration = time.Duration(val) * time.Hour
	case "m":
		duration = time.Duration(val) * time.Minute
	case "s":
		duration = time.Duration(val) * time.Second
	default:
		return time.Time{}, fmt.Errorf("unsupported time unit: %s", unit)
	}

	// Apply the duration
	if sign == "-" {
		return p.now.Add(-duration), nil
	} else {
		return p.now.Add(duration), nil
	}
}

// parseInt is a helper function to parse integers
func parseInt(s string) (int, error) {
	var result int
	_, err := fmt.Sscanf(s, "%d", &result)
	return result, err
}
