-- 将 queries.yaml 的内容导入到 query_configs 表
-- 这样可以实现动态配置管理

-- 清空现有配置（可选）
-- DELETE FROM query_configs;

-- 导入查询配置
INSERT INTO query_configs (
    query_id, name, description, query, schedule, timeout, 
    table_name, tags, enabled, retry_count, retry_interval
) VALUES 
-- 1. 磁盘使用率监控
(
    'disk_usage',
    '磁盘使用率监控',
    '监控根目录磁盘使用情况',
    'node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"} - node_filesystem_free_bytes{mountpoint="/",fstype!="rootfs"}) / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"}) * 100',
    '*/5 * * * *',
    '30s',
    'disk_metrics',
    JSON_ARRAY('performance', 'storage'),
    1,
    3,
    '10s'
),
-- 2. 网络流量监控
(
    'network_traffic',
    '网络流量监控',
    '监控网络接口的流量',
    'rate(node_network_receive_bytes_total{device!="lo"}[5m])',
    '*/2 * * * *',
    '30s',
    'network_metrics',
    JSON_ARRAY('network'),
    1,
    3,
    '10s'
),
-- 3. 系统负载监控
(
    'load_average',
    '系统负载监控',
    '监控系统1分钟负载',
    'node_load1',
    '*/1 * * * *',
    '30s',
    'load_metrics',
    JSON_ARRAY('performance'),
    1,
    3,
    '10s'
),
-- 4. 服务状态监控
(
    'up_status',
    '服务状态监控',
    '监控各服务的运行状态',
    'up',
    '*/30 * * * * *',
    '15s',
    'service_status',
    JSON_ARRAY('availability', 'health'),
    1,
    2,
    '5s'
);

-- 查看导入的数据
SELECT 
    query_id,
    name,
    description,
    LEFT(query, 50) as query_preview,
    schedule,
    timeout,
    table_name,
    tags,
    enabled,
    retry_count,
    retry_interval,
    created_at,
    updated_at
FROM query_configs 
ORDER BY created_at; 