# GeuseMaker Monitoring System Guide

Comprehensive monitoring, observability, and debugging capabilities for AWS deployments.

## Overview

The GeuseMaker monitoring system provides enterprise-grade observability for your AI infrastructure deployments with:

- **Structured Logging**: JSON-formatted logs with aggregation and analysis
- **Observability Framework**: Metrics, traces, and events collection
- **Real-time Dashboards**: Deployment visualization and monitoring
- **Intelligent Alerting**: Rule-based alerts with auto-remediation
- **Performance Metrics**: Comprehensive metrics collection and reporting
- **Debug Tools**: Advanced troubleshooting and diagnostics
- **Log Aggregation**: Centralized log collection and pattern analysis

## Quick Start

### Basic Usage

```bash
# Deploy with monitoring enabled (default)
./scripts/aws-deployment-modular.sh --monitoring standard my-stack

# Deploy with comprehensive monitoring
./scripts/aws-deployment-modular.sh --monitoring comprehensive prod-stack

# Deploy with debug monitoring
./scripts/aws-deployment-modular.sh --monitoring debug --monitoring-dir /tmp/debug dev-stack

# Deploy without monitoring
./scripts/aws-deployment-modular.sh --no-monitoring minimal-stack
```

### Monitoring Profiles

| Profile | Description | Use Case |
|---------|-------------|----------|
| `minimal` | Basic logging and critical alerts only | Development, testing |
| `standard` | Structured logging, metrics, alerts | Production deployments |
| `comprehensive` | Full observability with real-time collection | Mission-critical systems |
| `debug` | All features plus debug tools and tracing | Troubleshooting |

## Architecture

### Module Structure

```
lib/modules/monitoring/
├── integration.sh          # Main integration module
├── structured_logging.sh   # JSON logging with aggregation
├── observability.sh        # Metrics, traces, events
├── alerting.sh            # Alert management system
├── performance_metrics.sh  # Performance collection
├── dashboards.sh          # Real-time dashboards
├── debug_tools.sh         # Debugging utilities
└── log_aggregation.sh     # Log collection and analysis
```

### Data Flow

```
Deployment Events → Structured Logging → Aggregation → Analysis
                 ↓                    ↓              ↓
              Metrics → Dashboards → Alerts → Reports
                     ↓            ↓         ↓
                  Traces → Debug Tools → CloudWatch
```

## Features

### 1. Structured Logging

#### JSON Format Logging
```bash
# Initialize structured logging
init_structured_logging "json" "/var/log/deployment.json" "true"

# Log structured events
log_structured_event "INFO" "VPC created" "infrastructure" "create" \
    '{"vpc_id": "vpc-123", "cidr": "10.0.0.0/16"}'

# Log deployment events
log_deployment_event "start" '{"stack": "prod-stack", "region": "us-east-1"}'

# Log infrastructure events
log_infrastructure_event "instance" "launch" "i-1234567" "success" \
    '{"type": "g4dn.xlarge", "az": "us-east-1a"}'
```

#### Log Aggregation
```bash
# Query aggregated logs
query_aggregated_logs '[.[] | select(.level == "ERROR")] | .[-10:]'

# Get log statistics
get_aggregated_log_stats

# Generate log report
generate_aggregation_report "/tmp/log_report.txt" 86400  # Last 24 hours
```

### 2. Observability Framework

#### Metrics Collection
```bash
# Initialize observability
init_observability "detailed" "metrics,logs,traces,events"

# Record metrics
record_metric "deployment.duration" "300" "seconds" "deployment"
record_metric "service.health" "1" "bool" "health" '{"service": "n8n"}'

# Collect system metrics
collect_system_metrics      # CPU, memory, disk, network
collect_deployment_metrics  # Deployment-specific metrics
```

#### Distributed Tracing
```bash
# Start trace
trace_id=$(start_trace "deployment" "" '{"stack": "prod-stack"}')

# Add trace annotations
add_trace_annotation "$trace_id" "phase" "infrastructure"
add_trace_annotation "$trace_id" "vpc_id" "vpc-123456"

# End trace
end_trace "$trace_id" "ok"
```

#### Event Tracking
```bash
# Track custom events
track_event "deployment_milestone" '{"phase": "complete"}' "milestone"

# Track errors
track_error_event "$ERROR_AWS_QUOTA_EXCEEDED" "Instance limit reached" \
    '{"requested": "g4dn.xlarge", "region": "us-east-1"}'
```

### 3. Real-time Dashboards

#### Create Dashboards
```bash
# Create deployment dashboard
dashboard_id=$(create_dashboard "prod-deployment" "deployment")

# Add custom widgets
add_widget_to_dashboard "$dashboard_id" "cpu_usage" "CPU Usage" "chart" \
    '{"metrics": ["system.cpu.usage"], "refresh": 30}'

# Render dashboard
render_dashboard "$dashboard_id" "console"  # Console output
render_dashboard "$dashboard_id" "html"     # HTML format
render_dashboard "$dashboard_id" "json"     # JSON export
```

