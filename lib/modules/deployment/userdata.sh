#!/usr/bin/env bash
# =============================================================================
# User Data Generation Module
# Creates cloud-init scripts for instance configuration
# =============================================================================

# Prevent multiple sourcing
[ -n "${_USERDATA_SH_LOADED:-}" ] && return 0
_USERDATA_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/variables.sh"

# =============================================================================
# USER DATA GENERATION
# =============================================================================

# Generate user data script
generate_user_data() {
    local stack_name="${1:-$(get_variable STACK_NAME)}"
    local deployment_type="${2:-$(get_variable DEPLOYMENT_TYPE)}"
    local docker_compose_url="${3:-}"
    
    # Base64 encode the script
    base64 -w 0 <<'USERDATA_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# CLOUD-INIT USER DATA SCRIPT
# =============================================================================

# Logging setup
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "=== Starting user data script at $(date) ==="

# =============================================================================
# VARIABLES
# =============================================================================

STACK_NAME="${STACK_NAME}"
DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE}"
DOCKER_COMPOSE_URL="${DOCKER_COMPOSE_URL}"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# =============================================================================
# SYSTEM PREPARATION
# =============================================================================

# Update system
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y \
    docker.io \
    docker-compose \
    awscli \
    jq \
    git \
    htop \
    nvtop \
    curl \
    wget \
    unzip

# =============================================================================
# DOCKER SETUP
# =============================================================================

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Start Docker service
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker to start..."
    sleep 2
done

# =============================================================================
# GPU SETUP (if applicable)
# =============================================================================

if nvidia-smi &>/dev/null; then
    echo "GPU detected, setting up NVIDIA Docker runtime..."
    
    # Install NVIDIA Docker runtime
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
        tee /etc/apt/sources.list.d/nvidia-docker.list
    
    apt-get update -y
    apt-get install -y nvidia-docker2
    
    # Restart Docker with GPU support
    systemctl restart docker
    
    # Verify GPU access
    docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
else
    echo "No GPU detected, skipping GPU setup"
fi

# =============================================================================
# EFS SETUP
# =============================================================================

# Install EFS utils
apt-get install -y amazon-efs-utils

# Get EFS DNS from Parameter Store
EFS_DNS=$(aws ssm get-parameter \
    --name "/aibuildkit/${STACK_NAME}/efs_dns" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

if [ -n "$EFS_DNS" ]; then
    echo "Mounting EFS: $EFS_DNS"
    
    # Create mount point
    mkdir -p /mnt/efs
    
    # Mount EFS
    mount -t efs -o tls "$EFS_DNS:/" /mnt/efs || {
        echo "Failed to mount EFS with TLS, trying without..."
        mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
            "$EFS_DNS:/" /mnt/efs
    }
    
    # Add to fstab for persistence
    echo "$EFS_DNS:/ /mnt/efs efs tls,_netdev 0 0" >> /etc/fstab
    
    # Create application directories
    mkdir -p /mnt/efs/{n8n,qdrant,postgres,ollama}
    chown -R ubuntu:ubuntu /mnt/efs
else
    echo "No EFS DNS found, skipping EFS mount"
fi

# =============================================================================
# PARAMETER STORE INTEGRATION
# =============================================================================

echo "Loading configuration from Parameter Store..."

# Create environment file
ENV_FILE="/home/ubuntu/.env"

# Load parameters from Parameter Store
aws ssm get-parameters-by-path \
    --path "/aibuildkit" \
    --recursive \
    --with-decryption \
    --query 'Parameters[*].[Name,Value]' \
    --output text | while IFS=$'\t' read -r name value; do
    # Convert parameter name to env var
    var_name="${name#/aibuildkit/}"
    var_name="${var_name//\//_}"
    var_name=$(echo "$var_name" | tr '[:lower:]' '[:upper:]')
    
    # Write to env file
    echo "${var_name}=${value}" >> "$ENV_FILE"
done

# Set permissions
chown ubuntu:ubuntu "$ENV_FILE"
chmod 600 "$ENV_FILE"

# =============================================================================
# DOCKER COMPOSE SETUP
# =============================================================================

# Create project directory
PROJECT_DIR="/home/ubuntu/ai-starter-kit"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Download Docker Compose file
if [ -n "$DOCKER_COMPOSE_URL" ]; then
    echo "Downloading Docker Compose file from: $DOCKER_COMPOSE_URL"
    curl -fsSL "$DOCKER_COMPOSE_URL" -o docker-compose.yml
else
    echo "Creating default Docker Compose file..."
    cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-changeme}
    volumes:
      - /mnt/efs/postgres:/var/lib/postgresql/data
    restart: unless-stopped

  n8n:
    image: n8nio/n8n:latest
    environment:
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD:-changeme}
    volumes:
      - /mnt/efs/n8n:/home/node/.n8n
    ports:
      - "5678:5678"
    depends_on:
      - postgres
    restart: unless-stopped

  qdrant:
    image: qdrant/qdrant:latest
    volumes:
      - /mnt/efs/qdrant:/qdrant/storage
    ports:
      - "6333:6333"
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    volumes:
      - /mnt/efs/ollama:/root/.ollama
    ports:
      - "11434:11434"
    restart: unless-stopped
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
fi

