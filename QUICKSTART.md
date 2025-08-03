# GeuseMaker Quick Start Guide

Deploy a complete AI infrastructure on AWS in 5 minutes! This guide will get you up and running with n8n, Ollama, Qdrant, and Crawl4AI.

## 🚀 Prerequisites

Before you begin, ensure you have:

- ✅ AWS Account with EC2 permissions
- ✅ AWS CLI v2 configured (`aws configure`)
- ✅ SSH key pair in your AWS region
- ✅ bash and jq installed (pre-installed on macOS/Linux)

## 📦 Installation

### 1. Clone the Repository (30 seconds)

```bash
git clone https://github.com/yourusername/geusemaker.git
cd geusemaker
```

### 2. Run Setup Wizard (1 minute)

The interactive setup wizard will guide you through configuration:

```bash
./scripts/setup-configuration.sh
```

This will:
- Configure AWS credentials
- Set up your deployment environment
- Create necessary configuration files
- Validate prerequisites

## 🎯 Deploy Your AI Stack (3-5 minutes)

### Option 1: Cost-Optimized Deployment (Recommended)

Deploy on spot instances with 70% cost savings:

```bash
./deploy.sh spot my-ai-stack
```

### Option 2: Production Deployment

Deploy with load balancer and high availability:

```bash
./deploy.sh alb prod-stack
```

### Option 3: Full Enterprise Stack

Deploy with CloudFront CDN and all features:

```bash
./deploy.sh full enterprise-stack
```

## 🔍 What Happens During Deployment?

1. **VPC Creation**: Sets up networking infrastructure
2. **Security Groups**: Configures firewall rules
3. **EC2 Instance**: Launches optimized GPU instance
4. **Docker Setup**: Installs Docker and NVIDIA runtime
5. **AI Services**: Deploys n8n, Ollama, Qdrant, Crawl4AI
6. **Health Checks**: Validates all services are running

## 📊 Access Your Services

Once deployment completes, get your service URLs:

```bash
./unity status my-ai-stack
```

You'll see output like:
```
🌐 Service URLs:
   n8n:       http://your-instance-ip:5678
   Ollama:    http://your-instance-ip:11434
   Qdrant:    http://your-instance-ip:6333
   Crawl4AI:  http://your-instance-ip:11235
```

### Default Credentials

- **n8n**: Set during first access
- **Qdrant**: No authentication by default
- **Ollama**: No authentication required
- **Crawl4AI**: API-based access

## 🛠️ Post-Deployment Tasks

### 1. SSH into Your Instance

```bash
./unity ssh my-ai-stack
```

### 2. Check Service Health

```bash
./unity health my-ai-stack
```

### 3. View Logs

```bash
./unity logs my-ai-stack
```

### 4. Load AI Models

SSH into your instance and pull models:

```bash
# Inside the instance
docker exec -it ollama ollama pull deepseek-r1:8b
docker exec -it ollama ollama pull qwen2.5-vl:7b
```

## 💰 Cost Management

### Monitor Costs

```bash
./unity cost-report my-ai-stack
```

### Enable Auto-Shutdown

Save money by auto-stopping instances when idle:

```bash
./unity config set auto_shutdown_enabled true
./unity config set idle_timeout_minutes 30
```

## 🔧 Common Operations

### Stop Instance (Keep Data)

```bash
./unity stop my-ai-stack
```

### Restart Instance

```bash
./unity start my-ai-stack
```

### Update Services

```bash
./unity update my-ai-stack
```

### Destroy Everything

```bash
./unity destroy my-ai-stack
```

## 🚨 Troubleshooting

### Deployment Failed?

1. Check the logs:
   ```bash
   ./unity logs my-ai-stack --tail 50
   ```

2. Validate AWS credentials:
   ```bash
   aws sts get-caller-identity
   ```

3. Ensure you have required quotas:
   ```bash
   ./unity check-quotas
   ```

### Services Not Accessible?

1. Check security groups:
   ```bash
   ./unity check-security my-ai-stack
   ```

2. Verify instance is running:
   ```bash
   ./unity status my-ai-stack
   ```

### Need Help?

- 📖 Full documentation: [docs/unity/](docs/unity/)
- 💬 GitHub Issues: [Report an issue](https://github.com/yourusername/geusemaker/issues)
- 🎥 Video tutorials: [Unity Tutorials](docs/unity/tutorials/)

## 🎉 Next Steps

1. **Explore n8n**: Create your first automation workflow
2. **Test Ollama**: Run your first LLM inference
3. **Use Qdrant**: Store and search vector embeddings
4. **Try Crawl4AI**: Scrape and process web content

### Example: Your First AI Workflow

```bash
# SSH into your instance
./unity ssh my-ai-stack

# Test Ollama
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b",
    "prompt": "Hello, AI!"
  }'
```

## 📚 Learn More

- [Unity Architecture](docs/unity/unity-architecture.md)
- [Service Configuration](docs/unity/core/unity-configuration.md)
- [Plugin Development](docs/unity/plugin-development-guide.md)
- [Cost Optimization Guide](docs/unity/cost-optimization.md)

---

**Built with ❤️ by [Geuse](https://geuse.io) - Making AI infrastructure simple**