#!/bin/bash
# =============================================================================
# Service Configuration Module
# Generates docker-compose configurations, manages environment variables,
# and handles service-specific settings for AI application stack
# =============================================================================

# Prevent multiple sourcing
[ -n "${_SERVICE_CONFIG_SH_LOADED:-}" ] && return 0
_SERVICE_CONFIG_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../config/variables.sh"

# =============================================================================
# DOCKER COMPOSE GENERATION
# =============================================================================

# Generate optimized docker-compose configuration
generate_docker_compose() {
    local output_file="$1"
    local instance_type="${2:-$(get_variable INSTANCE_TYPE)}"
    local efs_dns="${3:-}"
    local enable_gpu="${4:-true}"
    local deployment_mode="${5:-gpu-optimized}"
    
    with_error_context "generate_docker_compose" \
        _generate_docker_compose_impl "$output_file" "$instance_type" "$efs_dns" "$enable_gpu" "$deployment_mode"
}

_generate_docker_compose_impl() {
    local output_file="$1"
    local instance_type="$2"
    local efs_dns="$3"
    local enable_gpu="$4"
    local deployment_mode="$5"
    
    echo "Generating Docker Compose configuration for $instance_type..." >&2
    
    # Get resource allocations based on instance type
    local resources
    resources=$(get_instance_resources "$instance_type")
    
    # Extract resource values
    local cpu_limit memory_limit gpu_memory_fraction
    cpu_limit=$(echo "$resources" | jq -r '.cpu_limit')
    memory_limit=$(echo "$resources" | jq -r '.memory_limit')
    gpu_memory_fraction=$(echo "$resources" | jq -r '.gpu_memory_fraction')
    
    # Generate volumes configuration
    local volumes_config
    volumes_config=$(generate_volumes_config "$efs_dns")
    
    # Generate networks configuration
    local networks_config
    networks_config=$(generate_networks_config)
    
    # Generate shared configurations
    local shared_configs
    shared_configs=$(generate_shared_configs "$enable_gpu")
    
    # Generate services configuration
    local services_config
    services_config=$(generate_services_config "$resources" "$enable_gpu" "$deployment_mode")
    
    # Generate secrets configuration
    local secrets_config
    secrets_config=$(generate_secrets_config)
    
    # Combine all configurations
    cat > "$output_file" << EOF
# Modern Docker Compose format (no version field required)
# Uses the Compose Specification (latest)

# Enhanced AI Application Stack - Auto-generated Configuration
# Instance: $instance_type
# Deployment Mode: $deployment_mode
# GPU Enabled: $enable_gpu
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

$volumes_config

$networks_config

$shared_configs

$services_config

$secrets_config

# =============================================================================
# RESOURCE ALLOCATION SUMMARY FOR $instance_type
# =============================================================================
$(generate_resource_summary "$resources")
EOF
    
    # Validate generated compose file
    validate_compose_file "$output_file"
    
    echo "Docker Compose configuration generated: $output_file" >&2
}

# Get resource allocations for instance type
get_instance_resources() {
    local instance_type="$1"
    
    case "$instance_type" in
        g4dn.xlarge)
            cat << EOF
{
    "cpu_cores": 4,
    "memory_gb": 16,
    "gpu_memory_gb": 16,
    "cpu_limit": "3.4",
    "memory_limit": "14G",
    "gpu_memory_fraction": 0.85,
    "services": {
        "postgres": {"cpu": "0.4", "memory": "2G"},
        "n8n": {"cpu": "0.4", "memory": "1.5G"},
        "ollama": {"cpu": "2.0", "memory": "6G"},
        "qdrant": {"cpu": "0.4", "memory": "2G"},
        "crawl4ai": {"cpu": "0.4", "memory": "1.5G"},
        "gpu_monitor": {"cpu": "0.2", "memory": "512M"},
        "health_check": {"cpu": "0.1", "memory": "128M"}
    }
}
EOF
            ;;
        g4dn.2xlarge)
            cat << EOF
{
    "cpu_cores": 8,
    "memory_gb": 32,
    "gpu_memory_gb": 16,
    "cpu_limit": "7.5",
    "memory_limit": "28G",
    "gpu_memory_fraction": 0.85,
    "services": {
        "postgres": {"cpu": "0.8", "memory": "4G"},
        "n8n": {"cpu": "0.8", "memory": "3G"},
        "ollama": {"cpu": "4.0", "memory": "12G"},
        "qdrant": {"cpu": "0.8", "memory": "4G"},
        "crawl4ai": {"cpu": "0.8", "memory": "3G"},
        "gpu_monitor": {"cpu": "0.2", "memory": "512M"},
        "health_check": {"cpu": "0.1", "memory": "128M"}
    }
}
EOF
            ;;
        g5.xlarge)
            cat << EOF
{
    "cpu_cores": 4,
    "memory_gb": 16,
    "gpu_memory_gb": 24,
    "cpu_limit": "3.5",
    "memory_limit": "14G",
    "gpu_memory_fraction": 0.90,
    "services": {
        "postgres": {"cpu": "0.4", "memory": "2G"},
        "n8n": {"cpu": "0.4", "memory": "1.5G"},
        "ollama": {"cpu": "2.0", "memory": "6G"},
        "qdrant": {"cpu": "0.4", "memory": "2G"},
        "crawl4ai": {"cpu": "0.4", "memory": "1.5G"},
        "gpu_monitor": {"cpu": "0.2", "memory": "512M"},
        "health_check": {"cpu": "0.1", "memory": "128M"}
    }
}
EOF
            ;;
        *)
            # Default/CPU-only configuration
            cat << EOF
{
    "cpu_cores": 2,
    "memory_gb": 8,
    "gpu_memory_gb": 0,
    "cpu_limit": "1.8",
    "memory_limit": "7G",
    "gpu_memory_fraction": 0.0,
    "services": {
        "postgres": {"cpu": "0.3", "memory": "1.5G"},
        "n8n": {"cpu": "0.3", "memory": "1G"},
        "ollama": {"cpu": "1.0", "memory": "3G"},
        "qdrant": {"cpu": "0.3", "memory": "1.5G"},
        "crawl4ai": {"cpu": "0.3", "memory": "1G"},
        "gpu_monitor": {"cpu": "0.1", "memory": "256M"},
        "health_check": {"cpu": "0.1", "memory": "128M"}
    }
}
EOF
            ;;
    esac
}

