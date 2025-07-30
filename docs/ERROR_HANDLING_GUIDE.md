# GeuseMaker Error Handling and Recovery Guide

## Overview

The enhanced `deploy.sh` script includes comprehensive error handling for all deployment operations, automatic rollback mechanisms, and detailed recovery procedures. This guide documents how errors are handled and how to recover from various failure scenarios.

## Error Handling Features

### 1. Structured Error Tracking

All errors are tracked using the structured error system from `lib/modules/errors/error_types.sh`:

- **Error Categories**: validation, infrastructure, network, authentication, capacity, timeout, dependency, configuration
- **Severity Levels**: INFO, WARNING, ERROR, CRITICAL
- **Recovery Strategies**: retry, fallback, skip, abort, manual

### 2. Automatic Error Recovery

The deployment script implements several automatic recovery mechanisms:

#### Retry with Exponential Backoff
```bash
retry_with_backoff "operation_to_retry" max_attempts base_delay
```
- Used for transient failures (API rate limits, temporary capacity issues)
- Exponentially increases delay between retries
- Default: 3 attempts with 30-second base delay

#### Partial Rollback
When `ENABLE_PARTIAL_ROLLBACK=true`, non-critical component failures allow deployment to continue:
- EFS creation failures
- CloudFront creation failures  
- Monitoring setup failures

#### Automatic Rollback
Critical failures trigger automatic rollback:
- VPC creation failures
- Security group creation failures
- Compute infrastructure failures
- ALB creation failures (when required)

### 3. Resource Tracking

All created resources are tracked for cleanup:
```bash
register_resource "resource_type" "resource_id" "region"
```

Resources are automatically cleaned up during:
- Rollback operations
- Emergency cleanup
- Normal destruction

### 4. Rollback Points

Deployment progress is tracked with rollback points:
```bash
add_rollback_point "point_name" "point_data"
```

Rollback points include:
- `initialization_complete`
- `validation_complete`
- `vpc_created`
- `security_created`
- `compute_created`
- `efs_created`
- `alb_created`
- `cdn_created`

## Error Types and Recovery

### Infrastructure Errors

#### EC2 Insufficient Capacity
**Error Code**: `EC2_INSUFFICIENT_CAPACITY`
**Recovery**: Automatic retry with fallback to different instance types/regions
```bash
Error: Insufficient capacity for instance type g4dn.xlarge in region us-east-1
Recovery: Retrying with fallback options...
```

#### Instance Limit Exceeded
**Error Code**: `EC2_INSTANCE_LIMIT_EXCEEDED`
**Recovery**: Manual intervention required
```bash
Error: Instance limit exceeded for type g4dn.xlarge
Recovery: Request limit increase or use different instance type
```

#### VPC Limit Exceeded
**Error Code**: `VPC_LIMIT_EXCEEDED`
**Recovery**: Manual cleanup of existing VPCs
```bash
Error: VPC limit exceeded in region us-east-1
Recovery: Delete unused VPCs or request limit increase
```

### Network Errors

#### Security Group Conflicts
**Error Code**: `NETWORK_SECURITY_GROUP_INVALID`
**Recovery**: Automatic cleanup and retry
```bash
Error: Security groups already exist for stack
Recovery: Cleaning up existing security groups...
```

#### Subnet Configuration Errors
**Error Code**: `NETWORK_SUBNET_INVALID`
**Recovery**: Validation and correction of subnet CIDR blocks
```bash
Error: Invalid subnet configuration
Recovery: Check subnet CIDR blocks for conflicts
```

### Authentication/Authorization Errors

#### Invalid Credentials
**Error Code**: `AUTH_INVALID_CREDENTIALS`
**Recovery**: Manual credential update required
```bash
Error: Invalid AWS credentials
Recovery: Run 'aws configure' to update credentials
```

#### Insufficient Permissions
**Error Code**: `AUTH_INSUFFICIENT_PERMISSIONS`
**Recovery**: Update IAM policies
```bash
Error: Insufficient permissions for ec2:CreateVpc
Recovery: Add required permissions to IAM user/role
```

### Configuration Errors

