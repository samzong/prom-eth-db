# Prometheus to MySQL ETL - Makefile
# 快速开发和测试工具

# 项目信息
PROJECT_NAME := prom-eth-db
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
GO_VERSION := $(shell go version | awk '{print $$3}')

# 构建配置
BINARY_NAME := prom-eth-db
MAIN_PATH := ./cmd/server
BUILD_DIR := ./build
DOCKER_IMAGE := $(PROJECT_NAME):$(VERSION)
DOCKER_COMPOSE_FILE := configs/docker-compose.yaml

# Go 构建标志
LDFLAGS := -ldflags "-X main.version=$(VERSION) -X main.buildTime=$(BUILD_TIME) -X main.goVersion=$(GO_VERSION)"
GO_FLAGS := -v

# 颜色输出
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

.PHONY: help
help: ## 显示帮助信息
	@echo "$(BLUE)$(PROJECT_NAME) - 开发工具$(NC)"
	@echo ""
	@echo "$(YELLOW)使用方法:$(NC)"
	@echo "  make <target>"
	@echo ""
	@echo "$(YELLOW)可用目标:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# =============================================================================
# 开发环境设置
# =============================================================================

.PHONY: setup
setup: ## 设置开发环境
	@echo "$(BLUE)设置开发环境...$(NC)"
	@go mod download
	@go mod tidy
	@if [ ! -f .env ]; then cp env.example .env; echo "$(GREEN)已创建 .env 文件$(NC)"; fi
	@mkdir -p $(BUILD_DIR)
	@mkdir -p logs
	@echo "$(GREEN)开发环境设置完成$(NC)"

.PHONY: deps
deps: ## 安装/更新依赖
	@echo "$(BLUE)安装依赖...$(NC)"
	@go mod download
	@go mod tidy
	@go mod verify
	@echo "$(GREEN)依赖安装完成$(NC)"

.PHONY: clean
clean: ## 清理构建文件
	@echo "$(BLUE)清理构建文件...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf logs/*
	@go clean -cache
	@echo "$(GREEN)清理完成$(NC)"

# =============================================================================
# 代码质量检查
# =============================================================================

.PHONY: fmt
fmt: ## 格式化代码
	@echo "$(BLUE)格式化代码...$(NC)"
	@go fmt ./...
	@echo "$(GREEN)代码格式化完成$(NC)"

.PHONY: vet
vet: ## 代码静态检查
	@echo "$(BLUE)执行代码静态检查...$(NC)"
	@go vet ./...
	@echo "$(GREEN)静态检查完成$(NC)"

.PHONY: lint
lint: ## 代码风格检查 (需要 golangci-lint)
	@echo "$(BLUE)执行代码风格检查...$(NC)"
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo "$(YELLOW)golangci-lint 未安装，跳过检查$(NC)"; \
		echo "$(YELLOW)安装命令: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest$(NC)"; \
	fi

.PHONY: check
check: fmt vet lint ## 执行所有代码检查

# =============================================================================
# 测试
# =============================================================================

.PHONY: test
test: ## 运行测试
	@echo "$(BLUE)运行测试...$(NC)"
	@go test $(GO_FLAGS) ./...

.PHONY: test-verbose
test-verbose: ## 运行详细测试
	@echo "$(BLUE)运行详细测试...$(NC)"
	@go test -v -race -coverprofile=coverage.out ./...

.PHONY: test-coverage
test-coverage: test-verbose ## 运行测试并生成覆盖率报告
	@echo "$(BLUE)生成覆盖率报告...$(NC)"
	@go tool cover -html=coverage.out -o coverage.html
	@echo "$(GREEN)覆盖率报告已生成: coverage.html$(NC)"

.PHONY: benchmark
benchmark: ## 运行性能测试
	@echo "$(BLUE)运行性能测试...$(NC)"
	@go test -bench=. -benchmem ./...

# =============================================================================
# 构建
# =============================================================================

.PHONY: build
build: ## 构建二进制文件
	@echo "$(BLUE)构建二进制文件...$(NC)"
	@mkdir -p $(BUILD_DIR)
	@go build $(LDFLAGS) $(GO_FLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) $(MAIN_PATH)
	@echo "$(GREEN)构建完成: $(BUILD_DIR)/$(BINARY_NAME)$(NC)"

