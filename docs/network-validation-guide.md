# Network Connectivity Validation Guide

## Overview

The GeuseMaker deployment system includes network connectivity validation to ensure reliable deployments. However, the validation is now more flexible to support development environments with limited or intermittent network connectivity.

## Validation Behavior

### Production Mode (Default)
- Network connectivity is **required** for production deployments
- Checks connectivity to:
  - `aws.amazon.com:443` - AWS services
  - `registry.docker.io:443` - Docker Hub
  - `github.com:443` - GitHub repositories
- Failures will block deployment
- Includes automatic retry logic (3 attempts with 2-second delays)

### Development Mode
- Network connectivity checks provide **warnings only**
- Deployment can proceed even with network issues
- Helpful troubleshooting tips are displayed
- Ideal for:
  - Local development
  - Air-gapped environments
  - Corporate networks with restrictions
  - Intermittent connectivity scenarios

## Configuration Options

### 1. Enable Development Mode

Set any of these environment variables:
```bash
export ENVIRONMENT=development
export ENVIRONMENT=dev
export DEPLOYMENT_MODE=development
export DEVELOPMENT_MODE=true
```

### 2. Skip Network Checks Entirely

```bash
export SKIP_NETWORK_CHECK=true
# or
export SKIP_NETWORK_VALIDATION=true
```

### 3. Per-Command Development Mode

```bash
ENVIRONMENT=development ./scripts/aws-deployment-modular.sh my-stack
```

## Network Requirements by Environment

### Development Environment
- **Minimum**: None (can work offline with local resources)
- **Recommended**: Internet access for pulling Docker images
- **Resource requirements**: Relaxed (512MB RAM, 5GB disk)

### Production Environment
- **Required**: Stable internet connection
- **Ports**: 443 (HTTPS) for AWS, Docker Hub, and GitHub
- **Resource requirements**: Standard (2GB RAM, 20GB disk)

## Troubleshooting Network Issues

When network connectivity issues are detected, the system provides helpful troubleshooting tips:

1. **Check Internet Connection**
   ```bash
   ping -c 1 google.com
   curl -I https://www.google.com
   ```

2. **Check DNS Resolution**
   ```bash
   nslookup aws.amazon.com
   dig github.com
   ```

3. **Check Proxy Settings**
   ```bash
   echo $HTTP_PROXY
   echo $HTTPS_PROXY
   ```

4. **Common Fixes**
   - Restart network service: `sudo systemctl restart network`
   - Reset DNS: `sudo systemctl restart systemd-resolved`
   - Check `/etc/resolv.conf` for valid nameservers

## Testing Network Validation

Run the test script to see how network validation behaves in different modes:

```bash
./scripts/test-network-validation.sh
```

## Best Practices

1. **Development**: Use development mode for local testing and development
2. **CI/CD**: Keep production mode for automated deployments
3. **Air-gapped**: Use `SKIP_NETWORK_CHECK=true` with local registries
4. **Corporate**: Configure proxy settings before running validation

## Integration with Deployment Scripts

All deployment scripts automatically use the network validation:

```bash
# Simple deployment (uses validation)
./scripts/aws-deployment-v2-simple.sh my-stack

# Modular deployment (uses validation)
./scripts/aws-deployment-modular.sh my-stack

# Development mode deployment
ENVIRONMENT=development ./scripts/aws-deployment-modular.sh my-dev-stack
```

## Summary

The enhanced network connectivity validation provides:
- ✅ Automatic retry logic for temporary issues
- ✅ Development mode with warnings instead of failures
- ✅ Skip options for air-gapped environments
- ✅ Helpful troubleshooting tips
- ✅ Production safety with strict validation