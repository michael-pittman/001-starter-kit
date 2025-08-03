# Quick Start Guide

> Get your GeuseMaker AI stack running on AWS in 5 minutes

## Overview

This guide will help you deploy a complete AI infrastructure (n8n + Ollama + Qdrant + Crawl4AI) on AWS using the Unity deployment system.

## Before You Start

✅ **Prerequisites completed?** → [Prerequisites Guide](prerequisites.md)

Required:
- AWS CLI v2 configured
- SSH key pair in AWS
- bash, jq, curl, git installed

## Step 1: Clone and Setup (1 minute)

```bash
# Clone the repository
git clone https://github.com/yourusername/geusemaker.git
cd geusemaker

# Run initial setup
./scripts/complete-unity-setup.sh
```

The setup script will:
- Initialize Unity services
- Validate AWS configuration
- Check system requirements
- Create initial configuration

## Step 2: Choose Your Deployment (1 minute)

### Development (Cheapest - ~$0.50/hour)
Perfect for learning and testing:

```bash
./deploy.sh spot dev-stack
```

### Staging (Production-like - ~$2-3/hour)
For testing with load balancer:

```bash
./deploy.sh alb staging-stack
```

### Production (Full features - ~$5-10/hour)
Complete setup with CDN:

```bash
./deploy.sh full prod-stack
```

## Step 3: Deploy (3-5 minutes)

For your first deployment, we recommend starting with development:

```bash
# Deploy development stack with spot instances
./deploy.sh spot my-first-stack

# Monitor deployment progress
./scripts/unity-cli.sh monitor my-first-stack
```

You'll see real-time progress:
```
[INFO] Unity deployment started: my-first-stack
[INFO] Creating VPC and networking...
[INFO] Launching EC2 instance...
[INFO] Installing Docker and AI services...
[INFO] Deployment completed successfully!
```

## Step 4: Access Your Services (1 minute)

Once deployment completes, get your service URLs:

```bash
# Get all service information
./unity info my-first-stack

# Or use Unity CLI
./scripts/unity-cli.sh info my-first-stack
```

You'll get output like:
```
🌟 GeuseMaker AI Stack: my-first-stack
📍 Region: us-east-1
💻 Instance: i-1234567890abcdef0 (g4dn.xlarge)
🌐 Public IP: 54.123.45.67

🔗 Service URLs:
├── n8n (Workflows):     http://54.123.45.67:5678
├── Ollama (LLM):        http://54.123.45.67:11434
├── Qdrant (Vectors):    http://54.123.45.67:6333
└── Crawl4AI:            http://54.123.45.67:11235

🔐 Access Information:
├── SSH: ssh -i ~/.ssh/geusemaker-key.pem ubuntu@54.123.45.67
└── n8n Login: admin / [check Parameter Store]
```

## Step 5: Test Your AI Stack (2 minutes)

### Test LLM (Ollama)
```bash
# Test Ollama API
curl -X POST http://YOUR-IP:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b", 
    "prompt": "What is artificial intelligence?",
    "stream": false
  }'
```

### Test Vector Database (Qdrant)
```bash
# Check Qdrant health
curl http://YOUR-IP:6333/health
```

### Test Workflow Engine (n8n)
1. Open http://YOUR-IP:5678 in browser
2. Login with admin credentials
3. Create your first workflow

### Test Web Scraper (Crawl4AI)
```bash
# Test Crawl4AI
curl -X POST http://YOUR-IP:11235/crawl \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```

## Next Steps

### Explore Advanced Features

1. **Add GPU Models**:
   ```bash
   # SSH into instance
   ./unity ssh my-first-stack
   
   # Pull additional models
   docker exec ollama ollama pull qwen2.5-vl:7b
   ```

2. **Configure Workflows**:
   - Access n8n at http://YOUR-IP:5678
   - Import example workflows from `n8n/demo-data/`
   - Connect to Ollama and Qdrant

3. **Scale Your Deployment**:
   ```bash
   # Upgrade to ALB deployment
   ./deploy.sh alb my-first-stack
   
   # Add CloudFront CDN
   ./deploy.sh full my-first-stack
   ```

### Learn More

- **[Unity Documentation](../unity/)** - Deep dive into the deployment system
- **[Architecture Guide](../guides/architecture.md)** - Understand the system design
- **[API Reference](../reference/api/)** - Integrate with the services
- **[Troubleshooting](../guides/troubleshooting.md)** - Solve common issues

## Common Quick Start Issues

### Issue: Deployment Fails
```bash
# Check Unity logs
cat logs/unity/core.log

# Debug deployment
export DEBUG=1
./deploy.sh spot my-first-stack
```

### Issue: Can't Access Services
```bash
# Check security groups
aws ec2 describe-security-groups

# Verify instance status
./scripts/unity-cli.sh status my-first-stack
```

### Issue: Out of Quota
```bash
# Check EC2 quotas
aws service-quotas list-service-quotas --service-code ec2 | grep -i running

# Request quota increase
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --desired-value 10
```

## Cleanup

When you're done experimenting:

```bash
# Destroy the stack (saves costs)
./deploy.sh destroy my-first-stack

# Verify cleanup
./scripts/unity-cli.sh status my-first-stack
```

## Configuration Examples

### Custom Instance Type
```bash
# Use larger instance
./deploy.sh spot my-stack --instance-type g4dn.2xlarge
```

### Custom Region
```bash
# Deploy in different region
export AWS_DEFAULT_REGION=us-west-2
./deploy.sh spot my-stack
```

### Use Existing VPC
```bash
# Deploy in existing VPC
./deploy.sh spot my-stack --vpc-id vpc-12345678
```

## Success Indicators

✅ **Deployment Successful** if you see:
- Unity deployment completed message
- All service URLs accessible
- Health checks passing
- AI models responding to API calls

✅ **Services Ready** when:
- n8n web interface loads
- Ollama returns model list
- Qdrant health check passes
- Crawl4AI accepts requests

## Getting Help

### Self-Service Resources
1. **Logs**: Check `logs/unity/` for detailed logs
2. **Status**: Run `./scripts/unity-cli.sh status my-stack`
3. **Health**: Run `./scripts/unity-cli.sh service health`

### Community Support
1. **Documentation**: This docs directory
2. **Examples**: Check `examples/` directory
3. **GitHub Issues**: Report bugs and get help

### Quick Debug Commands
```bash
# Unity system status
./scripts/unity-cli.sh service health

# AWS resource status
aws ec2 describe-instances --filters "Name=tag:Name,Values=*my-first-stack*"

# Container status (SSH into instance)
docker ps
docker logs n8n
docker logs ollama
```

## What's Next?

Now that your AI stack is running:

1. **Build Workflows**: Create n8n workflows that use Ollama for AI
2. **Store Vectors**: Use Qdrant for semantic search and RAG
3. **Scrape Content**: Use Crawl4AI to gather web data
4. **Scale Up**: Upgrade to production deployment when ready

**Ready for production?** → [Deployment Guide](../guides/deployment.md)

**Want to understand the system?** → [Architecture Guide](../guides/architecture.md)

---

🎉 **Congratulations!** You now have a complete AI infrastructure running on AWS.