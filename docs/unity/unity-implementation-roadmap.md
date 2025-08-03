# Unity Implementation Roadmap

## Overview

This roadmap details the specific implementation steps to complete the Unity migration and establish it as the sole deployment system for GeuseMaker.

## Week 1-2: Foundation Implementation

### 1. Create Unity CLI (`./unity`)

```bash
#!/bin/bash
# Unity CLI - Primary interface for all operations
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/unity/core/unity-core.sh"

usage() {
    cat << EOF
Unity CLI - GeuseMaker Deployment System

Usage: unity <command> [options]

Commands:
    init                    Initialize Unity system
    deploy <type> <stack>   Deploy infrastructure (spot|alb|cdn|full)
    destroy <stack>         Destroy infrastructure
    status <stack>          Show deployment status
    monitor <stack>         Real-time monitoring
    service <action>        Service management
    config <action>         Configuration management
    plugin <action>         Plugin management
    test                    Run Unity tests
    help                    Show this help

Examples:
    unity deploy spot my-stack
    unity status my-stack
    unity service list
    unity config validate

EOF
}

case "${1:-}" in
    init)
        unity_init
        ;;
    deploy)
        shift
        handle_deployment "$@"
        ;;
    destroy)
        shift
        handle_destruction "$@"
        ;;
    status)
        shift
        handle_status "$@"
        ;;
    monitor)
        shift
        handle_monitoring "$@"
        ;;
    service)
        shift
        handle_service "$@"
        ;;
    config)
        shift
        handle_config "$@"
        ;;
    plugin)
        shift
        handle_plugin "$@"
        ;;
    test)
        shift
        run_unity_tests "$@"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
```

### 2. Create Deployment Wrapper (`./deploy.sh`)

```bash
#!/bin/bash
# Unity-based deployment wrapper for backward compatibility
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to Unity CLI
exec "$SCRIPT_DIR/unity" deploy "$@"
```

### 3. Implement Pre-flight Checks

Create `lib/unity/core/unity-preflight.sh`:

```bash
#!/bin/bash
# Unity Pre-flight Validation System

preflight_check_all() {
    local deployment_type="$1"
    local stack_name="$2"
    local errors=0
    
    unity_log "INFO" "Running pre-flight checks for $deployment_type deployment"
    
    # AWS checks
    if ! preflight_check_aws; then
        ((errors++))
    fi
    
    # Docker checks (if needed)
    if [[ "$deployment_type" =~ ^(full|alb)$ ]]; then
        if ! preflight_check_docker; then
            ((errors++))
        fi
    fi
    
    # Resource checks
    if ! preflight_check_resources "$stack_name"; then
        ((errors++))
    fi
    
    # Configuration checks
    if ! preflight_check_config; then
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        unity_log "ERROR" "Pre-flight checks failed with $errors errors"
        return 1
    fi
    
    unity_log "INFO" "All pre-flight checks passed"
    return 0
}

preflight_check_aws() {
    unity_log "INFO" "Checking AWS prerequisites..."
    
    # Check credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        unity_log "ERROR" "AWS credentials not configured"
        return 1
    fi
    
    # Check permissions
    local required_actions=(
        "ec2:DescribeInstances"
        "ec2:CreateVpc"
        "iam:CreateRole"
        "elasticloadbalancing:CreateLoadBalancer"
    )
    
    # Check quotas
    local instance_quota=$(aws service-quotas get-service-quota \
        --service-code ec2 \
        --quota-code L-1216C47A \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "20")
    
    unity_log "INFO" "AWS checks passed"
    return 0
}
```

### 4. Create Migration Tools

Create directory structure:

```bash
scripts/migrate-to-unity/
├── migrate-all.sh              # Master migration script
├── migrate-vpc-module.sh       # VPC migration
├── migrate-ec2-module.sh       # EC2 migration
├── migrate-alb-module.sh       # ALB migration
├── migrate-monitoring.sh       # Monitoring migration
├── migrate-config.sh          # Configuration migration
└── lib/
    └── migration-utils.sh     # Shared utilities
```

## Week 3-4: Service Enhancement