.PHONY: build-linux
build-linux: ## 构建 Linux 二进制文件
	@echo "$(BLUE)构建 Linux 二进制文件...$(NC)"
	@mkdir -p $(BUILD_DIR)
	@GOOS=linux GOARCH=amd64 go build $(LDFLAGS) $(GO_FLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux $(MAIN_PATH)
	@echo "$(GREEN)Linux 构建完成: $(BUILD_DIR)/$(BINARY_NAME)-linux$(NC)"

.PHONY: build-all
build-all: build build-linux ## 构建所有平台的二进制文件

# =============================================================================
# 运行
# =============================================================================

.PHONY: run
run: ## 运行应用程序
	@echo "$(BLUE)运行应用程序...$(NC)"
	@if [ ! -f .env ]; then echo "$(RED)错误: .env 文件不存在，请先运行 make setup$(NC)"; exit 1; fi
	@go run $(MAIN_PATH)

.PHONY: run-build
run-build: build ## 构建并运行二进制文件
	@echo "$(BLUE)运行构建的二进制文件...$(NC)"
	@$(BUILD_DIR)/$(BINARY_NAME)

# =============================================================================
# Docker 操作
# =============================================================================

.PHONY: docker-build
docker-build: ## 构建 Docker 镜像
	@echo "$(BLUE)构建 Docker 镜像...$(NC)"
	@docker build -t $(DOCKER_IMAGE) .
	@echo "$(GREEN)Docker 镜像构建完成: $(DOCKER_IMAGE)$(NC)"

.PHONY: docker-run
docker-run: ## 运行 Docker 容器
	@echo "$(BLUE)运行 Docker 容器...$(NC)"
	@docker run --rm -it \
		-p 8080:8080 \
		-p 9090:9090 \
		--env-file .env \
		$(DOCKER_IMAGE)

.PHONY: docker-up
docker-up: ## 启动 Docker Compose 服务
	@echo "$(BLUE)启动 Docker Compose 服务...$(NC)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) up -d
	@echo "$(GREEN)服务已启动$(NC)"
	@echo "$(YELLOW)健康检查: http://localhost:8080/health$(NC)"
	@echo "$(YELLOW)数据库管理: http://localhost:8081$(NC)"
	@echo "$(YELLOW)指标端点: http://localhost:9090/metrics$(NC)"

.PHONY: docker-down
docker-down: ## 停止 Docker Compose 服务
	@echo "$(BLUE)停止 Docker Compose 服务...$(NC)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) down
	@echo "$(GREEN)服务已停止$(NC)"

.PHONY: docker-logs
docker-logs: ## 查看 Docker Compose 日志
	@echo "$(BLUE)查看应用日志...$(NC)"
	@docker-compose -f $(DOCKER_COMPOSE_FILE) logs -f prom-eth-db

.PHONY: docker-restart
docker-restart: docker-down docker-up ## 重启 Docker Compose 服务

# =============================================================================
# 数据库操作
# =============================================================================

.PHONY: db-migrate
db-migrate: ## 执行数据库迁移
	@echo "$(BLUE)执行数据库迁移...$(NC)"
	@if [ -z "$(MYSQL_HOST)" ]; then MYSQL_HOST=localhost; fi; \
	if [ -z "$(MYSQL_PORT)" ]; then MYSQL_PORT=3306; fi; \
	if [ -z "$(MYSQL_USER)" ]; then MYSQL_USER=root; fi; \
	if [ -z "$(MYSQL_DATABASE)" ]; then MYSQL_DATABASE=prometheus_data; fi; \
	mysql -h$$MYSQL_HOST -P$$MYSQL_PORT -u$$MYSQL_USER -p$$MYSQL_DATABASE < scripts/migrate.sql
	@echo "$(GREEN)数据库迁移完成$(NC)"

.PHONY: db-reset
db-reset: ## 重置数据库 (危险操作)
	@echo "$(RED)警告: 这将删除所有数据!$(NC)"
	@echo "$(YELLOW)按 Ctrl+C 取消，或按 Enter 继续...$(NC)"
	@read
	@if [ -z "$(MYSQL_HOST)" ]; then MYSQL_HOST=localhost; fi; \
	if [ -z "$(MYSQL_PORT)" ]; then MYSQL_PORT=3306; fi; \
	if [ -z "$(MYSQL_USER)" ]; then MYSQL_USER=root; fi; \
	if [ -z "$(MYSQL_DATABASE)" ]; then MYSQL_DATABASE=prometheus_data; fi; \
	mysql -h$$MYSQL_HOST -P$$MYSQL_PORT -u$$MYSQL_USER -p -e "DROP DATABASE IF EXISTS $$MYSQL_DATABASE; CREATE DATABASE $$MYSQL_DATABASE;"
	@make db-migrate
	@echo "$(GREEN)数据库重置完成$(NC)"

# =============================================================================
# 开发工具
# =============================================================================

.PHONY: dev
dev: setup ## 快速开发环境启动
	@echo "$(BLUE)启动开发环境...$(NC)"
	@make docker-up
	@echo "$(GREEN)开发环境已启动$(NC)"
	@echo "$(YELLOW)使用 'make run' 启动应用程序$(NC)"
	@echo "$(YELLOW)使用 'make docker-logs' 查看日志$(NC)"

.PHONY: health
health: ## 检查应用健康状态
	@echo "$(BLUE)检查应用健康状态...$(NC)"
	@curl -s http://localhost:8080/health | jq . || echo "$(RED)健康检查失败$(NC)"

.PHONY: metrics
metrics: ## 查看应用指标
	@echo "$(BLUE)查看应用指标...$(NC)"
	@curl -s http://localhost:9090/metrics | head -20

.PHONY: prometheus-test
prometheus-test: ## 测试 Prometheus 连接
	@echo "$(BLUE)测试 Prometheus 连接...$(NC)"
	@curl -s "http://10.20.100.200:30588/select/0/prometheus/api/v1/query?query=up" | jq . || echo "$(RED)Prometheus 连接失败$(NC)"

.PHONY: watch
watch: ## 监控代码变化并自动重启 (需要 air)
	@echo "$(BLUE)启动热重载开发模式...$(NC)"
	@if command -v air >/dev/null 2>&1; then \
		air; \
	else \
		echo "$(YELLOW)air 未安装，使用普通模式$(NC)"; \
		echo "$(YELLOW)安装命令: go install github.com/cosmtrek/air@latest$(NC)"; \
		make run; \
	fi

# =============================================================================
# 发布
# =============================================================================

.PHONY: release
release: clean check test build-all ## 准备发布版本
	@echo "$(BLUE)准备发布版本...$(NC)"
	@echo "$(GREEN)版本: $(VERSION)$(NC)"
	@echo "$(GREEN)构建时间: $(BUILD_TIME)$(NC)"
	@echo "$(GREEN)Go 版本: $(GO_VERSION)$(NC)"
	@echo "$(GREEN)发布准备完成$(NC)"

# =============================================================================
# 查询配置管理
# =============================================================================

.PHONY: config-list
config-list: ## 列出所有查询配置
	@echo "$(BLUE)列出查询配置...$(NC)"
	@./scripts/manage_queries.sh list

.PHONY: config-show
config-show: ## 显示特定查询配置详情 (使用: make config-show QUERY_ID=cpu_usage)
	@echo "$(BLUE)显示查询配置详情...$(NC)"
	@./scripts/manage_queries.sh show $(QUERY_ID)

.PHONY: config-enable
config-enable: ## 启用查询配置 (使用: make config-enable QUERY_ID=cpu_usage)
	@echo "$(BLUE)启用查询配置...$(NC)"
	@./scripts/manage_queries.sh enable $(QUERY_ID)

.PHONY: config-disable
config-disable: ## 禁用查询配置 (使用: make config-disable QUERY_ID=cpu_usage)
	@echo "$(BLUE)禁用查询配置...$(NC)"
	@./scripts/manage_queries.sh disable $(QUERY_ID)

.PHONY: config-backup
config-backup: ## 备份查询配置
	@echo "$(BLUE)备份查询配置...$(NC)"
	@./scripts/manage_queries.sh backup

.PHONY: config-add
config-add: ## 添加新查询配置（交互式）
	@echo "$(BLUE)添加查询配置...$(NC)"
	@./scripts/manage_queries.sh add

.PHONY: run-db
run-db: ## 使用数据库配置模式运行应用
	@echo "$(BLUE)使用数据库配置模式运行应用...$(NC)"
	@go run cmd/server/main_db.go

.PHONY: build-db
build-db: ## 构建数据库配置模式的二进制文件
	@echo "$(BLUE)构建数据库配置模式二进制文件...$(NC)"
	@mkdir -p $(BUILD_DIR)
	@go build $(LDFLAGS) $(GO_FLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-db cmd/server/main_db.go
	@echo "$(GREEN)构建完成: $(BUILD_DIR)/$(BINARY_NAME)-db$(NC)"

# =============================================================================
# 实用工具
# =============================================================================

.PHONY: info
info: ## 显示项目信息
	@echo "$(BLUE)项目信息:$(NC)"
	@echo "  项目名称: $(PROJECT_NAME)"
	@echo "  版本: $(VERSION)"
	@echo "  构建时间: $(BUILD_TIME)"
	@echo "  Go 版本: $(GO_VERSION)"
	@echo "  Docker 镜像: $(DOCKER_IMAGE)"

.PHONY: env
env: ## 显示环境变量
	@echo "$(BLUE)环境变量:$(NC)"
	@env | grep -E "^(PROMETHEUS|MYSQL|LOG|HTTP|WORKER)" | sort

# 默认目标
.DEFAULT_GOAL := help 