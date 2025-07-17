-- 创建 prometheus_data 数据库
CREATE DATABASE IF NOT EXISTS prometheus_data CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE prometheus_data;

-- 创建查询配置表
CREATE TABLE IF NOT EXISTS queries (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(512) NOT NULL,
    description TEXT,
    query TEXT NOT NULL,
    schedule VARCHAR(255) NOT NULL,
    timeout VARCHAR(255) DEFAULT '30s',
    table_name VARCHAR(255) NOT NULL DEFAULT 'metrics_data',
    tags JSON,
    enabled BOOLEAN DEFAULT TRUE,
    retry_count INT DEFAULT 3,
    retry_interval VARCHAR(255) DEFAULT '10s',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 创建指标数据表
CREATE TABLE IF NOT EXISTS metrics_data (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    query_id VARCHAR(255) NOT NULL,
    metric_name VARCHAR(512) NOT NULL,
    labels JSON,
    value DOUBLE NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    result_type VARCHAR(50) NOT NULL,
    collected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_query_id (query_id),
    INDEX idx_timestamp (timestamp),
    INDEX idx_collected_at (collected_at),
    INDEX idx_metric_name (metric_name)
);

-- 创建查询执行记录表
CREATE TABLE IF NOT EXISTS query_executions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    query_id VARCHAR(255) NOT NULL,
    query_name VARCHAR(512) NOT NULL,
    status VARCHAR(50) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    duration_ms BIGINT,
    records_count INT DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_query_id (query_id),
    INDEX idx_start_time (start_time),
    INDEX idx_status (status)
);

-- 插入 GPU 利用率查询配置
INSERT INTO queries (
    id, 
    name, 
    description, 
    query, 
    schedule, 
    timeout, 
    table_name, 
    tags, 
    enabled, 
    retry_count, 
    retry_interval
) VALUES (
    'gpu_utilization_daily',
    'GPU 利用率统计',
    '每日 GPU 利用率统计查询',
    'count_over_time((count(kpanda_gpu_pod_utilization{cluster_name="sh-07-d-run"}) by (UUID,node))[1d:1d] offset 1d) * 60 / 3600',
    '0 0 4 * * *',
    '60s',
    'metrics_data',
    '["gpu", "utilization", "daily"]',
    TRUE,
    3,
    '10s'
) ON DUPLICATE KEY UPDATE
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
    updated_at = CURRENT_TIMESTAMP;

-- 显示插入的查询配置
SELECT * FROM queries WHERE id = 'gpu_utilization_daily';