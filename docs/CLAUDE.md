# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **AI Starter Kit** designed for deploying GPU-optimized AI infrastructure on AWS. The project combines multiple AI services (n8n, Ollama, Qdrant, Crawl4AI) with intelligent deployment automation, cost optimization, and enterprise-grade monitoring.

## Architecture

### Core Services
- **n8n**: Visual workflow automation platform for AI agent orchestration
- **Ollama**: Local LLM inference server optimized for NVIDIA T4/T4G GPUs
- **Qdrant**: High-performance vector database for embeddings
- **Crawl4AI**: Intelligent web scraping with LLM-based extraction
- **PostgreSQL**: Primary database for n8n workflows and metadata

### Deployment Infrastructure
- **GPU Instances**: Optimized for g4dn.xlarge, g4dn.2xlarge (Intel + T4), g5g.xlarge, g5g.2xlarge (ARM64 + T4G)
- **EFS Integration**: Persistent storage that survives spot interruptions
- **Spot Instance Management**: 70% cost savings with automatic failover
- **Multi-Region Support**: Cross-region analysis for optimal pricing and availability

## Key Commands

### Deployment Commands
```bash
# Basic intelligent deployment (recommended)
./scripts/aws-deployment.sh

# Cross-region optimization for best pricing
./scripts/aws-deployment.sh --cross-region

# Custom configuration
./scripts/aws-deployment.sh --instance-type g4dn.xlarge --region us-west-2 --max-spot-price 1.50

# Simple on-demand deployment (higher cost, higher reliability)
./scripts/aws-deployment-simple.sh

# Full on-demand deployment
./scripts/aws-deployment-ondemand.sh
```

### Testing and Validation
```bash
# Test intelligent selection without deploying
./scripts/test-intelligent-selection.sh --comprehensive

# Quick demo of intelligent selection
./scripts/simple-demo.sh

# Check AWS quotas
./scripts/check-quotas.sh
```

### Post-Deployment Validation
```bash
# Comprehensive deployment validation (all services, health checks, diagnostics)
./scripts/aws-deployment.sh validate <IP_ADDRESS>

# Performance benchmarking (GPU, containers, network, system)
./scripts/aws-deployment.sh benchmark <IP_ADDRESS>           # All benchmarks
./scripts/aws-deployment.sh benchmark <IP_ADDRESS> gpu       # GPU only
./scripts/aws-deployment.sh benchmark <IP_ADDRESS> container # Container performance

# Security audit and compliance validation
./scripts/aws-deployment.sh security-audit <IP_ADDRESS>         # Complete audit
./scripts/aws-deployment.sh security-audit <IP_ADDRESS> network # Network security
./scripts/aws-deployment.sh security-audit <IP_ADDRESS> system  # System security

# Run individual validation scripts directly
./scripts/deployment-validator.sh <IP_ADDRESS>
./scripts/performance-benchmark.sh <IP_ADDRESS>
./scripts/security-audit.sh <IP_ADDRESS>
```

### Local Development
```bash
# Start services locally (CPU-only)
docker compose --profile cpu up

# GPU-optimized services (requires NVIDIA GPU)
docker compose -f docker-compose.gpu-optimized.yml up
```

### Monitoring and Status
```bash
# Check deployment status
./scripts/aws-deployment.sh check-status <IP_ADDRESS>

# Monitor costs
python3 scripts/cost-optimization.py --action report
```

## Configuration Files

### Docker Compose Architecture
- `docker-compose.gpu-optimized.yml`: Production GPU-optimized configuration
  - Resource limits tuned for g4dn.xlarge (4 vCPUs, 16GB RAM, 16GB T4 VRAM)
  - EFS integration for persistence across spot interruptions
  - GPU monitoring and health checks
  - Optimized model loading for DeepSeek-R1:8B, Qwen2.5-VL:7B

### AWS Deployment Scripts
- `scripts/aws-deployment.sh`: Main intelligent deployment with multi-architecture support
- `scripts/aws-deployment-simple.sh`: Simplified deployment for basic use cases
- `scripts/aws-deployment-ondemand.sh`: Guaranteed on-demand instances

