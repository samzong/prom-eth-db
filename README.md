# Prometheus to MySQL ETL

一个用 Golang 开发的 Prometheus 数据采集工具，将 Prometheus 指标数据定时采集并存储到 MySQL 数据库中。

## 功能特性

- 🔄 **定时采集**: 支持 Cron 表达式配置的定时任务
- 📊 **多查询支持**: 同时执行多个 PromQL 查询
- 💾 **统一存储**: 将不同格式的查询结果统一存储到 MySQL
- 🔧 **灵活配置**: 支持 YAML 配置文件和环境变量
- 📈 **监控集成**: 内置健康检查和指标暴露
- 🔄 **重试机制**: 支持查询失败重试和错误恢复
- 🐳 **容器化**: 完整的 Docker 部署支持

## 快速开始

### 1. 环境准备

确保您的环境中已安装：
- Go 1.21+
- MySQL 8.0+
- Docker & Docker Compose (可选)

### 2. 配置文件

复制环境变量模板：
```bash
cp env.example .env
```

编辑 `.env` 文件，配置您的 Prometheus 和 MySQL 连接信息：
```bash
# Prometheus 配置
PROMETHEUS_URL=http://10.20.100.200:30588/select/0/prometheus
PROMETHEUS_TIMEOUT=30s

# MySQL 配置
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_DATABASE=prometheus_data
MYSQL_USERNAME=root
MYSQL_PASSWORD=password
```

### 3. 数据库初始化

执行数据库迁移脚本：
```bash
mysql -u root -p prometheus_data < scripts/migrate.sql
```

### 4. 运行方式

#### 方式一：Docker Compose (推荐)
```bash
# 启动所有服务 (包括 MySQL 和 Adminer)
docker-compose -f configs/docker-compose.yaml up -d

# 查看日志
docker-compose -f configs/docker-compose.yaml logs -f prom-etl-db
```

#### 方式二：本地运行
```bash
# 安装依赖
go mod download

# 编译运行
go run cmd/server/main.go
```

### 5. 验证运行

- **健康检查**: http://localhost:8080/health
- **指标端点**: http://localhost:9090/metrics
- **数据库管理**: http://localhost:8081 (Adminer)

## 配置说明

### 查询配置 (configs/queries.yaml)

```yaml
queries:
  - id: "cpu_usage"
    name: "CPU 使用率监控"
    description: "监控各节点的 CPU 使用率"
    query: |
      100 - (avg by (instance) (
        irate(node_cpu_seconds_total{mode="idle"}[5m])
      ) * 100)
    schedule: "*/1 * * * *"      # 每分钟执行
    timeout: "30s"               # 查询超时
    table: "cpu_metrics"         # 目标表名
    enabled: true                # 是否启用
    retry_count: 3               # 重试次数
    retry_interval: "10s"        # 重试间隔
```

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `PROMETHEUS_URL` | Prometheus 服务器地址 | - |
| `PROMETHEUS_TIMEOUT` | 查询超时时间 | `30s` |
| `MYSQL_HOST` | MySQL 主机地址 | `localhost` |
| `MYSQL_PORT` | MySQL 端口 | `3306` |
| `MYSQL_DATABASE` | 数据库名 | `prometheus_data` |
| `LOG_LEVEL` | 日志级别 | `info` |
| `HTTP_PORT` | 健康检查端口 | `8080` |
| `WORKER_POOL_SIZE` | 工作池大小 | `10` |

## 数据结构

### 主要数据表

#### metrics_data - 指标数据表
```sql
CREATE TABLE `metrics_data` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `query_id` varchar(100) NOT NULL COMMENT '查询ID',
  `metric_name` varchar(255) NOT NULL COMMENT '指标名称',
  `labels` json NOT NULL COMMENT '标签信息（JSON格式）',
  `value` double NOT NULL COMMENT '指标值',
  `timestamp` timestamp(3) NOT NULL COMMENT '指标时间戳',
  `result_type` enum('instant','range','scalar') NOT NULL COMMENT '结果类型',
  `collected_at` timestamp DEFAULT CURRENT_TIMESTAMP COMMENT '采集时间',
  PRIMARY KEY (`id`),
  KEY `idx_query_id_timestamp` (`query_id`, `timestamp`)
);
```

