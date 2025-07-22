package logger

import (
	"log/slog"
	"os"
	"strings"
)

// Logger levels
const (
	LevelDebug = "debug"
	LevelInfo  = "info"
	LevelWarn  = "warn"
	LevelError = "error"
)

// NewLogger creates a new structured logger
func NewLogger(level string) *slog.Logger {
	var logLevel slog.Level

	switch strings.ToLower(level) {
	case LevelDebug:
		logLevel = slog.LevelDebug
	case LevelInfo:
		logLevel = slog.LevelInfo
	case LevelWarn:
		logLevel = slog.LevelWarn
	case LevelError:
		logLevel = slog.LevelError
	default:
		logLevel = slog.LevelInfo
	}

	// Create handler with JSON format
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level:     logLevel,
		AddSource: true,
	})

	return slog.New(handler)
}

// WithComponent adds component field to logger
func WithComponent(logger *slog.Logger, component string) *slog.Logger {
	return logger.With("component", component)
}

// WithQueryID adds query_id field to logger
func WithQueryID(logger *slog.Logger, queryID string) *slog.Logger {
	return logger.With("query_id", queryID)
}

// WithDuration adds duration field to logger
func WithDuration(logger *slog.Logger, duration int64) *slog.Logger {
	return logger.With("duration_ms", duration)
}

// WithError adds error field to logger
func WithError(logger *slog.Logger, err error) *slog.Logger {
	return logger.With("error", err.Error())
}

// WithCount adds count field to logger
func WithCount(logger *slog.Logger, count int) *slog.Logger {
	return logger.With("count", count)
}
