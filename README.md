# AI Starter Kit

A comprehensive starter kit for building AI applications with n8n, Ollama, and Qdrant.

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured with your credentials
- Docker and Docker Compose installed locally (for development)
- Ubuntu 22.04 LTS (for production deployment)

## Supported Hardware

This starter kit supports various hardware configurations:

- CPU-only instances
- NVIDIA GPU instances (automatically detected and configured)
- AMD GPU instances (automatically detected and configured)

## Quick Start

1. Clone the repository:
```bash
git clone https://github.com/michael-pittman/001-starter-kit.git
cd 001-starter-kit
```

2. Copy the example environment file:
```bash
cp .env.example .env
```

3. Update the `.env` file with your configuration values.

4. Start the services:
```bash
docker-compose up -d
```

## Production Deployment

The starter kit includes a cloud-init script for automated deployment on AWS EC2 instances. The script:

- Automatically detects and configures GPU support (NVIDIA or AMD)
- Sets up EFS storage for persistent data
- Configures all necessary services
- Handles spot instance termination gracefully

### Supported AMIs

- Ubuntu 22.04 LTS (recommended)
- Amazon Linux 2023 (legacy support)

### GPU Support

The starter kit automatically detects and configures GPU support:

- **NVIDIA GPUs**: Installs NVIDIA drivers and container toolkit
- **AMD GPUs**: Installs ROCm drivers and configures necessary device files
- **CPU-only**: Automatically falls back to CPU mode

### Storage

The starter kit uses Amazon EFS for persistent storage. The following directories are mounted:

- `/mnt/efs/n8n`: n8n data and workflows
- `/mnt/efs/postgres`: PostgreSQL database files
- `/mnt/efs/ollama`: Ollama model storage
- `/mnt/efs/qdrant`: Qdrant vector database storage

## Services

### n8n
- Web interface: https://your-ip:5678
- Default credentials: admin/admin (change on first login)

### Ollama
- API endpoint: http://localhost:11434
- Default model: llama2 (automatically pulled on first run)

### Qdrant
- API endpoint: http://localhost:6333
- Web interface: http://localhost:6333/dashboard

### PostgreSQL
- Host: postgres
- Port: 5432
- Database: n8n_db
- User: n8n_user
- Password: (from environment variables)

## Development

### Local Development

1. Install dependencies:
```bash
# Ubuntu 22.04
sudo apt-get update
sudo apt-get install -y docker.io docker-compose git
```

2. Start the services:
```bash
docker-compose up -d
```

### GPU Development

For GPU development, ensure you have the appropriate drivers installed:

- **NVIDIA**: Install NVIDIA drivers and nvidia-container-toolkit
- **AMD**: Install ROCm drivers

The cloud-init script will handle this automatically in production.

## Security

- All sensitive data is stored in AWS SSM Parameter Store
- Environment variables are automatically fetched during deployment
- Services run with appropriate user permissions
- EFS mounts use IAM authentication

## Monitoring

- n8n provides built-in monitoring at https://your-ip:5678
- Qdrant dashboard available at http://localhost:6333/dashboard
- CloudWatch logs available for all services

## Troubleshooting

### Common Issues

1. **GPU Not Detected**
   - Check if the instance type supports GPU
   - Verify GPU drivers are installed
   - Check system logs for driver errors

2. **EFS Mount Issues**
   - Verify EFS ID is correctly set in SSM
   - Check security group allows EFS access
   - Verify IAM role has EFS permissions

3. **Service Startup Issues**
   - Check Docker logs: `docker-compose logs`
   - Verify environment variables are set
   - Check service dependencies

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
