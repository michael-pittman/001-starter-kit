# GeuseMaker

> Enterprise-ready AI infrastructure platform with modular deployment, intelligent cost optimization, and comprehensive monitoring.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Supported-blue.svg)](https://www.docker.com/)
[![AWS](https://img.shields.io/badge/AWS-Optimized-orange.svg)](https://aws.amazon.com/)
[![Bash](https://img.shields.io/badge/Bash-3.x%2F4.x-green.svg)](https://www.gnu.org/software/bash/)

## 🚀 Quick Start

Deploy your AI infrastructure in under 5 minutes:

```bash
# Clone and setup
git clone <repository-url> && cd GeuseMaker
make setup

# Deploy development environment
make deploy-simple STACK_NAME=my-dev-stack

# Access your AI services
# n8n: http://your-ip:5678 (workflow automation)
# Ollama: http://your-ip:11434 (LLM API with DeepSeek-R1, Qwen2.5-VL)
# Qdrant: http://your-ip:6333 (vector database)
# Crawl4AI: http://your-ip:11235 (web scraping)
```

## 🌟 Key Features

### 💰 **70% Cost Savings**
- Intelligent spot instance management with cross-region failover
- Automatic price optimization and capacity analysis
- Smart instance type selection with GPU optimization

### 🔧 **Modular Architecture**
- 23 specialized modules for maintainable, scalable deployments
- bash 3.x/4.x compatibility (macOS + Linux)
- Comprehensive error handling with recovery strategies

### 🤖 **Complete AI Stack**
- **n8n**: Workflow automation and AI orchestration
- **Ollama**: Local LLM inference (DeepSeek-R1:8B, Qwen2.5-VL:7B)
- **Qdrant**: High-performance vector database
- **Crawl4AI**: Intelligent web scraping with LLM extraction
- **PostgreSQL**: Reliable data persistence

### 🏗️ **Enterprise Ready**
- Multi-AZ deployment with high availability
- Application Load Balancer with health checks
- CloudFront CDN for global distribution
- EFS persistent storage with encryption
- Comprehensive monitoring and alerting

## 📚 Documentation

### 🎯 **Getting Started**
- [**Deployment Guide**](docs/guides/deployment.md) - Complete deployment walkthrough
- [**Architecture Guide**](docs/guides/architecture.md) - System design and patterns
- [**Security Guide**](docs/security-guide.md) - Security implementation

### 🔧 **Operations**
- [**Testing Guide**](docs/guides/testing.md) - Comprehensive testing framework
- [**Troubleshooting Guide**](docs/guides/troubleshooting.md) - Common issues and solutions
- [**CLI Reference**](docs/reference/cli/) - Command-line tools

## 🛠️ Available Commands

### Core Deployment Commands

| Command | Description | Use Case |
|---------|-------------|----------|
| `make deploy-simple STACK_NAME=dev` | Development deployment | Quick testing |
| `make deploy-spot STACK_NAME=prod` | Production with spot instances | Cost-optimized production |
| `./scripts/aws-deployment-modular.sh --multi-az --alb prod` | Enterprise deployment | High-availability production |

### Advanced Deployment Options

```bash
# Cost-optimized deployment with intelligent fallback
./scripts/aws-deployment-modular.sh --spot --multi-az stack-name

# Enterprise deployment with all features
./scripts/aws-deployment-modular.sh \
  --multi-az \
  --private-subnets \
  --nat-gateway \
  --alb \
  --spot \
  production-stack

# Simple development deployment
./scripts/aws-deployment-v2-simple.sh dev-stack
```

### Management Commands

| Command | Description |
|---------|-------------|
| `make setup` | Initial setup with security validation |
| `make test` | Run comprehensive test suite |
| `make lint` | Code quality checks |
| `make health-check STACK_NAME=stack` | Service health validation |
| `make destroy STACK_NAME=stack` | Clean resource removal |

### Testing Commands (No AWS Costs)

```bash
# Test deployment logic locally
./scripts/simple-demo.sh

# Validate modular system
./tests/final-validation.sh

# Run specific test categories
./tools/test-runner.sh unit
./tools/test-runner.sh --report
```

## 🏗️ Architecture Overview

### Modular System Structure

```
GeuseMaker/
├── lib/modules/           # 23 specialized modules
│   ├── core/             # Variable management, resource registry
│   ├── infrastructure/   # VPC, security, IAM, EFS, ALB
│   ├── compute/          # EC2 provisioning, spot optimization
│   ├── application/      # Docker, AI services, monitoring
│   └── errors/           # Structured error handling
├── scripts/              # Deployment orchestrators
│   ├── aws-deployment-v2-simple.sh      # Bash 3.x compatible
│   └── aws-deployment-modular.sh        # Enterprise features
├── tests/                # Comprehensive test suite
└── docs/                 # Complete documentation
```

### Service Architecture

```yaml
Infrastructure:
  AWS: EC2 (g4dn.xlarge) + EFS + ALB + CloudFront
  
Container Services:
  n8n:      5678  | Workflow automation
  ollama:   11434 | LLM inference (GPU optimized)
  qdrant:   6333  | Vector database
  crawl4ai: 11235 | Web scraping
  postgres: 5432  | Data persistence

Resource Allocation (g4dn.xlarge):
  CPU: 4 vCPUs (85% target utilization)
  Memory: 16GB (Ollama: 6GB, others: 2GB each)
  GPU: T4 16GB (Ollama: 13.6GB, system: 2.4GB)
```

## 💡 Use Cases

### 🔬 **AI Research & Development**
- Rapid prototyping with n8n workflows
- Local LLM experimentation with Ollama
- Vector similarity search with Qdrant
- Data collection with Crawl4AI

### 🏢 **Enterprise AI Applications**
- Multi-AZ deployment for production reliability
- Cost optimization with spot instances
- Scalable AI API endpoints
- Comprehensive monitoring and alerting

### 📊 **Data Processing Pipelines**
- Automated web scraping and content extraction
- LLM-powered data analysis and transformation
- Vector embeddings for similarity search
- Workflow automation with n8n

## 🔧 System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **AWS Account** | Basic permissions | Admin access for full features |
| **Local Machine** | 4GB RAM, bash 3.x+ | 8GB RAM, latest bash |
| **Network** | Internet access | Stable broadband |

**Supported Platforms:** macOS (bash 3.x), Linux (bash 4.x+), Windows WSL

## 🚦 Getting Started

### 1. Prerequisites Setup

```bash
# Install AWS CLI
aws configure

# Verify prerequisites
make check-deps
```

### 2. Security Configuration

```bash
# Setup required secrets
make setup-secrets

# Validate security
make security-check
```

### 3. Deploy Your First Stack

```bash
# Development deployment
make deploy-simple STACK_NAME=my-first-stack

# Check deployment status
make health-check STACK_NAME=my-first-stack
```

### 4. Access Your Services

After deployment, access your AI services at:
- **n8n**: `http://YOUR_IP:5678` - Create AI workflows
- **Ollama**: `http://YOUR_IP:11434` - LLM API endpoints
- **Qdrant**: `http://YOUR_IP:6333` - Vector database
- **Crawl4AI**: `http://YOUR_IP:11235` - Web scraping API

## 📈 Cost Optimization

### Spot Instance Benefits

| Deployment Type | Hourly Cost | Monthly Cost | Savings |
|----------------|-------------|--------------|---------|
| On-Demand | $0.52 | $380 | Baseline |
| Spot (Single AZ) | $0.15 | $110 | 71% |
| Spot (Multi-AZ) | $0.25 | $180 | 53% |

### Intelligent Cost Features

- **Cross-region spot analysis** - Finds optimal pricing
- **Instance type fallbacks** - Automatic alternatives when capacity unavailable
- **EFS lifecycle policies** - Auto-archive after 30 days
- **Resource cleanup** - Automatic cleanup on deployment failure

## 🔒 Security Features

- **Least privilege IAM** - Minimal required permissions
- **Encrypted storage** - EFS encryption at rest
- **Secrets management** - AWS Parameter Store integration
- **Network security** - Private subnets, security groups
- **Input sanitization** - Prevents injection attacks

## 🧪 Testing & Validation

### Comprehensive Test Suite

```bash
# Run all tests (no AWS charges)
make test

# Test categories:
# - unit: Individual module testing
# - integration: Component interactions
# - security: Security validation
# - performance: Benchmarking
# - deployment: Script validation
```

### Local Development

```bash
# Test deployment logic without AWS
./scripts/simple-demo.sh

# Validate specific modules
bash -n lib/modules/core/variables.sh
```

## 🆘 Support & Troubleshooting

### Quick Fixes

| Issue | Solution |
|-------|----------|
| Disk space full | `./scripts/fix-deployment-issues.sh STACK REGION` |
| Services not starting | `docker compose down && docker compose up -d` |
| Spot capacity issues | Use `ec2-provisioning-specialist` Claude agent |
| Variable export errors | Use modular deployment scripts |

### Comprehensive Support

- [**Troubleshooting Guide**](docs/guides/troubleshooting.md) - Detailed solutions
- [**Architecture Guide**](docs/guides/architecture.md) - System understanding
- [**Testing Guide**](docs/guides/testing.md) - Validation procedures

## 🤝 Contributing

1. **Follow modular patterns** - Use existing module structure
2. **Test thoroughly** - Run `make test` before commits
3. **Document changes** - Update CLAUDE.md for AI assistance
4. **Security first** - Run `make security-check`

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**GeuseMaker** - Transforming AI infrastructure deployment with intelligence, modularity, and cost optimization. 🚀