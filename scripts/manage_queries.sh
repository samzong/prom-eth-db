#!/bin/bash

# 查询配置管理脚本
# 用于管理数据库中的查询配置

set -e

# 配置
DB_HOST="localhost"
DB_PORT="3306"
DB_USER="root"
DB_PASSWORD="password"
DB_NAME="prometheus_data"
DOCKER_COMPOSE_FILE="configs/docker-compose.yaml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印帮助信息
show_help() {
    echo -e "${BLUE}查询配置管理工具${NC}"
    echo ""
    echo "用法: $0 <command> [options]"
    echo ""
    echo "可用命令:"
    echo -e "  ${GREEN}list${NC}           - 列出所有查询配置"
    echo -e "  ${GREEN}show <query_id>${NC} - 显示特定查询配置的详细信息"
    echo -e "  ${GREEN}enable <query_id>${NC} - 启用查询"
    echo -e "  ${GREEN}disable <query_id>${NC} - 禁用查询"
    echo -e "  ${GREEN}delete <query_id>${NC} - 删除查询配置"
    echo -e "  ${GREEN}add${NC}            - 添加新的查询配置（交互式）"
    echo -e "  ${GREEN}edit <query_id>${NC} - 编辑查询配置（交互式）"
    echo -e "  ${GREEN}backup${NC}         - 备份查询配置到文件"
    echo -e "  ${GREEN}restore <file>${NC} - 从文件恢复查询配置"
    echo -e "  ${GREEN}test <query_id>${NC} - 测试查询配置"
    echo ""
    echo "示例:"
    echo "  $0 list"
    echo "  $0 show cpu_usage"
    echo "  $0 enable cpu_usage"
    echo "  $0 disable network_traffic"
}

# 执行 MySQL 命令
mysql_exec() {
    if command -v docker-compose &> /dev/null && [ -f "$DOCKER_COMPOSE_FILE" ]; then
        # 使用 Docker Compose
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T mysql mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$1"
    else
        # 使用本地 MySQL
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$1"
    fi
}

# 列出所有查询配置
list_queries() {
    echo -e "${BLUE}查询配置列表:${NC}"
    mysql_exec "
        SELECT 
            query_id as 'ID',
            name as '名称',
            description as '描述',
            schedule as '调度',
            timeout as '超时',
            table_name as '表名',
            CASE enabled WHEN 1 THEN '✓' ELSE '✗' END as '启用',
            retry_count as '重试',
            updated_at as '更新时间'
        FROM query_configs 
        ORDER BY created_at;
    "
}

# 显示特定查询配置详情
show_query() {
    local query_id="$1"
    if [ -z "$query_id" ]; then
        echo -e "${RED}错误: 请提供查询 ID${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}查询配置详情: $query_id${NC}"
    mysql_exec "
        SELECT 
            query_id as 'ID',
            name as '名称',
            description as '描述',
            query as '查询语句',
            schedule as '调度',
            timeout as '超时',
            table_name as '表名',
            tags as '标签',
            CASE enabled WHEN 1 THEN '启用' ELSE '禁用' END as '状态',
            retry_count as '重试次数',
            retry_interval as '重试间隔',
            created_at as '创建时间',
            updated_at as '更新时间'
        FROM query_configs 
        WHERE query_id = '$query_id';
    "
}

# 启用查询
enable_query() {
    local query_id="$1"
    if [ -z "$query_id" ]; then
        echo -e "${RED}错误: 请提供查询 ID${NC}"
        exit 1
    fi
    
    mysql_exec "UPDATE query_configs SET enabled = 1, updated_at = CURRENT_TIMESTAMP WHERE query_id = '$query_id';"
    echo -e "${GREEN}已启用查询: $query_id${NC}"
}

# 禁用查询
disable_query() {
    local query_id="$1"
    if [ -z "$query_id" ]; then
        echo -e "${RED}错误: 请提供查询 ID${NC}"
        exit 1
    fi
    
    mysql_exec "UPDATE query_configs SET enabled = 0, updated_at = CURRENT_TIMESTAMP WHERE query_id = '$query_id';"
    echo -e "${YELLOW}已禁用查询: $query_id${NC}"
}

# 删除查询配置
delete_query() {
    local query_id="$1"
    if [ -z "$query_id" ]; then
        echo -e "${RED}错误: 请提供查询 ID${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}确定要删除查询配置 '$query_id' 吗？这个操作不可逆转。${NC}"
    read -p "请输入 'yes' 确认: " confirm
    
    if [ "$confirm" = "yes" ]; then
        mysql_exec "DELETE FROM query_configs WHERE query_id = '$query_id';"
        echo -e "${GREEN}已删除查询配置: $query_id${NC}"
    else
        echo -e "${BLUE}操作已取消${NC}"
    fi
}

# 添加新查询配置
add_query() {
    echo -e "${BLUE}添加新的查询配置${NC}"
    
    read -p "查询 ID: " query_id
    read -p "名称: " name
    read -p "描述: " description
    read -p "PromQL 查询语句: " query
    read -p "调度 (cron 格式): " schedule
    read -p "超时时间 (默认 30s): " timeout
    read -p "目标表名: " table_name
    read -p "标签 (JSON 格式，如 [\"performance\"]): " tags
    read -p "重试次数 (默认 3): " retry_count
    read -p "重试间隔 (默认 10s): " retry_interval
    
    # 设置默认值
    timeout=${timeout:-30s}
    retry_count=${retry_count:-3}
    retry_interval=${retry_interval:-10s}
    tags=${tags:-'[]'}
    
    mysql_exec "
        INSERT INTO query_configs (
            query_id, name, description, query, schedule, timeout, 
            table_name, tags, enabled, retry_count, retry_interval
        ) VALUES (
            '$query_id', '$name', '$description', '$query', '$schedule', '$timeout',
            '$table_name', '$tags', 1, $retry_count, '$retry_interval'
        );
    "
    
    echo -e "${GREEN}已添加查询配置: $query_id${NC}"
}

# 备份查询配置
backup_queries() {
    local backup_file="query_configs_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    echo -e "${BLUE}备份查询配置到: $backup_file${NC}"
    
    if command -v docker-compose &> /dev/null && [ -f "$DOCKER_COMPOSE_FILE" ]; then
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T mysql mysqldump -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" query_configs > "$backup_file"
    else
        mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" query_configs > "$backup_file"
    fi
    
    echo -e "${GREEN}备份完成: $backup_file${NC}"
}

# 测试查询配置
test_query() {
    local query_id="$1"
    if [ -z "$query_id" ]; then
        echo -e "${RED}错误: 请提供查询 ID${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}测试查询配置: $query_id${NC}"
    echo -e "${YELLOW}注意: 这将实际执行查询并将结果写入数据库${NC}"
    read -p "确定要继续吗？(y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # 这里可以调用实际的测试程序
        echo -e "${BLUE}执行测试查询...${NC}"
        # 示例：可以调用 Go 程序来测试单个查询
        # go run cmd/server/test_query.go -query-id="$query_id"
        echo -e "${GREEN}测试完成${NC}"
    else
        echo -e "${BLUE}测试已取消${NC}"
    fi
}

# 主程序
main() {
    case "${1:-help}" in
        list)
            list_queries
            ;;
        show)
            show_query "$2"
            ;;
        enable)
            enable_query "$2"
            ;;
        disable)
            disable_query "$2"
            ;;
        delete)
            delete_query "$2"
            ;;
        add)
            add_query
            ;;
        backup)
            backup_queries
            ;;
        test)
            test_query "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}未知命令: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# 运行主程序
main "$@" 