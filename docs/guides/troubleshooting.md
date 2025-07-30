# Troubleshooting Guide

## Common Issues and Solutions

### Bash Version Compatibility

#### Working with Different Bash Versions

**Symptom**: Running on systems with older bash versions (e.g., macOS with bash 3.2)

**Solution**: Scripts are fully compatible with bash 3.x+
```bash
# Check your current bash version
bash --version

# No upgrade required - compatibility layers handle older versions automatically
# Optional: Upgrade for additional features
# macOS:
brew install bash
echo '/usr/local/bin/bash' | sudo tee -a /etc/shells
chsh -s /usr/local/bin/bash

# Ubuntu/Debian:
sudo apt update && sudo apt install bash

# RHEL/Amazon Linux:
sudo yum install bash
```

**Note**: 
- Scripts remain functional with bash 3.2+ (macOS default)
- Core features work across all versions
- Some advanced features may have reduced functionality with older bash

### Deployment Issues

#### 1. EC2 Instance Launch Failures

**Symptom**: Instance fails to launch with insufficient capacity error
```
InsufficientInstanceCapacity: We currently do not have sufficient capacity in the requested Availability Zone.
```

**Solution**: The modular system automatically handles this
```bash
# The system will try:
# 1. Different AZs in same region
# 2. Fallback instance types (g4dn.large, g5.xlarge)
# 3. Fallback regions (us-east-2, us-west-2)

# Manual override if needed:
export EC2_INSTANCE_TYPE=g5.xlarge
export AWS_REGION=us-west-2
make deploy-spot ENV=dev STACK_NAME=my-stack
```

**Prevention**: Use spot instance optimization
```bash
make deploy-spot ENV=dev STACK_NAME=my-stack
```

#### 2. Variable Export Errors

**Symptom**: 
```
export: 'efs-id=fs-0bba0ecccb246a550': not a valid identifier
```

**Solution**: Variable sanitization is now automatic
```bash
# This is fixed in the modular system
# Variables are automatically sanitized:
# efs-id → efs_id
# stack-name → stack_name
```

**Manual fix for legacy scripts**:
```bash
# Use sanitize_variable_name function
source lib/modules/core/variables.sh
sanitized=$(sanitize_variable_name "efs-id")
export "${sanitized}=fs-12345"
```

#### 3. Spot Instance Interruptions

**Symptom**: Spot instances terminated unexpectedly
```
Spot Instance interruption notice received
```

**Solution**: Use intelligent spot management
```bash
# Enable spot optimization with fallback
make deploy-spot ENV=prod STACK_NAME=my-stack

# Check spot instance health
make status ENV=prod STACK_NAME=my-stack
```

### Service Issues

#### 1. Docker Services Not Starting

**Symptom**: Services fail to start or restart constantly
```bash
docker compose ps
# Shows services in "restarting" state
```

**Diagnosis**:
```bash
# Check disk space (most common cause)
df -h
du -sh /var/lib/docker

# Check logs
docker compose logs service-name

# Check memory usage
free -h
```

**Solutions**:
```bash
# Clean up disk space
./lib/modules/cleanup/resources.sh --stack-name my-stack

# Restart services
docker compose down && docker compose up -d

# Check service health
make health ENV=dev STACK_NAME=my-stack
```

#### 2. GPU Not Detected

**Symptom**: Ollama cannot use GPU acceleration
```
Error: CUDA not available
```

**Diagnosis**:
```bash
# Check NVIDIA drivers
nvidia-smi

# Check Docker NVIDIA runtime
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

**Solutions**:
```bash
# Reinstall NVIDIA Docker runtime
sudo systemctl stop docker
sudo apt-get purge nvidia-docker2
sudo apt-get update
sudo apt-get install nvidia-docker2
sudo systemctl restart docker

# Or redeploy with GPU optimization
export EC2_INSTANCE_TYPE=g4dn.xlarge
make deploy-spot ENV=dev STACK_NAME=my-stack
```

#### 3. EFS Mount Failures

**Symptom**: EFS not mounting correctly
```
mount.nfs4: access denied by server while mounting
```

**Diagnosis**:
```bash
# Check EFS DNS
nslookup fs-12345.efs.region.amazonaws.com

