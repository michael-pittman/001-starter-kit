# Monitoring API Reference

> Complete API documentation for GeuseMaker monitoring and health check services

## Overview

The GeuseMaker monitoring system provides comprehensive health checks, metrics collection, and system status reporting across all services and infrastructure components.

**Base URLs**: Multiple endpoints across services
**Authentication**: None (internal services)
**Monitoring Stack**: Unity Monitor Service + CloudWatch + Custom metrics

## Unity Monitoring API

### System Health Check

Get overall system health status.

```bash
GET /api/health
```

**Example Request:**
```bash
curl http://your-ip:8080/api/health
```

**Example Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "services": {
    "unity-core": {
      "status": "healthy",
      "uptime": 3600,
      "version": "2.0.0"
    },
    "aws-service": {
      "status": "healthy",
      "last_check": "2024-01-01T11:59:00Z",
      "resources": {
        "ec2_instances": 2,
        "vpcs": 1,
        "albs": 1
      }
    },
    "docker-service": {
      "status": "healthy",
      "containers_running": 4,
      "containers_total": 4
    }
  },
  "infrastructure": {
    "aws": {
      "region": "us-east-1",
      "account_id": "123456789012",
      "quotas_ok": true
    },
    "compute": {
      "cpu_usage": 45.2,
      "memory_usage": 67.8,
      "disk_usage": 23.4
    }
  }
}
```

### Service-Specific Health

Check health of individual services.

```bash
GET /api/health/{service}
```

**Available Services:**
- `unity-core`: Core Unity system
- `aws-service`: AWS infrastructure management
- `docker-service`: Container management
- `monitor-service`: Monitoring system itself

**Example Request:**
```bash
curl http://your-ip:8080/api/health/aws-service
```

**Example Response:**
```json
{
  "service": "aws-service",
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "details": {
    "aws_connectivity": "ok",
    "credentials": "valid",
    "permissions": "sufficient",
    "resources": {
      "ec2_instances": {
        "running": 2,
        "stopped": 0,
        "terminated": 0
      },
      "load_balancers": {
        "active": 1,
        "provisioning": 0
      }
    },
    "last_operation": {
      "type": "instance_health_check",
      "timestamp": "2024-01-01T11:58:30Z",
      "status": "success"
    }
  }
}
```

### Metrics Collection

Get system and service metrics.

```bash
GET /api/metrics
```

**Query Parameters:**
- `service`: Filter by service name
- `timerange`: Time range (1h, 24h, 7d)
- `resolution`: Data resolution (1m, 5m, 1h)

**Example Request:**
```bash
curl "http://your-ip:8080/api/metrics?service=aws-service&timerange=1h&resolution=5m"
```

**Example Response:**
```json
{
  "service": "aws-service",
  "timerange": "1h",
  "resolution": "5m",
  "timestamp": "2024-01-01T12:00:00Z",
  "metrics": {
    "system": {
      "cpu_usage": [
        {"timestamp": "2024-01-01T11:00:00Z", "value": 45.2},
        {"timestamp": "2024-01-01T11:05:00Z", "value": 42.1}
      ],
      "memory_usage": [
        {"timestamp": "2024-01-01T11:00:00Z", "value": 67.8},
        {"timestamp": "2024-01-01T11:05:00Z", "value": 69.2}
      ]
    },
    "service_specific": {
      "aws_api_calls": [
        {"timestamp": "2024-01-01T11:00:00Z", "value": 15},
        {"timestamp": "2024-01-01T11:05:00Z", "value": 12}
      ],
      "resource_count": [
        {"timestamp": "2024-01-01T11:00:00Z", "value": 8},
        {"timestamp": "2024-01-01T11:05:00Z", "value": 8}
      ]
    }
  }
}
```

### Real-time Monitoring

WebSocket endpoint for real-time monitoring updates.

```bash
WS /api/monitor/realtime
```

**WebSocket Message Format:**
```json
{
  "type": "health_update",
  "timestamp": "2024-01-01T12:00:00Z",
  "service": "docker-service",
  "status": "healthy",
  "data": {
    "containers_running": 4,
    "cpu_usage": 23.4,
    "memory_usage": 512
  }
}
```

## Service-Specific Monitoring

### n8n Monitoring

Monitor n8n workflow engine.

```bash
GET http://your-ip:5678/healthz
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-01T12:00:00Z",
  "database": "connected",
  "workflows": {
    "total": 5,
    "active": 3,
    "paused": 2
  },
  "executions": {
    "running": 2,
    "queued": 0,
    "completed_today": 150
  }
}
```

### Ollama Monitoring

Monitor LLM service status and performance.

```bash
GET http://your-ip:11434/api/tags
```

**Custom Health Check:**
```bash
curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b",
    "prompt": "test",
    "stream": false,
    "options": {"max_tokens": 1}
  }'