#### Dashboard Types
- **Deployment**: Overall deployment status and progress
- **Infrastructure**: VPC, subnet, instance details
- **Services**: Application service health
- **Performance**: System and application metrics
- **Errors**: Error tracking and analysis

### 4. Intelligent Alerting

#### Alert Management
```bash
# Initialize alerting
init_alerting "log,console,webhook" "$WEBHOOK_URL" "$SNS_TOPIC"

# Create alerts
alert_id=$(create_alert "high_cpu" "warning" "CPU usage above 80%" "system" \
    '{"cpu_usage": 85, "threshold": 80}')

# Resolve alerts
resolve_alert "$alert_id" "CPU usage normalized"
```

#### Alert Rules
```bash
# Add custom alert rules
add_alert_rule "deployment_timeout" "Deployment Timeout" "critical" \
    '{"condition": "deployment_duration > 1800", "window": 60}'

# Evaluate rules with context
evaluate_alert_rules '{"deployment_duration": 2000, "error_rate": 5}'
```

#### Alert Channels
- **Log**: Structured log entries
- **Console**: Terminal output with colors
- **Webhook**: HTTP POST to custom endpoints
- **SNS**: AWS Simple Notification Service
- **Slack**: Slack webhook integration

### 5. Performance Metrics

#### Metric Collection
```bash
# Initialize performance metrics
init_performance_metrics 60 true  # 60s interval, aggregation enabled

# Record metrics
record_performance_metric "api.latency" "250" "histogram" "ms" \
    '{"endpoint": "/health", "method": "GET"}'

# Query metrics
query_metrics "api\.latency" 3600 "avg"  # Average latency last hour

# Get metric statistics
get_metric_statistics "system.cpu.usage" 3600
```

#### Metric Types
- **Counter**: Monotonically increasing values
- **Gauge**: Point-in-time measurements
- **Histogram**: Distribution of values
- **Summary**: Statistical summaries

### 6. Debug Tools

#### Debug Logging
```bash
# Initialize debug tools
init_debug_tools "verbose" "/tmp/debug" true

# Debug logging
debug_log $DEBUG_LEVEL_BASIC "Starting deployment" "DEPLOY"
debug_var "INSTANCE_TYPE"  # Log variable value

# Function instrumentation
debug_function_entry "$@"
# ... function code ...
debug_function_exit $?
```

#### Breakpoints
```bash
# Set breakpoint
set_breakpoint "pre_deployment" 'test "$VALIDATE_ONLY" = "true"'

# Check breakpoint (enters debug shell if condition met)
check_breakpoint "pre_deployment"
```

#### Diagnostics
```bash
# Run full diagnostics
run_diagnostics "/tmp/diagnostics.txt"

# Create debug dump
debug_dump=$(create_debug_dump "deployment_issue")
echo "Debug dump created: $debug_dump"

# Troubleshoot specific issues
troubleshoot_deployment "timeout"    # Timeout issues
troubleshoot_deployment "failed"     # Failure analysis
troubleshoot_deployment "network"    # Network problems
```

### 7. Log Aggregation and Analysis

#### Log Collection
```bash
# Initialize log aggregation
init_log_aggregation "realtime" "/var/log/aggregation" 7

# Register custom collector
register_log_collector "app_logs" "collect_app_logs" "application" \
    '{"paths": ["/var/log/n8n/*.log"]}'

# Search logs
search_logs "error" 3600 false  # Case-insensitive search
```

#### Pattern Detection
```bash
# Analyze patterns
analyze_patterns      # Detect error patterns
analyze_trends        # Volume and trend analysis
analyze_correlations  # Find correlated events

# Get insights
generate_insights  # AI-powered insights
```

## Integration

### Deployment Script Integration

The monitoring system automatically integrates with deployment phases:

```bash
# Pre-deployment
monitor_pre_deployment "$STACK_NAME"

# Phase monitoring
monitor_deployment_phase "infrastructure" "start"
# ... infrastructure setup ...
monitor_deployment_phase "infrastructure" "end"

# AWS operations
monitor_aws_operation "create" "vpc" "" "aws ec2 create-vpc ..."

# Service health
monitor_service_health "n8n" "healthy"

# Post-deployment
monitor_post_deployment "success"
```

### CloudWatch Integration

```bash
# Export metrics to CloudWatch
export_metrics_to_cloudwatch "GeuseMaker" 300  # Last 5 minutes

# Create CloudWatch dashboard
create_cloudwatch_dashboard "prod-stack" "GeuseMaker"

# Create CloudWatch alarms
create_monitoring_alarms "prod-stack" "GeuseMaker"
```

