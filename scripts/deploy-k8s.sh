#!/bin/bash

# Kubernetes 部署脚本
# 使用方法: ./scripts/deploy-k8s.sh

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

# 检查必要工具
check_tools() {
    print_info "检查必要工具..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl 未安装，请先安装 kubectl"
        exit 1
    fi
    
    if ! command -v mysql &> /dev/null; then
        print_warn "mysql 客户端未安装，您需要手动执行数据库初始化脚本"
    fi
}

# 检查 Kubernetes 连接
check_k8s_connection() {
    print_info "检查 Kubernetes 连接..."
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    print_info "Kubernetes 连接正常"
}

# 创建 namespace
create_namespace() {
    print_info "创建 namespace..."
    
    if kubectl get namespace monitoring &> /dev/null; then
        print_info "namespace monitoring 已存在"
    else
        kubectl create namespace monitoring
        print_info "namespace monitoring 创建成功"
    fi
}

# 部署应用
deploy_app() {
    print_info "部署应用..."
    
    # 应用 Secret
    print_info "应用 Secret 配置..."
    kubectl apply -f deployments/k8s/secret.yaml
    
    # 应用 ConfigMap
    print_info "应用 ConfigMap 配置..."
    kubectl apply -f deployments/k8s/configmap.yaml
    
    # 应用 Deployment
    print_info "应用 Deployment 配置..."
    kubectl apply -f deployments/k8s/deployment.yaml
    
    # 应用 Service
    print_info "应用 Service 配置..."
    kubectl apply -f deployments/k8s/service.yaml
    
    print_info "应用部署完成"
}

# 等待 Pod 就绪
wait_for_pods() {
    print_info "等待 Pod 就绪..."
    
    kubectl wait --for=condition=ready pod -l app=prom-eth-db -n monitoring --timeout=300s
    
    print_info "Pod 已就绪"
}

# 检查部署状态
check_deployment() {
    print_info "检查部署状态..."
    
    echo
    print_info "Pod 状态:"
    kubectl get pods -n monitoring -l app=prom-eth-db
    
    echo
    print_info "Service 状态:"
    kubectl get svc -n monitoring -l app=prom-eth-db
    
    echo
    print_info "Deployment 状态:"
    kubectl get deployment -n monitoring prom-eth-db
}

# 显示访问信息
show_access_info() {
    print_info "访问信息:"
    
    echo
    print_info "集群内访问:"
    echo "  HTTP: http://prom-eth-db:8080"
    echo "  Metrics: http://prom-eth-db:9090/metrics"
    
    echo
    print_info "端口转发访问 (在另一个终端运行):"
    echo "  kubectl port-forward -n monitoring svc/prom-eth-db 8080:8080"
    echo "  kubectl port-forward -n monitoring svc/prom-eth-db 9090:9090"
    
    echo
    print_info "NodePort 访问 (如果启用):"
    echo "  HTTP: http://<node-ip>:30080"
    echo "  Metrics: http://<node-ip>:30090/metrics"
}

# 显示日志
show_logs() {
    print_info "显示应用日志 (按 Ctrl+C 退出):"
    kubectl logs -n monitoring -l app=prom-eth-db -f
}

# 主函数
main() {
    print_info "开始 Kubernetes 部署..."
    
    check_tools
    check_k8s_connection
    create_namespace
    deploy_app
    wait_for_pods
    check_deployment
    show_access_info
    
    echo
    print_info "部署完成！"
    
    echo
    read -p "是否查看应用日志？[y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        show_logs
    fi
}

# 帮助信息
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     显示帮助信息"
    echo "  -l, --logs     仅显示日志"
    echo "  -s, --status   仅检查状态"
    echo ""
    echo "Examples:"
    echo "  $0              完整部署"
    echo "  $0 --logs       查看日志"
    echo "  $0 --status     检查状态"
}

# 命令行参数处理
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -l|--logs)
        show_logs
        exit 0
        ;;
    -s|--status)
        check_deployment
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