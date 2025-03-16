#!/bin/bash
set -e

# 1. Install updates and required packages using yum
yum update -y
yum install -y docker amazon-efs-utils jq git awscli

# Install docker-compose plugin (if not already present)
# (Amazon Linux 2 may come with docker-compose-plugin; if not, install via yum or download binary)
if ! command -v docker-compose &>/dev/null; then
    curl -L "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Enable and start Docker
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user

# 2. Mount EFS file system
EFS_ID="$(aws ssm get-parameter --name "/myapp/efs-id" --query Parameter.Value --output text 2>/dev/null || true)"
if [ -z "$EFS_ID" ]; then
    echo "ERROR: SSM parameter /myapp/efs-id not found. Please ensure it exists."
    exit 1
fi

mkdir -p /mnt/efs
# Check if the EFS mount helper exists
if [ -x "/sbin/mount.efs" ]; then
    echo "Using mount.efs helper..."
    mount -t efs ${EFS_ID}:/ /mnt/efs || { echo "EFS mount failed using efs helper"; exit 1; }
else
    echo "mount.efs helper not found; falling back to nfs4..."
    REGION="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)"
    mount -t nfs4 -o nfsvers=4.1 ${EFS_ID}.efs.${REGION}.amazonaws.com:/ /mnt/efs || { echo "EFS mount failed using nfs4"; exit 1; }
fi

# 3. Create dedicated directories on EFS for each service
mkdir -p /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant

# 4. Set appropriate permissions for each directory
# n8n container (uid 1000), Postgres (uid 999), Ollama and Qdrant (root)
chown -R 1000:1000 /mnt/efs/n8n
chown -R 999:999 /mnt/efs/postgres
chown -R 0:0 /mnt/efs/ollama
chown -R 0:0 /mnt/efs/qdrant
chmod -R 770 /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant

# 5. Retrieve secrets from AWS SSM and populate .env
echo "Fetching secrets from SSM Parameter Store..."
AWS_DEFAULT_REGION="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)"
export AWS_DEFAULT_REGION

DB_PASSWORD="$(aws ssm get-parameter --with-decryption --name "/aibuildkit/POSTGRES_PASSWORD" --query Parameter.Value --output text 2>/dev/null || true)"
if [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: SSM parameter /aibuildkit/POSTGRES_PASSWORD not found."
    exit 1
fi

ENCRYPTION_KEY="$(aws ssm get-parameter --with-decryption --name "/aibuildkit/N8N_ENCRYPTION_KEY" --query Parameter.Value --output text 2>/dev/null || true)"
if [ -z "$ENCRYPTION_KEY" ]; then
    echo "ERROR: SSM parameter /aibuildkit/N8N_ENCRYPTION_KEY not found."
    exit 1
fi

N8N_USER_MANAGEMENT_JWT_SECRET="$(aws ssm get-parameter --with-decryption --name "/aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET" --query Parameter.Value --output text 2>/dev/null || true)"
if [ -z "$N8N_USER_MANAGEMENT_JWT_SECRET" ]; then
    echo "ERROR: SSM parameter /aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET not found."
    exit 1
fi

mkdir -p /opt/myapp
cat > /opt/myapp/.env <<EOF
# .env file for docker-compose
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n_db
DB_POSTGRESDB_USER=n8n_user
DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
WEBHOOK_URL=https://n8n.geuse.io/
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
EOF

# 6. Detect GPU and install NVIDIA components if present
if lspci | grep -qi "NVIDIA"; then
    echo "NVIDIA GPU detected, installing drivers and toolkit..."
    distribution=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    if [[ "$distribution" =~ ^\"?ubuntu\"?$ ]]; then
        apt-get install -y nvidia-driver-525 nvidia-container-toolkit
    else
        amazon-linux-extras install -y kernel-nvidia
        yum install -y nvidia-driver nvidia-container-toolkit
    fi
    echo "ENABLE_CUDA=1" >> /opt/myapp/.env
fi

# 7. Start Docker Compose to launch all containers
docker compose -f /opt/myapp/docker-compose.yml --env-file /opt/myapp/.env up -d

# 8. Print success message with public IP (fallback to private IP if needed)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
fi
echo "==============================================="
echo "AI Starter Kit deployment complete! Access n8n at: https://$PUBLIC_IP:5678/"
echo "==============================================="

# 9. Set up Spot Instance Termination Handling
cat <<'EOF' > /usr/local/bin/spot-termination-check.sh
#!/bin/bash
CHECK_INTERVAL=60
while true; do
  TERMINATION_TIME=$(curl -s http://169.254.169.254/latest/meta-data/spot/termination-time || true)
  if [ ! -z "$TERMINATION_TIME" ]; then
    echo "Spot instance termination notice received at $TERMINATION_TIME. Initiating graceful shutdown..."
    cd /opt/myapp && docker compose -f docker-compose.yml down
    shutdown -h now
    exit 0
  fi
  sleep ${CHECK_INTERVAL}
done
EOF
chmod +x /usr/local/bin/spot-termination-check.sh
nohup /usr/local/bin/spot-termination-check.sh >/var/log/spot-termination.log 2>&1 &