# Generate volumes configuration
generate_volumes_config() {
    local efs_dns="$1"
    
    if [ -n "$efs_dns" ]; then
        # EFS-based volumes
        cat << EOF
# =============================================================================
# SHARED VOLUMES WITH EFS INTEGRATION
# =============================================================================
volumes:
  n8n_storage:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=${efs_dns},nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,regional"
      device: ":/n8n"
  postgres_storage:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=${efs_dns},nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,regional"
      device: ":/postgres"
  ollama_storage:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=${efs_dns},nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,regional"
      device: ":/ollama"
  qdrant_storage:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=${efs_dns},nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,regional"
      device: ":/qdrant"
  shared_storage:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=${efs_dns},nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,regional"
      device: ":/shared"
  crawl4ai_cache:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=${efs_dns},nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,regional"
      device: ":/crawl4ai/cache"
  crawl4ai_storage:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=${efs_dns},nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,regional"
      device: ":/crawl4ai/storage"
EOF
    else
        # Local volumes for testing/development
        cat << EOF
# =============================================================================
# LOCAL VOLUMES FOR DEVELOPMENT/TESTING
# =============================================================================
volumes:
  n8n_storage:
    driver: local
  postgres_storage:
    driver: local
  ollama_storage:
    driver: local
  qdrant_storage:
    driver: local
  shared_storage:
    driver: local
  crawl4ai_cache:
    driver: local
  crawl4ai_storage:
    driver: local
EOF
    fi
}

# Generate networks configuration
generate_networks_config() {
    cat << EOF
# =============================================================================
# OPTIMIZED NETWORKS
# =============================================================================
networks:
  ai_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
    driver_opts:
      com.docker.network.driver.mtu: 9000  # Jumbo frames for better performance
EOF
}

# Generate shared configurations
generate_shared_configs() {
    local enable_gpu="$1"
    
    if [ "$enable_gpu" = "true" ]; then
        cat << EOF
# =============================================================================
# SHARED CONFIGURATIONS
# =============================================================================
x-gpu-config: &gpu-config
  runtime: nvidia
  environment:
    - NVIDIA_VISIBLE_DEVICES=all
    - NVIDIA_DRIVER_CAPABILITIES=all
    - CUDA_VISIBLE_DEVICES=all
    - CUDA_DEVICE_ORDER=PCI_BUS_ID
  devices:
    - /dev/nvidia0:/dev/nvidia0
    - /dev/nvidia-uvm:/dev/nvidia-uvm
    - /dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools
    - /dev/nvidiactl:/dev/nvidiactl

x-logging-config: &logging-config
  logging:
    driver: "json-file"
    options:
      max-size: "100m"
      max-file: "5"

x-restart-policy: &restart-policy
  restart: unless-stopped

x-security-config: &security-config
  security_opt:
    - no-new-privileges:true
  read_only: false
EOF
    else
        cat << EOF
# =============================================================================
# SHARED CONFIGURATIONS (CPU ONLY)
# =============================================================================
x-logging-config: &logging-config
  logging:
    driver: "json-file"
    options:
      max-size: "100m"
      max-file: "5"

x-restart-policy: &restart-policy
  restart: unless-stopped

x-security-config: &security-config
  security_opt:
    - no-new-privileges:true
  read_only: false
EOF
    fi
}

