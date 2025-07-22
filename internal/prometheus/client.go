package prometheus

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/samzong/prom-etl-db/internal/models"
	"github.com/samzong/prom-etl-db/internal/timeparser"
)

// Client represents a Prometheus client
type Client struct {
	baseURL    string
	httpClient *http.Client
	timeout    time.Duration
}

// NewClient creates a new Prometheus client
func NewClient(baseURL, timeout string) (*Client, error) {
	// Parse timeout
	timeoutDuration, err := time.ParseDuration(timeout)
	if err != nil {
		return nil, fmt.Errorf("invalid timeout format: %w", err)
	}

	// Create HTTP client with timeout
	httpClient := &http.Client{
		Timeout: timeoutDuration,
	}

	return &Client{
		baseURL:    baseURL,
		httpClient: httpClient,
		timeout:    timeoutDuration,
	}, nil
}

// QueryInstant executes an instant query
func (c *Client) QueryInstant(ctx context.Context, query string) (*models.PrometheusResponse, error) {
	return c.QueryInstantWithTime(ctx, query, time.Now())
}

// QueryInstantWithTime executes an instant query at a specific time
func (c *Client) QueryInstantWithTime(ctx context.Context, query string, queryTime time.Time) (*models.PrometheusResponse, error) {
	// Build query URL
	queryURL := fmt.Sprintf("%s/api/v1/query", c.baseURL)

	// Create URL with parameters
	u, err := url.Parse(queryURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse query URL: %w", err)
	}

	params := url.Values{}
	params.Set("query", query)
	params.Set("time", fmt.Sprintf("%d", queryTime.Unix()))
	u.RawQuery = params.Encode()

	return c.executeQuery(ctx, u.String())
}

// QueryWithTimeRange executes a query with time range configuration
func (c *Client) QueryWithTimeRange(ctx context.Context, query string, timeRange *models.TimeRangeConfig) (*models.PrometheusResponse, error) {
	// Create timezone-aware time parser (using Asia/Shanghai)
	parser := timeparser.NewRelativeTimeParser(time.Now())

	switch timeRange.Type {
	case "instant":
		queryTime := time.Now()
		if timeRange.Time != "" {
			var err error
			queryTime, err = parser.Parse(timeRange.Time)
			if err != nil {
				return nil, fmt.Errorf("failed to parse query time: %w", err)
			}
		}
		return c.QueryInstantWithTime(ctx, query, queryTime)

	case "range":
		start, err := parser.Parse(timeRange.Start)
		if err != nil {
			return nil, fmt.Errorf("failed to parse start time: %w", err)
		}

		end, err := parser.Parse(timeRange.End)
		if err != nil {
			return nil, fmt.Errorf("failed to parse end time: %w", err)
		}

		step, err := time.ParseDuration(timeRange.Step)
		if err != nil {
			return nil, fmt.Errorf("failed to parse step duration: %w", err)
		}

		return c.QueryRange(ctx, query, start, end, step)

	default:
		// Default to instant query with current time
		return c.QueryInstant(ctx, query)
	}
}

// executeQuery executes HTTP request and parses response
func (c *Client) executeQuery(ctx context.Context, url string) (*models.PrometheusResponse, error) {
	// Create HTTP request
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "prom-etl-db/1.0")

	// Execute request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	// Check status code
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("prometheus API returned status %d: %s", resp.StatusCode, string(body))
	}

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	// Parse JSON response
	var promResponse models.PrometheusResponse
	if err := json.Unmarshal(body, &promResponse); err != nil {
		return nil, fmt.Errorf("failed to parse JSON response: %w", err)
	}

	// Check response status
	if promResponse.Status != "success" {
		return nil, fmt.Errorf("prometheus query failed with status: %s", promResponse.Status)
	}

	return &promResponse, nil
}

// QueryRange executes a range query
func (c *Client) QueryRange(ctx context.Context, query string, start, end time.Time, step time.Duration) (*models.PrometheusResponse, error) {
	// Build query URL
	queryURL := fmt.Sprintf("%s/api/v1/query_range", c.baseURL)

	// Create URL with parameters
	u, err := url.Parse(queryURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse query URL: %w", err)
	}

	params := url.Values{}
	params.Set("query", query)
	params.Set("start", fmt.Sprintf("%d", start.Unix()))
	params.Set("end", fmt.Sprintf("%d", end.Unix()))
	params.Set("step", fmt.Sprintf("%ds", int(step.Seconds())))
	u.RawQuery = params.Encode()

	// Create HTTP request
	req, err := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "prom-etl-db/1.0")

	// Execute request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	// Check status code
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("prometheus API returned status %d: %s", resp.StatusCode, string(body))
	}

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	// Parse JSON response
	var promResponse models.PrometheusResponse
	if err := json.Unmarshal(body, &promResponse); err != nil {
		return nil, fmt.Errorf("failed to parse JSON response: %w", err)
	}

	// Check response status
	if promResponse.Status != "success" {
		return nil, fmt.Errorf("prometheus query failed with status: %s", promResponse.Status)
	}

	return &promResponse, nil
}

// TestConnection tests the connection to Prometheus
func (c *Client) TestConnection(ctx context.Context) error {
	// Test with a simple query
	_, err := c.QueryInstant(ctx, "up")
	if err != nil {
		return fmt.Errorf("connection test failed: %w", err)
	}
	return nil
}

// GetMetrics returns available metrics
func (c *Client) GetMetrics(ctx context.Context) ([]string, error) {
	// Build query URL
	queryURL := fmt.Sprintf("%s/api/v1/label/__name__/values", c.baseURL)

	// Create HTTP request
	req, err := http.NewRequestWithContext(ctx, "GET", queryURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "prom-etl-db/1.0")

	// Execute request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	// Check status code
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("prometheus API returned status %d: %s", resp.StatusCode, string(body))
	}

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	// Parse JSON response
	var response struct {
		Status string   `json:"status"`
		Data   []string `json:"data"`
	}

	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("failed to parse JSON response: %w", err)
	}

	// Check response status
	if response.Status != "success" {
		return nil, fmt.Errorf("prometheus query failed with status: %s", response.Status)
	}

	return response.Data, nil
}

// Close closes the client
func (c *Client) Close() error {
	// HTTP client doesn't need explicit closing
	return nil
}
