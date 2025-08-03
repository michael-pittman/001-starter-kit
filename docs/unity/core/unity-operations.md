# Unity Operations Manual

## Table of Contents

1. [Deployment Procedures](#deployment-procedures)
2. [Monitoring & Maintenance](#monitoring--maintenance)
3. [Performance Tuning](#performance-tuning)
4. [Troubleshooting Guide](#troubleshooting-guide)
5. [Backup & Recovery](#backup--recovery)
6. [Security Operations](#security-operations)
7. [Scaling & High Availability](#scaling--high-availability)
8. [Operational Runbooks](#operational-runbooks)

## Deployment Procedures

### Standard Deployment Process

#### 1. Pre-Deployment Checklist

```bash
# Run pre-deployment validation
./scripts/unity-cli.sh validate deployment --stack-name production

# Check system requirements
./scripts/unity-cli.sh check requirements

# Verify AWS quotas
./scripts/unity-cli.sh aws check-quotas --region us-east-1

# Test configuration
./scripts/unity-cli.sh config validate --env production
```

#### 2. Production Deployment

```bash
# Step 1: Deploy infrastructure
./scripts/unity-cli.sh deploy infrastructure \
    --stack-name production \
    --env production \
    --multi-az \
    --backup-enabled

# Step 2: Deploy applications
./scripts/unity-cli.sh deploy applications \
    --stack-name production \
    --health-check-grace-period 300

# Step 3: Configure monitoring
./scripts/unity-cli.sh monitor setup \
    --stack-name production \
    --alert-email ops@company.com

# Step 4: Verify deployment
./scripts/unity-cli.sh verify deployment \
    --stack-name production \
    --comprehensive
```

### Deployment Strategies

#### Blue-Green Deployment

```bash
# Create green environment
./scripts/unity-cli.sh deploy \
    --stack-name production-green \
    --copy-from production-blue

# Test green environment
./scripts/unity-cli.sh test \
    --stack-name production-green \
    --smoke-tests

# Switch traffic
./scripts/unity-cli.sh switch-traffic \
    --from production-blue \
    --to production-green \
    --percentage 100

# Clean up old environment
./scripts/unity-cli.sh destroy \
    --stack-name production-blue \
    --after-hours 24
```

#### Canary Deployment

```bash
# Deploy canary version
./scripts/unity-cli.sh deploy canary \
    --stack-name production \
    --version 2.0.0 \
    --traffic-percentage 10

# Monitor canary metrics
./scripts/unity-cli.sh monitor canary \
    --stack-name production \
    --duration 1h

# Promote or rollback
./scripts/unity-cli.sh canary promote --stack-name production
# OR
./scripts/unity-cli.sh canary rollback --stack-name production
```

### Rollback Procedures

```bash
# Immediate rollback
./scripts/unity-cli.sh rollback \
    --stack-name production \
    --to-version previous

# Rollback to specific version
./scripts/unity-cli.sh rollback \
    --stack-name production \
    --to-version 1.2.3

# Rollback with data preservation
./scripts/unity-cli.sh rollback \
    --stack-name production \
    --preserve-data \
    --backup-first
```

## Monitoring & Maintenance

### Health Monitoring

#### System Health Checks

```bash
# Run comprehensive health check
./scripts/unity-cli.sh health check --all

# Check specific components
./scripts/unity-cli.sh health check --service aws
./scripts/unity-cli.sh health check --service docker
./scripts/unity-cli.sh health check --database

# Continuous monitoring
./scripts/unity-cli.sh monitor start \
    --interval 60 \
    --alert-threshold critical
```

#### Custom Health Checks

```bash
# Define custom health check
cat > health-checks/api-endpoint.yml << EOF
name: api-endpoint
type: http
url: https://api.example.com/health
expected_status: 200
timeout: 5
interval: 30
retries: 3
EOF

# Register health check
./scripts/unity-cli.sh health register health-checks/api-endpoint.yml
```

### Log Management

#### Log Collection

```bash
# View unified logs
./scripts/unity-cli.sh logs --follow

# Filter logs by service
./scripts/unity-cli.sh logs --service aws --level error

# Export logs
./scripts/unity-cli.sh logs export \
    --from "2024-01-01" \
    --to "2024-01-31" \
    --format json \
    --output /backup/logs/
```

#### Log Analysis

```bash
# Analyze error patterns
./scripts/unity-cli.sh logs analyze \
    --pattern "ERROR|CRITICAL" \
    --group-by service

# Generate log report
./scripts/unity-cli.sh logs report \
    --period daily \
    --email ops@company.com
```

### Maintenance Tasks

#### Scheduled Maintenance

```bash
# Schedule maintenance window
./scripts/unity-cli.sh maintenance schedule \
    --start "2024-01-15 02:00" \
    --duration 2h \
    --notify-users

# Enter maintenance mode
./scripts/unity-cli.sh maintenance start \
    --message "System upgrade in progress"

# Exit maintenance mode
./scripts/unity-cli.sh maintenance end
```

#### Routine Maintenance

```bash
# Clean up old resources
./scripts/unity-cli.sh cleanup \
    --older-than 30d \
    --resource-types "logs,snapshots,amis"

# Update system components
./scripts/unity-cli.sh update \
    --components "docker-images,plugins" \
    --backup-first

# Optimize database
./scripts/unity-cli.sh database optimize \
    --vacuum \
    --analyze
```

## Performance Tuning

### Performance Monitoring

```bash
# Real-time performance metrics
./scripts/unity-cli.sh performance monitor \
    --metrics "cpu,memory,network,disk"

# Generate performance report
./scripts/unity-cli.sh performance report \
    --period weekly \
    --format pdf
```

### Optimization Strategies

#### Resource Optimization

```bash
# Analyze resource usage
./scripts/unity-cli.sh analyze resources \
    --recommend-sizing

# Apply optimizations
./scripts/unity-cli.sh optimize \
    --auto-scaling \
    --spot-instances \
    --reserved-capacity
```

#### Caching Configuration

```bash
# Configure caching layers
cat > cache-config.yml << EOF
redis:
  enabled: true
  size: cache.r6g.xlarge
  eviction_policy: lru
  
cloudfront:
  enabled: true
  ttl:
    default: 3600
    static: 86400
    api: 300
EOF

./scripts/unity-cli.sh cache configure --file cache-config.yml
```

### Performance Benchmarking

```bash
# Run performance tests
./scripts/unity-cli.sh benchmark \
    --test-suite comprehensive \
    --duration 1h \
    --concurrent-users 1000

# Compare performance
./scripts/unity-cli.sh benchmark compare \
    --baseline v1.0.0 \
    --current v2.0.0
```

## Troubleshooting Guide

### Common Issues

#### 1. Service Registration Failures

```bash
# Diagnose registration issues
./scripts/unity-cli.sh diagnose service-registration

# Manual service registration
./scripts/unity-cli.sh registry register \
    --service-name aws \
    --service-path /lib/unity/services/aws.sh \
    --force

# Verify registration
./scripts/unity-cli.sh registry list --verbose
```

#### 2. Event Bus Problems

```bash
# Check event bus status
./scripts/unity-cli.sh events status

# Clear event queue
./scripts/unity-cli.sh events clear-queue \
    --queue dead-letter \
    --backup-first

# Replay failed events
./scripts/unity-cli.sh events replay \
    --from-dlq \
    --pattern "deployment.*"
```

#### 3. Configuration Issues

```bash
# Validate configuration
./scripts/unity-cli.sh config doctor

# Show configuration conflicts
./scripts/unity-cli.sh config conflicts --resolve

# Reset to defaults
./scripts/unity-cli.sh config reset \
    --keep-secrets \
    --backup-current
```

### Debug Mode Operations

```bash
# Enable debug mode
export UNITY_DEBUG=true
export UNITY_LOG_LEVEL=trace

# Run with verbose output
./scripts/unity-cli.sh --verbose --debug deploy test-stack

# Trace execution
./scripts/unity-cli.sh trace \
    --command "deploy" \
    --save-to trace-output.log
```

### Emergency Procedures

#### System Recovery

```bash
# Emergency stop all services
./scripts/unity-cli.sh emergency stop-all

# Recover from corrupted state
./scripts/unity-cli.sh recover \
    --from-backup latest \
    --verify-integrity

# Force cleanup
./scripts/unity-cli.sh cleanup \
    --force \
    --include-persistent-data
```

## Backup & Recovery

### Backup Strategies

#### Automated Backups

```bash
# Configure automated backups
cat > backup-policy.yml << EOF
schedule:
  full: "0 2 * * 0"  # Weekly full backup
  incremental: "0 2 * * 1-6"  # Daily incremental
retention:
  daily: 7
  weekly: 4
  monthly: 12
targets:
  - s3://backup-bucket/unity/
  - efs://backup-volume/
EOF

./scripts/unity-cli.sh backup configure --policy backup-policy.yml
```

#### Manual Backups

```bash
# Full system backup
./scripts/unity-cli.sh backup create \
    --type full \
    --include-secrets \
    --compress

# Selective backup
./scripts/unity-cli.sh backup create \
    --components "config,data,state" \
    --tag pre-upgrade
```

### Recovery Procedures

```bash
# List available backups
./scripts/unity-cli.sh backup list

# Restore from backup
./scripts/unity-cli.sh restore \
    --backup-id backup-2024-01-15-full \
    --target-env staging

# Verify restoration
./scripts/unity-cli.sh verify restore \
    --compare-checksums \
    --test-functionality
```

## Security Operations

### Security Monitoring

```bash
# Run security audit
./scripts/unity-cli.sh security audit \
    --compliance "pci,hipaa" \
    --report-format json

# Monitor security events
./scripts/unity-cli.sh security monitor \
    --alert-on "unauthorized,anomaly"

# Check vulnerabilities
./scripts/unity-cli.sh security scan \
    --include-dependencies \
    --severity "high,critical"
```

### Access Management

```bash
# Review access permissions
./scripts/unity-cli.sh iam review \
    --check-least-privilege

# Rotate credentials
./scripts/unity-cli.sh security rotate-credentials \
    --service all \
    --grace-period 24h

# Audit access logs
./scripts/unity-cli.sh audit logs \
    --filter "authentication,authorization" \
    --suspicious-only
```

## Scaling & High Availability

### Auto-Scaling Configuration

```bash
# Configure auto-scaling
cat > scaling-policy.yml << EOF
metrics:
  - type: cpu
    target: 70
    scale_up_threshold: 80
    scale_down_threshold: 50
  - type: memory
    target: 80
    scale_up_threshold: 90
capacity:
  min: 2
  max: 10
  desired: 4
cooldown:
  scale_up: 300
  scale_down: 600
EOF

./scripts/unity-cli.sh scaling configure --policy scaling-policy.yml
```

### Multi-Region Setup

```bash
# Deploy to multiple regions
./scripts/unity-cli.sh deploy multi-region \
    --primary us-east-1 \
    --secondary "us-west-2,eu-west-1" \
    --replication-mode active-active

# Configure cross-region replication
./scripts/unity-cli.sh replication setup \
    --source us-east-1 \
    --targets "us-west-2,eu-west-1" \
    --real-time
```

## Operational Runbooks

### Daily Operations

```bash
#!/bin/bash
# Daily operations runbook

# 1. Check system health
./scripts/unity-cli.sh health check --all

# 2. Review overnight alerts
./scripts/unity-cli.sh alerts review --unacknowledged

# 3. Check backup status
./scripts/unity-cli.sh backup status --verify-latest

# 4. Review resource usage
./scripts/unity-cli.sh resources report --cost-analysis

# 5. Update monitoring dashboard
./scripts/unity-cli.sh dashboard refresh
```

### Incident Response

```bash
#!/bin/bash
# Incident response runbook

# 1. Assess impact
./scripts/unity-cli.sh incident assess --auto-classify

# 2. Gather diagnostics
./scripts/unity-cli.sh diagnose --comprehensive \
    --output incident-$(date +%Y%m%d-%H%M%S)

# 3. Apply immediate fixes
./scripts/unity-cli.sh incident mitigate --auto-apply-safe

# 4. Document incident
./scripts/unity-cli.sh incident document \
    --template standard \
    --include-timeline

# 5. Post-mortem
./scripts/unity-cli.sh incident post-mortem \
    --generate-report \
    --action-items
```

### Capacity Planning

```bash
# Analyze growth trends
./scripts/unity-cli.sh capacity analyze \
    --period 90d \
    --forecast 180d

# Generate capacity report
./scripts/unity-cli.sh capacity report \
    --include-recommendations \
    --cost-projection

# Plan infrastructure changes
./scripts/unity-cli.sh capacity plan \
    --target-growth 50% \
    --optimize-cost
```

## Operational Best Practices

1. **Always maintain backups** before any major changes
2. **Use staging environments** to test changes
3. **Document all manual interventions** in runbooks
4. **Monitor key metrics** continuously
5. **Automate repetitive tasks** to reduce errors
6. **Regular security audits** and credential rotation
7. **Capacity planning** based on growth trends
8. **Incident post-mortems** for continuous improvement

## Support Escalation

- **Level 1**: Automated monitoring alerts
- **Level 2**: On-call engineer via PagerDuty
- **Level 3**: Senior operations team
- **Level 4**: Architecture team + vendor support