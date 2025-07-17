package executor

import (
	"context"
	"fmt"
	"log/slog"
	"strconv"
	"time"

	"github.com/samzong/prom-etl-db/internal/database"
	"github.com/samzong/prom-etl-db/internal/logger"
	"github.com/samzong/prom-etl-db/internal/models"
	"github.com/samzong/prom-etl-db/internal/prometheus"
)

// Executor handles query execution and data storage
type Executor struct {
	promClient *prometheus.Client
	db         *database.DB
	logger     *slog.Logger
}

// NewExecutor creates a new query executor
func NewExecutor(promClient *prometheus.Client, db *database.DB, baseLogger *slog.Logger) *Executor {
	return &Executor{
		promClient: promClient,
		db:         db,
		logger:     logger.WithComponent(baseLogger, "executor"),
	}
}

// ExecuteQuery executes a single query and stores the results
func (e *Executor) ExecuteQuery(ctx context.Context, queryConfig *models.QueryConfig) error {
	startTime := time.Now()
	queryLogger := logger.WithQueryID(e.logger, queryConfig.ID)
	
	// Create query execution record
	execution := &models.QueryExecution{
		QueryID:   queryConfig.ID,
		QueryName: queryConfig.Name,
		Status:    "running",
		StartTime: startTime,
		CreatedAt: startTime,
	}

	queryLogger.Info("Starting query execution",
		"query", queryConfig.Query,
		"name", queryConfig.Name,
	)

	// Execute Prometheus query
	response, err := e.promClient.QueryInstant(ctx, queryConfig.Query)
	if err != nil {
		// Record failure
		execution.Status = "failed"
		endTime := time.Now()
		execution.EndTime = &endTime
		duration := endTime.Sub(startTime).Milliseconds()
		execution.DurationMs = &duration
		errorMsg := err.Error()
		execution.ErrorMessage = &errorMsg

		// Log error
		logger.WithError(queryLogger, err).Error("Query execution failed")

		// Store execution record
		if dbErr := e.db.InsertQueryExecution(execution); dbErr != nil {
			logger.WithError(queryLogger, dbErr).Error("Failed to store execution record")
		}

		return fmt.Errorf("failed to execute query: %w", err)
	}

	// Parse vector result
	vectorResult, err := response.ParseVectorResult()
	if err != nil {
		// Record failure
		execution.Status = "failed"
		endTime := time.Now()
		execution.EndTime = &endTime
		duration := endTime.Sub(startTime).Milliseconds()
		execution.DurationMs = &duration
		errorMsg := err.Error()
		execution.ErrorMessage = &errorMsg

		logger.WithError(queryLogger, err).Error("Failed to parse query result")

		// Store execution record
		if dbErr := e.db.InsertQueryExecution(execution); dbErr != nil {
			logger.WithError(queryLogger, dbErr).Error("Failed to store execution record")
		}

		return fmt.Errorf("failed to parse query result: %w", err)
	}

	// Convert to metric records
	var metricRecords []*models.MetricRecord
	for _, sample := range vectorResult {
		record, err := e.convertSampleToRecord(&sample, queryConfig.ID)
		if err != nil {
			logger.WithError(queryLogger, err).Warn("Failed to convert sample to record, skipping")
			continue
		}
		metricRecords = append(metricRecords, record)
	}

	// Store metric records
	if len(metricRecords) > 0 {
		if err := e.db.InsertMetricRecords(metricRecords); err != nil {
			// Record failure
			execution.Status = "failed"
			endTime := time.Now()
			execution.EndTime = &endTime
			duration := endTime.Sub(startTime).Milliseconds()
			execution.DurationMs = &duration
			errorMsg := err.Error()
			execution.ErrorMessage = &errorMsg

			logger.WithError(queryLogger, err).Error("Failed to store metric records")

			// Store execution record
			if dbErr := e.db.InsertQueryExecution(execution); dbErr != nil {
				logger.WithError(queryLogger, dbErr).Error("Failed to store execution record")
			}

			return fmt.Errorf("failed to store metric records: %w", err)
		}
	}

	// Record success
	execution.Status = "success"
	endTime := time.Now()
	execution.EndTime = &endTime
	duration := endTime.Sub(startTime).Milliseconds()
	execution.DurationMs = &duration
	execution.RecordsCount = len(metricRecords)

	// Store execution record
	if err := e.db.InsertQueryExecution(execution); err != nil {
		logger.WithError(queryLogger, err).Error("Failed to store execution record")
	}

	// Log success
	logger.WithDuration(
		logger.WithCount(queryLogger, len(metricRecords)),
		duration,
	).Info("Query execution completed successfully")

	return nil
}

// convertSampleToRecord converts a VectorSample to MetricRecord
func (e *Executor) convertSampleToRecord(sample *models.VectorSample, queryID string) (*models.MetricRecord, error) {
	// Extract metric name
	metricName := sample.Metric["__name__"]
	if metricName == "" {
		metricName = queryID
	}

	// Parse timestamp and value
	if len(sample.Value) != 2 {
		return nil, fmt.Errorf("invalid sample value format")
	}

	timestamp, ok := sample.Value[0].(float64)
	if !ok {
		return nil, fmt.Errorf("invalid timestamp format")
	}

	valueStr, ok := sample.Value[1].(string)
	if !ok {
		return nil, fmt.Errorf("invalid value format")
	}

	// Convert string value to float64
	value, err := strconv.ParseFloat(valueStr, 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse value: %w", err)
	}

	// Clean labels (remove internal labels)
	labels := make(map[string]interface{})
	for k, v := range sample.Metric {
		if k != "__name__" {
			labels[k] = v
		}
	}

	return &models.MetricRecord{
		QueryID:     queryID,
		MetricName:  metricName,
		Labels:      labels,
		Value:       value,
		Timestamp:   time.Unix(int64(timestamp), 0),
		ResultType:  "instant",
		CollectedAt: time.Now(),
	}, nil
}

// ExecuteQueryWithRetry executes a query with retry logic
func (e *Executor) ExecuteQueryWithRetry(ctx context.Context, queryConfig *models.QueryConfig) error {
	var lastErr error
	
	for attempt := 0; attempt <= queryConfig.RetryCount; attempt++ {
		if attempt > 0 {
			// Parse retry interval
			retryInterval, err := time.ParseDuration(queryConfig.RetryInterval)
			if err != nil {
				retryInterval = 5 * time.Second
			}

			e.logger.Info("Retrying query execution",
				"query_id", queryConfig.ID,
				"attempt", attempt,
				"retry_interval", retryInterval,
			)

			// Wait before retry
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(retryInterval):
			}
		}

		// Execute query
		if err := e.ExecuteQuery(ctx, queryConfig); err != nil {
			lastErr = err
			continue
		}

		// Success
		return nil
	}

	return fmt.Errorf("query failed after %d attempts: %w", queryConfig.RetryCount+1, lastErr)
}

// TestConnections tests both Prometheus and MySQL connections
func (e *Executor) TestConnections(ctx context.Context) error {
	// Test Prometheus connection
	if err := e.promClient.TestConnection(ctx); err != nil {
		return fmt.Errorf("prometheus connection test failed: %w", err)
	}

	// Test MySQL connection
	if err := e.db.TestConnection(); err != nil {
		return fmt.Errorf("mysql connection test failed: %w", err)
	}

	e.logger.Info("All connections tested successfully")
	return nil
} 