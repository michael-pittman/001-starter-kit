# Maintenance Suite Guide

> Comprehensive guide for GeuseMaker maintenance operations using Unity

## Overview

The GeuseMaker maintenance suite provides unified maintenance operations through the Unity system. All maintenance tasks are orchestrated through Unity services, ensuring consistent and reliable operations.

## Maintenance Commands

### Unity CLI Maintenance Commands

The primary interface for all maintenance operations:

```bash
# Core maintenance operations
./scripts/unity-cli.sh maintenance fix my-stack           # Fix deployment issues
./scripts/unity-cli.sh maintenance cleanup my-stack       # Clean up resources  
./scripts/unity-cli.sh maintenance backup my-stack        # Create system backup
./scripts/unity-cli.sh maintenance health my-stack        # Comprehensive health check
./scripts/unity-cli.sh maintenance update my-stack        # Update services and images

# Advanced maintenance
./scripts/unity-cli.sh maintenance optimize my-stack      # Performance optimization
./scripts/unity-cli.sh maintenance security-scan my-stack # Security compliance check
./scripts/unity-cli.sh maintenance cost-analysis my-stack # Cost optimization analysis
```

### Legacy Makefile Support

All maintenance operations are integrated into the Unity CLI:

```bash
# Unity maintenance commands
./unity maintenance fix my-stack              # Fix deployment issues
./unity maintenance cleanup my-stack          # Clean up resources
./unity maintenance backup --type full my-stack  # Create backup
./unity health my-stack                       # Health check
./unity update production                     # Update Docker images
```

## Maintenance Operations

### 1. Fix Deployment Issues

Automatically diagnose and fix common deployment problems:

```bash
./scripts/unity-cli.sh maintenance fix my-stack
```

**What it fixes:**
- Service startup failures
- Container restart loops
- Network connectivity issues
- Resource allocation problems
- Configuration inconsistencies
- Unity service dependencies

**Example Output:**
```
🔧 Starting maintenance fix for stack: my-stack
📊 Diagnosing issues...
   ✅ Unity services: healthy
   ❌ Docker service: container restart loop detected
   ✅ AWS resources: healthy
   
🛠️  Applying fixes...
   🔄 Restarting failed containers
   🔧 Updating container configurations
   ✅ All services restored

✨ Maintenance fix completed successfully
```

### 2. Resource Cleanup

Clean up unused resources and optimize system performance:

```bash
./scripts/unity-cli.sh maintenance cleanup my-stack
```

**Cleanup Operations:**
- Remove unused Docker images and containers
- Clean up temporary files and logs
- Optimize disk space usage
- Clear application caches
- Remove obsolete configuration files
- Clean up AWS resources (if safe)

**Options:**
```bash
# Aggressive cleanup (more thorough)
./scripts/unity-cli.sh maintenance cleanup my-stack --aggressive

# Dry run (show what would be cleaned)
./scripts/unity-cli.sh maintenance cleanup my-stack --dry-run

# Clean specific components
./scripts/unity-cli.sh maintenance cleanup my-stack --docker-only
./scripts/unity-cli.sh maintenance cleanup my-stack --logs-only
```

### 3. System Backup

Create comprehensive backups of your deployment:

```bash
./scripts/unity-cli.sh maintenance backup my-stack
```

**Backup Types:**
```bash
# Full system backup (default)
./scripts/unity-cli.sh maintenance backup my-stack --type full

# Configuration backup only
./scripts/unity-cli.sh maintenance backup my-stack --type config

# Data backup only (AI models, databases)
./scripts/unity-cli.sh maintenance backup my-stack --type data

# Quick backup (essential files only)
./scripts/unity-cli.sh maintenance backup my-stack --type quick
```

**Backup Contents:**
- Unity configuration and state
- Docker Compose files and configurations
- AI models and data (Ollama, Qdrant)
- n8n workflows and credentials
- Application logs and metrics
- AWS resource configurations

**Backup Locations:**
- Local: `backups/my-stack-YYYYMMDD-HHMMSS/`
- S3: `s3://your-backup-bucket/geusemaker/my-stack/`
- EFS: `/efs/backups/my-stack/`

### 4. Health Monitoring

Comprehensive health checks across all system components:

```bash
./scripts/unity-cli.sh maintenance health my-stack
```

