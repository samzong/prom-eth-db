-- Prometheus to MySQL ETL Database Schema
-- Clean database schema without sample data

-- Create database with utf8mb4 charset
CREATE DATABASE IF NOT EXISTS `prometheus_data` 
  DEFAULT CHARACTER SET utf8mb4 
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE `prometheus_data`;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Metrics data table
-- Stores all Prometheus query results
CREATE TABLE `metrics_data` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `query_id` varchar(100) NOT NULL,
  `metric_name` varchar(255) NOT NULL,
  `labels` json NOT NULL,
  `value` double NOT NULL,
  `timestamp` timestamp(3) NOT NULL,
  `result_type` enum('instant','range','scalar') NOT NULL,
  `collected_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_query_id_timestamp` (`query_id`, `timestamp`),
  KEY `idx_metric_name` (`metric_name`),
  KEY `idx_timestamp` (`timestamp`),
  KEY `idx_result_type` (`result_type`),
  KEY `idx_collected_at` (`collected_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Query execution records
-- Tracks execution history and performance
CREATE TABLE `query_executions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `query_id` varchar(100) NOT NULL,
  `query_name` varchar(255) NOT NULL,
  `status` enum('running','success','failed','timeout') NOT NULL,
  `start_time` timestamp(3) NOT NULL,
  `end_time` timestamp(3) NULL,
  `duration_ms` int NULL,
  `records_count` int DEFAULT 0,
  `error_message` text NULL,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_query_id` (`query_id`),
  KEY `idx_status` (`status`),
  KEY `idx_start_time` (`start_time`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Query configurations
-- Stores query configuration information
CREATE TABLE `query_configs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `query_id` varchar(100) NOT NULL,
  `name` varchar(255) NOT NULL,
  `description` text NULL,
  `query` text NOT NULL,
  `schedule` varchar(100) NOT NULL,
  `timeout` varchar(20) DEFAULT '30s',
  `enabled` tinyint(1) DEFAULT 1,
  `retry_count` int DEFAULT 3,
  `retry_interval` varchar(20) DEFAULT '10s',
  `time_range_type` enum('instant','range') DEFAULT 'instant',
  `time_range_time` varchar(50) NULL,
  `time_range_start` varchar(50) NULL,
  `time_range_end` varchar(50) NULL,
  `time_range_step` varchar(20) NULL,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_query_id` (`query_id`),
  KEY `idx_enabled` (`enabled`),
  KEY `idx_time_range_type` (`time_range_type`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



SET FOREIGN_KEY_CHECKS = 1;