# Check security groups
aws ec2 describe-security-groups --group-ids sg-12345
```

**Solutions**:
```bash
# Validate Parameter Store
./scripts/setup-parameter-store.sh validate

# Fix EFS configuration
./lib/modules/cleanup/resources.sh --stack-name my-stack

# Manual mount test
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 \
    fs-12345.efs.region.amazonaws.com:/ /mnt/efs
```

### Network Issues

#### 1. Services Not Accessible

**Symptom**: Cannot access services on configured ports
```
curl: (7) Failed to connect to IP:5678: Connection refused
```

**Diagnosis**:
```bash
# Check if services are running
docker compose ps

# Check port bindings
docker compose port n8n 5678

# Check security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*stack-name*"
```

**Solutions**:
```bash
# Update security groups
make deploy-alb ENV=dev STACK_NAME=my-stack

# Check ALB health
make health ENV=dev STACK_NAME=my-stack

# Direct service test
ssh -i key.pem ubuntu@ip "curl localhost:5678"
```

#### 2. ALB Health Check Failures

**Symptom**: ALB shows unhealthy targets
```
Target health check failed
```

**Diagnosis**:
```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn arn

# Check service health endpoints
curl http://localhost:5678/healthz
```

**Solutions**:
```bash
# Services should be running first
docker compose up -d

# Allow time for health checks (5+ minutes)
# ALB health checks have 5 consecutive success requirement

# Check health check paths in ALB
aws elbv2 describe-target-groups --target-group-arns arn
```

### Performance Issues

#### 1. High Memory Usage

**Symptom**: System running out of memory
```bash
free -h
# Shows very low available memory
```

**Diagnosis**:
```bash
# Check memory usage by service
docker stats

# Check system memory
ps aux --sort=-%mem | head -10
```

**Solutions**:
```bash
# Restart memory-intensive services
docker compose restart ollama

# Upgrade instance type
export EC2_INSTANCE_TYPE=g4dn.2xlarge
make deploy-spot ENV=dev STACK_NAME=my-stack

# Optimize resource allocation
# Edit docker-compose.yml memory limits
```

#### 2. Slow Response Times

**Symptom**: Services respond slowly
```bash
curl -w "%{time_total}" http://ip:5678/
# Shows >10s response times
```

**Diagnosis**:
```bash
# Check CPU usage
top
htop

# Check GPU usage (if applicable)
nvidia-smi

# Check disk I/O
iostat -x 1
```

**Solutions**:
```bash
# Scale up instance
export EC2_INSTANCE_TYPE=g5.xlarge
make deploy-spot ENV=dev STACK_NAME=my-stack

# Check model loading
docker compose logs ollama

# Optimize Docker resources
docker system prune -f
```

### Security Issues

#### 1. Parameter Store Access Denied

**Symptom**: 
```
AccessDenied: User is not authorized to perform: ssm:GetParameter
```

**Solutions**:
```bash
# Check IAM permissions
aws iam get-role-policy --role-name role-name --policy-name policy-name

# Update IAM policies
./archive/legacy/setup-parameter-store.sh setup

# Verify parameters exist
aws ssm get-parameter --name /aibuildkit/OPENAI_API_KEY
```

#### 2. Security Group Issues

**Symptom**: Connection timeouts or refused connections

**Diagnosis**:
```bash
# Check security group rules
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*stack-name*" \
    --query 'SecurityGroups[].IpPermissions'
```

**Solutions**:
```bash
# Update security groups with current IP
./scripts/security-validation.sh

# Use ALB for controlled access
make deploy-alb ENV=dev STACK_NAME=my-stack
```

## Debug Commands

### System Diagnostics

```bash
# Comprehensive system check
make health ENV=dev STACK_NAME=my-stack

# Check all services
make status ENV=dev STACK_NAME=my-stack

# Instance status
./lib/modules/monitoring/health.sh --stack-name my-stack