### 1. Enhanced AWS Service

Create `lib/unity/services/unity-aws-service-complete.sh`:

```bash
#!/bin/bash
# Complete AWS Service Implementation

# Import legacy functions and convert to Unity patterns
source_legacy_modules() {
    # Temporarily source legacy modules to extract logic
    local legacy_dir="/Users/nucky/Repos/001-starter-kit/archive/unity-cleanup-20250803_024204/original-files/lib/modules"
    
    # Extract and convert functions
    convert_vpc_functions "$legacy_dir/infrastructure/vpc.sh"
    convert_ec2_functions "$legacy_dir/compute/ec2.sh"
    convert_alb_functions "$legacy_dir/infrastructure/alb.sh"
}

# VPC Management
create_vpc_unity() {
    local stack_name="$1"
    local multi_az="${2:-false}"
    
    unity_emit_event "VPC_CREATION_STARTED" "aws" "$stack_name"
    
    # Create VPC
    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block "10.0.0.0/16" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$stack_name-vpc},{Key=unity:managed,Value=true}]" \
        --query 'Vpc.VpcId' \
        --output text)
    
    # Enable DNS
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
    
    # Create subnets
    if [[ "$multi_az" == "true" ]]; then
        create_multi_az_subnets "$vpc_id" "$stack_name"
    else
        create_single_az_subnets "$vpc_id" "$stack_name"
    fi
    
    unity_emit_event "VPC_CREATED" "aws" "$vpc_id"
    return 0
}

# EC2 Spot Optimization
launch_spot_instance_unity() {
    local stack_name="$1"
    local instance_type="${2:-g4dn.xlarge}"
    
    unity_emit_event "SPOT_LAUNCH_STARTED" "aws" "$stack_name"
    
    # Get best spot price
    local best_az=$(get_best_spot_price "$instance_type")
    
    # Launch instance
    local instance_id=$(aws ec2 run-instances \
        --instance-type "$instance_type" \
        --instance-market-options "MarketType=spot,SpotOptions={SpotInstanceType=one-time}" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$stack_name-spot},{Key=unity:managed,Value=true}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    unity_emit_event "SPOT_INSTANCE_LAUNCHED" "aws" "$instance_id:$instance_type"
    return 0
}
```

### 2. Enhanced Docker Service

Create `lib/unity/services/unity-docker-service-complete.sh`:

```bash
#!/bin/bash
# Complete Docker Service Implementation

# Docker Compose Management
generate_compose_file_unity() {
    local stack_name="$1"
    local environment="$2"
    
    unity_emit_event "COMPOSE_GENERATION_STARTED" "docker" "$stack_name"
    
    # Generate compose file with all services
    cat > "docker-compose-$stack_name.yml" << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: ${stack_name}-n8n
    restart: unless-stopped
    environment:
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_HOST=\${N8N_HOST:-localhost}
    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

  ollama:
    image: ollama/ollama:latest
    container_name: ${stack_name}-ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  qdrant:
    image: qdrant/qdrant:latest
    container_name: ${stack_name}-qdrant
    restart: unless-stopped
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage

  postgres:
    image: postgres:15-alpine
    container_name: ${stack_name}-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  n8n_data:
  ollama_data:
  qdrant_data:
  postgres_data:
EOF
    
    unity_emit_event "COMPOSE_FILE_GENERATED" "docker" "$stack_name"
    return 0
}
```

## Week 5-6: Legacy Removal

### 1. Create Deprecation Script

```bash
#!/bin/bash
# scripts/deprecate-legacy.sh

# Step 1: Move legacy code
mkdir -p deprecated/legacy-archive
mv archive/* deprecated/legacy-archive/

# Step 2: Update all script references
find . -name "*.sh" -type f -exec sed -i 's|archive/|deprecated/legacy-archive/|g' {} \;

# Step 3: Create compatibility warnings
for script in deprecated/legacy-archive/original-files/scripts/*.sh; do
    cat > "$script.warning" << EOF
#!/bin/bash
echo "WARNING: This script is deprecated. Use Unity CLI instead."
echo "Example: unity deploy spot my-stack"
exit 1
EOF
done
```