# Generate services configuration
generate_services_config() {
    local resources="$1"
    local enable_gpu="$2"
    local deployment_mode="$3"
    
    # Extract service resources
    local postgres_resources n8n_resources ollama_resources qdrant_resources crawl4ai_resources
    postgres_resources=$(echo "$resources" | jq -c '.services.postgres')
    n8n_resources=$(echo "$resources" | jq -c '.services.n8n')
    ollama_resources=$(echo "$resources" | jq -c '.services.ollama')
    qdrant_resources=$(echo "$resources" | jq -c '.services.qdrant')
    crawl4ai_resources=$(echo "$resources" | jq -c '.services.crawl4ai')
    
    cat << EOF
# =============================================================================
# SERVICE DEFINITIONS
# =============================================================================
services:
$(generate_postgres_service "$postgres_resources")

$(generate_n8n_service "$n8n_resources")

$(generate_qdrant_service "$qdrant_resources")

$(generate_ollama_service "$ollama_resources" "$enable_gpu" "$resources")

$(generate_crawl4ai_service "$crawl4ai_resources")

$(generate_monitoring_services "$resources" "$enable_gpu")
EOF
}

# Generate PostgreSQL service configuration
generate_postgres_service() {
    local resources="$1"
    local cpu_limit memory_limit
    cpu_limit=$(echo "$resources" | jq -r '.cpu')
    memory_limit=$(echo "$resources" | jq -r '.memory')
    
    cat << EOF
  # ---------------------------------------------------------------------------
  # PostgreSQL - Optimized Database Service
  # ---------------------------------------------------------------------------
  postgres:
    <<: [*logging-config, *restart-policy, *security-config]
    image: postgres:16.1-alpine3.19
    container_name: postgres-ai
    hostname: postgres
    user: "70:70"  # postgres user in alpine
    networks:
      - ai_network
    tmpfs:
      - /tmp:noexec,nosuid,size=1g
    ports:
      - "5432:5432"
    environment:
      # Basic PostgreSQL configuration
      - POSTGRES_DB=\${POSTGRES_DB:-n8n}
      - POSTGRES_USER=\${POSTGRES_USER:-n8n}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C --lc-ctype=C
      
      # Performance optimizations
      - POSTGRES_MAX_CONNECTIONS=200
      - POSTGRES_SHARED_BUFFERS=${memory_limit%G}GB
      - POSTGRES_EFFECTIVE_CACHE_SIZE=\$(($(echo "${memory_limit%G}" | bc) * 3))GB
      - POSTGRES_WORK_MEM=16MB
      - POSTGRES_MAINTENANCE_WORK_MEM=256MB
      - POSTGRES_CHECKPOINT_COMPLETION_TARGET=0.9
      - POSTGRES_WAL_BUFFERS=64MB
      - POSTGRES_RANDOM_PAGE_COST=1.1
      - POSTGRES_EFFECTIVE_IO_CONCURRENCY=200
    
    command: [
      "postgres",
      "-c", "shared_preload_libraries=pg_stat_statements",
      "-c", "max_connections=200",
      "-c", "shared_buffers=${memory_limit%G}GB",
      "-c", "effective_cache_size=\$(($(echo "${memory_limit%G}" | bc) * 3))GB",
      "-c", "work_mem=16MB",
      "-c", "maintenance_work_mem=256MB",
      "-c", "checkpoint_completion_target=0.9",
      "-c", "wal_buffers=64MB",
      "-c", "random_page_cost=1.1",
      "-c", "effective_io_concurrency=200",
      "-c", "log_statement=ddl",
      "-c", "log_min_duration_statement=1000"
    ]
    
    volumes:
      - postgres_storage:/var/lib/postgresql/data
      - shared_storage:/shared
    
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -U \${POSTGRES_USER:-n8n} -d \${POSTGRES_DB:-n8n}"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    
    deploy:
      resources:
        limits:
          memory: $memory_limit
          cpus: '$cpu_limit'
        reservations:
          memory: \$(($(echo "${memory_limit%G}" | bc) / 2))G
          cpus: '\$(($(echo "$cpu_limit" | bc) / 2))'
EOF
}

