# Unity Deployment Orchestration Service Guide

## Overview

The Unity Deployment Orchestration Service provides event-driven deployment orchestration with self-healing capabilities, dynamic scaling, and automated cost optimization. It transforms traditional deployment workflows into reactive, self-managing systems that can automatically recover from failures and optimize for cost and performance.

## Key Features

### 1. Event-Driven Deployment Workflows
- **Reactive Orchestration**: All deployment phases emit and respond to events
- **Workflow Templates**: Pre-defined workflows for common deployment patterns
- **State Management**: Persistent tracking of deployment state and progress
- **Parallel Execution**: Multiple deployments can run concurrently

### 2. Self-Healing Mechanisms
- **Automatic Recovery**: Services automatically restart on failure
- **Container Resilience**: Failed containers restart with exponential backoff
- **Spot Instance Handling**: Automatic replacement of terminated spot instances
- **Health-Based Actions**: Proactive remediation based on health checks

### 3. Dynamic Scaling Triggers
- **Metric-Based Scaling**: Scale based on CPU, memory, requests, or custom metrics
- **Predictive Scaling**: Learn from patterns to scale proactively
- **Scheduled Scaling**: Scale based on time of day or business patterns
- **Multi-Dimensional**: Consider multiple metrics for scaling decisions

### 4. Cost Optimization Automation
- **Spot Conversion**: Automatically convert to spot instances when suitable
- **Rightsizing**: Detect and fix over-provisioned resources
- **Scheduled Optimization**: Turn off resources during non-business hours
- **Unused Resource Cleanup**: Identify and remove orphaned resources

### 5. Deployment Strategies
- **Rolling Updates**: Gradual replacement with zero downtime
- **Blue-Green**: Instant switchover between environments
- **Canary**: Progressive rollout with automated rollback
- **Recreate**: Simple stop-and-start deployment

## Architecture

```
Unity Deployment Service
├── Event Bus Integration
│   ├── Deployment Events
│   ├── Health Events
│   ├── Scaling Events
│   └── Cost Events
├── Workflow Engine
│   ├── Deployment Workflows
│   ├── Self-Healing Workflows
│   ├── Scaling Workflows
│   └── Cost Optimization Workflows
├── State Management
│   ├── Active Deployments
│   ├── Completed Deployments
│   └── Failed Deployments
└── Monitoring
    ├── Health Checks
    ├── Metric Collection
    └── Cost Tracking
```

## Usage

### Basic Deployment

```bash
# Initialize the deployment service
source lib/unity/services/unity-deployment-service.sh
unity_deployment_init

# Deploy with rolling strategy (default)
deployment_id=$(unity_deployment_execute "deploy" "my-stack" "spot" "rolling")

# Deploy with blue-green strategy
deployment_id=$(unity_deployment_execute "deploy" "my-stack" "spot" "blue-green")

# Deploy with canary strategy
deployment_id=$(unity_deployment_execute "deploy" "my-stack" "spot" "canary")
```

### Monitoring Deployments

```bash
# Check all deployments
unity_deployment_execute "status" "all"

# Check specific deployment
unity_deployment_execute "status" "$deployment_id"

# Get service status
unity_deployment_status
```

### Manual Operations

```bash
# Trigger manual rollback
unity_deployment_execute "rollback" "$deployment_id" "manual"

# Trigger manual scaling
unity_deployment_execute "scale" "up" "manual" "{\"instances\":2}"

# Trigger cost optimization
unity_deployment_execute "cost-optimize" "analyze"
```

## Event Flows

### Deployment Event Flow
```
deployment.started
  → deployment.initialized
    → deployment.infrastructure_ready
      → deployment.application_ready
        → deployment.verified
          → deployment.completed
```

### Self-Healing Event Flow
```
monitor.service.unhealthy
  → deployment.self_healing.started
    → deployment.service.stopping
      → deployment.service.starting
        → deployment.service.validating
          → deployment.self_healing.completed
```

### Scaling Event Flow
```
monitor.metric.collected
  → monitor.threshold.exceeded
    → deployment.scaling.started
      → deployment.scaling.completed
```

### Cost Optimization Event Flow
```
aws.cost.threshold_exceeded
  → cost.optimization.started (saga)
    → deployment.cost_analysis.completed
      → deployment.cost_optimization.processing
        → cost.optimization.completed
```

## Configuration

### Self-Healing Configuration

```bash
# Failure thresholds
UNITY_ROLLBACK_FAILURE_THRESHOLD=3      # Consecutive failures before action
UNITY_ROLLBACK_ERROR_RATE_THRESHOLD=0.5 # Error rate threshold
UNITY_ROLLBACK_HEALTH_CHECK_FAILURES=5  # Health check failures before action

# Retry configuration
UNITY_EVENT_MAX_RETRIES=3               # Max retry attempts
UNITY_EVENT_RETRY_DELAY=2               # Delay between retries (seconds)
```

### Scaling Configuration

```bash
# Scaling thresholds
UNITY_DEPLOYMENT_SCALING_THRESHOLD_CPU=80     # CPU threshold for scale-up
UNITY_DEPLOYMENT_SCALING_THRESHOLD_MEMORY=85  # Memory threshold for scale-up

# Scaling limits
UNITY_DEPLOYMENT_MAX_CONCURRENT_DEPLOYMENTS=3 # Max concurrent deployments
```

### Monitoring Configuration

```bash
# Check intervals
UNITY_DEPLOYMENT_HEALTH_CHECK_INTERVAL=30        # Health check interval (seconds)
UNITY_DEPLOYMENT_METRIC_COLLECTION_INTERVAL=60   # Metric collection interval
UNITY_DEPLOYMENT_COST_CHECK_INTERVAL=300         # Cost check interval
```