## Configuration

### Environment Variables

```bash
# Monitoring control
export MONITORING_ENABLED=true
export MONITORING_PROFILE=comprehensive
export MONITORING_OUTPUT_DIR=/var/log/monitoring

# Component control
export TRACE_ENABLED=true
export TRACE_SAMPLING_RATE=0.1
export DEBUG_ENABLED=true
export DEBUG_LEVEL=2

# Alert configuration
export ALERT_WEBHOOK_URL="https://example.com/webhook"
export ALERT_SNS_TOPIC="arn:aws:sns:us-east-1:123456789012:alerts"
export ALERT_SLACK_WEBHOOK="https://hooks.slack.com/services/..."

# CloudWatch integration
export CLOUDWATCH_METRICS_NAMESPACE="GeuseMaker/Production"
```

### Configuration Files

#### Alert Rules (JSON)
```json
[
  {
    "id": "high_error_rate",
    "name": "High Error Rate",
    "severity": "critical",
    "conditions": {
      "condition": "error_rate > 10",
      "window": 300,
      "threshold": 2
    }
  }
]
```

#### Dashboard Configuration
```json
{
  "name": "Production Dashboard",
  "refresh_interval": 30,
  "widgets": [
    {
      "id": "deployment_status",
      "type": "status",
      "position": {"row": 0, "col": 0, "width": 12, "height": 4}
    }
  ]
}
```

## Troubleshooting

### Common Issues

#### Monitoring Not Starting
```bash
# Check if monitoring is available
if [[ "$MONITORING_AVAILABLE" == "true" ]]; then
    echo "Monitoring is available"
else
    echo "Monitoring modules not loaded"
    # Check library path
    ls -la "$LIB_DIR/modules/monitoring/"
fi
```

#### Missing Metrics
```bash
# Verify metrics collection is running
ps aux | grep "perf_metrics_collector"

# Check metrics storage
cat "$PERF_METRICS_STORAGE_FILE" | jq '.[-10:]'

# Force metric collection
run_metric_collectors
```

#### Alert Not Firing
```bash
# Check alert rules
cat "$ALERT_RULES_FILE" | jq '.'

# Manually evaluate rules
evaluate_alert_rules '{"error_rate": 15}'

# Check alert history
get_alert_history 3600 | jq '.'
```

### Debug Mode

```bash
# Enable maximum debugging
export DEBUG_ENABLED=true
export DEBUG_LEVEL=4  # TRACE level
export MONITORING_PROFILE=debug

# Run deployment with debug monitoring
./scripts/aws-deployment-modular.sh \
    --monitoring debug \
    --monitoring-dir /tmp/debug_session \
    debug-stack

# Analyze debug output
cat /tmp/debug_session/debug.log
cat /tmp/debug_session/diagnostics.txt
```

## Performance Considerations

### Resource Usage

- **Minimal Profile**: ~5MB memory, <1% CPU
- **Standard Profile**: ~20MB memory, 1-2% CPU
- **Comprehensive Profile**: ~50MB memory, 2-5% CPU
- **Debug Profile**: ~100MB memory, 5-10% CPU

### Optimization Tips

1. **Sampling**: Reduce trace sampling rate for high-volume deployments
   ```bash
   export TRACE_SAMPLING_RATE=0.01  # 1% sampling
   ```

2. **Batch Size**: Increase batch size for log aggregation
   ```bash
   export LOG_AGG_BATCH_SIZE=5000
   ```

3. **Metric Intervals**: Adjust collection intervals
   ```bash
   export METRICS_COLLECTION_INTERVAL=300  # 5 minutes
   ```

4. **Log Rotation**: Configure aggressive rotation
   ```bash
   export LOG_AGG_RETENTION_DAYS=3
   ```

## Examples

See `/examples/monitoring-example.sh` for comprehensive examples:

```bash
# Run interactive examples
./examples/monitoring-example.sh

# Run specific example
bash -c "source ./examples/monitoring-example.sh && comprehensive_monitoring_example"
```

## API Reference

For detailed API documentation, see the source files:

- [integration.sh](../lib/modules/monitoring/integration.sh) - Main integration API
- [structured_logging.sh](../lib/modules/monitoring/structured_logging.sh) - Logging API
- [observability.sh](../lib/modules/monitoring/observability.sh) - Observability API
- [alerting.sh](../lib/modules/monitoring/alerting.sh) - Alerting API
- [performance_metrics.sh](../lib/modules/monitoring/performance_metrics.sh) - Metrics API
- [dashboards.sh](../lib/modules/monitoring/dashboards.sh) - Dashboard API
- [debug_tools.sh](../lib/modules/monitoring/debug_tools.sh) - Debug API
- [log_aggregation.sh](../lib/modules/monitoring/log_aggregation.sh) - Aggregation API