#### Missing Parameters
**Error Code**: `CONFIG_MISSING_PARAMETER`
**Recovery**: Provide required parameters
```bash
Error: Missing required parameter: instance_type
Recovery: Specify --instance-type parameter
```

#### Invalid Values
**Error Code**: `CONFIG_INVALID_VARIABLE`
**Recovery**: Correct parameter values
```bash
Error: Invalid variable value: VPC_CIDR=invalid
Recovery: Use valid CIDR notation (e.g., 10.0.0.0/16)
```

## Recovery Procedures

### 1. Automatic Recovery Mode

Default mode that attempts automatic recovery:
```bash
ERROR_RECOVERY_MODE="automatic"
./deploy.sh --type spot my-stack
```

Recovery actions:
- Retry transient failures
- Rollback on critical errors
- Skip non-critical components
- Clean up partial deployments

### 2. Manual Recovery Mode

Requires user intervention for all errors:
```bash
ERROR_RECOVERY_MODE="manual"
./deploy.sh --type spot my-stack
```

When errors occur, detailed instructions are displayed:
```
========================================
MANUAL RECOVERY REQUIRED
========================================

Recovery Options:

1. ROLLBACK - Remove all created resources:
   ./deploy.sh --rollback my-stack

2. RESUME - Attempt to continue deployment:
   ./deploy.sh --resume my-stack

3. DESTROY - Force removal of all resources:
   ./deploy.sh --destroy my-stack

4. STATUS - Check current deployment status:
   ./deploy.sh --status my-stack
========================================
```

### 3. Abort Mode

Immediately stops on any error:
```bash
ERROR_RECOVERY_MODE="abort"
./deploy.sh --type spot my-stack
```

### 4. Emergency Cleanup

For severe failures, emergency cleanup removes all tracked resources:
```bash
# Triggered automatically on critical errors
execute_emergency_cleanup
```

Manual emergency cleanup:
```bash
# List all resources tagged with stack
aws ec2 describe-instances --filters "Name=tag:Stack,Values=my-stack"
aws ec2 describe-vpcs --filters "Name=tag:Stack,Values=my-stack"

# Force delete all resources
./deploy.sh --destroy my-stack --force
```

## Error Reporting

### Error Log Files

All errors are logged to multiple locations:

1. **Main Error Log**: `/tmp/GeuseMaker-errors.log`
2. **Deployment Error Report**: `logs/deployment-error-report-TIMESTAMP.json`
3. **Session Log**: `logs/deployment-TIMESTAMP.log`

### Error Report Format

```json
{
    "deployment": {
        "stack_name": "my-stack",
        "deployment_type": "spot",
        "region": "us-east-1",
        "start_time": "1234567890",
        "end_time": "1234567900",
        "duration_seconds": 10,
        "state": "FAILED",
        "error_count": 2
    },
    "errors": [
        {
            "code": "EC2_INSUFFICIENT_CAPACITY",
            "message": "Insufficient capacity for instance type g4dn.xlarge",
            "timestamp": "2024-01-15T10:30:00Z"
        }
    ],
    "rollback_points": 5,
    "created_resources": 12
}
```

### Viewing Error Details

```bash
# View recent errors
tail -f /tmp/GeuseMaker-errors.log

# View deployment-specific errors
cat logs/deployment-error-report-*.json | jq .

# Check error summary
./deploy.sh --logs my-stack
```

## Best Practices

### 1. Pre-Deployment Validation

Always validate before deployment:
```bash
./deploy.sh --validate --type spot my-stack
```

### 2. Dry Run Testing

Test deployment without creating resources:
```bash
./deploy.sh --dry-run --type spot my-stack
```

### 3. Incremental Deployment

Deploy components incrementally:
```bash
# Start with basic infrastructure
./deploy.sh --type spot my-stack

# Add ALB later
./deploy.sh --alb my-stack

# Add CDN last
./deploy.sh --cdn my-stack
```

### 4. Monitor Deployment Progress

```bash
# In another terminal
watch -n 5 './deploy.sh --status my-stack'
```

### 5. Regular Cleanup