## Deployment Strategies

### Rolling Deployment
- Gradually replaces instances one at a time
- Zero downtime deployment
- Automatic rollback on failure
- Best for: Most production deployments

### Blue-Green Deployment
- Creates complete parallel environment
- Instant switchover via load balancer
- Quick rollback capability
- Best for: Critical production systems

### Canary Deployment
- Progressive traffic shifting (10% → 20% → ... → 100%)
- Automated metrics analysis
- Automatic rollback on anomalies
- Best for: High-risk changes

### Recreate Deployment
- Stops all instances then starts new ones
- Simplest strategy but has downtime
- Best for: Development environments

## Self-Healing Mechanisms

### Service Recovery
```json
{
  "trigger": "monitor.service.unhealthy",
  "condition": "consecutive_failures > 3",
  "actions": [
    "stop_unhealthy_service",
    "clear_service_cache",
    "start_service_fresh",
    "validate_service_health"
  ]
}
```

### Container Recovery
```json
{
  "trigger": "docker.container.failed",
  "condition": "exit_code != 0",
  "actions": [
    "analyze_failure_reason",
    "apply_backoff_delay",
    "restart_container",
    "monitor_container_health"
  ],
  "backoff_multiplier": 2,
  "max_backoff": 300
}
```

### Spot Instance Recovery
```json
{
  "trigger": "aws.ec2.terminated",
  "condition": "termination_reason == 'spot_interruption'",
  "actions": [
    "select_replacement_az",
    "launch_spot_instance",
    "configure_instance",
    "restore_application_state",
    "update_load_balancer"
  ]
}
```

## Cost Optimization Strategies

### Spot Conversion
- Analyzes workload suitability for spot instances
- Implements interruption handling
- Potential savings: 70%
- Risk level: Medium

### Rightsizing
- Identifies over-provisioned resources
- Recommends optimal instance types
- Potential savings: 30%
- Risk level: Low

### Scheduled Scaling
- Scales down during off-hours
- Scales up before business hours
- Potential savings: 40%
- Risk level: Low

### Unused Resource Cleanup
- Identifies orphaned resources
- Validates dependencies
- Potential savings: 100% of unused resources
- Risk level: Very Low

## Troubleshooting

### Common Issues

1. **Deployment Stuck in "initializing"**
   - Check event processing is running
   - Verify all prerequisites are met
   - Check deployment logs

2. **Self-healing Not Triggering**
   - Verify event handlers are registered
   - Check failure threshold configuration
   - Ensure monitoring is active

3. **Scaling Not Working**
   - Verify metrics are being collected
   - Check scaling policy thresholds
   - Ensure cooldown periods have elapsed

4. **Cost Optimization Not Running**
   - Check cost monitoring is enabled
   - Verify AWS credentials have Cost Explorer access
   - Check cost threshold configuration

### Debug Commands

```bash
# Check deployment logs
tail -f logs/unity/deployment-service.log

# Check event audit log
tail -f logs/unity/events-audit.log

# Check reactive patterns log
tail -f logs/unity/reactive-patterns.log

# List active workflows
ls -la .unity/deployment/state/active/

# Check failed deployments
ls -la .unity/deployment/state/failed/
```

## Best Practices

1. **Always Use Event-Driven Patterns**
   - Emit events for all significant actions
   - React to events rather than polling
   - Use appropriate event priorities

2. **Configure Appropriate Thresholds**
   - Set scaling thresholds based on actual usage
   - Configure failure thresholds to avoid flapping
   - Adjust cost thresholds to business needs

3. **Monitor Deployment Health**
   - Regularly check deployment status
   - Review self-healing actions
   - Analyze cost optimization recommendations

4. **Test Deployment Strategies**
   - Use canary for risky changes
   - Test rollback procedures
   - Validate self-healing in staging

5. **Implement Proper Tagging**
   - Tag all resources for cost tracking
   - Use consistent naming conventions
   - Document deployment metadata

## Integration with Unity System

The Deployment Service integrates seamlessly with other Unity components:

- **Event Bus**: All operations are event-driven
- **Config Service**: Deployment configurations
- **Monitor Service**: Health and metrics
- **AWS Service**: Infrastructure operations
- **Docker Service**: Container management

## Advanced Usage

### Custom Deployment Workflows

Create custom workflows by defining workflow templates:

```bash
cat > .unity/deployment/workflows/templates/custom.workflow <<EOF
{
  "workflow_id": "custom_deployment",
  "phases": [
    {
      "phase": "custom_step_1",
      "steps": ["action1", "action2"],
      "timeout": 300
    }
  ]
}
EOF
```

### Custom Self-Healing Actions

Add custom recovery actions:

```bash
# Register custom handler
unity_on_event "custom.failure" "handle_custom_failure" "priority=high"

# Define handler
handle_custom_failure() {
    local event_data="$3"
    # Custom recovery logic
}
```

### Custom Scaling Policies

Define custom scaling metrics:

```bash
# Emit custom metric
unity_emit_event "monitor.metric.collected" "custom" \
  '{"metric":"queue_depth","value":150,"resource_id":"worker-pool"}'
```

## Performance Considerations

- Event processing is asynchronous for better performance
- Deployments run in parallel up to configured limit
- Metrics are collected at configurable intervals
- Cost analysis runs periodically to avoid API limits

## Security Considerations

- All deployment operations require proper IAM permissions
- Sensitive data is never logged
- Rollback operations preserve security configurations
- Cost optimization respects resource access policies