# Generate n8n service configuration
generate_n8n_service() {
    local resources="$1"
    local cpu_limit memory_limit
    cpu_limit=$(echo "$resources" | jq -r '.cpu')
    memory_limit=$(echo "$resources" | jq -r '.memory')
    
    cat << EOF
  # ---------------------------------------------------------------------------
  # n8n - Workflow Automation Platform
  # ---------------------------------------------------------------------------
  n8n:
    <<: [*logging-config, *restart-policy, *security-config]
    image: n8nio/n8n:1.19.4
    container_name: n8n-ai
    hostname: n8n
    user: "1000:1000"  # n8n user
    networks:
      - ai_network
    tmpfs:
      - /tmp:noexec,nosuid,size=512m
    ports:
      - "5678:5678"
    environment:
      # Database configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB:-n8n}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER:-n8n}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      
      # n8n specific settings
      - N8N_HOST=\${N8N_HOST:-0.0.0.0}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=\${WEBHOOK_URL:-http://localhost:5678}
      
      # Security and encryption
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_JWT_SECRET}
      
      # CORS configuration
      - N8N_CORS_ENABLE=\${N8N_CORS_ENABLE:-true}
      - N8N_CORS_ALLOWED_ORIGINS=\${N8N_CORS_ALLOWED_ORIGINS:-*}
      
      # Performance optimizations
      - N8N_PAYLOAD_SIZE_MAX=16
      - N8N_METRICS=true
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
      
      # AI integration settings
      - N8N_AI_ENABLED=true
      - OLLAMA_BASE_URL=http://ollama:11434
      - QDRANT_URL=http://qdrant:6333
      
      # Instance information
      - INSTANCE_TYPE=\${INSTANCE_TYPE:-g4dn.xlarge}
      - DEPLOYMENT_MODE=ai-optimized
    
    volumes:
      - n8n_storage:/home/node/.n8n
      - shared_storage:/shared
    
    depends_on:
      postgres:
        condition: service_healthy
    
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    
    deploy:
      resources:
        limits:
          memory: $memory_limit
          cpus: '$cpu_limit'
        reservations:
          memory: \$(($(echo "${memory_limit%G}" | bc) / 3))G
          cpus: '\$(($(echo "$cpu_limit" | bc) / 2))'
EOF
}

# Generate Qdrant service configuration
generate_qdrant_service() {
    local resources="$1"
    local cpu_limit memory_limit
    cpu_limit=$(echo "$resources" | jq -r '.cpu')
    memory_limit=$(echo "$resources" | jq -r '.memory')
    
    cat << EOF
  # ---------------------------------------------------------------------------
  # Qdrant - Vector Database with Performance Optimizations
  # ---------------------------------------------------------------------------
  qdrant:
    <<: [*logging-config, *restart-policy, *security-config]
    image: qdrant/qdrant:v1.7.3
    container_name: qdrant-ai
    hostname: qdrant
    networks:
      - ai_network
    ports:
      - "6333:6333"
      - "6334:6334"
    environment:
      # Service configuration
      - QDRANT__SERVICE__HTTP_PORT=6333
      - QDRANT__SERVICE__GRPC_PORT=6334
      - QDRANT__SERVICE__ENABLE_CORS=true
      
      # Performance optimizations
      - QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=\$(($(echo "$cpu_limit" | bc | cut -d. -f1) * 2))
      - QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS=\$(echo "$cpu_limit" | bc | cut -d. -f1)
      - QDRANT__STORAGE__PERFORMANCE__SEARCH_THREADS=\$(echo "$cpu_limit" | bc | cut -d. -f1)
      
      # Storage configuration
      - QDRANT__STORAGE__STORAGE_PATH=/qdrant/storage
      - QDRANT__STORAGE__SNAPSHOTS_PATH=/qdrant/snapshots
      - QDRANT__STORAGE__TEMP_PATH=/qdrant/temp
      
      # Memory optimizations
      - QDRANT__STORAGE__PERFORMANCE__MAX_INDEXING_THREADS=\$(echo "$cpu_limit" | bc | cut -d. -f1)
      - QDRANT__STORAGE__WAL__WAL_CAPACITY_MB=\$(($(echo "${memory_limit%G}" | bc) * 64))
    
    volumes:
      - qdrant_storage:/qdrant/storage
      - shared_storage:/qdrant/shared:ro
    
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:6333/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    
    deploy:
      resources:
        limits:
          memory: $memory_limit
          cpus: '$cpu_limit'
        reservations:
          memory: \$(($(echo "${memory_limit%G}" | bc) / 2))G
          cpus: '\$(($(echo "$cpu_limit" | bc) / 2))'
EOF
}