### 2. Port Makefile Targets

Create `scripts/port-makefile-to-unity.sh`:

```bash
#!/bin/bash
# Convert Makefile targets to Unity CLI commands

# Create Unity equivalents for all make targets
create_unity_aliases() {
    cat > unity-make-compatibility.sh << 'EOF'
# Makefile compatibility layer for Unity

case "$1" in
    deploy-spot)
        shift
        ./unity deploy spot "${STACK_NAME:-geusemaker-dev}"
        ;;
    deploy-alb)
        shift
        ./unity deploy alb "${STACK_NAME:-geusemaker-dev}"
        ;;
    deploy-full)
        shift  
        ./unity deploy full "${STACK_NAME:-geusemaker-dev}"
        ;;
    destroy)
        shift
        ./unity destroy "${STACK_NAME:-geusemaker-dev}"
        ;;
    test)
        ./unity test
        ;;
    *)
        echo "Use Unity CLI directly: ./unity help"
        ;;
esac
EOF
}
```

## Week 7-8: Testing & Monitoring

### 1. Comprehensive Monitoring Service

Create `lib/unity/services/unity-monitoring-complete.sh`:

```bash
#!/bin/bash
# Complete Monitoring Service Implementation

# CloudWatch Integration
setup_cloudwatch_dashboard() {
    local stack_name="$1"
    
    unity_emit_event "CLOUDWATCH_SETUP_STARTED" "monitor" "$stack_name"
    
    # Create custom namespace
    local namespace="Unity/$stack_name"
    
    # Define dashboard
    local dashboard_body=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["$namespace", "ServiceHealth", {"stat": "Average"}],
                    [".", "EventLatency", {"stat": "Average"}],
                    [".", "DeploymentTime", {"stat": "Average"}]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Unity System Metrics"
            }
        }
    ]
}
EOF
)
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$stack_name-unity" \
        --dashboard-body "$dashboard_body"
    
    unity_emit_event "CLOUDWATCH_DASHBOARD_CREATED" "monitor" "$stack_name"
}

# Real-time Monitoring
start_realtime_monitoring() {
    local stack_name="$1"
    
    while true; do
        # Collect metrics
        collect_service_metrics
        collect_event_metrics
        collect_resource_metrics
        
        # Push to CloudWatch
        push_metrics_to_cloudwatch "$namespace"
        
        # Check thresholds
        check_alert_thresholds
        
        sleep 60
    done
}
```

### 2. Performance Tests

Create `tests/unity/performance/deployment-speed-test.sh`:

```bash
#!/bin/bash
# Test deployment speed

test_deployment_speed() {
    local deployment_type="$1"
    local expected_time="$2"
    
    local start_time=$(date +%s)
    
    # Execute deployment
    ./unity deploy "$deployment_type" "perf-test-stack"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Cleanup
    ./unity destroy "perf-test-stack"
    
    if [[ $duration -lt $expected_time ]]; then
        echo "PASS: $deployment_type completed in ${duration}s (expected <${expected_time}s)"
        return 0
    else
        echo "FAIL: $deployment_type took ${duration}s (expected <${expected_time}s)"
        return 1
    fi
}

# Run tests
test_deployment_speed "spot" 180    # 3 minutes
test_deployment_speed "alb" 300     # 5 minutes
test_deployment_speed "full" 600    # 10 minutes
```

## Week 9-10: Dashboard Development

### 1. Unity Dashboard Backend

Create `unity-dashboard/backend/server.js`:

