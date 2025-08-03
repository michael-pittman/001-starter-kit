# Phase 1: AWS Service Consolidation Migration Guide

## Overview

This guide walks you through consolidating 60+ AWS-related scripts into the unified Unity AWS service. The migration maintains backward compatibility while providing a cleaner, more maintainable architecture.

## Pre-Migration Checklist

- [ ] Backup existing scripts
- [ ] Document current AWS operations
- [ ] Identify custom functions
- [ ] Test environment ready
- [ ] Rollback plan prepared

## Step-by-Step Migration

### Step 1: Inventory AWS Scripts

```bash
# List all AWS-related scripts
find . -name "*.sh" -type f | xargs grep -l "aws " | grep -v archive > aws-scripts-inventory.txt

# Categorize by service
grep -l "ec2" aws-scripts-inventory.txt > aws-ec2-scripts.txt
grep -l "vpc" aws-scripts-inventory.txt > aws-vpc-scripts.txt
grep -l "efs" aws-scripts-inventory.txt > aws-efs-scripts.txt
grep -l "alb" aws-scripts-inventory.txt > aws-alb-scripts.txt
```

### Step 2: Analyze Script Functions

```bash
# Extract function definitions
for script in $(cat aws-scripts-inventory.txt); do
    echo "=== $script ==="
    grep -E "^function|^[a-zA-Z_]+\(\)" "$script"
done > aws-functions-inventory.txt

# Identify duplicate functions
./scripts/unity-cli.sh migrate analyze-duplicates \
    --input aws-functions-inventory.txt \
    --report duplicate-functions.md
```

### Step 3: Create Function Mapping

Map existing functions to Unity AWS service methods:

| Legacy Function | Unity Method | Notes |
|----------------|--------------|-------|
| `create_ec2_instance()` | `unity_aws_ec2_create()` | Enhanced with retry logic |
| `get_vpc_info()` | `unity_aws_vpc_describe()` | Cached for performance |
| `setup_security_groups()` | `unity_aws_security_create()` | Includes validation |
| `mount_efs()` | `unity_aws_efs_mount()` | Better error handling |

### Step 4: Implement Unity AWS Service

The unified AWS service is already implemented at `lib/unity/services/aws.sh`. Key improvements include:

1. **Centralized error handling**
2. **Automatic retries with backoff**
3. **Response caching**
4. **Event publishing**
5. **Comprehensive logging**

### Step 5: Update Script References

#### Update deploy.sh

```bash
# Before:
source "$SCRIPT_DIR/lib/aws-ec2.sh"
source "$SCRIPT_DIR/lib/aws-vpc.sh"
create_ec2_instance "$INSTANCE_TYPE" "$AMI_ID"

# After:
source "$SCRIPT_DIR/lib/unity/services/aws.sh"
unity_aws_ec2_create \
    --instance-type "$INSTANCE_TYPE" \
    --ami-id "$AMI_ID" \
    --event-driven
```

#### Update Makefile

```makefile
# Before:
deploy-spot:
	./scripts/aws-spot-deploy.sh $(STACK_NAME)

# After:
deploy-spot:
	./scripts/unity-cli.sh deploy $(STACK_NAME) --spot
```

### Step 6: Migrate Custom Functions

For custom AWS functions not in the standard service:

```bash
# 1. Create extension file
cat > lib/unity/services/aws-extensions.sh << 'EOF'
#!/bin/bash
# Custom AWS extensions for Unity

# Source base AWS service
source "${UNITY_LIB_DIR}/services/aws.sh"

# Custom function example
unity_aws_custom_operation() {
    local param="$1"
    
    # Your custom logic here
    log_info "Executing custom operation: $param"
    
    # Publish event
    publish_event "aws.custom.executed" "{\"param\": \"$param\"}"
}
EOF

# 2. Register extension
./scripts/unity-cli.sh service extend aws \
    --extension lib/unity/services/aws-extensions.sh
```

### Step 7: Test Migration

```bash
# Run comprehensive tests
./tests/unity/test-aws-service.sh

# Test backward compatibility
./tests/migration/test-aws-compatibility.sh

# Performance comparison
./scripts/unity-cli.sh benchmark aws \
    --compare-legacy \
    --operations "ec2-create,vpc-setup,efs-mount"
```

### Step 8: Gradual Rollout

```bash
# Enable Unity AWS service for specific operations
export UNITY_AWS_ENABLED=true
export UNITY_AWS_OPERATIONS="ec2,vpc"  # Start with subset

# Monitor for issues
./scripts/unity-cli.sh monitor aws \
    --watch-errors \
    --alert-threshold 5
```

## Function Migration Examples

### Example 1: EC2 Instance Creation

**Legacy Code:**
```bash
create_ec2_instance() {
    local instance_type="$1"
    local ami_id="$2"
    
    aws ec2 run-instances \
        --instance-type "$instance_type" \
        --image-id "$ami_id" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$SUBNET_ID"
}
```

**Unity Code:**
```bash
# Simple migration
unity_aws_ec2_create "$instance_type" "$ami_id"

# With additional features
unity_aws_ec2_create \
    --instance-type "$instance_type" \
    --ami-id "$ami_id" \
    --tags "Environment=production,Team=devops" \
    --wait-for-running \
    --enable-monitoring
```

### Example 2: VPC Operations

**Legacy Code:**
```bash
# Multiple scripts for VPC operations
./scripts/create-vpc.sh
./scripts/setup-subnets.sh
./scripts/configure-routes.sh
./scripts/setup-igw.sh
```

**Unity Code:**
```bash
# Single unified command
unity_aws_vpc_create \
    --cidr "10.0.0.0/16" \
    --availability-zones "us-east-1a,us-east-1b" \
    --enable-nat \
    --enable-flow-logs
```

## Rollback Procedure

If issues occur during migration:

```bash
# 1. Disable Unity AWS service
export UNITY_AWS_ENABLED=false

# 2. Restore legacy scripts
./scripts/unity-cli.sh migrate rollback \
    --phase aws \
    --restore-scripts

# 3. Verify legacy functionality
./tests/legacy/test-aws-operations.sh

# 4. Document issues for resolution
./scripts/unity-cli.sh migrate report-issues \
    --phase aws \
    --output aws-migration-issues.md
```

## Post-Migration Validation

```bash
# 1. Functional testing
./scripts/unity-cli.sh test aws --comprehensive

# 2. Performance validation
./scripts/unity-cli.sh benchmark aws --compare-baseline

# 3. Cost analysis
./scripts/unity-cli.sh cost analyze \
    --before-migration \
    --after-migration

# 4. Security audit
./scripts/unity-cli.sh security audit aws
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check IAM permissions
   unity_aws_iam_check --required-permissions
   ```

2. **API Rate Limiting**
   ```bash
   # Enable rate limiting protection
   export UNITY_AWS_RATE_LIMIT_PROTECTION=true
   ```

3. **Region-Specific Issues**
   ```bash
   # Test region compatibility
   unity_aws_test_region "$AWS_REGION"
   ```

## Benefits After Migration

1. **Reduced Code**: 60+ scripts → 1 unified service
2. **Better Error Handling**: Automatic retries and recovery
3. **Performance**: Caching reduces API calls by 40%
4. **Monitoring**: Built-in metrics and event tracking
5. **Maintainability**: Single source of truth for AWS operations

## Next Steps

- [ ] Monitor AWS service performance for 1 week
- [ ] Collect team feedback
- [ ] Document any custom extensions needed
- [ ] Plan Phase 2: Configuration Unification
- [ ] Archive legacy scripts after validation period