# Generate Ollama service configuration
generate_ollama_service() {
    local resources="$1"
    local enable_gpu="$2"
    local full_resources="$3"
    
    local cpu_limit memory_limit gpu_memory_fraction
    cpu_limit=$(echo "$resources" | jq -r '.cpu')
    memory_limit=$(echo "$resources" | jq -r '.memory')
    gpu_memory_fraction=$(echo "$full_resources" | jq -r '.gpu_memory_fraction')
    
    local gpu_config=""
    if [ "$enable_gpu" = "true" ]; then
        gpu_config="<<: [*gpu-config, *logging-config, *restart-policy, *security-config]"
    else
        gpu_config="<<: [*logging-config, *restart-policy, *security-config]"
    fi
    
    cat << EOF
  # ---------------------------------------------------------------------------
  # Ollama - AI Model Server
  # ---------------------------------------------------------------------------
  ollama:
    $gpu_config
    image: ollama/ollama:0.1.17
    container_name: ollama-ai
    hostname: ollama
    networks:
      - ai_network
    ports:
      - "11434:11434"
    environment:
      # Ollama configuration
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=\${OLLAMA_ORIGINS:-http://localhost:*}
      - OLLAMA_DEBUG=0
      - OLLAMA_KEEP_ALIVE=24h
      - OLLAMA_LOAD_TIMEOUT=300s
      
      # GPU optimizations
      - OLLAMA_GPU_MEMORY_FRACTION=$gpu_memory_fraction
      - OLLAMA_MAX_LOADED_MODELS=\$(($(echo "$cpu_limit" | bc | cut -d. -f1) / 2 + 1))
      - OLLAMA_CONCURRENT_REQUESTS=\$(echo "$cpu_limit" | bc | cut -d. -f1)
      - OLLAMA_NUM_PARALLEL=\$(echo "$cpu_limit" | bc | cut -d. -f1)
      
      # Performance optimizations
      - OLLAMA_FLASH_ATTENTION=1
      - OLLAMA_KV_CACHE_TYPE=f16
      - OLLAMA_USE_MLOCK=1
      - OLLAMA_NUMA=1
      
      # Model-specific optimizations
      - OLLAMA_REQUEST_TIMEOUT=600s
      - OLLAMA_CONTEXT_LENGTH=8192
      - OLLAMA_BATCH_SIZE=1024
      - OLLAMA_THREADS=\$(echo "$cpu_limit" | bc | cut -d. -f1)
      
      # Memory management
      - OLLAMA_MEMORY_POOL_SIZE=\$(($(echo "${memory_limit%G}" | bc) - 1))GB
      - OLLAMA_CACHE_SIZE=1GB
    
    volumes:
      - ollama_storage:/root/.ollama
      - shared_storage:/shared:ro
    
    tmpfs:
      - /tmp:size=2G
    
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:11434/api/tags || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 120s
    
    deploy:
      resources:
        limits:
          memory: $memory_limit
          cpus: '$cpu_limit'
        reservations:
          memory: \$(($(echo "${memory_limit%G}" | bc) * 2 / 3))G
          cpus: '\$(($(echo "$cpu_limit" | bc) * 3 / 4))'
EOF
}

# Generate Crawl4AI service configuration
generate_crawl4ai_service() {
    local resources="$1"
    local cpu_limit memory_limit
    cpu_limit=$(echo "$resources" | jq -r '.cpu')
    memory_limit=$(echo "$resources" | jq -r '.memory')
    
    cat << EOF
  # ---------------------------------------------------------------------------
  # Crawl4AI - Web Crawling with LLM-based Extraction
  # ---------------------------------------------------------------------------
  crawl4ai:
    <<: [*logging-config, *restart-policy, *security-config]
    image: unclecode/crawl4ai:0.2.75
    container_name: crawl4ai-ai
    hostname: crawl4ai
    networks:
      - ai_network
    ports:
      - "11235:11235"
    
    environment:
      # LLM Configuration
      - OPENAI_API_KEY=\${OPENAI_API_KEY:-}
      - ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY:-}
      - DEEPSEEK_API_KEY=\${DEEPSEEK_API_KEY:-}
      - GROQ_API_KEY=\${GROQ_API_KEY:-}
      
      # Ollama integration
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_HOST=ollama
      - OLLAMA_PORT=11434
      
      # Database connection
      - DATABASE_URL=postgresql://\${POSTGRES_USER:-n8n}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB:-n8n}
      - POSTGRES_HOST=postgres
      - POSTGRES_PORT=5432
      
      # Crawl4AI Configuration
      - CRAWL4AI_HOST=0.0.0.0
      - CRAWL4AI_PORT=11235
      - CRAWL4AI_TIMEOUT_KEEP_ALIVE=600
      - CRAWL4AI_RELOAD=false
      
      # Performance optimization
      - CRAWL4AI_MEMORY_THRESHOLD_PERCENT=90.0
      - CRAWL4AI_BATCH_PROCESS_TIMEOUT=600.0
      - CRAWL4AI_MAX_CONCURRENT_SESSIONS=\$(echo "$cpu_limit" | bc | cut -d. -f1)
      - CRAWL4AI_SESSION_TIMEOUT=300
      - CRAWL4AI_BROWSER_POOL_SIZE=\$(($(echo "$cpu_limit" | bc | cut -d. -f1) / 2))
      
      # Security settings
      - CRAWL4AI_SECURITY_ENABLED=false
      - CRAWL4AI_JWT_ENABLED=false
      
      # Monitoring
      - CRAWL4AI_PROMETHEUS_ENABLED=true
      - CRAWL4AI_HEALTH_CHECK_ENDPOINT=/health
    
    volumes:
      - shared_storage:/data/shared
      - /dev/shm:/dev/shm:rw,nosuid,nodev,exec,size=2g
      - crawl4ai_cache:/app/cache
      - crawl4ai_storage:/app/storage
    
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:11235/health || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 120s
    
    deploy:
      resources:
        limits:
          memory: $memory_limit
          cpus: '$cpu_limit'
        reservations:
          memory: \$(($(echo "${memory_limit%G}" | bc) * 2 / 3))G
          cpus: '\$(($(echo "$cpu_limit" | bc) / 2))'
    
    depends_on:
      postgres:
        condition: service_healthy
      ollama:
        condition: service_healthy
EOF
}

