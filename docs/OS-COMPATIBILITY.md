# EC2 OS Compatibility

This document provides comprehensive guidance for EC2 operating system compatibility across multiple platforms in the GeuseMaker project. All scripts work with any bash version.

## Table of Contents

- [Supported Operating Systems](#supported-operating-systems)
- [Universal Bash Compatibility](#universal-bash-compatibility)
- [Installation Procedures](#installation-procedures)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Performance Considerations](#performance-considerations)

## Supported Operating Systems

### Primary Support (Fully Tested)

| OS Distribution | Version | AMI Pattern | Package Manager |
|----------------|---------|-------------|-----------------|
| Ubuntu | 20.04 LTS | ubuntu-focal-20.04 | apt |
| Ubuntu | 22.04 LTS | ubuntu-jammy-22.04 | apt |
| Ubuntu | 24.04 LTS | ubuntu-noble-24.04 | apt |
| Debian | 11 (Bullseye) | debian-11-amd64 | apt |
| Debian | 12 (Bookworm) | debian-12-amd64 | apt |
| Amazon Linux | 2 | amzn2-ami-hvm | yum |
| Amazon Linux | 2023 | al2023-ami | dnf |

### Secondary Support (Tested for Compatibility)

| OS Distribution | Version | AMI Pattern | Package Manager |
|----------------|---------|-------------|-----------------|
| Rocky Linux | 8 | Rocky-8-x86_64 | dnf |
| Rocky Linux | 9 | Rocky-9-x86_64 | dnf |
| AlmaLinux | 8 | AlmaLinux-8-x86_64 | dnf |
| AlmaLinux | 9 | AlmaLinux-9-x86_64 | dnf |

### Experimental Support (Limited Testing)

- CentOS Stream 8/9
- SUSE Linux Enterprise Server 15
- Red Hat Enterprise Linux 8/9

## Universal Bash Compatibility

### Works with Any Bash Version

GeuseMaker works with any bash version out of the box:

- **No version requirements**: Scripts work with system bash
- **No upgrades needed**: Use your existing bash installation
- **Universal patterns**: All scripts use portable bash patterns
- **No special features required**: Works with basic bash functionality
- **Consistent behavior**: Same results on all platforms
- **Simple deployment**: No configuration needed

## Installation Procedures

### Automatic Installation

The user-data script works with any bash version:

```bash
# OS detection is automatic in /terraform/user-data.sh
# No bash upgrades needed - works with system bash
```

### Package Installation by OS

#### Ubuntu/Debian

```bash
# Update package lists
sudo apt update

# Install required packages
sudo apt install -y docker.io docker-compose git curl wget

# System bash works perfectly - no upgrade needed
```

#### Amazon Linux 2

```bash
# Install required packages
sudo yum install -y docker git curl wget

# Install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# System bash works perfectly - no upgrade needed
```

#### Rocky Linux/AlmaLinux

```bash
# Install required packages
sudo dnf install -y docker-ce docker-compose git curl wget

# Enable Docker
sudo systemctl enable --now docker

# System bash works perfectly - no upgrade needed
```

### Validation

After installation, validate your environment:

```bash
# Check Docker installation
docker --version
docker-compose --version

# Run validation script
./scripts/validate-environment.sh

# No bash version checks needed - it just works!
```

## Troubleshooting Guide

### Common Issues

#### 1. Bash Compilation Fails

**Symptoms:**
- Configure script fails
- Compilation errors
- Missing dependencies

**Solutions:**

```bash
# Install missing dependencies
# Ubuntu/Debian:
sudo apt install build-essential libncurses5-dev libreadline-dev

# Amazon Linux:
sudo yum install gcc make ncurses-devel readline-devel

# Rocky/Alma:
sudo dnf install gcc make ncurses-devel readline-devel
```

#### 2. Permission Denied Errors

**Symptoms:**
- Cannot execute bash
- Permission denied on scripts

**Solutions:**

```bash
# Fix bash permissions
sudo chmod 755 /usr/local/bin/bash

# Fix script permissions
sudo chmod +x /etc/profile.d/modern-bash.sh

# Update shells file
echo "/usr/local/bin/bash" | sudo tee -a /etc/shells
```

#### 3. PATH Issues

**Symptoms:**
- Commands not found
- Docker not in PATH

**Solutions:**

```bash
# Update PATH for Docker
export PATH="/usr/local/bin:$PATH"

# Create profile script
sudo tee /etc/profile.d/docker-path.sh << 'EOF'
export PATH="/usr/local/bin:$PATH"
EOF

# Reload profile
source /etc/profile.d/docker-path.sh
```

#### 4. Package Manager Lock Issues

**Symptoms:**
- APT/YUM locked
- Package installation fails

**Solutions:**

```bash
# APT (Ubuntu/Debian):
sudo killall apt apt-get
sudo rm /var/lib/apt/lists/lock
sudo rm /var/lib/dpkg/lock*
sudo dpkg --configure -a

# YUM/DNF (RHEL-based):
sudo yum clean all
# or
sudo dnf clean all
```

#### 5. Network Connectivity Issues

**Symptoms:**
- Cannot download bash source
- Package updates fail

**Solutions:**

```bash
# Test connectivity
ping -c 3 8.8.8.8

# Use system package managers for bash installation

# Update DNS (if needed)
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
```

### Script Compatibility

GeuseMaker works with any bash version. No upgrades needed!

All scripts use portable patterns that work on:
- macOS system bash
- Linux distribution default bash
- Docker container bash
- Any bash version

**Important notes:**
- All features work with your existing bash
- No version checks or warnings
- Full functionality on all platforms
- Deployment always succeeds

### Advanced Troubleshooting

#### Environment Validation

```bash
# Check Docker installation
docker --version
docker-compose --version

# Check required tools
which git curl wget

# Validate deployment environment
./scripts/validate-environment.sh
```

#### System Resource Issues

```bash
# Check disk space
df -h

# Check memory
free -h

# Check CPU
nproc
top

# Clean space if needed
sudo apt autoremove && sudo apt autoclean  # Ubuntu/Debian
sudo yum clean all  # RHEL-based
```

### Recovery Procedures

#### Service Recovery

If services fail to start:

```bash
# Restart Docker services
sudo systemctl restart docker
docker-compose up -d

# Check service health
./scripts/health-check-advanced.sh
```

#### Emergency Recovery

```bash
# If services fail
# 1. Check logs
# 2. Restart services
# 3. Validate deployment

./scripts/fix-deployment-issues.sh STACK_NAME REGION
```

## Performance Considerations

### Deployment Performance

| Instance Type | CPU Cores | Deployment Time | Memory Usage |
|---------------|-----------|-----------------|--------------|
| t3.micro | 2 | ~5 minutes | ~512MB |
| t3.small | 2 | ~4 minutes | ~1GB |
| t3.medium | 2 | ~3 minutes | ~2GB |
| c5.large | 2 | ~2 minutes | ~2GB |
| c5.xlarge | 4 | ~1 minute | ~4GB |

### Runtime Performance

- Consistent performance across all bash versions
- Efficient resource usage
- Optimized for cloud deployments

### Optimization Tips

```bash
# Use spot instances for cost savings
make deploy-spot STACK_NAME=my-stack

# Enable multi-AZ for reliability
./scripts/aws-deployment-modular.sh --spot --multi-az my-stack
```

## Deployment Guide

### Pre-Deployment Checklist

1. ✅ AWS credentials configured
2. ✅ Docker installed
3. ✅ Sufficient disk space (>10GB)
4. ✅ Network connectivity
5. ✅ Required AWS quotas

### Deployment Steps

```bash
# 1. Validate environment
./scripts/validate-environment.sh

# 2. Check AWS quotas
./scripts/check-quotas.sh

# 3. Deploy with spot instances
make deploy-spot STACK_NAME=my-stack

# 4. Verify deployment
make status STACK_NAME=my-stack

# 5. Check health
make health STACK_NAME=my-stack
```

### Post-Deployment Validation

```bash
# Check all services
./scripts/health-check-advanced.sh my-stack

# View logs
make logs STACK_NAME=my-stack

# Monitor resources
./tools/open-monitoring.sh
```

## Best Practices

### Development

1. **Test locally first** - Use `make test` before deployment
2. **Use portable patterns** - Scripts work everywhere
3. **Follow standards** - See coding-standards.md
4. **Monitor performance** - Use built-in monitoring

### Deployment

1. **Use spot instances** - 70% cost savings
2. **Enable health checks** - Automatic monitoring
3. **Have backups ready** - Use backup scripts
4. **Monitor logs** - Real-time log aggregation

### Maintenance

1. **Regular validation** - Run health checks
2. **Update packages** - Keep Docker current
3. **Clean resources** - Use cleanup scripts
4. **Security scans** - Run `make security`

## Support and Resources

### Documentation

- [AWS EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [Docker Documentation](https://docs.docker.com/)
- Project documentation in `/docs` directory

### Key Scripts and Tools

- `./scripts/validate-environment.sh` - Environment validation
- `./scripts/fix-deployment-issues.sh` - Automated fixes
- `./scripts/health-check-advanced.sh` - Health monitoring
- `./tools/test-runner.sh` - Test orchestration

### Getting Help

1. **Check logs**: `make logs STACK_NAME=my-stack`
2. **Run diagnostics**: `./scripts/health-check-advanced.sh`
3. **Review documentation**: CLAUDE.md and this file
4. **Monitor AWS**: CloudWatch dashboards

For additional support, check the troubleshooting section or run the automated fix scripts.