```

**Health Response:**
```json
{
  "status": "healthy",
  "models_loaded": 2,
  "active_requests": 1,
  "gpu_status": {
    "available": true,
    "memory_used": "8.2GB",
    "memory_total": "16GB",
    "utilization": 51
  },
  "performance": {
    "average_response_time": 2.3,
    "tokens_per_second": 45.2
  }
}
```

### Qdrant Monitoring

Monitor vector database health and performance.

```bash
GET http://your-ip:6333/health
```

**Detailed Metrics:**
```bash
GET http://your-ip:6333/metrics
```

**Custom Health Check:**
```bash
curl http://your-ip:6333/collections
```

**Health Response:**
```json
{
  "status": "ok",
  "version": "1.7.3",
  "collections": 3,
  "total_points": 10000,
  "memory_usage": {
    "resident": "2.1GB",
    "virtual": "3.5GB"
  },
  "performance": {
    "average_search_time": 0.045,
    "indexing_rate": 1000
  }
}
```

### Crawl4AI Monitoring

Monitor web scraping service.

```bash
GET http://your-ip:11235/health
```

**Response:**
```json
{
  "status": "healthy",
  "version": "0.2.77",
  "uptime": 3600,
  "active_crawls": 2,
  "queue_size": 5,
  "browser_status": "running",
  "performance": {
    "average_crawl_time": 2.8,
    "success_rate": 0.95,
    "cache_hit_rate": 0.75
  }
}
```

## AWS CloudWatch Integration

### Custom Metrics

Unity automatically publishes custom metrics to CloudWatch.

**Metric Namespaces:**
- `GeuseMaker/Unity`: Core Unity metrics
- `GeuseMaker/Services`: Service-specific metrics
- `GeuseMaker/Applications`: Application-level metrics

**Example Metrics:**
```bash
# Get Unity service health metrics
aws cloudwatch get-metric-statistics \
  --namespace "GeuseMaker/Unity" \
  --metric-name "ServiceHealth" \
  --dimensions Name=ServiceName,Value=aws-service \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T12:00:00Z \
  --period 300 \
  --statistics Average
```

### CloudWatch Alarms

Automated alarm creation for critical metrics:

```json
{
  "AlarmName": "GeuseMaker-HighCPU",
  "ComparisonOperator": "GreaterThanThreshold",
  "EvaluationPeriods": 2,
  "MetricName": "CPUUtilization",
  "Namespace": "AWS/EC2",
  "Period": 300,
  "Statistic": "Average",
  "Threshold": 80.0,
  "ActionsEnabled": true,
  "AlarmActions": [
    "arn:aws:sns:us-east-1:123456789012:geusemaker-alerts"
  ]
}
```

### Dashboard Creation

Automated CloudWatch dashboard:

```bash
# Create dashboard
./scripts/unity-cli.sh monitoring setup-dashboard my-stack
```

## Integration Examples

### Python Monitoring Client

```python
import requests
import websocket
import json
import threading
from typing import Dict, List, Callable