**Health Check Categories:**
- Unity system health
- AWS infrastructure status
- Docker container health
- AI service functionality
- Network connectivity
- Performance metrics
- Security compliance

**Health Check Output:**
```
🏥 GeuseMaker Health Check Report
Stack: my-stack | Region: us-east-1 | Time: 2024-01-01 12:00:00

🔧 Unity System Health
   ✅ Unity Core: healthy (uptime: 2d 4h)
   ✅ AWS Service: healthy (last check: 30s ago)
   ✅ Docker Service: healthy (4/4 containers running)
   ✅ Monitor Service: healthy (collecting metrics)

☁️  AWS Infrastructure
   ✅ EC2 Instance: running (i-1234567890abcdef0)
   ✅ VPC: healthy (vpc-12345678)
   ✅ Load Balancer: healthy (3/3 targets)
   ✅ Security Groups: configured correctly

🤖 AI Services
   ✅ n8n: healthy (5 workflows active)
   ✅ Ollama: healthy (2 models loaded)
   ✅ Qdrant: healthy (3 collections, 10K points)
   ✅ Crawl4AI: healthy (2 active crawls)

📊 Performance Metrics
   ✅ CPU Usage: 45% (normal)
   ✅ Memory Usage: 68% (normal)
   ✅ Disk Usage: 23% (good)
   ✅ GPU Usage: 51% (normal)

🔒 Security Status
   ✅ Security Groups: restrictive
   ✅ SSL Certificates: valid
   ✅ Access Logs: enabled
   ⚠️  SSH Key: expires in 30 days

Overall Status: HEALTHY ✅
```

### 5. Service Updates

Update Docker images and service configurations:

```bash
./scripts/unity-cli.sh maintenance update my-stack
```

**Update Operations:**
- Pull latest Docker images
- Update service configurations
- Restart services with zero downtime
- Validate service functionality
- Rollback on failure

**Update Options:**
```bash
# Update specific services
./scripts/unity-cli.sh maintenance update my-stack --services n8n,ollama

# Check for updates only (no actual update)
./scripts/unity-cli.sh maintenance update my-stack --check-only

# Force update even if versions match
./scripts/unity-cli.sh maintenance update my-stack --force

# Update with rollback protection
./scripts/unity-cli.sh maintenance update my-stack --safe-mode
```

### 6. Performance Optimization

Analyze and optimize system performance:

```bash
./scripts/unity-cli.sh maintenance optimize my-stack
```

**Optimization Areas:**
- Docker container resource allocation
- AI model loading and caching
- Database query optimization
- Network configuration tuning
- Storage I/O optimization
- Memory usage optimization

### 7. Security Scanning

Perform comprehensive security assessments:

```bash
./scripts/unity-cli.sh maintenance security-scan my-stack
```

**Security Checks:**
- Container vulnerability scanning
- AWS security group analysis
- SSL certificate validation
- Access log analysis
- Configuration security review
- Compliance checks

### 8. Cost Analysis

Analyze and optimize AWS costs:

```bash
./scripts/unity-cli.sh maintenance cost-analysis my-stack
```

**Cost Analysis Features:**
- Current resource costs
- Cost optimization recommendations
- Spot instance savings opportunities
- Right-sizing recommendations
- Unused resource identification

## Scheduled Maintenance

### Automated Maintenance

Set up automated maintenance schedules:

```bash
# Setup daily health checks
./scripts/unity-cli.sh maintenance schedule my-stack \
  --operation health \
  --frequency daily \
  --time "02:00"

# Setup weekly cleanup
./scripts/unity-cli.sh maintenance schedule my-stack \
  --operation cleanup \
  --frequency weekly \
  --day sunday \
  --time "03:00"

# Setup monthly backups
./scripts/unity-cli.sh maintenance schedule my-stack \
  --operation backup \
  --frequency monthly \
  --day 1 \
  --time "01:00"
```

### Maintenance Windows

Define maintenance windows for updates:

```bash
# Set maintenance window
./scripts/unity-cli.sh maintenance window my-stack \
  --start "02:00" \
  --end "04:00" \
  --timezone "UTC" \
  --days "sunday,wednesday"

# Perform maintenance during window
./scripts/unity-cli.sh maintenance update my-stack --use-window
```

## Maintenance Monitoring

### Maintenance Logs