# Set permissions
chown -R ubuntu:ubuntu "$PROJECT_DIR"

# =============================================================================
# START SERVICES
# =============================================================================

echo "Starting services..."

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Pull images
docker-compose pull

# Start services
docker-compose up -d

# Wait for services to be healthy
echo "Waiting for services to start..."
sleep 30

# Check service status
docker-compose ps

# =============================================================================
# HEALTH CHECK ENDPOINT
# =============================================================================

# Create simple health check server
cat > /home/ubuntu/health-check.py <<'EOF'
#!/usr/bin/env python3
import http.server
import json
import subprocess
import socketserver

class HealthCheckHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            try:
                # Check Docker services
                result = subprocess.run(
                    ['docker-compose', 'ps', '--format', 'json'],
                    capture_output=True,
                    text=True,
                    cwd='/home/ubuntu/ai-starter-kit'
                )
                
                services = []
                if result.returncode == 0:
                    for line in result.stdout.strip().split('\n'):
                        if line:
                            services.append(json.loads(line))
                
                health = {
                    'status': 'healthy' if all(s.get('State') == 'running' for s in services) else 'unhealthy',
                    'services': services
                }
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(health, indent=2).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("", 8080), HealthCheckHandler) as httpd:
    print("Health check server running on port 8080")
    httpd.serve_forever()
EOF

chmod +x /home/ubuntu/health-check.py

# Create systemd service for health check
cat > /etc/systemd/system/health-check.service <<EOF
[Unit]
Description=Health Check Service
After=docker.service

[Service]
Type=simple
User=ubuntu
ExecStart=/usr/bin/python3 /home/ubuntu/health-check.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable health-check
systemctl start health-check

# =============================================================================
# CLOUDWATCH MONITORING
# =============================================================================

# Configure CloudWatch agent if available
if command -v amazon-cloudwatch-agent-ctl &> /dev/null; then
    echo "Configuring CloudWatch monitoring..."
    
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
    "metrics": {
        "namespace": "AIStarterKit/${STACK_NAME}",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_active"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "nvidia_gpu": {
                "measurement": [
                    "utilization_gpu",
                    "utilization_memory"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/${STACK_NAME}",
                        "log_stream_name": "{instance_id}/user-data"
                    }
                ]
            }
        }
    }
}
EOF
    
    # Start CloudWatch agent
    amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
        -s
fi

# =============================================================================
# COMPLETION
# =============================================================================

echo "=== User data script completed at $(date) ==="

# Create completion marker
touch /var/lib/cloud/instance/user-data-finished
USERDATA_SCRIPT
}

# Generate user data with specific configuration
generate_custom_user_data() {
    local template_file="$1"
    local variables="$2"
    
    # Read template
    local template
    template=$(<"$template_file") || {
        echo "ERROR: Failed to read template file: $template_file" >&2
        return 1
    }
    
    # Replace variables
    echo "$variables" | jq -r 'to_entries[] | "\\${" + .key + "}=" + (.value | tostring)' | \
    while IFS='=' read -r search replace; do
        template="${template//$search/$replace}"
    done
    
    # Base64 encode
    echo "$template" | base64 -w 0
}

# =============================================================================
# USER DATA VALIDATION
# =============================================================================

# Validate user data script
validate_user_data() {
    local user_data_base64="$1"
    
    # Decode and check syntax
    local user_data
    user_data=$(echo "$user_data_base64" | base64 -d) || {
        echo "ERROR: Invalid base64 encoding" >&2
        return 1
    }
    
    # Basic validation
    if [ -z "$user_data" ]; then
        echo "ERROR: Empty user data" >&2
        return 1
    fi
    
    # Check shebang
    if ! head -n1 <<< "$user_data" | grep -q '^#!/bin/bash'; then
        echo "WARNING: User data doesn't start with #!/bin/bash" >&2
    fi
    
    # Check for common issues
    if grep -q 'set -e' <<< "$user_data" && ! grep -q 'set -euo pipefail' <<< "$user_data"; then
        echo "WARNING: Consider using 'set -euo pipefail' for better error handling" >&2
    fi
    
    echo "User data validation passed" >&2
    return 0
}