Remove failed deployments promptly:
```bash
# List all stacks
aws ec2 describe-vpcs --filters "Name=tag:ManagedBy,Values=GeuseMaker" --query 'Vpcs[].Tags[?Key==`Stack`].Value'

# Clean up failed stack
./deploy.sh --destroy failed-stack
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Deployment Hangs
**Symptom**: Deployment appears stuck
**Solution**: 
```bash
# Check CloudFormation events (if using CF)
aws cloudformation describe-stack-events --stack-name my-stack

# Check EC2 instance status
aws ec2 describe-instance-status --instance-ids i-xxxxx

# Force timeout and rollback
kill -TERM <deploy_pid>
./deploy.sh --rollback my-stack
```

#### 2. Partial Deployment
**Symptom**: Some resources created, others failed
**Solution**:
```bash
# Check what was created
./deploy.sh --status my-stack

# Option 1: Complete deployment
./deploy.sh --resume my-stack

# Option 2: Clean up and retry
./deploy.sh --destroy my-stack
./deploy.sh --type spot my-stack
```

#### 3. Permission Errors
**Symptom**: Access denied errors
**Solution**:
```bash
# Check current permissions
aws iam get-user
aws iam list-attached-user-policies --user-name <username>

# Use AWS CloudShell or EC2 instance role
# Or update IAM policies as needed
```

#### 4. Resource Limits
**Symptom**: Limit exceeded errors
**Solution**:
```bash
# Check current limits
aws service-quotas list-service-quotas --service-code ec2

# Request increase
aws service-quotas request-service-quota-increase \
    --service-code ec2 \
    --quota-code <quota-code> \
    --desired-value <new-value>
```

## Recovery Scripts

### Quick Recovery Script
```bash
#!/bin/bash
# quick-recovery.sh

STACK_NAME="$1"
REGION="${2:-us-east-1}"

echo "Attempting quick recovery for stack: $STACK_NAME"

# Check current state
./deploy.sh --status "$STACK_NAME"

# Try to resume
if ./deploy.sh --resume "$STACK_NAME"; then
    echo "Recovery successful!"
else
    echo "Recovery failed. Initiating rollback..."
    ./deploy.sh --rollback "$STACK_NAME"
fi
```

### Force Cleanup Script
```bash
#!/bin/bash
# force-cleanup.sh

STACK_NAME="$1"
REGION="${2:-us-east-1}"

echo "Force cleaning stack: $STACK_NAME in region: $REGION"

# Set expected failure flag to avoid trap
export EXPECTED_FAILURE=true

# Delete all resources with stack tag
for resource_type in instances security-groups subnets vpcs; do
    echo "Cleaning $resource_type..."
    aws ec2 describe-$resource_type \
        --filters "Name=tag:Stack,Values=$STACK_NAME" \
        --region "$REGION" \
        --query '*[].{ID:*Id}' \
        --output text | while read id; do
            echo "  Deleting: $id"
            # Add appropriate delete commands
        done
done
```

## Error Prevention

### 1. Pre-flight Checks
The deployment script automatically performs:
- AWS credential validation
- Region availability check
- Service quota validation
- Network configuration validation
- IAM permission checks

### 2. Configuration Validation
All parameters are validated before use:
- CIDR block format
- Instance type availability
- Security group rules
- IAM role permissions

### 3. Dependency Management
Resources are created in the correct order:
1. VPC and networking
2. Security groups and IAM
3. Compute infrastructure
4. Optional components (EFS, ALB, CDN)
5. Monitoring and alerts

### 4. Timeout Protection
Long-running operations have timeouts:
- CloudFront creation: 600 seconds
- Instance launches: 300 seconds
- EFS mount: 180 seconds

## Summary

The enhanced error handling in GeuseMaker provides:

1. **Automatic Recovery**: Most transient errors are handled automatically
2. **Graceful Degradation**: Non-critical failures don't stop deployment
3. **Complete Tracking**: All resources and errors are tracked
4. **Easy Recovery**: Multiple recovery options for different scenarios
5. **Detailed Reporting**: Comprehensive error logs and reports

For additional support, check:
- Error logs in `/tmp/GeuseMaker-errors.log`
- Deployment reports in `logs/`
- AWS CloudTrail for API call history
- Instance system logs for application errors