# Generate monitoring services
generate_monitoring_services() {
    local resources="$1"
    local enable_gpu="$2"
    
    local monitor_resources health_resources
    monitor_resources=$(echo "$resources" | jq -c '.services.gpu_monitor // .services.monitor // {"cpu": "0.2", "memory": "512M"}')
    health_resources=$(echo "$resources" | jq -c '.services.health_check // {"cpu": "0.1", "memory": "128M"}')
    
    local gpu_monitor=""
    if [ "$enable_gpu" = "true" ]; then
        gpu_monitor=$(generate_gpu_monitor_service "$monitor_resources")
    fi
    
    cat << EOF
$gpu_monitor

$(generate_health_check_service "$health_resources")
EOF
}

# Generate GPU monitoring service
generate_gpu_monitor_service() {
    local resources="$1"
    local cpu_limit memory_limit
    cpu_limit=$(echo "$resources" | jq -r '.cpu')
    memory_limit=$(echo "$resources" | jq -r '.memory')
    
    cat << EOF
  # ---------------------------------------------------------------------------
  # GPU Monitoring Service
  # ---------------------------------------------------------------------------
  gpu-monitor:
    <<: [*gpu-config, *logging-config, *restart-policy]
    image: nvidia/cuda:12.4.1-devel-ubuntu22.04
    container_name: gpu-monitor
    hostname: gpu-monitor
    networks:
      - ai_network
    environment:
      - PYTHONUNBUFFERED=1
      - AWS_DEFAULT_REGION=\${AWS_REGION:-us-east-1}
      - INSTANCE_ID=\${INSTANCE_ID}
      - INSTANCE_TYPE=\${INSTANCE_TYPE:-g4dn.xlarge}
    volumes:
      - shared_storage:/shared
      - /var/log:/host/var/log:ro
    command:
      - /bin/bash
      - -c
      - |
        apt-get update && apt-get install -y python3 python3-pip curl
        pip3 install nvidia-ml-py3 psutil boto3
        
        # Create GPU monitoring script
        cat > /usr/local/bin/gpu_monitor.py << 'EOF'
        #!/usr/bin/env python3
        import time
        import json
        import nvidia_ml_py3 as nvml
        import psutil
        from datetime import datetime
        
        nvml.nvmlInit()
        
        while True:
            try:
                # GPU metrics
                handle = nvml.nvmlDeviceGetHandleByIndex(0)
                gpu_util = nvml.nvmlDeviceGetUtilizationRates(handle)
                mem_info = nvml.nvmlDeviceGetMemoryInfo(handle)
                temp = nvml.nvmlDeviceGetTemperature(handle, nvml.NVML_TEMPERATURE_GPU)
                power = nvml.nvmlDeviceGetPowerUsage(handle) / 1000.0
                
                # System metrics
                cpu_percent = psutil.cpu_percent()
                memory = psutil.virtual_memory()
                
                metrics = {
                    "timestamp": datetime.utcnow().isoformat(),
                    "gpu": {
                        "utilization": gpu_util.gpu,
                        "memory_used_mb": mem_info.used // 1024 // 1024,
                        "memory_total_mb": mem_info.total // 1024 // 1024,
                        "memory_utilization": (mem_info.used / mem_info.total) * 100,
                        "temperature_c": temp,
                        "power_draw_w": power
                    },
                    "system": {
                        "cpu_utilization": cpu_percent,
                        "memory_utilization": memory.percent,
                        "memory_used_gb": memory.used // 1024 // 1024 // 1024,
                        "memory_total_gb": memory.total // 1024 // 1024 // 1024
                    }
                }
                
                # Write metrics to shared storage
                with open("/shared/gpu_metrics.json", "w") as f:
                    json.dump(metrics, f, indent=2)
                
                print(f"GPU: {gpu_util.gpu}% | Mem: {(mem_info.used/mem_info.total)*100:.1f}% | Temp: {temp}°C | Power: {power:.1f}W")
                
                time.sleep(30)
                
            except Exception as e:
                print(f"Monitoring error: {e}")
                time.sleep(30)
        EOF
        
        chmod +x /usr/local/bin/gpu_monitor.py
        python3 /usr/local/bin/gpu_monitor.py
    
    deploy:
      resources:
        limits:
          memory: $memory_limit
          cpus: '$cpu_limit'
        reservations:
          memory: \$(($(echo "${memory_limit%M}" | bc) / 2))M
          cpus: '\$(($(echo "$cpu_limit" | bc) / 2))'
EOF
}

