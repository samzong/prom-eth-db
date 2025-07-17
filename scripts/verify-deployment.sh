#!/bin/bash

# 部署验证脚本
# 使用方法: ./scripts/verify-deployment.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印消息函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查 Pod 状态
check_pods() {
    print_info "检查 Pod 状态..."
    
    # 检查 Pod 是否运行
    if kubectl get pods -n monitoring -l app=prom-eth-db --no-headers | grep -q "Running"; then
        print_success "Pod 状态正常"
        kubectl get pods -n monitoring -l app=prom-eth-db
    else
        print_error "Pod 状态异常"
        kubectl get pods -n monitoring -l app=prom-eth-db
        return 1
    fi
}

# 检查 Service 状态
check_services() {
    print_info "检查 Service 状态..."
    
    if kubectl get svc -n monitoring -l app=prom-eth-db --no-headers | grep -q "prom-eth-db"; then
        print_success "Service 状态正常"
        kubectl get svc -n monitoring -l app=prom-eth-db
    else
        print_error "Service 状态异常"
        return 1
    fi
}

# 检查健康检查端点
check_health_endpoints() {
    print_info "检查健康检查端点..."
    
    # 获取 Pod 名称
    POD_NAME=$(kubectl get pods -n monitoring -l app=prom-eth-db -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$POD_NAME" ]; then
        print_error "找不到 Pod"
        return 1
    fi
    
    # 检查健康检查端点
    print_info "检查 /health 端点..."
    if kubectl exec -n monitoring "$POD_NAME" -- curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        print_success "/health 端点正常"
    else
        print_error "/health 端点异常"
        return 1
    fi
    
    print_info "检查 /health/ready 端点..."
    if kubectl exec -n monitoring "$POD_NAME" -- curl -sf http://localhost:8080/health/ready > /dev/null 2>&1; then
        print_success "/health/ready 端点正常"
    else
        print_error "/health/ready 端点异常"
        return 1
    fi
    
    print_info "检查 /health/live 端点..."
    if kubectl exec -n monitoring "$POD_NAME" -- curl -sf http://localhost:8080/health/live > /dev/null 2>&1; then
        print_success "/health/live 端点正常"
    else
        print_error "/health/live 端点异常"
        return 1
    fi
}

# 检查 Prometheus 指标端点
check_metrics_endpoint() {
    print_info "检查 Prometheus 指标端点..."
    
    POD_NAME=$(kubectl get pods -n monitoring -l app=prom-eth-db -o jsonpath='{.items[0].metadata.name}')
    
    if kubectl exec -n monitoring "$POD_NAME" -- curl -sf http://localhost:9090/metrics > /dev/null 2>&1; then
        print_success "Prometheus 指标端点正常"
    else
        print_error "Prometheus 指标端点异常"
        return 1
    fi
}

# 检查数据库连接
check_database_connection() {
    print_info "检查数据库连接..."
    
    POD_NAME=$(kubectl get pods -n monitoring -l app=prom-eth-db -o jsonpath='{.items[0].metadata.name}')
    
    # 从 Secret 获取数据库连接信息
    MYSQL_HOST=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_HOST}' | base64 -d)
    MYSQL_USERNAME=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_USERNAME}' | base64 -d)
    MYSQL_PASSWORD=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d)
    MYSQL_DATABASE=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_DATABASE}' | base64 -d)
    
    if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_USERNAME" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$MYSQL_DATABASE" ]; then
        print_error "无法获取数据库连接信息"
        return 1
    fi
    
    # 测试数据库连接
    if kubectl exec -n monitoring "$POD_NAME" -- mysql -h "$MYSQL_HOST" -u "$MYSQL_USERNAME" -p"$MYSQL_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
        print_success "数据库连接正常"
    else
        print_error "数据库连接异常"
        return 1
    fi
}

