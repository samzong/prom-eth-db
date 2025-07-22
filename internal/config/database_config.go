package config

import (
	"database/sql"
	"encoding/json"
	"fmt"

	"github.com/samzong/prom-etl-db/internal/models"
)

// LoadQueriesFromDB loads query configurations from the database
func LoadQueriesFromDB(db *sql.DB) ([]models.QueryConfig, error) {
	query := `
		SELECT 
			query_id, name, description, query, schedule, timeout, 
			table_name, tags, enabled, retry_count, retry_interval,
			time_range_type, time_range_start, time_range_end, time_range_step
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
		var tagsJSON sql.NullString
		var retryInterval string
		var timeRangeType, timeRangeStart, timeRangeEnd, timeRangeStep sql.NullString

		err := rows.Scan(
			&config.ID,
			&config.Name,
			&config.Description,
			&config.Query,
			&config.Schedule,
			&config.Timeout,
			&config.Table,
			&tagsJSON,
			&config.Enabled,
			&config.RetryCount,
			&retryInterval,
			&timeRangeType,
			&timeRangeStart,
			&timeRangeEnd,
			&timeRangeStep,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan configuration row: %w", err)
		}

		// Parse tags JSON
		if tagsJSON.Valid {
			var tags []string
			if err := json.Unmarshal([]byte(tagsJSON.String), &tags); err != nil {
				return nil, fmt.Errorf("failed to parse tags JSON: %w", err)
			}
			config.Tags = tags
		}

		// Set retry interval as string
		config.RetryInterval = retryInterval

		// Parse time range configuration
		if timeRangeType.Valid && timeRangeType.String != "" {
			config.TimeRange = &models.TimeRangeConfig{
				Type: timeRangeType.String,
			}
			
			if timeRangeStart.Valid {
				config.TimeRange.Start = timeRangeStart.String
			}
			
			if timeRangeEnd.Valid {
				config.TimeRange.End = timeRangeEnd.String
			}
			
			if timeRangeStep.Valid {
				config.TimeRange.Step = timeRangeStep.String
			}
		}

		configs = append(configs, config)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating over rows: %w", err)
	}

	return configs, nil
}

// SaveQueryToDB saves or updates a query configuration in the database
func SaveQueryToDB(db *sql.DB, config *models.QueryConfig) error {
	tagsJSON, err := json.Marshal(config.Tags)
	if err != nil {
		return fmt.Errorf("failed to marshal tags: %w", err)
	}

	query := `
		INSERT INTO query_configs (
			query_id, name, description, query, schedule, timeout, 
			table_name, tags, enabled, retry_count, retry_interval,
			time_range_type, time_range_start, time_range_end, time_range_step
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE 
			name = VALUES(name),
			description = VALUES(description),
			query = VALUES(query),
			schedule = VALUES(schedule),
			timeout = VALUES(timeout),
			table_name = VALUES(table_name),
			tags = VALUES(tags),
			enabled = VALUES(enabled),
			retry_count = VALUES(retry_count),
			retry_interval = VALUES(retry_interval),
			time_range_type = VALUES(time_range_type),
			time_range_start = VALUES(time_range_start),
			time_range_end = VALUES(time_range_end),
			time_range_step = VALUES(time_range_step),
			updated_at = CURRENT_TIMESTAMP
	`

	// Prepare time range values
	var timeRangeType, timeRangeStart, timeRangeEnd, timeRangeStep interface{}
	if config.TimeRange != nil {
		timeRangeType = config.TimeRange.Type
		timeRangeStart = config.TimeRange.Start
		timeRangeEnd = config.TimeRange.End
		timeRangeStep = config.TimeRange.Step
	}

	_, err = db.Exec(query,
		config.ID,
		config.Name,
		config.Description,
		config.Query,
		config.Schedule,
		config.Timeout,
		config.Table,
		string(tagsJSON),
		config.Enabled,
		config.RetryCount,
		config.RetryInterval,
		timeRangeType,
		timeRangeStart,
		timeRangeEnd,
		timeRangeStep,
	)

	if err != nil {
		return fmt.Errorf("failed to save configuration: %w", err)
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