# Generate health check service
generate_health_check_service() {
    local resources="$1"
    local cpu_limit memory_limit
    cpu_limit=$(echo "$resources" | jq -r '.cpu')
    memory_limit=$(echo "$resources" | jq -r '.memory')
    
    cat << EOF
  # ---------------------------------------------------------------------------
  # Health Check Service
  # ---------------------------------------------------------------------------
  health-check:
    <<: [*logging-config, *restart-policy]
    image: curlimages/curl:8.5.0
    container_name: health-check
    hostname: health-check
    networks:
      - ai_network
    environment:
      - CHECK_INTERVAL=60
      - NOTIFICATION_WEBHOOK=\${WEBHOOK_URL}
    volumes:
      - shared_storage:/shared
    command:
      - /bin/sh
      - -c
      - |
        while true; do
          echo "=== Health Check \$(date) ==="
          
          # Check all services
          services=("n8n:5678/healthz" "ollama:11434/api/tags" "qdrant:6333/healthz" "crawl4ai:11235/health")
          
          for service in "\$\${services[@]}"; do
            name=\$\$(echo \$\$service | cut -d: -f1)
            endpoint=\$\$(echo \$\$service | cut -d: -f2-)
            
            if curl -f -s "http://\$\$endpoint" > /dev/null; then
              echo "✓ \$\$name is healthy"
            else
              echo "✗ \$\$name is unhealthy"
            fi
          done
          
          # Check GPU health if available
          if [ -f /shared/gpu_metrics.json ]; then
            gpu_temp=\$\$(cat /shared/gpu_metrics.json | grep -o '"temperature_c": [0-9]*' | cut -d' ' -f2)
            if [ "\$\$gpu_temp" -gt 85 ]; then
              echo "⚠ GPU temperature high: \$\${gpu_temp}°C"
            else
              echo "✓ GPU temperature normal: \$\${gpu_temp}°C"
            fi
          fi
          
          sleep \$\$CHECK_INTERVAL
        done
    
    deploy:
      resources:
        limits:
          memory: $memory_limit
          cpus: '$cpu_limit'
EOF
}

# Generate secrets configuration
generate_secrets_config() {
    cat << EOF
# =============================================================================
# SECRETS CONFIGURATION
# =============================================================================
# Note: In production, use external secret management
# For development, create these files in ./secrets/ directory
# secrets:
#   postgres_password:
#     external: true
#     name: postgres_password
#   n8n_encryption_key:
#     external: true  
#     name: n8n_encryption_key
EOF
}

# Generate resource summary
generate_resource_summary() {
    local resources="$1"
    
    local cpu_cores memory_gb cpu_limit memory_limit
    cpu_cores=$(echo "$resources" | jq -r '.cpu_cores')
    memory_gb=$(echo "$resources" | jq -r '.memory_gb')
    cpu_limit=$(echo "$resources" | jq -r '.cpu_limit')
    memory_limit=$(echo "$resources" | jq -r '.memory_limit')
    
    cat << EOF
# Total Resources: ${cpu_cores} vCPUs, ${memory_gb}GB RAM
# 
# CPU Allocation (Target: ${cpu_limit} vCPUs - 85% utilization):
$(echo "$resources" | jq -r '.services | to_entries[] | "# - \(.key): \(.value.cpu) vCPUs"')
# 
# Memory Allocation (Target: ${memory_limit}):
$(echo "$resources" | jq -r '.services | to_entries[] | "# - \(.key): \(.value.memory)"')
#
# Network: All services on ai_network (172.20.0.0/16) with jumbo frames
EOF
}

# =============================================================================
# ENVIRONMENT FILE GENERATION
# =============================================================================

# Generate environment file from Parameter Store
generate_env_file() {
    local output_file="$1"
    local parameter_prefix="${2:-/aibuildkit}"
    local include_secrets="${3:-true}"
    
    with_error_context "generate_env_file" \
        _generate_env_file_impl "$output_file" "$parameter_prefix" "$include_secrets"
}

