# Prometheus to MySQL ETL - Makefile

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
DOCKER_COMPOSE_FILE := docker-compose.yaml

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
# 构建
# =============================================================================

.PHONY: build
build: ## 构建二进制文件
	@echo "$(BLUE)构建二进制文件...$(NC)"
	@mkdir -p $(BUILD_DIR)
	@go build $(LDFLAGS) $(GO_FLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) $(MAIN_PATH)
	@echo "$(GREEN)构建完成: $(BUILD_DIR)/$(BINARY_NAME)$(NC)"

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

# =============================================================================
# 实用工具
# =============================================================================

.PHONY: env
env: ## 显示环境变量
	@echo "$(BLUE)环境变量:$(NC)"
	@env | grep -E "^(PROMETHEUS|MYSQL|LOG|HTTP|WORKER)" | sort

# 默认目标
.DEFAULT_GOAL := help
