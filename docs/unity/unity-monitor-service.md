# Unity Monitor Service Documentation

## Overview

The Unity Monitor Service provides comprehensive monitoring, telemetry collection, health check orchestration, alert management, and performance analytics for the GeuseMaker deployment system. It unifies all monitoring operations into a single, coherent service interface.

## Features

### 1. **Unified Telemetry Collection**
- System metrics (CPU, memory, disk usage)
- Application metrics (service status, endpoints)
- AWS infrastructure metrics (EC2, CloudFormation stacks)
- Custom metrics with time-series storage

### 2. **Intelligent Health Check Orchestration**
- Comprehensive health checks (system, services, infrastructure, applications)
- Auto-recovery mechanisms
- Configurable check intervals and timeouts
- Health status tracking and history

### 3. **Advanced Alert Management**
- Multi-channel alerts (log, console, webhook, SNS, Slack, email)
- Alert throttling to prevent spam
- Severity-based routing
- Alert aggregation and correlation

### 4. **Performance Analytics**
- Real-time metrics collection
- Performance baselines and thresholds
- Trend analysis and anomaly detection
- Resource usage tracking

### 5. **Centralized Logging**
- Log aggregation from multiple sources
- Pattern detection and analysis
- Log rotation and retention policies
- Structured logging support

### 6. **Distributed Tracing**
- Operation tracing with unique IDs
- Parent-child trace relationships
- Performance profiling
- Cross-service correlation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Unity Monitor Service                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   Health    │  │    Alert     │  │     Metrics      │   │
│  │   Checks    │  │  Management  │  │   Collection     │   │
│  └──────┬──────┘  └──────┬───────┘  └────────┬─────────┘   │
│         │                 │                    │             │
│  ┌──────┴─────────────────┴────────────────────┴────────┐   │
│  │              Core Monitoring Engine                   │   │
│  └──────┬─────────────────┬────────────────────┬────────┘   │
│         │                 │                    │             │
│  ┌──────┴──────┐  ┌──────┴───────┐  ┌────────┴─────────┐   │
│  │     Log     │  │   Tracing    │  │   Performance    │   │
│  │ Aggregation │  │   System     │  │    Analytics     │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Usage

### Initialization

```bash
# Source the service
source lib/unity/services/unity-monitor-service.sh

# Initialize the monitoring service
unity_monitor_init
```

### Health Checks

```bash
# Run comprehensive health check
unity_monitor_health_check "all"

# Check specific component
unity_monitor_health_check "system"
unity_monitor_health_check "service"
unity_monitor_health_check "infrastructure"
unity_monitor_health_check "application"

# Check specific service
unity_monitor_health_check "unity-aws"
```

### Alert Management

```bash
# Send an alert
unity_monitor_alert "warning" "High CPU Usage" "CPU usage is at 85%"

# Send critical alert with tags
unity_monitor_alert "critical" "Service Down" "API service is not responding" "service:api,env:prod"
```

### Metrics Collection

```bash
# Collect metrics (async by default)
unity_monitor_collect_metrics

# Collect metrics synchronously
unity_monitor_collect_metrics "false"
```

### Log Analysis

```bash
# Aggregate logs from all sources
unity_monitor_aggregate_logs "all" "json"

# Analyze logs for patterns
unity_monitor_analyze_logs "pattern" "1h"

# Detect anomalies
unity_monitor_analyze_logs "anomaly" "24h"
```

### Distributed Tracing

```bash
# Start a trace
trace_id=$(unity_monitor_start_trace "deployment_operation")

# Do some work...

# End the trace
unity_monitor_end_trace "$trace_id" "success"
```

### Service Lifecycle

```bash
# Start the monitoring service
unity_monitor_start

# Get service status
unity_monitor_status

# Stop the monitoring service
unity_monitor_stop
```

## Configuration

### Environment Variables

```bash
# Health check configuration
HEALTH_CHECK_INTERVAL=60           # Seconds between health checks
HEALTH_CHECK_TIMEOUT=30            # Timeout for each check
HEALTH_CHECK_RETRIES=3             # Number of retries
AUTO_RECOVERY_ENABLED=true         # Enable auto-recovery

# Alert configuration
ALERT_CHANNELS_ENABLED="log,console"  # Comma-separated channels
ALERT_THROTTLE_MINUTES=5             # Alert throttling period
ALERT_WEBHOOK_URL=""                 # Webhook for alerts
ALERT_SNS_TOPIC=""                   # AWS SNS topic ARN
ALERT_SLACK_WEBHOOK=""               # Slack webhook URL
ALERT_EMAIL_ADDRESS=""               # Email for alerts

# Performance configuration
PERF_COLLECTION_INTERVAL=30        # Metric collection interval
PERF_RETENTION_DAYS=30            # Metric retention period
PERF_ANALYTICS_ENABLED=true       # Enable analytics

# Directory configuration
MONITOR_STATE_DIR=".unity/monitoring"
MONITOR_METRICS_DIR="$MONITOR_STATE_DIR/metrics"
MONITOR_LOGS_DIR="$MONITOR_STATE_DIR/logs"
MONITOR_ALERTS_DIR="$MONITOR_STATE_DIR/alerts"
```