class MonitoringClient:
    def __init__(self, base_url: str = "http://localhost:8080"):
        self.base_url = base_url
        self.ws = None
        self.callbacks = {}
    
    def get_system_health(self) -> Dict:
        """Get overall system health"""
        response = requests.get(f"{self.base_url}/api/health")
        return response.json()
    
    def get_service_health(self, service: str) -> Dict:
        """Get specific service health"""
        response = requests.get(f"{self.base_url}/api/health/{service}")
        return response.json()
    
    def get_metrics(
        self, 
        service: str = None, 
        timerange: str = "1h",
        resolution: str = "5m"
    ) -> Dict:
        """Get service metrics"""
        params = {
            "timerange": timerange,
            "resolution": resolution
        }
        if service:
            params["service"] = service
            
        response = requests.get(
            f"{self.base_url}/api/metrics",
            params=params
        )
        return response.json()
    
    def check_all_services(self) -> Dict:
        """Check health of all services"""
        services = [
            "unity-core",
            "aws-service", 
            "docker-service",
            "monitor-service"
        ]
        
        results = {}
        for service in services:
            try:
                results[service] = self.get_service_health(service)
            except Exception as e:
                results[service] = {
                    "status": "error",
                    "error": str(e)
                }
        
        return results
    
    def start_realtime_monitoring(self, callback: Callable):
        """Start real-time monitoring via WebSocket"""
        def on_message(ws, message):
            data = json.loads(message)
            callback(data)
        
        def on_error(ws, error):
            print(f"WebSocket error: {error}")
        
        def on_close(ws, close_status_code, close_msg):
            print("WebSocket connection closed")
        
        ws_url = self.base_url.replace("http://", "ws://")
        self.ws = websocket.WebSocketApp(
            f"{ws_url}/api/monitor/realtime",
            on_message=on_message,
            on_error=on_error,
            on_close=on_close
        )
        
        # Run in separate thread
        wst = threading.Thread(target=self.ws.run_forever)
        wst.daemon = True
        wst.start()
    
    def stop_realtime_monitoring(self):
        """Stop real-time monitoring"""
        if self.ws:
            self.ws.close()

# Usage examples
monitor = MonitoringClient("http://your-ip:8080")

# Check system health
health = monitor.get_system_health()
print(f"System status: {health['status']}")

# Check all services
all_services = monitor.check_all_services()
for service, status in all_services.items():
    print(f"{service}: {status['status']}")

# Get metrics
metrics = monitor.get_metrics(service="aws-service", timerange="24h")
print(f"AWS API calls: {len(metrics['metrics']['service_specific']['aws_api_calls'])}")

# Real-time monitoring
def handle_update(data):
    print(f"Real-time update: {data['service']} - {data['status']}")

monitor.start_realtime_monitoring(handle_update)
```

### Comprehensive Health Check Script

```bash
#!/bin/bash

# GeuseMaker Health Check Script
set -euo pipefail

INSTANCE_IP="your-ip"
LOG_FILE="/tmp/geusemaker-health.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_service() {
    local service_name="$1"
    local url="$2"
    local expected_status="${3:-ok}"
    
    log "Checking $service_name..."
    
    if curl -s --max-time 10 "$url" > /dev/null 2>&1; then
        log "✅ $service_name is responding"
        return 0
    else
        log "❌ $service_name is not responding"
        return 1
    fi
}

check_unity_health() {
    log "=== Unity System Health Check ==="
    
    # Unity Monitor Service
    if check_service "Unity Monitor" "http://$INSTANCE_IP:8080/api/health"; then
        # Get detailed health info
        curl -s "http://$INSTANCE_IP:8080/api/health" | jq '.services' || true
    fi
}

check_ai_services() {
    log "=== AI Services Health Check ==="
    
    # n8n
    check_service "n8n" "http://$INSTANCE_IP:5678/healthz"
    
    # Ollama
    check_service "Ollama" "http://$INSTANCE_IP:11434/api/tags"
    
    # Qdrant
    check_service "Qdrant" "http://$INSTANCE_IP:6333/health"
    
    # Crawl4AI
    check_service "Crawl4AI" "http://$INSTANCE_IP:11235/health"
}

check_performance() {
    log "=== Performance Check ==="
    
    # CPU and Memory
    if command -v ssh >/dev/null 2>&1; then
        ssh -i ~/.ssh/geusemaker-key.pem ubuntu@$INSTANCE_IP '
            echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | cut -d"%" -f1)%"
            echo "Memory Usage: $(free | grep Mem | awk "{printf \"%.1f%%\", \$3/\$2 * 100.0}")"
            echo "Disk Usage: $(df -h / | awk "NR==2{printf \"%s\", \$5}")"
            echo "GPU Usage: $(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "N/A")%"
        ' 2>/dev/null || log "Could not check performance metrics"
    fi
}