#### query_executions - 执行记录表
```sql
CREATE TABLE `query_executions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `query_id` varchar(100) NOT NULL COMMENT '查询ID',
  `status` enum('running','success','failed','timeout') NOT NULL COMMENT '执行状态',
  `start_time` timestamp(3) NOT NULL COMMENT '开始时间',
  `end_time` timestamp(3) NULL COMMENT '结束时间',
  `duration_ms` int NULL COMMENT '执行时长(毫秒)',
  `records_count` int DEFAULT 0 COMMENT '记录数量',
  `error_message` text NULL COMMENT '错误信息',
  PRIMARY KEY (`id`)
);
```

### 查询数据示例

```sql
-- 查询 CPU 使用率数据
SELECT 
    query_id,
    metric_name,
    JSON_EXTRACT(labels, '$.instance') as instance,
    value,
    timestamp
FROM metrics_data 
WHERE query_id = 'cpu_usage' 
  AND timestamp >= '2024-01-15 10:00:00'
ORDER BY timestamp DESC;

-- 查询特定实例的所有指标
SELECT 
    query_id,
    metric_name,
    value,
    timestamp
FROM metrics_data 
WHERE JSON_EXTRACT(labels, '$.instance') = 'node1'
  AND timestamp >= '2024-01-15 10:00:00'
ORDER BY timestamp DESC;
```

## API 接口

### 健康检查
- `GET /health` - 基本健康检查
- `GET /health/ready` - 就绪状态检查
- `GET /health/live` - 存活状态检查

### 指标端点
- `GET /metrics` - Prometheus 格式的指标数据

## 监控指标

系统会暴露以下监控指标：

```
# 查询执行指标
prometheus_query_executions_total{query_id, status}
prometheus_query_duration_seconds{query_id}
prometheus_query_records_total{query_id}

# 系统指标
prometheus_exporter_up
mysql_connections_active
mysql_connections_idle
```

## 故障排除

### 常见问题

1. **连接 Prometheus 失败**
   ```bash
   # 检查网络连通性
   curl -v http://10.20.100.200:30588/select/0/prometheus/api/v1/query?query=up
   
   # 检查配置
   echo $PROMETHEUS_URL
   ```

2. **MySQL 连接失败**
   ```bash
   # 检查 MySQL 连接
   mysql -h localhost -u root -p prometheus_data
   
   # 检查表结构
   SHOW TABLES;
   ```

3. **查询执行失败**
   ```bash
   # 查看执行记录
   SELECT * FROM query_executions WHERE status = 'failed' ORDER BY start_time DESC LIMIT 10;
   
   # 检查日志
   docker-compose logs prom-etl-db
   ```

### 日志级别

设置 `LOG_LEVEL=debug` 获取详细的调试信息：
```bash
export LOG_LEVEL=debug
```

## 开发指南

### 项目结构
```
prom-etl-db/
├── cmd/server/main.go          # 程序入口
├── internal/
│   ├── config/config.go        # 配置管理
│   ├── prometheus/client.go    # Prometheus 客户端
│   ├── database/mysql.go       # MySQL 连接管理
│   ├── scheduler/scheduler.go  # 定时任务调度器
│   └── models/models.go        # 数据模型
├── configs/
│   ├── queries.yaml           # 查询配置
│   └── docker-compose.yaml    # Docker 编排
├── scripts/migrate.sql        # 数据库迁移
└── README.md                  # 项目说明
```

### 构建和测试
```bash
# 运行测试
go test ./...

# 构建二进制文件
go build -o prom-etl-db cmd/server/main.go

# 构建 Docker 镜像
docker build -t prom-etl-db .
```

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

---

更多详细信息请参考 [FEATURE.md](FEATURE.md) 文档。 