package config

import (
	"database/sql"
	"fmt"

	"github.com/samzong/prom-etl-db/internal/models"
)

// LoadQueriesFromDB loads query configurations from the database
func LoadQueriesFromDB(db *sql.DB) ([]models.QueryConfig, error) {
	query := `
		SELECT 
			query_id, name, description, query, schedule, timeout, 
			enabled, retry_count, retry_interval,
			time_range_type, time_range_time, time_range_start, time_range_end, time_range_step
		FROM query_configs 
		WHERE enabled = 1 
		ORDER BY created_at
	`

	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("failed to query configurations: %w", err)
	}
	defer rows.Close()

	var configs []models.QueryConfig
	for rows.Next() {
		var config models.QueryConfig
		var retryInterval string
		var timeRangeType sql.NullString
		var timeRangeTime sql.NullString
		var timeRangeStart sql.NullString
		var timeRangeEnd sql.NullString
		var timeRangeStep sql.NullString

		err := rows.Scan(
			&config.ID,
			&config.Name,
			&config.Description,
			&config.Query,
			&config.Schedule,
			&config.Timeout,
			&config.Enabled,
			&config.RetryCount,
			&retryInterval,
			&timeRangeType,
			&timeRangeTime,
			&timeRangeStart,
			&timeRangeEnd,
			&timeRangeStep,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan configuration row: %w", err)
		}

		// Set retry interval as string
		config.RetryInterval = retryInterval

		// Build TimeRange configuration if any time range fields are set
		if timeRangeType.Valid && timeRangeType.String != "" {
			timeRange := &models.TimeRangeConfig{
				Type: timeRangeType.String,
			}

			if timeRangeTime.Valid {
				timeRange.Time = timeRangeTime.String
			}
			if timeRangeStart.Valid {
				timeRange.Start = timeRangeStart.String
			}
			if timeRangeEnd.Valid {
				timeRange.End = timeRangeEnd.String
			}
			if timeRangeStep.Valid {
				timeRange.Step = timeRangeStep.String
			}

			config.TimeRange = timeRange
		}

		configs = append(configs, config)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating over rows: %w", err)
	}

	return configs, nil
}

// SaveQueryToDB saves a query configuration to the database
func SaveQueryToDB(db *sql.DB, config models.QueryConfig) error {
	var timeRangeType, timeRangeTime, timeRangeStart, timeRangeEnd, timeRangeStep sql.NullString

	if config.TimeRange != nil {
		timeRangeType = sql.NullString{String: config.TimeRange.Type, Valid: true}
		if config.TimeRange.Time != "" {
			timeRangeTime = sql.NullString{String: config.TimeRange.Time, Valid: true}
		}
		if config.TimeRange.Start != "" {
			timeRangeStart = sql.NullString{String: config.TimeRange.Start, Valid: true}
		}
		if config.TimeRange.End != "" {
			timeRangeEnd = sql.NullString{String: config.TimeRange.End, Valid: true}
		}
		if config.TimeRange.Step != "" {
			timeRangeStep = sql.NullString{String: config.TimeRange.Step, Valid: true}
		}
	}

	query := `
		INSERT INTO query_configs (
			query_id, name, description, query, schedule, timeout, 
			enabled, retry_count, retry_interval,
			time_range_type, time_range_time, time_range_start, time_range_end, time_range_step
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			name = VALUES(name),
			description = VALUES(description),
			query = VALUES(query),
			schedule = VALUES(schedule),
			timeout = VALUES(timeout),
			enabled = VALUES(enabled),
			retry_count = VALUES(retry_count),
			retry_interval = VALUES(retry_interval),
			time_range_type = VALUES(time_range_type),
			time_range_time = VALUES(time_range_time),
			time_range_start = VALUES(time_range_start),
			time_range_end = VALUES(time_range_end),
			time_range_step = VALUES(time_range_step),
			updated_at = CURRENT_TIMESTAMP
	`

	_, err := db.Exec(query,
		config.ID,
		config.Name,
		config.Description,
		config.Query,
		config.Schedule,
		config.Timeout,
		config.Enabled,
		config.RetryCount,
		config.RetryInterval,
		timeRangeType,
		timeRangeTime,
		timeRangeStart,
		timeRangeEnd,
		timeRangeStep,
	)

	if err != nil {
		return fmt.Errorf("failed to save query configuration: %w", err)
	}

	return nil
}

// DeleteQueryFromDB deletes a query configuration from the database
func DeleteQueryFromDB(db *sql.DB, queryID string) error {
	query := `DELETE FROM query_configs WHERE query_id = ?`

	result, err := db.Exec(query, queryID)
	if err != nil {
		return fmt.Errorf("failed to delete configuration: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("no configuration found with query_id: %s", queryID)
	}

	return nil
}

// ToggleQueryEnabled enables or disables a query configuration
func ToggleQueryEnabled(db *sql.DB, queryID string, enabled bool) error {
	query := `UPDATE query_configs SET enabled = ?, updated_at = CURRENT_TIMESTAMP WHERE query_id = ?`

	result, err := db.Exec(query, enabled, queryID)
	if err != nil {
		return fmt.Errorf("failed to update configuration: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("no configuration found with query_id: %s", queryID)
	}

	return nil
}
