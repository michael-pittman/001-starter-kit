# Rollback Mechanism Guide

This guide documents the comprehensive rollback mechanism implemented for the GeuseMaker deployment system.

## Overview

The rollback mechanism provides automatic and manual rollback capabilities for failed deployments with:
- **Automatic trigger detection** - Health failures, timeouts, quota limits, cost thresholds
- **Multiple rollback modes** - Full, partial, incremental, and emergency
- **State management** - Complete tracking of rollback progress and outcomes
- **Resource cleanup** - Comprehensive cleanup of AWS resources in correct order
- **Testing capabilities** - Built-in test mode for verification

## Architecture

### Components

1. **Rollback Module** (`/lib/modules/deployment/rollback.sh`)
   - Core rollback logic and orchestration
   - Trigger detection and evaluation
   - State management and snapshots
   - Resource deletion with retry logic

2. **Orchestrator Integration** (`/lib/modules/deployment/orchestrator.sh`)
   - Rollback monitoring during deployments
   - Automatic trigger checking
   - Phase-based deployment tracking

## Rollback Triggers

### Automatic Triggers

The system monitors for these conditions during deployment:

```bash
# Health Check Failure
- Trigger: HEALTH_STATUS = "UNHEALTHY" or "CRITICAL"
- Priority: 10 (highest)
- Action: Immediate rollback

# Deployment Timeout
- Trigger: Deployment exceeds DEPLOYMENT_TIMEOUT (default: 1800s)
- Priority: 20
- Action: Timeout-triggered rollback

# Resource Quota Exceeded
- Trigger: QUOTA_STATUS = "EXCEEDED"
- Priority: 30
- Action: Quota-triggered rollback

# Cost Threshold
- Trigger: DEPLOYMENT_COST > COST_LIMIT
- Priority: 40
- Action: Cost-triggered rollback

# Validation Failure
- Trigger: VALIDATION_STATUS = "FAILED"
- Priority: 50
- Action: Validation-triggered rollback
```

### Manual Triggers

```bash
# Manual rollback command
rollback_deployment "stack-name" "deployment-type" "" "full" "manual"
```

## Rollback Modes

### Full Rollback (Default)
Removes all resources created during deployment in reverse order.

```bash
rollback_deployment "stack" "full" "" "$ROLLBACK_MODE_FULL" "trigger"
```

### Partial Rollback
Only removes failed components, leaving successful ones intact.

```bash
# Set failed components
set_variable "FAILED_COMPONENTS" "alb instances" "$VARIABLE_SCOPE_STACK"
rollback_deployment "stack" "full" "" "$ROLLBACK_MODE_PARTIAL" "trigger"
```

### Incremental Rollback
Rolls back deployment phases in reverse order.

```bash
# Tracks phases: infrastructure -> compute -> application
rollback_deployment "stack" "full" "" "$ROLLBACK_MODE_INCREMENTAL" "trigger"
```

### Emergency Rollback
Force-deletes all resources without waiting or dependency checking.

```bash
rollback_deployment "stack" "full" "" "$ROLLBACK_MODE_EMERGENCY" "trigger"
```

## Deployment Type Support

### Spot Instance Stack
- Components: VPC, Security Groups, EC2 Instances
- Rollback Order: Instances → Security Groups → VPC

### ALB Stack
- Components: VPC, Security Groups, ALB, Target Groups, Instances
- Rollback Order: ALB → Target Groups → Instances → Security Groups → VPC

### CDN Stack
- Components: CloudFront Distribution
- Rollback Order: CloudFront (with disable first)

### Full Stack
- Components: All of the above + EFS, IAM
- Rollback Order: CDN → ALB → EFS → Instances → IAM → Security Groups → VPC

## State Management

### Rollback States
```bash
ROLLBACK_STATE_INITIALIZING  # Preparing rollback
ROLLBACK_STATE_IN_PROGRESS   # Actively rolling back
ROLLBACK_STATE_VERIFYING     # Verifying cleanup
ROLLBACK_STATE_COMPLETED     # Successfully rolled back
ROLLBACK_STATE_FAILED        # Rollback failed
ROLLBACK_STATE_PARTIAL       # Partially rolled back
```

### State Tracking
```bash
# Set state
set_rollback_state "stack-name" "in_progress"

# Get state
state=$(get_rollback_state "stack-name")
```

## Snapshots and Reporting

### Snapshots
Created before and after rollback for audit trail:
```bash
create_rollback_snapshot "stack-name" "pre_rollback"
create_rollback_snapshot "stack-name" "post_rollback"
```

### Reports
Automatic report generation with metrics:
- Duration
- Resources removed
- Success/failure status
- Trigger information

Reports saved to: `./config/rollback_reports/`

## Testing

### Unit Tests
```bash
./tests/unit/test-rollback-module.sh
```

### Integration Tests
```bash
./tests/test-rollback-mechanism.sh
```

### Built-in Test Mode
```bash
# Test rollback mechanism without actual AWS calls
test_rollback_mechanism "spot"
```

## Usage Examples

### Enable Rollback in Deployment
```bash
# Rollback is automatically enabled when module is sourced
./scripts/aws-deployment-modular.sh --spot my-stack
```

### Monitor Deployment with Triggers
The orchestrator automatically:
1. Starts rollback monitoring
2. Checks triggers every 30 seconds
3. Initiates rollback if triggered
4. Stops monitoring on completion

### Manual Rollback
```bash
# Source required modules
source lib/modules/deployment/rollback.sh

# Execute rollback
rollback_deployment "my-stack" "spot" "" "full" "manual"
```

### Custom Trigger Registration
```bash
# Register custom trigger
register_rollback_trigger "disk_space_low" \
    "check_disk_space" \
    "rollback_deployment" \
    25  # priority
```

## Resource Cleanup

### Retry Logic
Failed deletions are retried with exponential backoff:
- Default: 3 attempts
- Initial delay: 30s
- Max backoff: 300s

### Dependency Handling
Resources are deleted in dependency order:
1. Dependent resources first (instances, ALBs)
2. Network resources (subnets, gateways)
3. Container resources (VPCs, security groups)

### Force Deletion
Emergency mode skips dependency checks:
```bash
force_delete_resource "ec2_instance" "i-1234567890"
```

## Best Practices

1. **Always test rollback** before production deployments
2. **Set appropriate timeouts** based on deployment complexity
3. **Configure cost limits** to prevent runaway costs
4. **Monitor rollback reports** for patterns
5. **Use partial rollback** when possible to preserve working resources
6. **Keep snapshots** for audit trail (auto-cleaned after 7 days)

## Troubleshooting

### Rollback Fails
1. Check rollback reports in `./config/rollback_reports/`
2. Verify AWS credentials and permissions
3. Check for resource dependencies preventing deletion
4. Use emergency mode as last resort

### Triggers Not Activating
1. Verify rollback module is loaded
2. Check trigger registration with debug logging
3. Ensure variables are set correctly
4. Verify monitoring process is running

### State Inconsistencies
1. Check variable store file
2. Verify stack name consistency
3. Review snapshots for state history
4. Manually clear state if needed

## Integration Requirements

### Bash Version
Requires bash 4.0+ for associative arrays

### Dependencies
- aws-deployment-common.sh
- error-handling.sh
- variable-management.sh

### AWS Permissions
Requires permissions to:
- Delete all resource types
- Tag and query resources
- Modify security group rules