# AWS resource validation
aws ec2 describe-instances --filters "Name=tag:Stack,Values=my-stack"
```

### Log Analysis

```bash
# Service logs
docker compose logs -f service-name

# System logs
sudo journalctl -u docker.service

# AWS CloudWatch logs
aws logs describe-log-groups
aws logs get-log-events --log-group-name group-name --log-stream-name stream-name
```

### Network Debugging

```bash
# Port connectivity
nmap -p 5678,11434,6333 instance-ip

# DNS resolution
nslookup fs-12345.efs.region.amazonaws.com

# Security groups
aws ec2 describe-security-groups --group-ids sg-12345
```

## Recovery Procedures

### Service Recovery

```bash
# Restart all services
docker compose down
docker compose up -d

# Rebuild and restart
docker compose down
docker compose build --no-cache
docker compose up -d

# Clean restart
docker system prune -f
docker compose up -d --force-recreate
```

### Instance Recovery

```bash
# Reboot instance
aws ec2 reboot-instances --instance-ids i-12345

# Replace instance (spot interruption)
make destroy ENV=dev STACK_NAME=my-stack
make deploy-spot ENV=dev STACK_NAME=my-stack

# Emergency cleanup
./lib/modules/cleanup/resources.sh --stack-name my-stack
```

### Data Recovery

```bash
# EFS data is persistent across instance replacements
# Check EFS mount after new instance launch
ls -la /mnt/efs/

# Database backup (if configured)
docker compose exec postgres pg_dump database_name > backup.sql

# Restore from backup
docker compose exec -T postgres psql database_name < backup.sql
```

## Prevention Strategies

### Monitoring Setup

```bash
# Set up CloudWatch alarms
# CPU > 80% for 10 minutes
# Memory > 80% for 10 minutes
# Disk space > 80%

# Application monitoring
# Enable health check endpoints
# Set up log aggregation
# Configure alert webhooks
```

### Backup Strategy

```bash
# Regular backups
# EFS automatic backups enabled
# Database dumps to S3
# Configuration backups

# Test recovery procedures monthly
./tests/test-recovery.sh my-stack
```

### Cost Monitoring

```bash
# Set up billing alerts
# Monitor spot instance pricing
# Track resource usage

# Regular cost optimization
./scripts/check-quotas.sh
aws ce get-cost-and-usage --time-period Start=2023-01-01,End=2023-02-01
```

## Getting Help

### Log Collection

```bash
# Collect all relevant logs
mkdir debug-logs-$(date +%Y%m%d)
cd debug-logs-*

# System info
uname -a > system-info.txt
docker --version >> system-info.txt
aws --version >> system-info.txt

# Service logs
docker compose logs > docker-logs.txt
sudo journalctl -u docker.service > docker-service.txt

# AWS info
aws ec2 describe-instances > ec2-instances.json
aws elbv2 describe-load-balancers > alb-info.json

# Package into archive
cd ..
tar -czf debug-logs-$(date +%Y%m%d).tar.gz debug-logs-*
```

### Support Information

When reporting issues, include:

1. **Error message** (exact text)
2. **Steps to reproduce**
3. **System information** (OS, bash version, AWS region)
4. **Recent changes** (what was modified)
5. **Log files** (relevant excerpts)
6. **Stack configuration** (instance type, deployment options)

### Quick Fixes Summary

| Issue | Quick Fix |
|-------|-----------|
| Disk space full | `./lib/modules/cleanup/resources.sh --stack-name STACK` |
| Services not starting | `docker compose down && docker compose up -d` |
| EFS not mounting | `./scripts/setup-parameter-store.sh validate` |
| GPU not detected | Redeploy with `export EC2_INSTANCE_TYPE=g4dn.xlarge` |
| Spot interruption | `make deploy-spot ENV=dev STACK_NAME=STACK` |
| Security group issues | `./scripts/security-validation.sh` |
| Variable errors | Use modular deployment scripts |
| High costs | `make deploy-spot ENV=dev STACK_NAME=STACK` |