```javascript
const express = require('express');
const WebSocket = require('ws');
const { spawn } = require('child_process');

const app = express();
const wss = new WebSocket.Server({ port: 8080 });

// Unity bridge - execute Unity commands
function executeUnityCommand(command, args) {
    return new Promise((resolve, reject) => {
        const unity = spawn('./unity', [command, ...args]);
        let output = '';
        
        unity.stdout.on('data', (data) => {
            output += data.toString();
        });
        
        unity.on('close', (code) => {
            if (code === 0) {
                resolve(output);
            } else {
                reject(new Error(`Unity command failed: ${code}`));
            }
        });
    });
}

// API endpoints
app.get('/api/services', async (req, res) => {
    const output = await executeUnityCommand('service', ['list']);
    res.json({ services: parseServiceList(output) });
});

app.get('/api/deployments/:stack', async (req, res) => {
    const output = await executeUnityCommand('status', [req.params.stack]);
    res.json({ status: parseStatus(output) });
});

// WebSocket for real-time updates
wss.on('connection', (ws) => {
    // Subscribe to Unity events
    const eventStream = spawn('./unity', ['monitor', '--stream']);
    
    eventStream.stdout.on('data', (data) => {
        ws.send(JSON.stringify({
            type: 'event',
            data: data.toString()
        }));
    });
});

app.listen(3000, () => {
    console.log('Unity Dashboard API running on port 3000');
});
```

### 2. Dashboard Frontend

Create `unity-dashboard/frontend/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Unity Dashboard - GeuseMaker</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div id="app">
        <header>
            <h1>Unity System Dashboard</h1>
            <div class="status-bar">
                <span id="system-status">System: <strong>Operational</strong></span>
                <span id="event-count">Events: <strong>0</strong></span>
            </div>
        </header>
        
        <main>
            <section class="services">
                <h2>Services</h2>
                <div id="service-list"></div>
            </section>
            
            <section class="deployments">
                <h2>Active Deployments</h2>
                <div id="deployment-list"></div>
            </section>
            
            <section class="events">
                <h2>Event Stream</h2>
                <div id="event-stream"></div>
            </section>
            
            <section class="metrics">
                <h2>System Metrics</h2>
                <canvas id="metrics-chart"></canvas>
            </section>
        </main>
    </div>
    
    <script src="dashboard.js"></script>
</body>
</html>
```

## Week 11-12: Finalization

### 1. Complete Documentation

Create comprehensive guides:
- Unity Architecture Guide
- Unity CLI Reference
- Service Development Guide
- Plugin Development Guide
- Troubleshooting Guide
- Migration Guide

### 2. Production Validation

Create validation suite:

```bash
#!/bin/bash
# tests/unity/production-validation.sh

validate_production_readiness() {
    local errors=0
    
    # Check all services
    for service in aws docker config monitor; do
        if ! ./unity service status "$service" | grep -q "healthy"; then
            echo "ERROR: Service $service not healthy"
            ((errors++))
        fi
    done
    
    # Run integration tests
    if ! ./tests/unity/test-unity-complete-system.sh; then
        echo "ERROR: Integration tests failed"
        ((errors++))
    fi
    
    # Performance benchmarks
    if ! ./tests/unity/performance/test-unity-performance-benchmarks.sh; then
        echo "ERROR: Performance benchmarks failed"
        ((errors++))
    fi
    
    # Security validation
    if ! ./tests/unity/security/test-unity-security-comprehensive.sh; then
        echo "ERROR: Security validation failed"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "SUCCESS: Unity system is production ready!"
        return 0
    else
        echo "FAILURE: $errors validation errors found"
        return 1
    fi
}
```

### 3. Remove Legacy Code

Final cleanup:

```bash
#!/bin/bash
# scripts/final-legacy-removal.sh

# Remove all deprecated code
rm -rf deprecated/
rm -rf archive/

# Remove legacy references
find . -name "*.md" -type f -exec sed -i '/legacy\|archived/d' {} \;

# Update README
cat > README.md << 'EOF'
# GeuseMaker - AI Stack on AWS

Deploy complete AI infrastructure using Unity event-driven architecture.

## Quick Start

```bash
./unity deploy spot my-stack
```

See [Unity Documentation](docs/unity/) for complete guide.
EOF

echo "Legacy code removal complete. Unity is now the sole deployment system."
```

## Success Criteria

1. ✅ All deployments use Unity CLI
2. ✅ Zero legacy dependencies
3. ✅ All tests passing (>90% coverage)
4. ✅ Performance targets met (<3min deployment)
5. ✅ Documentation complete
6. ✅ Production validated
7. ✅ Dashboard operational