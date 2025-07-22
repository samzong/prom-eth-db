-- Prometheus to MySQL ETL 数据库迁移脚本
-- 创建表结构并插入GPU查询配置

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

-- ===== 3. 查询配置表 =====
-- 存储查询配置信息
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
  -- 新增时间范围配置字段
  `time_range_type` enum('instant','range') DEFAULT 'instant' COMMENT '查询类型：instant=即时查询，range=范围查询',
  `time_range_time` varchar(50) NULL COMMENT '即时查询的时间点（支持相对时间，如：now、-1d、-2h）',
  `time_range_start` varchar(50) NULL COMMENT '范围查询的开始时间（支持相对时间）',
  `time_range_end` varchar(50) NULL COMMENT '范围查询的结束时间（支持相对时间）',
  `time_range_step` varchar(20) NULL COMMENT '范围查询的步长（如：1m、5m、1h）',
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_query_id` (`query_id`),
  KEY `idx_enabled` (`enabled`),
  KEY `idx_time_range_type` (`time_range_type`),
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

-- ===== 5. 插入GPU利用率查询配置 =====
INSERT INTO `query_configs` (
  `query_id`, `name`, `description`, `query`, `schedule`, `timeout`, `table_name`, `tags`, `enabled`, `retry_count`, `retry_interval`,
  `time_range_type`, `time_range_time`
) VALUES
('gpu_utilization_daily', 'GPU每日利用率统计', '每天计算昨天的GPU利用率', 'count_over_time((count(kpanda_gpu_pod_utilization{cluster_name="sh-07-d-run"}) by (cluster_name,UUID,node))[1d:1d]) * 60 / 3600', '0 0 1 * * *', '120s', 'gpu_metrics', '["gpu", "utilization", "daily"]', 1, 3, '30s', 'instant', '-1d');

-- 恢复外键检查
SET FOREIGN_KEY_CHECKS = 1; 