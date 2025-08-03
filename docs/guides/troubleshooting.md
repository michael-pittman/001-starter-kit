# Troubleshooting Guide

> Common issues and solutions for GeuseMaker deployments

## Quick Diagnostics

### Health Check Commands

```bash
# Unity system health
./scripts/unity-cli.sh service health

# Deployment status
./scripts/unity-cli.sh status my-stack

# Service monitoring
./scripts/unity-cli.sh monitor my-stack

# AWS resource validation
./scripts/unity-cli.sh validate-resources my-stack
```

### Debug Mode

```bash
# Enable verbose debugging
export DEBUG=1
export UNITY_LOG_LEVEL=DEBUG

# Run deployment with debugging
./deploy.sh spot my-stack
```

## Common Issues

### 1. AWS Authentication Issues

**Symptoms:**
- "Unable to locate credentials" errors
- "Access Denied" errors

**Solutions:**
```bash
# Configure AWS CLI
aws configure

# Verify credentials
aws sts get-caller-identity

# Use specific profile
export AWS_PROFILE=dev
aws configure --profile dev

# Check IAM permissions
aws iam get-user
```

### 2. Deployment Failures

**Symptoms:**
- Stack creation fails
- Resources not created
- Timeout errors

**Solutions:**
```bash
# Check AWS quotas
aws service-quotas list-service-quotas --service-code ec2

# Verify region availability
aws ec2 describe-availability-zones

# Check VPC limits
aws ec2 describe-vpcs

# Force cleanup and retry
./deploy.sh destroy my-stack --force
./deploy.sh spot my-stack
```

### 3. Unity Service Issues

**Symptoms:**
- Services not starting
- Event system failures
- Service discovery problems

**Solutions:**
```bash
# Restart Unity services
./scripts/unity-cli.sh service restart aws
./scripts/unity-cli.sh service restart docker

# Check service dependencies
./scripts/unity-cli.sh service dependencies

# Validate Unity configuration
./scripts/unity-cli.sh config validate

# Check event system
./scripts/unity-cli.sh events status
```

### 4. Network Connectivity Issues

**Symptoms:**
- Cannot access services
- SSH connection failures
- Load balancer health checks failing

**Solutions:**
```bash
# Check security groups
aws ec2 describe-security-groups

# Verify network ACLs
aws ec2 describe-network-acls

# Test connectivity
./scripts/unity-cli.sh test connectivity my-stack

# Check ALB target health
aws elbv2 describe-target-health
```

### 5. Docker and AI Service Issues

**Symptoms:**
- Docker containers not starting
- GPU not available
- AI services unresponsive

**Solutions:**
```bash
# Check Docker status
./scripts/unity-cli.sh service status docker

# Verify GPU availability
./scripts/unity-cli.sh gpu-check

# Restart AI services
./scripts/unity-cli.sh service restart ai-services

# Check container logs
docker logs n8n
docker logs ollama
docker logs qdrant
```

### 6. Performance Issues

**Symptoms:**
- Slow response times
- High resource usage
- Memory errors

**Solutions:**
```bash
# Monitor system resources
./scripts/unity-cli.sh monitor resources my-stack

# Check instance metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization

# Optimize instance type
./deploy.sh spot my-stack --instance-type g4dn.2xlarge

# Scale services
./scripts/unity-cli.sh scale my-stack --replicas 2
```

### 7. State Management Issues

**Symptoms:**
- Deployment state inconsistent
- Resource cleanup failures
- State file corruption

**Solutions:**
```bash
# Check Unity state
./scripts/unity-cli.sh state show my-stack

# Repair state
./scripts/unity-cli.sh state repair my-stack

# Reset state (caution: destructive)
./scripts/unity-cli.sh state reset my-stack

# Backup state
./scripts/unity-cli.sh state backup
```

## Error Categories

### Deployment Errors

| Error Code | Description | Solution |
|------------|-------------|----------|
| `VPC_CREATION_FAILED` | VPC creation failed | Check quotas, permissions |
| `EC2_LAUNCH_FAILED` | EC2 instance launch failed | Verify AMI, instance type availability |
| `ALB_SETUP_FAILED` | Load balancer setup failed | Check subnets, security groups |
| `EFS_MOUNT_FAILED` | EFS mount failed | Verify mount targets, security groups |

### Unity Errors

| Error Code | Description | Solution |
|------------|-------------|----------|
| `SERVICE_INIT_FAILED` | Service initialization failed | Check dependencies, configuration |
| `EVENT_BUS_ERROR` | Event system error | Restart event bus, check logs |
| `CONFIG_VALIDATION_ERROR` | Configuration validation failed | Fix config files, check syntax |
| `PLUGIN_LOAD_ERROR` | Plugin loading error | Check plugin compatibility |