# 检查查询配置
check_query_config() {
    print_info "检查查询配置..."
    
    POD_NAME=$(kubectl get pods -n monitoring -l app=prom-eth-db -o jsonpath='{.items[0].metadata.name}')
    
    # 从 Secret 获取数据库连接信息
    MYSQL_HOST=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_HOST}' | base64 -d)
    MYSQL_USERNAME=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_USERNAME}' | base64 -d)
    MYSQL_PASSWORD=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d)
    MYSQL_DATABASE=$(kubectl get secret -n monitoring prom-eth-db-secret-plain -o jsonpath='{.data.MYSQL_DATABASE}' | base64 -d)
    
    # 检查查询配置
    QUERY_COUNT=$(kubectl exec -n monitoring "$POD_NAME" -- mysql -h "$MYSQL_HOST" -u "$MYSQL_USERNAME" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM queries WHERE enabled = 1" --skip-column-names 2>/dev/null || echo "0")
    
    if [ "$QUERY_COUNT" -gt 0 ]; then
        print_success "查询配置正常，共 $QUERY_COUNT 个启用的查询"
        kubectl exec -n monitoring "$POD_NAME" -- mysql -h "$MYSQL_HOST" -u "$MYSQL_USERNAME" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT id, name, schedule, enabled FROM queries" 2>/dev/null | head -10
    else
        print_error "查询配置异常，没有启用的查询"
        return 1
    fi
}

# 检查应用日志
check_logs() {
    print_info "检查应用日志 (最近 20 行)..."
    
    kubectl logs -n monitoring -l app=prom-eth-db --tail=20
    
    # 检查是否有错误日志
    if kubectl logs -n monitoring -l app=prom-eth-db --tail=100 | grep -i error > /dev/null 2>&1; then
        print_warn "发现错误日志，建议检查详细日志"
    else
        print_success "日志正常，没有发现错误"
    fi
}

# 性能测试
performance_test() {
    print_info "执行性能测试..."
    
    POD_NAME=$(kubectl get pods -n monitoring -l app=prom-eth-db -o jsonpath='{.items[0].metadata.name}')
    
    # 测试健康检查端点响应时间
    print_info "测试健康检查端点响应时间..."
    RESPONSE_TIME=$(kubectl exec -n monitoring "$POD_NAME" -- curl -w "%{time_total}" -s -o /dev/null http://localhost:8080/health)
    print_info "健康检查端点响应时间: ${RESPONSE_TIME}s"
    
    # 测试指标端点响应时间
    print_info "测试指标端点响应时间..."
    METRICS_RESPONSE_TIME=$(kubectl exec -n monitoring "$POD_NAME" -- curl -w "%{time_total}" -s -o /dev/null http://localhost:9090/metrics)
    print_info "指标端点响应时间: ${METRICS_RESPONSE_TIME}s"
}

# 主函数
main() {
    print_info "开始验证部署..."
    
    local failed=0
    
    check_pods || failed=1
    echo
    
    check_services || failed=1
    echo
    
    check_health_endpoints || failed=1
    echo
    
    check_metrics_endpoint || failed=1
    echo
    
    check_database_connection || failed=1
    echo
    
    check_query_config || failed=1
    echo
    
    check_logs
    echo
    
    performance_test
    echo
    
    if [ $failed -eq 0 ]; then
        print_success "所有检查通过，部署验证成功！"
    else
        print_error "部分检查失败，请检查相关配置"
        exit 1
    fi
}

# 帮助信息
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     显示帮助信息"
    echo "  -q, --quick    快速检查 (仅检查 Pod 和 Service)"
    echo "  -l, --logs     仅显示日志"
    echo "  -p, --perf     仅执行性能测试"
    echo ""
    echo "Examples:"
    echo "  $0              完整验证"
    echo "  $0 --quick      快速验证"
    echo "  $0 --logs       查看日志"
    echo "  $0 --perf       性能测试"
}

# 快速检查
quick_check() {
    print_info "执行快速检查..."
    
    local failed=0
    
    check_pods || failed=1
    echo
    
    check_services || failed=1
    echo
    
    if [ $failed -eq 0 ]; then
        print_success "快速检查通过！"
    else
        print_error "快速检查失败"
        exit 1
    fi
}

# 命令行参数处理
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -q|--quick)
        quick_check
        exit 0
        ;;
    -l|--logs)
        check_logs
        exit 0
        ;;
    -p|--perf)
        performance_test
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "未知参数: $1"
        show_help
        exit 1
        ;;
esac