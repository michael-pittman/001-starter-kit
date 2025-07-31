# 🚀 GeuseMaker Quick Start Guide

Get your AI stack deployed on AWS in under 10 minutes!

## 📋 Prerequisites

Before you begin, ensure you have:

1. **AWS Account** with appropriate permissions
2. **AWS CLI v2** installed and configured (`aws configure`)
3. **SSH Key Pair** created in your target AWS region
4. **bash** and **jq** installed (included on macOS/Linux)

## 🏃 5-Minute Deployment

### Step 1: Clone and Setup (1 minute)

```bash
# Clone the repository
git clone https://github.com/yourusername/geusemaker.git
cd geusemaker

# Run configuration setup
./scripts/setup-configuration.sh
```

Choose option 1 for local development setup. The wizard will:
- Create `.env.local` from template
- Prompt for required values (STACK_NAME and KEY_NAME)
- Validate your configuration

### Step 2: Quick Deploy (3-5 minutes)

```bash
# Deploy with spot instances (70% cost savings)
make deploy-spot

# Or using the script directly
./scripts/aws-deployment-modular.sh my-ai-stack
```

That's it! Your AI stack is deploying. ☕ Grab a coffee while it completes.

## 🎯 Deployment Scenarios

### Development Environment (Minimal Cost)

```bash
# Copy development template
cp .env.development.template .env.local

# Edit configuration
nano .env.local  # Set STACK_NAME and KEY_NAME

# Deploy minimal stack
make deploy-spot STACK_NAME=dev-stack
```

**What you get:**
- Single spot instance (g4dn.xlarge)
- All AI services (n8n, Ollama, Qdrant)
- ~$0.50/hour cost
- Auto-cleanup on failure

### Staging Environment (Production-like)

```bash
# Use staging configuration
cp .env.staging.template .env.staging

# Deploy with ALB
ENVIRONMENT=staging make deploy-alb STACK_NAME=staging-stack
```

**What you get:**
- Application Load Balancer
- Spot instances with fallback
- EFS persistent storage
- ~$2-3/hour cost

### Production Environment (Full Features)

```bash
# Use production configuration
cp .env.production.template .env.production

# Deploy enterprise stack
ENVIRONMENT=production make deploy-full STACK_NAME=prod-stack
```

**What you get:**
- Multi-AZ deployment
- ALB + CloudFront CDN
- Automated backups
- Full monitoring
- ~$5-10/hour cost

## 📊 Post-Deployment

### Access Your Services

After deployment completes, you'll see output like:
```
=== Deployment Complete ===
Stack: my-ai-stack
Services:
- n8n: http://1.2.3.4:5678
- Qdrant: http://1.2.3.4:6333
- Ollama: http://1.2.3.4:11434

SSH: ssh -i your-key.pem ubuntu@1.2.3.4
```

### Verify Deployment

```bash
# Check status
make status STACK_NAME=my-ai-stack

# View logs
make logs STACK_NAME=my-ai-stack

# Health check
make health STACK_NAME=my-ai-stack
```

## 🛠️ Common Tasks

### Update Configuration

```bash
# Edit your environment file
nano .env.local

# Validate changes
./scripts/validate-configuration.sh

# Apply updates
make update STACK_NAME=my-ai-stack
```

### Scale Resources

```bash
# Change instance type
INSTANCE_TYPE=g5.2xlarge make update STACK_NAME=my-ai-stack

# Add more storage
VOLUME_SIZE=100 make update STACK_NAME=my-ai-stack
```

### Manage Services

```bash
# Stop services (keeps infrastructure)
make stop STACK_NAME=my-ai-stack

# Start services
make start STACK_NAME=my-ai-stack

# Restart services
make restart STACK_NAME=my-ai-stack
```

## 💰 Cost Optimization

### Use Spot Instances (Default)
- 70% cost savings
- Suitable for development/testing
- Automatic fallback to on-demand

### Schedule Start/Stop
```bash
# Stop at night
make stop STACK_NAME=dev-stack

# Start in morning
make start STACK_NAME=dev-stack
```

### Right-Size Instances
```bash
# Development: g4dn.xlarge ($0.50/hr)
# Staging: g4dn.2xlarge ($1.00/hr)  
# Production: g5.2xlarge ($2.00/hr)
```

## 🚨 Troubleshooting

### Deployment Failed?

```bash
# Check detailed logs
make logs STACK_NAME=my-ai-stack

# Run diagnostics
./scripts/fix-deployment-issues.sh my-ai-stack us-east-1

# Manual cleanup if needed
make destroy STACK_NAME=my-ai-stack
```

### Common Issues

1. **"Key pair not found"**
   - Create SSH key in AWS Console → EC2 → Key Pairs
   - Update KEY_NAME in .env.local

2. **"Insufficient capacity"**
   - Try different region: `AWS_REGION=us-west-2 make deploy-spot`
   - Use on-demand: `DEPLOYMENT_TYPE=ondemand make deploy`

3. **"Access denied"**
   - Check AWS credentials: `aws sts get-caller-identity`
   - Ensure IAM permissions for EC2, VPC, EFS

## 📚 Next Steps

1. **Explore AI Services**
   - Access n8n workflows at http://your-ip:5678
   - Test Ollama models: `curl http://your-ip:11434/api/tags`
   - Use Qdrant vector DB at http://your-ip:6333

2. **Secure Your Deployment**
   ```bash
   # Enable HTTPS with ALB
   make deploy-alb STACK_NAME=my-stack
   
   # Add custom domain
   make configure-domain DOMAIN=ai.example.com
   ```

3. **Monitor and Optimize**
   ```bash
   # View metrics
   make metrics STACK_NAME=my-stack
   
   # Optimize costs
   make cost-report STACK_NAME=my-stack
   ```

## 🆘 Getting Help

- **Documentation**: See `/docs` folder
- **Issues**: Check `./scripts/fix-deployment-issues.sh`
- **Validation**: Run `./scripts/validate-configuration.sh`
- **Community**: File issues on GitHub

## 🎉 Success Checklist

- [ ] Prerequisites installed
- [ ] Configuration created (`.env.local`)
- [ ] Deployment completed
- [ ] Services accessible
- [ ] Health checks passing

Congratulations! Your AI stack is ready to use. 🚀