### Configuration Files

#### Health Check Registry (`health_registry.conf`)
```
# Format: service:check_type:interval:timeout:retries
system:basic:60:30:3
aws:connectivity:300:60:2
docker:service:120:45:3
application:endpoint:60:30:3
infrastructure:resources:300:90:2
```

#### Application Endpoints (`app_endpoints.conf`)
```
# Format: name|url|expected_code|timeout
api|http://localhost:8080/health|200|5
webapp|http://localhost:3000|200|10
database|http://localhost:5432/ping|200|3
```

#### Performance Baseline (`performance_baseline.json`)
```json
{
  "deployment_time": {"p50": 180, "p95": 240, "p99": 300},
  "api_response_time": {"p50": 100, "p95": 500, "p99": 1000},
  "resource_usage": {
    "cpu": {"normal": 20, "warning": 70, "critical": 90},
    "memory": {"normal": 50, "warning": 80, "critical": 95},
    "disk": {"normal": 60, "warning": 80, "critical": 90}
  }
}
```

## Auto-Recovery Mechanisms

The service includes intelligent auto-recovery for common issues:

### System Recovery
- Clear caches when memory usage is high
- Clean up disk space by removing old logs
- Optimize system resources

### Service Recovery
- Restart stopped Unity services
- Restart failed Docker containers
- Re-initialize service connections

### Infrastructure Recovery
- Refresh AWS credentials
- Reset network connections
- Clear DNS caches

### Application Recovery
- Restart application endpoints
- Reset database connections
- Clear application caches

## Metrics Storage

Metrics are stored in multiple formats for efficient access:

1. **Metrics Database** (`metrics.db`)
   - CSV format: `timestamp,metric_name,value,unit,tags`
   - Central repository for all metrics

2. **Time-Series Files** (`metrics/YYYY/MM/DD/metric_name.tsv`)
   - Quick access to specific metrics
   - Efficient for trend analysis

3. **Alert History** (`alerts/alert_history.log`)
   - Chronological alert records
   - Used for alert correlation

## Bash Compatibility

The service is compatible with both Bash 3.x (macOS) and Bash 4.x+ (Linux):

- **Bash 4+**: Uses associative arrays for efficient storage
- **Bash 3**: Falls back to file-based storage
- **Cross-platform**: Works on macOS, Linux, and AWS environments

## Integration with GeuseMaker

The Unity Monitor Service integrates seamlessly with GeuseMaker's deployment system:

1. **Deployment Monitoring**: Track deployment progress and health
2. **Resource Monitoring**: Monitor AWS resources during deployment
3. **Cost Tracking**: Alert on cost thresholds
4. **Performance Optimization**: Identify and resolve bottlenecks
5. **Security Monitoring**: Track security events and compliance

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Permission denied errors | Ensure proper directory permissions |
| Missing metrics | Check collector registration and intervals |
| Alert not received | Verify channel configuration and credentials |
| High memory usage | Adjust retention policies and clean old data |
| Service won't start | Check dependencies and initialization |

### Debug Mode

Enable debug logging:
```bash
export UNITY_LOG_LEVEL="DEBUG"
export MONITOR_DEBUG="true"
```

### Manual Cleanup

```bash
# Clean old metrics
find "$MONITOR_METRICS_DIR" -name "*.tsv" -mtime +30 -delete

# Clean old alerts
find "$MONITOR_ALERTS_DIR" -name "*.json" -mtime +7 -delete

# Reset monitoring state
rm -rf "$MONITOR_STATE_DIR"
unity_monitor_init
```

## Performance Considerations

1. **Metric Collection**: Adjust intervals based on system load
2. **Log Aggregation**: Use batch mode for large volumes
3. **Alert Throttling**: Prevent alert storms
4. **Storage Management**: Implement retention policies
5. **Memory Usage**: Monitor service memory consumption

## Security

1. **Credential Management**: Use AWS Parameter Store for sensitive data
2. **Alert Sanitization**: Remove sensitive data from alerts
3. **Access Control**: Restrict monitoring data access
4. **Audit Trail**: Log all monitoring operations
5. **Encryption**: Encrypt metrics and logs at rest

## Future Enhancements

1. **Machine Learning**: Anomaly detection using ML
2. **Predictive Analytics**: Forecast resource usage
3. **Custom Dashboards**: Web-based monitoring UI
4. **Plugin System**: Extensible monitoring plugins
5. **Multi-Region Support**: Cross-region monitoring