### AWS Errors

| Error Code | Description | Solution |
|------------|-------------|----------|
| `QUOTA_EXCEEDED` | AWS service quota exceeded | Request quota increase |
| `PERMISSION_DENIED` | Insufficient permissions | Review IAM policies |
| `RESOURCE_NOT_FOUND` | AWS resource not found | Check resource IDs, region |
| `LIMIT_EXCEEDED` | Service limit exceeded | Clean up unused resources |

## Recovery Procedures

### Automatic Recovery

Unity includes automatic recovery mechanisms:

```bash
# Enable auto-recovery
./deploy.sh spot my-stack --auto-recovery

# Check recovery status
./scripts/unity-cli.sh recovery status my-stack
```

### Manual Recovery

```bash
# Step 1: Assess current state
./scripts/unity-cli.sh status my-stack
./scripts/unity-cli.sh service health

# Step 2: Stop failed services
./scripts/unity-cli.sh service stop failed-service

# Step 3: Clean up corrupted resources
./scripts/unity-cli.sh cleanup corrupted-resources my-stack

# Step 4: Restore from backup
./scripts/unity-cli.sh restore my-stack --backup-id backup-123

# Step 5: Restart services
./scripts/unity-cli.sh service start all
```

### Rollback Procedures

```bash
# Automatic rollback (during deployment)
./deploy.sh spot my-stack --auto-rollback

# Manual rollback to previous state
./scripts/unity-cli.sh rollback my-stack

# Rollback to specific version
./scripts/unity-cli.sh rollback my-stack --version v1.2.3

# Emergency rollback (immediate)
./scripts/unity-cli.sh emergency-rollback my-stack
```

## Preventive Measures

### Pre-flight Checks

```bash
# Run comprehensive pre-flight checks
./scripts/unity-cli.sh preflight my-stack

# Check AWS quotas
./scripts/unity-cli.sh check-quotas

# Validate configuration
./scripts/unity-cli.sh config validate

# Test connectivity
./scripts/unity-cli.sh test-network
```

### Monitoring Setup

```bash
# Set up continuous monitoring
./scripts/unity-cli.sh setup-monitoring my-stack

# Configure alerts
./scripts/unity-cli.sh setup-alerts my-stack

# Health check scheduling
./scripts/unity-cli.sh schedule-health-checks my-stack
```

### Backup Strategy

```bash
# Create deployment backup
./scripts/unity-cli.sh backup create my-stack

# Schedule automatic backups
./scripts/unity-cli.sh backup schedule my-stack --frequency daily

# Test backup restoration
./scripts/unity-cli.sh backup test-restore backup-123
```

## Getting Help

### Log Collection

```bash
# Collect all logs
./scripts/unity-cli.sh logs collect my-stack

# Generate diagnostic report
./scripts/unity-cli.sh diagnostics my-stack

# Export system state
./scripts/unity-cli.sh export-state my-stack
```

### Support Information

When requesting support, include:

1. **System Information:**
   ```bash
   uname -a
   aws --version
   ./scripts/unity-cli.sh version
   ```

2. **Error Logs:**
   ```bash
   # Unity logs
   cat logs/unity/core.log
   cat logs/unity/events.log
   
   # AWS CLI logs
   cat ~/.aws/cli/cache/
   ```

3. **Configuration:**
   ```bash
   cat config/unity.yml
   ./scripts/unity-cli.sh config show
   ```

### Escalation Path

1. **Self-Service:** Use this troubleshooting guide
2. **Documentation:** Check [Unity Documentation](../unity/)
3. **Community:** GitHub Discussions
4. **Support:** GitHub Issues with diagnostic information

## Advanced Debugging

### Unity Event System

```bash
# Monitor events in real-time
./scripts/unity-cli.sh events monitor

# Check event history
./scripts/unity-cli.sh events history my-stack

# Debug event flow
./scripts/unity-cli.sh events debug --trace
```

### Performance Profiling

```bash
# Profile deployment performance
./scripts/unity-cli.sh profile deployment my-stack

# Monitor resource usage
./scripts/unity-cli.sh profile resources my-stack

# Generate performance report
./scripts/unity-cli.sh profile report my-stack
```

### Network Debugging

```bash
# Test network connectivity
./scripts/unity-cli.sh network test my-stack

# Trace network paths
./scripts/unity-cli.sh network trace my-stack

# Analyze security groups
./scripts/unity-cli.sh network analyze-security-groups my-stack
```

---

**Need more help?** Check the [Unity Documentation](../unity/) or create an issue with diagnostic information.