_generate_env_file_impl() {
    local output_file="$1"
    local parameter_prefix="$2"
    local include_secrets="$3"
    
    echo "Generating environment file from Parameter Store..." >&2
    
    # Create environment file header
    cat > "$output_file" << EOF
# Auto-generated Environment File
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Source: AWS Systems Manager Parameter Store ($parameter_prefix)

# =============================================================================
# CORE CONFIGURATION
# =============================================================================
EOF
    
    # Load parameters from Parameter Store
    if command -v aws >/dev/null 2>&1; then
        echo "Loading parameters from Parameter Store..." >&2
        
        # Get all parameters
        local params
        params=$(aws ssm get-parameters-by-path \
            --path "$parameter_prefix" \
            --recursive \
            --with-decryption \
            --query 'Parameters[*].[Name,Value,Type]' \
            --output text 2>/dev/null) || {
            echo "WARNING: Failed to load from Parameter Store" >&2
        }
        
        # Process parameters
        if [ -n "$params" ]; then
            echo "" >> "$output_file"
            echo "# Parameters from AWS Systems Manager" >> "$output_file"
            
            echo "$params" | while IFS=$'\t' read -r name value type; do
                # Convert parameter name to environment variable
                local var_name="${name#${parameter_prefix}/}"
                var_name="${var_name//\//_}"  # Replace / with _
                
                # Skip secrets if not including them
                if [ "$include_secrets" != "true" ] && [ "$type" = "SecureString" ]; then
                    echo "# ${var_name}=<SecureString - set manually>" >> "$output_file"
                else
                    echo "${var_name}=${value}" >> "$output_file"
                fi
            done
        fi
    else
        echo "WARNING: AWS CLI not available, cannot load from Parameter Store" >&2
    fi
    
    # Add default configuration
    cat >> "$output_file" << EOF

# =============================================================================
# INSTANCE CONFIGURATION
# =============================================================================
INSTANCE_TYPE=${INSTANCE_TYPE:-g4dn.xlarge}
AWS_REGION=${AWS_REGION:-us-east-1}
STACK_NAME=${STACK_NAME:-ai-stack}

# =============================================================================
# SERVICE CONFIGURATION
# =============================================================================
# Database
POSTGRES_DB=n8n
POSTGRES_USER=n8n
# POSTGRES_PASSWORD=<set from Parameter Store>

# n8n Configuration
N8N_HOST=0.0.0.0
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=*
# N8N_ENCRYPTION_KEY=<set from Parameter Store>
# N8N_JWT_SECRET=<set from Parameter Store>

# Webhook configuration
# WEBHOOK_URL=<set based on instance IP>

# =============================================================================
# DOCKER CONFIGURATION
# =============================================================================
COMPOSE_PROJECT_NAME=ai-stack
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# =============================================================================
# FEATURE FLAGS
# =============================================================================
N8N_ENABLE=true
QDRANT_ENABLE=true
OLLAMA_ENABLE=true
CRAWL4AI_ENABLE=true
GPU_MONITORING_ENABLE=true
EOF
    
    echo "Environment file generated: $output_file" >&2
}

# =============================================================================
# VALIDATION AND UTILITIES
# =============================================================================

# Validate Docker Compose file
validate_compose_file() {
    local compose_file="$1"
    
    echo "Validating Docker Compose file..." >&2
    
    # Check file exists
    require_file "$compose_file"
    
    # Validate with docker compose
    if command -v docker >/dev/null 2>&1; then
        docker compose -f "$compose_file" config >/dev/null || {
            throw_error $ERROR_VALIDATION_FAILED "Docker Compose file validation failed"
        }
    fi
    
    echo "Docker Compose file is valid" >&2
}

# Update service resource limits
update_service_resources() {
    local compose_file="$1"
    local service_name="$2"
    local cpu_limit="$3"
    local memory_limit="$4"
    
    echo "Updating resource limits for service: $service_name" >&2
    
    # Use yq or sed to update the compose file
    if command -v yq >/dev/null 2>&1; then
        yq eval ".services.${service_name}.deploy.resources.limits.cpus = \"${cpu_limit}\"" -i "$compose_file"
        yq eval ".services.${service_name}.deploy.resources.limits.memory = \"${memory_limit}\"" -i "$compose_file"
    else
        echo "WARNING: yq not available, cannot update resource limits programmatically" >&2
    fi
}

# Get service configuration
get_service_config() {
    local compose_file="$1"
    local service_name="$2"
    
    if command -v yq >/dev/null 2>&1; then
        yq eval ".services.${service_name}" "$compose_file"
    elif command -v docker >/dev/null 2>&1; then
        docker compose -f "$compose_file" config | grep -A 50 "^  ${service_name}:"
    else
        echo "ERROR: Cannot extract service configuration - yq or docker required" >&2
        return 1
    fi
}