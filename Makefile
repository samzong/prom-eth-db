# Prometheus to MySQL ETL - Makefile

# 项目配置
PROJECT_NAME := prom-etl-db
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
GO_VERSION := $(shell go version | awk '{print $$3}')

# 构建配置
BINARY_NAME := prom-etl-db
MAIN_PATH := ./cmd/server
BUILD_DIR := ./build
DOCKER_REGISTRY := release.daocloud.io/ndx-product
DOCKER_IMAGE := $(DOCKER_REGISTRY)/prom-etl-db
DOCKER_TAG ?= $(shell echo $${DOCKER_TAG:-v0.1.2})

# Go 构建标志
LDFLAGS := -ldflags "-X main.version=$(VERSION) -X main.buildTime=$(BUILD_TIME) -X main.goVersion=$(GO_VERSION)"

# 颜色输出
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m

.PHONY: help
help: ## 显示帮助信息
	@echo "$(BLUE)$(PROJECT_NAME) - 开发工具$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# 开发环境
.PHONY: setup
setup: ## 设置开发环境
	@go mod download && go mod tidy
	@if [ ! -f .env ]; then cp env.example .env; echo "$(GREEN)已创建 .env 文件$(NC)"; fi
	@mkdir -p $(BUILD_DIR) logs

.PHONY: fmt
fmt: ## 格式化Go代码
	@echo "$(BLUE)格式化Go代码...$(NC)"
	@go fmt ./...
	@echo "$(GREEN)代码格式化完成$(NC)"

.PHONY: clean
clean: ## 清理构建文件
	@rm -rf $(BUILD_DIR) logs/*
	@go clean -cache

# 构建和运行
.PHONY: build
build: ## 构建二进制文件
	@mkdir -p $(BUILD_DIR)
	@go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) $(MAIN_PATH)
	@echo "$(GREEN)构建完成: $(BUILD_DIR)/$(BINARY_NAME)$(NC)"

.PHONY: debug
debug: ## 调试运行应用程序
	@if [ ! -f .env ]; then echo "$(RED)错误: .env 文件不存在，请先运行 make setup$(NC)"; exit 1; fi
	@export $$(cat .env | grep -v '^#' | xargs) && go run $(MAIN_PATH)

# Docker
.PHONY: docker-build
docker-build: ## 构建 Docker 镜像 (Linux x86_64)
	@docker build --platform linux/amd64 \
		--build-arg VERSION=$(VERSION) \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		--build-arg GO_VERSION=$(GO_VERSION) \
		-t $(DOCKER_IMAGE):$(DOCKER_TAG) .
	@echo "$(GREEN)Docker 镜像: $(DOCKER_IMAGE):$(DOCKER_TAG)$(NC)"

.PHONY: docker-push
docker-push: ## 推送 Docker 镜像
	@docker push $(DOCKER_IMAGE):$(DOCKER_TAG)

.PHONY: docker-build-push
docker-build-push: docker-build docker-push ## 构建并推送 Docker 镜像

# 默认目标
.DEFAULT_GOAL := help