check_docker_containers() {
    log "=== Docker Containers Check ==="
    
    if command -v ssh >/dev/null 2>&1; then
        ssh -i ~/.ssh/geusemaker-key.pem ubuntu@$INSTANCE_IP '
            echo "Container Status:"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Could not check containers"
        ' 2>/dev/null
    fi
}

generate_report() {
    log "=== Health Check Summary ==="
    
    local failed_services=0
    
    # Count failed services
    if ! curl -s --max-time 5 "http://$INSTANCE_IP:8080/api/health" >/dev/null 2>&1; then
        ((failed_services++))
    fi
    
    if ! curl -s --max-time 5 "http://$INSTANCE_IP:5678/healthz" >/dev/null 2>&1; then
        ((failed_services++))
    fi
    
    if ! curl -s --max-time 5 "http://$INSTANCE_IP:11434/api/tags" >/dev/null 2>&1; then
        ((failed_services++))
    fi
    
    if ! curl -s --max-time 5 "http://$INSTANCE_IP:6333/health" >/dev/null 2>&1; then
        ((failed_services++))
    fi
    
    if ! curl -s --max-time 5 "http://$INSTANCE_IP:11235/health" >/dev/null 2>&1; then
        ((failed_services++))
    fi
    
    if [[ $failed_services -eq 0 ]]; then
        log "🎉 All services are healthy!"
        exit 0
    else
        log "⚠️  $failed_services services are unhealthy"
        log "📋 Check the log file: $LOG_FILE"
        exit 1
    fi
}

main() {
    log "Starting GeuseMaker health check..."
    
    check_unity_health
    check_ai_services
    check_performance
    check_docker_containers
    generate_report
}

main "$@"
```

### Monitoring Dashboard Setup

```python
import boto3
import json

def create_monitoring_dashboard(stack_name, instance_id):
    """Create CloudWatch dashboard for GeuseMaker stack"""
    
    cloudwatch = boto3.client('cloudwatch')
    
    dashboard_body = {
        "widgets": [
            {
                "type": "metric",
                "x": 0, "y": 0, "width": 12, "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id],
                        [".", "MemoryUtilization", ".", "."],
                        [".", "DiskSpaceUtilization", ".", "."]
                    ],
                    "period": 300,
                    "stat": "Average",
                    "region": "us-east-1",
                    "title": "System Metrics"
                }
            },
            {
                "type": "metric",
                "x": 12, "y": 0, "width": 12, "height": 6,
                "properties": {
                    "metrics": [
                        ["GeuseMaker/Unity", "ServiceHealth", "ServiceName", "aws-service"],
                        [".", ".", ".", "docker-service"],
                        [".", ".", ".", "monitor-service"]
                    ],
                    "period": 300,
                    "stat": "Average",
                    "region": "us-east-1",
                    "title": "Unity Services Health"
                }
            }
        ]
    }
    
    cloudwatch.put_dashboard(
        DashboardName=f"GeuseMaker-{stack_name}",
        DashboardBody=json.dumps(dashboard_body)
    )
    
    print(f"Dashboard created: GeuseMaker-{stack_name}")

# Usage
create_monitoring_dashboard("my-stack", "i-1234567890abcdef0")
```

## Alert Configuration

### Email Alerts

Set up email notifications for critical issues:

```bash
# Create SNS topic
aws sns create-topic --name geusemaker-alerts

# Subscribe to email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789012:geusemaker-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### Slack Integration

```python
import requests

def send_slack_alert(webhook_url, message):
    """Send alert to Slack"""
    payload = {
        "text": f"🚨 GeuseMaker Alert: {message}",
        "username": "GeuseMaker Monitor",
        "icon_emoji": ":warning:"
    }
    
    requests.post(webhook_url, json=payload)

# Usage in monitoring script
if failed_services > 0:
    send_slack_alert(
        "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK",
        f"{failed_services} services are unhealthy"
    )
```

---

**Back to API Overview**: [API Reference](README.md) | **Next**: [CLI Reference](../cli/README.md)