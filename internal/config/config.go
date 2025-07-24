package config

import (
	"database/sql"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/samzong/prom-etl-db/internal/models"
)

// LoadConfig loads configuration from environment variables only (no queries)
func LoadConfig() (*models.Config, error) {
	config := &models.Config{}

	// Load from environment variables first
	if err := loadFromEnv(config); err != nil {
		return nil, fmt.Errorf("failed to load config from env: %w", err)
	}

	// Initialize empty queries slice - will be loaded from database later
	config.Queries = []models.QueryConfig{}

	return config, nil
}

// LoadConfigWithDB loads configuration from environment variables and database
func LoadConfigWithDB(db *sql.DB) (*models.Config, error) {
	config := &models.Config{}

	// Load from environment variables first
	if err := loadFromEnv(config); err != nil {
		return nil, fmt.Errorf("failed to load config from env: %w", err)
	}

	// Load queries from database
	queries, err := LoadQueriesFromDB(db)
	if err != nil {
		return nil, fmt.Errorf("failed to load queries from database: %w", err)
	}
	config.Queries = queries

	// Validate configuration
	if err := validateConfig(config); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return config, nil
}

// loadFromEnv loads configuration from environment variables
func loadFromEnv(config *models.Config) error {
	// Prometheus configuration
	config.Prometheus.URL = getEnvOrDefault("PROMETHEUS_URL", "http://localhost:9090")
	config.Prometheus.Timeout = getEnvOrDefault("PROMETHEUS_TIMEOUT", "30s")

	// MySQL configuration
	config.MySQL.Host = getEnvOrDefault("MYSQL_HOST", "localhost")
	config.MySQL.Port = getEnvIntOrDefault("MYSQL_PORT", 3306)
	config.MySQL.Database = getEnvOrDefault("MYSQL_DATABASE", "prometheus_data")
	config.MySQL.Username = getEnvOrDefault("MYSQL_USERNAME", "root")
	config.MySQL.Password = getEnvOrDefault("MYSQL_PASSWORD", "password")
	config.MySQL.Charset = getEnvOrDefault("MYSQL_CHARSET", "utf8mb4")

	// App configuration
	config.App.LogLevel = getEnvOrDefault("LOG_LEVEL", "info")
	config.App.HTTPPort = getEnvIntOrDefault("HTTP_PORT", 8080)
	config.App.WorkerPool = getEnvIntOrDefault("WORKER_POOL_SIZE", 10)

	return nil
}

// loadQueriesFromFile loads queries configuration from YAML file (unused)
// func loadQueriesFromFile(config *models.Config, configFile string) error {
//	viper.SetConfigFile(configFile)
//	viper.SetConfigType("yaml")
//
//	if err := viper.ReadInConfig(); err != nil {
//		return fmt.Errorf("failed to read config file: %w", err)
//	}
//
//	var fileConfig struct {
//		Queries []models.QueryConfig `yaml:"queries"`
//	}
//
//	if err := viper.Unmarshal(&fileConfig); err != nil {
//		return fmt.Errorf("failed to unmarshal config: %w", err)
//	}
//
//	config.Queries = fileConfig.Queries
//	return nil
// }

// validateConfig validates the configuration
func validateConfig(config *models.Config) error {
	if config.Prometheus.URL == "" {
		return fmt.Errorf("prometheus URL is required")
	}

	if config.MySQL.Host == "" {
		return fmt.Errorf("mysql host is required")
	}

	if config.MySQL.Database == "" {
		return fmt.Errorf("mysql database is required")
	}

	if config.MySQL.Username == "" {
		return fmt.Errorf("mysql username is required")
	}

	// Validate queries
	for i, query := range config.Queries {
		if query.ID == "" {
			return fmt.Errorf("query[%d]: ID is required", i)
		}
		if query.Query == "" {
			return fmt.Errorf("query[%d]: query is required", i)
		}
	}

	return nil
}

// getEnvOrDefault returns environment variable value or default
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvIntOrDefault returns environment variable as int or default
func getEnvIntOrDefault(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

// GetMySQLDSN returns MySQL DSN string
func GetMySQLDSN(config *models.MySQLConfig) string {
	return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?charset=%s&parseTime=true&loc=Local",
		config.Username,
		config.Password,
		config.Host,
		config.Port,
		config.Database,
		config.Charset,
	)
}

// GetDefaultQueries returns default queries for MVP
func GetDefaultQueries() []models.QueryConfig {
	return []models.QueryConfig{
		{
			ID:            "up_status",
			Name:          "Service Status",
			Description:   "Monitor service availability",
			Query:         "up",
			Schedule:      "*/30 * * * * *", // Every 30 seconds
			Timeout:       "15s",
			Enabled:       true,
			RetryCount:    2,
			RetryInterval: "5s",
		},
	}
}

// PrintConfig prints configuration (without sensitive data)
func PrintConfig(config *models.Config) {
	fmt.Printf("=== Configuration ===\n")
	fmt.Printf("Prometheus URL: %s\n", config.Prometheus.URL)
	fmt.Printf("Prometheus Timeout: %s\n", config.Prometheus.Timeout)
	fmt.Printf("MySQL Host: %s:%d\n", config.MySQL.Host, config.MySQL.Port)
	fmt.Printf("MySQL Database: %s\n", config.MySQL.Database)
	fmt.Printf("MySQL Username: %s\n", config.MySQL.Username)
	fmt.Printf("MySQL Password: %s\n", strings.Repeat("*", len(config.MySQL.Password)))
	fmt.Printf("Log Level: %s\n", config.App.LogLevel)
	fmt.Printf("HTTP Port: %d\n", config.App.HTTPPort)
	fmt.Printf("Worker Pool: %d\n", config.App.WorkerPool)
	fmt.Printf("Queries Count: %d\n", len(config.Queries))
	fmt.Printf("=====================\n")
}
