package models

import (
	"encoding/json"
	"time"
)

// PrometheusResponse represents the response from Prometheus API
type PrometheusResponse struct {
	Status string     `json:"status"`
	Data   ResultData `json:"data"`
}

// ResultData represents the data part of Prometheus response
type ResultData struct {
	ResultType string      `json:"resultType"`
	Result     interface{} `json:"result"`
}

// VectorResult represents a vector query result
type VectorResult []VectorSample

// VectorSample represents a single sample in vector result
type VectorSample struct {
	Metric map[string]string `json:"metric"`
	Value  []interface{}     `json:"value"`
}

// MetricRecord represents a metric record to be stored in database
type MetricRecord struct {
	ID          int64                  `json:"id"`
	QueryID     string                 `json:"query_id"`
	MetricName  string                 `json:"metric_name"`
	Labels      map[string]interface{} `json:"labels"`
	Value       float64                `json:"value"`
	Timestamp   time.Time              `json:"timestamp"`
	ResultType  string                 `json:"result_type"`
	CollectedAt time.Time              `json:"collected_at"`
}

// QueryExecution represents a query execution record
type QueryExecution struct {
	ID           int64     `json:"id"`
	QueryID      string    `json:"query_id"`
	QueryName    string    `json:"query_name"`
	Status       string    `json:"status"`
	StartTime    time.Time `json:"start_time"`
	EndTime      *time.Time `json:"end_time,omitempty"`
	DurationMs   *int64    `json:"duration_ms,omitempty"`
	RecordsCount int       `json:"records_count"`
	ErrorMessage *string   `json:"error_message,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

// QueryConfig represents a query configuration
type QueryConfig struct {
	ID            string            `yaml:"id" json:"id"`
	Name          string            `yaml:"name" json:"name"`
	Description   string            `yaml:"description" json:"description"`
	Query         string            `yaml:"query" json:"query"`
	Schedule      string            `yaml:"schedule" json:"schedule"`
	Timeout       string            `yaml:"timeout" json:"timeout"`
	Table         string            `yaml:"table" json:"table"`
	Tags          []string          `yaml:"tags" json:"tags"`
	Enabled       bool              `yaml:"enabled" json:"enabled"`
	RetryCount    int               `yaml:"retry_count" json:"retry_count"`
	RetryInterval string            `yaml:"retry_interval" json:"retry_interval"`
}

// Config represents the application configuration
type Config struct {
	Prometheus PrometheusConfig `yaml:"prometheus" json:"prometheus"`
	MySQL      MySQLConfig      `yaml:"mysql" json:"mysql"`
	App        AppConfig        `yaml:"app" json:"app"`
	Queries    []QueryConfig    `yaml:"queries" json:"queries"`
}

// PrometheusConfig represents Prometheus configuration
type PrometheusConfig struct {
	URL     string `yaml:"url" json:"url"`
	Timeout string `yaml:"timeout" json:"timeout"`
}

// MySQLConfig represents MySQL configuration
type MySQLConfig struct {
	Host     string `yaml:"host" json:"host"`
	Port     int    `yaml:"port" json:"port"`
	Database string `yaml:"database" json:"database"`
	Username string `yaml:"username" json:"username"`
	Password string `yaml:"password" json:"password"`
	Charset  string `yaml:"charset" json:"charset"`
}

// AppConfig represents application configuration
type AppConfig struct {
	LogLevel   string `yaml:"log_level" json:"log_level"`
	HTTPPort   int    `yaml:"http_port" json:"http_port"`
	WorkerPool int    `yaml:"worker_pool" json:"worker_pool"`
}

// ParseVectorResult parses vector result from Prometheus response
func (pr *PrometheusResponse) ParseVectorResult() (VectorResult, error) {
	resultBytes, err := json.Marshal(pr.Data.Result)
	if err != nil {
		return nil, err
	}

	var vectorResult VectorResult
	err = json.Unmarshal(resultBytes, &vectorResult)
	if err != nil {
		return nil, err
	}

	return vectorResult, nil
}

// ToMetricRecord converts VectorSample to MetricRecord
func (vs *VectorSample) ToMetricRecord(queryID string) (*MetricRecord, error) {
	// Extract metric name
	metricName := vs.Metric["__name__"]
	if metricName == "" {
		metricName = queryID
	}

	// Parse timestamp and value
	timestamp := time.Unix(int64(vs.Value[0].(float64)), 0)
	value := vs.Value[1].(string)
	
	// Convert string value to float64
	var floatValue float64
	if err := json.Unmarshal([]byte(value), &floatValue); err != nil {
		return nil, err
	}

	// Clean labels (remove internal labels)
	labels := make(map[string]interface{})
	for k, v := range vs.Metric {
		if k != "__name__" {
			labels[k] = v
		}
	}

	return &MetricRecord{
		QueryID:     queryID,
		MetricName:  metricName,
		Labels:      labels,
		Value:       floatValue,
		Timestamp:   timestamp,
		ResultType:  "instant",
		CollectedAt: time.Now(),
	}, nil
} 