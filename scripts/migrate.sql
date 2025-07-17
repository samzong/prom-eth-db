-- Prometheus to MySQL ETL 数据库迁移脚本
-- 创建数据库和表结构

-- 设置字符集
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ===== 1. 统一指标数据表 =====
-- 存储所有 Prometheus 查询结果的统一表
CREATE TABLE IF NOT EXISTS `metrics_data` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `query_id` varchar(100) NOT NULL COMMENT '查询ID',
  `metric_name` varchar(255) NOT NULL COMMENT '指标名称',
  `labels` json NOT NULL COMMENT '标签信息（JSON格式）',
  `value` double NOT NULL COMMENT '指标值',
  `timestamp` timestamp(3) NOT NULL COMMENT '指标时间戳',
  `result_type` enum('instant','range','scalar') NOT NULL COMMENT '结果类型',
  `collected_at` timestamp DEFAULT CURRENT_TIMESTAMP COMMENT '采集时间',
  PRIMARY KEY (`id`),
  KEY `idx_query_id_timestamp` (`query_id`, `timestamp`),
  KEY `idx_metric_name` (`metric_name`),
  KEY `idx_timestamp` (`timestamp`),
  KEY `idx_result_type` (`result_type`),
  KEY `idx_collected_at` (`collected_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci 
COMMENT='Prometheus 指标数据统一存储表';

-- ===== 2. 查询执行记录表 =====
-- 记录每次查询的执行状态和结果
CREATE TABLE IF NOT EXISTS `query_executions` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `query_id` varchar(100) NOT NULL COMMENT '查询ID',
  `query_name` varchar(255) NOT NULL COMMENT '查询名称',
  `status` enum('running','success','failed','timeout') NOT NULL COMMENT '执行状态',
  `start_time` timestamp(3) NOT NULL COMMENT '开始时间',
  `end_time` timestamp(3) NULL COMMENT '结束时间',
  `duration_ms` int NULL COMMENT '执行时长(毫秒)',
  `records_count` int DEFAULT 0 COMMENT '记录数量',
  `error_message` text NULL COMMENT '错误信息',
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_query_id` (`query_id`),
  KEY `idx_status` (`status`),
  KEY `idx_start_time` (`start_time`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci 
COMMENT='查询执行记录表';

-- ===== 3. 查询配置表 (可选) =====
-- 存储查询配置信息，支持动态配置管理
CREATE TABLE IF NOT EXISTS `query_configs` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `query_id` varchar(100) NOT NULL UNIQUE COMMENT '查询ID',
  `name` varchar(255) NOT NULL COMMENT '查询名称',
  `description` text NULL COMMENT '描述',
  `query` text NOT NULL COMMENT 'PromQL 查询语句',
  `schedule` varchar(100) NOT NULL COMMENT 'Cron 表达式',
  `timeout` varchar(20) DEFAULT '30s' COMMENT '超时时间',
  `table_name` varchar(100) NOT NULL COMMENT '目标表名',
  `tags` json NULL COMMENT '标签',
  `enabled` tinyint(1) DEFAULT 1 COMMENT '是否启用',
  `retry_count` int DEFAULT 3 COMMENT '重试次数',
  `retry_interval` varchar(20) DEFAULT '10s' COMMENT '重试间隔',
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_query_id` (`query_id`),
  KEY `idx_enabled` (`enabled`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci 
COMMENT='查询配置表';

-- ===== 4. 系统状态表 =====
-- 记录系统运行状态和健康信息
CREATE TABLE IF NOT EXISTS `system_status` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `component` varchar(100) NOT NULL COMMENT '组件名称',
  `status` enum('healthy','unhealthy','warning') NOT NULL COMMENT '状态',
  `message` text NULL COMMENT '状态信息',
  `last_check` timestamp(3) NOT NULL COMMENT '最后检查时间',
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_component` (`component`),
  KEY `idx_status` (`status`),
  KEY `idx_last_check` (`last_check`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci 
COMMENT='系统状态表';

-- ===== 5. 插入初始配置数据 =====
-- 插入默认的查询配置
INSERT INTO `query_configs` (`query_id`, `name`, `description`, `query`, `schedule`, `timeout`, `table_name`, `tags`, `enabled`, `retry_count`, `retry_interval`) VALUES
('cpu_usage', 'CPU 使用率监控', '监控各节点的 CPU 使用率', '100 - (avg by (instance) (\n  irate(node_cpu_seconds_total{mode=\"idle\"}[5m])\n) * 100)', '*/1 * * * *', '30s', 'cpu_metrics', '[\"performance\", \"system\"]', 1, 3, '10s'),
('memory_usage', '内存使用率监控', '监控各节点的内存使用率', '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100', '*/2 * * * *', '30s', 'memory_metrics', '[\"performance\", \"memory\"]', 1, 3, '10s'),
('disk_usage', '磁盘使用率监控', '监控各节点的磁盘使用率', '100 - ((node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"rootfs\"} / \nnode_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"rootfs\"}) * 100)', '*/5 * * * *', '30s', 'disk_metrics', '[\"performance\", \"storage\"]', 1, 3, '10s'),
('network_traffic', '网络流量监控', '监控网络接口的流量', 'rate(node_network_receive_bytes_total{device!=\"lo\"}[5m])', '*/2 * * * *', '30s', 'network_metrics', '[\"network\", \"traffic\"]', 1, 3, '10s'),
('load_average', '系统负载监控', '监控系统1分钟负载平均值', 'node_load1', '*/1 * * * *', '30s', 'load_metrics', '[\"performance\", \"load\"]', 1, 3, '10s'),
('up_status', '服务状态监控', '监控各服务的运行状态', 'up', '*/30 * * * * *', '15s', 'service_status', '[\"availability\", \"health\"]', 1, 2, '5s')
ON DUPLICATE KEY UPDATE 
  `name` = VALUES(`name`),
  `description` = VALUES(`description`),
  `query` = VALUES(`query`),
  `schedule` = VALUES(`schedule`),
  `updated_at` = CURRENT_TIMESTAMP;

-- ===== 6. 创建视图 =====
-- 创建最新指标数据视图
CREATE OR REPLACE VIEW `latest_metrics_view` AS
SELECT 
    md.query_id,
    md.metric_name,
    md.labels,
    md.value,
    md.timestamp,
    md.result_type,
    qc.name as query_name,
    qc.description as query_description
FROM metrics_data md
INNER JOIN (
    SELECT query_id, metric_name, MAX(timestamp) as max_timestamp
    FROM metrics_data
    GROUP BY query_id, metric_name
) latest ON md.query_id = latest.query_id 
    AND md.metric_name = latest.metric_name 
    AND md.timestamp = latest.max_timestamp
LEFT JOIN query_configs qc ON md.query_id = qc.query_id
ORDER BY md.timestamp DESC;

-- ===== 7. 创建存储过程 =====
-- 清理过期数据的存储过程
DELIMITER //
CREATE PROCEDURE `CleanupOldMetrics`(IN days_to_keep INT)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE table_name VARCHAR(100);
    DECLARE cleanup_date TIMESTAMP;
    
    SET cleanup_date = DATE_SUB(NOW(), INTERVAL days_to_keep DAY);
    
    -- 清理指标数据
    DELETE FROM metrics_data WHERE collected_at < cleanup_date;
    
    -- 清理执行记录
    DELETE FROM query_executions WHERE created_at < cleanup_date;
    
    -- 清理系统状态
    DELETE FROM system_status WHERE created_at < cleanup_date;
    
    SELECT CONCAT('Cleaned up data older than ', days_to_keep, ' days') as result;
END //
DELIMITER ;

-- 恢复外键检查
SET FOREIGN_KEY_CHECKS = 1;

-- 显示创建的表
SHOW TABLES; 