All maintenance operations are logged:

```bash
# View maintenance logs
./scripts/unity-cli.sh logs maintenance

# View specific operation logs
./scripts/unity-cli.sh logs maintenance --operation backup

# Follow maintenance logs in real-time
./scripts/unity-cli.sh logs maintenance --follow
```

### Maintenance Metrics

Track maintenance operation metrics:

```bash
# View maintenance statistics
./scripts/unity-cli.sh maintenance stats my-stack

# Export maintenance metrics
./scripts/unity-cli.sh maintenance export-metrics my-stack
```

## Emergency Procedures

### Emergency Maintenance

For critical issues requiring immediate attention:

```bash
# Emergency fix (skip confirmations)
./scripts/unity-cli.sh maintenance emergency-fix my-stack

# Emergency rollback
./scripts/unity-cli.sh maintenance emergency-rollback my-stack

# Emergency shutdown
./scripts/unity-cli.sh maintenance emergency-shutdown my-stack
```

### Recovery Procedures

Recover from critical failures:

```bash
# Restore from backup
./scripts/unity-cli.sh maintenance restore my-stack \
  --backup-id "backup-20240101-120000"

# Disaster recovery
./scripts/unity-cli.sh maintenance disaster-recovery my-stack \
  --recovery-plan production
```

## Maintenance Best Practices

### Pre-Maintenance Checklist

Before performing maintenance:

1. **Create Backup**: Always backup before major changes
2. **Check Health**: Ensure system is healthy before maintenance
3. **Schedule Window**: Perform maintenance during low-usage periods
4. **Notify Users**: Inform users of planned maintenance
5. **Monitor Resources**: Ensure sufficient resources for maintenance operations

### During Maintenance

1. **Monitor Progress**: Watch maintenance operation logs
2. **Verify Operations**: Confirm each step completes successfully
3. **Check Dependencies**: Ensure dependent services remain healthy
4. **Document Issues**: Record any problems encountered

### Post-Maintenance Checklist

After maintenance:

1. **Health Check**: Perform comprehensive health verification
2. **Functional Testing**: Test critical application functionality
3. **Performance Check**: Verify performance hasn't degraded
4. **Update Documentation**: Document any changes made
5. **Notify Users**: Confirm maintenance completion

## Troubleshooting Maintenance Issues

### Common Issues

1. **Maintenance Operation Fails**:
   ```bash
   # Check Unity logs
   ./scripts/unity-cli.sh logs core
   
   # Retry with debug mode
   export UNITY_LOG_LEVEL=DEBUG
   ./scripts/unity-cli.sh maintenance fix my-stack
   ```

2. **Backup Fails**:
   ```bash
   # Check disk space
   df -h
   
   # Check S3 permissions
   aws s3 ls s3://your-backup-bucket/
   
   # Retry with different backup type
   ./scripts/unity-cli.sh maintenance backup my-stack --type quick
   ```

3. **Service Update Fails**:
   ```bash
   # Check Docker daemon
   docker info
   
   # Check image availability
   docker pull your-image:latest
   
   # Rollback to previous version
   ./scripts/unity-cli.sh maintenance rollback my-stack
   ```

### Getting Help

For maintenance issues:

1. **Check Logs**: Review Unity and service logs
2. **Run Diagnostics**: Use built-in diagnostic tools
3. **Consult Documentation**: Check specific service documentation
4. **Contact Support**: Create issue with diagnostic information

## Integration with CI/CD

### GitHub Actions Integration

```yaml
# .github/workflows/maintenance.yml
name: Scheduled Maintenance
on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM

jobs:
  maintenance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Maintenance
        run: |
          ./scripts/unity-cli.sh maintenance health production
          ./scripts/unity-cli.sh maintenance cleanup production
          ./scripts/unity-cli.sh maintenance backup production
```

### Monitoring Integration

```bash
# Send maintenance metrics to monitoring system
./scripts/unity-cli.sh maintenance health my-stack --output json | \
  curl -X POST https://your-monitoring-system.com/api/metrics \
  -H "Content-Type: application/json" \
  -d @-
```

---

**Related Documentation:**
- [Unity Operations Guide](unity/core/unity-operations.md)
- [Troubleshooting Guide](guides/troubleshooting.md)
- [Monitoring API Reference](reference/api/monitoring.md)