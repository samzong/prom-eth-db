# Prometheus to MySQL ETL

A Go-based ETL tool that collects Prometheus metrics and stores them in MySQL database with scheduled execution.

## Features

- Scheduled metric collection using cron expressions
- Multiple PromQL query support with instant and range queries
- Unified storage in MySQL with JSON labels
- Database-driven query configuration
- Retry mechanism with configurable intervals
- Relative time parsing for flexible time ranges
- Transaction-based batch inserts

## Quick Start

### Prerequisites

- Go 1.21+
- MySQL 8.0+
- Docker & Docker Compose (optional)

### Configuration

Copy environment template:

```bash
cp env.example .env
```

Configure environment variables:

```bash
# Prometheus Configuration
PROMETHEUS_URL=http://localhost:9090
PROMETHEUS_TIMEOUT=30s

# MySQL Configuration
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_DATABASE=prometheus_data
MYSQL_USERNAME=root
MYSQL_PASSWORD=password

# Application Configuration
LOG_LEVEL=info
WORKER_POOL_SIZE=10
```

### Database Setup

Initialize database schema:

```bash
mysql -u root -p prometheus_data < scripts/migrate.sql
```

### Running

#### Docker Compose

```bash
docker-compose up -d
```

#### Local Development

```bash
go mod download
go run cmd/server/main.go
```

## Configuration

### Environment Variables

| Variable             | Description           | Default           |
| -------------------- | --------------------- | ----------------- |
| `PROMETHEUS_URL`     | Prometheus server URL | -                 |
| `PROMETHEUS_TIMEOUT` | Query timeout         | `30s`             |
| `MYSQL_HOST`         | MySQL host            | `localhost`       |
| `MYSQL_PORT`         | MySQL port            | `3306`            |
| `MYSQL_DATABASE`     | Database name         | `prometheus_data` |
| `MYSQL_USERNAME`     | Database username     | `root`            |
| `MYSQL_PASSWORD`     | Database password     | -                 |
| `LOG_LEVEL`          | Log level             | `info`            |
| `WORKER_POOL_SIZE`   | Worker pool size      | `10`              |

### Query Configuration

Queries are stored in the `query_configs` table with the following structure:

- **query_id**: Unique identifier
- **name**: Human-readable name
- **query**: PromQL expression
- **schedule**: Cron expression (with seconds)
- **time_range_type**: `instant` or `range`
- **time_range_start/end**: Relative time expressions
- **enabled**: Boolean flag
- **retry_count**: Number of retries on failure

## Database Schema

### metrics_data

Stores all metric values with JSON labels:

```sql
CREATE TABLE metrics_data (
  id bigint AUTO_INCREMENT PRIMARY KEY,
  query_id varchar(100) NOT NULL,
  metric_name varchar(255) NOT NULL,
  labels json NOT NULL,
  value double NOT NULL,
  timestamp timestamp(3) NOT NULL,
  result_type enum('instant','range','scalar') NOT NULL,
  collected_at timestamp DEFAULT CURRENT_TIMESTAMP,
  KEY idx_query_id_timestamp (query_id, timestamp)
);
```

### query_executions

Tracks execution history and performance:

```sql
CREATE TABLE query_executions (
  id bigint AUTO_INCREMENT PRIMARY KEY,
  query_id varchar(100) NOT NULL,
  status enum('running','success','failed','timeout') NOT NULL,
  start_time timestamp(3) NOT NULL,
  end_time timestamp(3) NULL,
  duration_ms int NULL,
  records_count int DEFAULT 0,
  error_message text NULL
);
```

## Project Structure

```
prom-etl-db/
├── cmd/server/main.go              # Application entry point
├── internal/
│   ├── config/                     # Configuration management
│   ├── database/                   # MySQL operations
│   ├── executor/                   # Query execution logic
│   ├── logger/                     # Structured logging
│   ├── models/                     # Data models
│   ├── prometheus/                 # Prometheus client
│   └── timeparser/                 # Relative time parsing
├── scripts/migrate.sql             # Database schema
└── docker-compose.yaml             # Container orchestration
```

## Time Range Support

The tool supports flexible time range configurations:

### Instant Queries

```yaml
time_range_type: instant
time_range_time: "now-1h" # 1 hour ago
```

### Range Queries

```yaml
time_range_type: range
time_range_start: "now-1d/d" # Yesterday 00:00:00
time_range_end: "now/d" # Today 00:00:00
time_range_step: "1h" # 1 hour intervals
```

## Building

```bash
# Run tests
go test ./...

# Build binary
go build -o prom-etl-db cmd/server/main.go

# Build Docker image
docker build -t prom-etl-db .
```

## Dependencies

- `github.com/go-sql-driver/mysql` - MySQL driver
- `github.com/robfig/cron/v3` - Cron scheduler
- `github.com/spf13/viper` - Configuration management

## License

[MIT](LICENSE)