### Model Configuration
- `ollama/models/`: Custom Modelfiles for optimized inference
  - `DeepSeek-R1-8B.Modelfile`: Reasoning and problem-solving model
  - `Qwen2.5-VL-7B.Modelfile`: Vision-language understanding
  - `Snowflake-Arctic-Embed2-568M.Modelfile`: Embedding generation

## Development Patterns

### Resource Allocation Strategy
The system automatically optimizes resource allocation based on instance type:
- **CPU**: Primary allocation to Ollama (62.5%), secondary to Postgres/Qdrant/n8n
- **Memory**: Ollama gets 62.5% for model loading, others share remaining
- **GPU**: 90% allocated to Ollama, 10% system reserve

### Cost Optimization Features
- **Intelligent Instance Selection**: Automatically chooses optimal price/performance ratio
- **Multi-AZ Spot Deployment**: Distributes across availability zones for better availability
- **Cross-Region Analysis**: Compares pricing across 6 AWS regions
- **Budget Enforcement**: Respects max spot price constraints
- **ARM64 Support**: Graviton2 instances for better price/performance on compatible workloads

### Configuration Management
All sensitive configuration is managed via AWS Systems Manager Parameter Store:
```bash
# Required parameters
/aibuildkit/OPENAI_API_KEY
/aibuildkit/n8n/ENCRYPTION_KEY
/aibuildkit/POSTGRES_PASSWORD
/aibuildkit/WEBHOOK_URL
```

## Important Implementation Notes

### Multi-Architecture Support
The project supports both Intel x86_64 and ARM64 architectures:
- **Intel (g4dn)**: Traditional x86_64 with NVIDIA T4 GPUs
- **ARM64 (g5g)**: Graviton2 processors with NVIDIA T4G GPUs
- Deployment scripts automatically detect and configure appropriate AMIs

### AWS Deep Learning AMI Integration
Uses AWS Deep Learning AMIs with pre-configured:
- NVIDIA drivers and CUDA toolkit
- Docker GPU runtime (nvidia-docker2)
- Optimized GPU libraries and frameworks

### Spot Instance Management
Implements sophisticated spot instance handling:
- 2-minute termination warning processing
- Graceful service shutdown and data backup to EFS
- Automatic replacement through Auto Scaling Groups
- Multi-AZ distribution for availability

### Security Considerations
- All API keys stored in AWS SSM Parameter Store
- Security groups with minimal required permissions
- EFS encryption at rest and in transit
- Regular security group and IAM policy audits

## Cursor Rules Integration

The repository includes comprehensive AWS-focused Cursor rules at `.cursor/rules/aws.mdc` providing:
- AWS Well-Architected Framework guidance
- Service selection decision frameworks
- Infrastructure as Code best practices
- Security and cost optimization patterns
- Scale-adaptive recommendations (startup/midsize/enterprise)

## Troubleshooting

### Common Issues
- **InvalidAMIID.Malformed**: Use `--cross-region` flag for better AMI availability
- **Spot instance failures**: Check spot price limits and try different AZs
- **GPU not detected**: Verify NVIDIA drivers and Docker GPU runtime in user-data logs
- **High costs**: Review auto-scaling policies and enable cost monitoring

### Debug Commands
```bash
# Check service status
docker compose -f docker-compose.gpu-optimized.yml ps

# View logs
docker compose -f docker-compose.gpu-optimized.yml logs [service_name]

# GPU monitoring
nvidia-smi

# SSH into instance for debugging
ssh -i ai-starter-kit-key.pem ubuntu@<instance-ip>
```

### Instance Access
- Default username: `ubuntu`
- SSH key: Generated automatically during deployment
- Services accessible via: `http://<instance-ip>:5678` (n8n), `:11434` (Ollama), `:6333` (Qdrant)

## Testing Strategy

The project includes comprehensive testing without requiring AWS resources:
- `scripts/test-intelligent-selection.sh`: Validates configuration selection logic
- `scripts/simple-demo.sh`: Demonstrates intelligent selection capabilities
- Mock AWS API responses for testing deployment scenarios
- Configuration validation for all supported regions and instance types