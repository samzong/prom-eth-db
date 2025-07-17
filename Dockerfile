# Multi-stage build for Go application
# Build stage
FROM golang:1.21-alpine AS builder

# Set build arguments for version info
ARG VERSION=dev
ARG BUILD_TIME
ARG GO_VERSION

# Install git (needed for go modules)
RUN apk add --no-cache git

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies with retry and proxy configuration
ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags "-X main.version=${VERSION} -X main.buildTime=${BUILD_TIME} -X main.goVersion=${GO_VERSION}" \
    -o prom-eth-db \
    ./cmd/server/main.go

# Runtime stage
FROM alpine:latest

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates

# Create non-root user
RUN addgroup -g 1001 appuser && \
    adduser -D -u 1001 -G appuser appuser

# Set working directory
WORKDIR /app

# Copy binary from build stage
COPY --from=builder /app/prom-eth-db .

# Copy configuration files
COPY --from=builder /app/configs ./configs

# Create logs directory
RUN mkdir -p logs && chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose ports
EXPOSE 8080 9090

# Note: Health check disabled for MVP version as HTTP server is not yet implemented
# HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
#   CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the application
CMD ["./prom-eth-db"] 