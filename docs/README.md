# GeuseMaker Documentation

Welcome to the GeuseMaker documentation. This directory contains all essential documentation for deploying and managing the GeuseMaker AWS infrastructure.

## 📚 Documentation Structure

### Getting Started
- [Prerequisites](getting-started/prerequisites.md) - System requirements and setup
- [Quick Start](getting-started/quick-start.md) - Get up and running quickly

### Core Guides
- [Architecture Overview](guides/architecture.md) - System architecture and design
- [Deployment Guide](guides/deployment.md) - Complete deployment instructions
- [Testing Guide](guides/testing.md) - Testing procedures and best practices
- [Troubleshooting](guides/troubleshooting.md) - Common issues and solutions

### Architecture Documentation
- [Module Architecture](module-architecture.md) - Modular system design
- [Components](architecture/components.md) - System components overview
- [Module Consolidation](architecture/module-consolidation.md) - Module organization
- [Module Dependency Optimization](architecture/module-dependency-optimization.md) - Dependency management
- [Compute Consolidation Plan](architecture/compute-consolidation-plan.md) - Compute resource organization
- [Source Tree](architecture/source-tree.md) - Codebase structure

### Operations & Maintenance
- [Maintenance Suite Guide](maintenance-suite-guide.md) - Unified maintenance operations
- [Monitoring Guide](monitoring-guide.md) - System monitoring and health checks
- [Backup Procedures](backup-procedures.md) - Backup and recovery procedures
- [Security Guide](security-guide.md) - Security best practices
- [Maintenance Safety Guide](maintenance-safety-guide.md) - Safe maintenance procedures

### Configuration & Setup
- [Configuration Management](configuration-management.md) - Managing configurations
- [ALB & CloudFront Setup](alb-cloudfront-setup.md) - Load balancer and CDN setup
- [Docker Image Management](docker-image-management.md) - Container management
- [Network Validation Guide](network-validation-guide.md) - Network configuration
- [EFS Cleanup Guide](efs-cleanup-guide.md) - EFS management

### Error Handling & Recovery
- [Error Handling Guide](ERROR_HANDLING_GUIDE.md) - Comprehensive error handling
- [Recovery Procedures](RECOVERY_PROCEDURES_GUIDE.md) - System recovery steps
- [Clear Error Messages Guide](clear-error-messages-guide.md) - Error message standards
- [Rollback Mechanism Guide](rollback-mechanism-guide.md) - Deployment rollback
- [Error Recovery](troubleshooting/error-recovery.md) - Specific error recovery procedures

### Reference Documentation

#### API Reference
- [API Overview](reference/api/README.md) - Service APIs overview
- [n8n Workflows API](reference/api/n8n-workflows.md) - Workflow automation
- [Ollama LLM API](reference/api/ollama-endpoints.md) - Large Language Model API
- [Qdrant Vector DB API](reference/api/qdrant-collections.md) - Vector database
- [Crawl4AI Service API](reference/api/crawl4ai-service.md) - Web crawling service
- [Monitoring APIs](reference/api/monitoring.md) - Metrics and monitoring

#### CLI Reference
- [CLI Overview](reference/cli/README.md) - Command-line tools overview
- [Deployment Scripts](reference/cli/deployment.md) - Deployment commands
- [Management Scripts](reference/cli/management.md) - Management tools
- [Development Tools](reference/cli/development.md) - Development utilities
- [Makefile Commands](reference/cli/makefile.md) - Make targets reference

### Standards & Best Practices
- [Coding Standards](coding-standards.md) - Development standards
- [Library Loading Standard](library-loading-standard.md) - Module loading patterns
- [Architecture Overview](architecture.md) - System design principles

### Platform-Specific
- [OS Compatibility](OS-COMPATIBILITY.md) - Operating system support
- [AWS CLI v2 Enhancements](aws-cli-v2-enhancements.md) - AWS CLI features
- [Performance Enhancements](PERFORMANCE_ENHANCEMENTS.md) - Performance optimizations

### Setup & Troubleshooting
- [Setup Troubleshooting](setup/troubleshooting.md) - Setup issue resolution

## 🗂️ Archived Documentation

Historical documentation has been organized into the archive:
- `archive/docs/stories/` - Completed user stories and epics
- `archive/docs/prd/` - Product requirement documents
- `archive/docs/architecture/` - Legacy architecture documents
- `archive/docs/implementation-guides/` - Implementation summaries
- `archive/docs/legacy-guides/` - Deprecated guides

## 📖 Quick Links

### For Deployment
1. Check [Prerequisites](getting-started/prerequisites.md)
2. Follow [Quick Start](getting-started/quick-start.md)
3. Read [Deployment Guide](guides/deployment.md)
4. Review [Troubleshooting](guides/troubleshooting.md) if needed

### For Development
1. Review [Architecture](guides/architecture.md)
2. Check [Coding Standards](coding-standards.md)
3. Use [CLI Reference](reference/cli/)
4. See [API Reference](reference/api/)

### For Operations
1. Follow [Maintenance Suite Guide](maintenance-suite-guide.md)
2. Setup [Monitoring](monitoring-guide.md)
3. Review [Security Guide](security-guide.md)
4. Plan [Backup Procedures](backup-procedures.md)