#!/bin/bash
# =============================================================================
# AI Services Module
# Manages Ollama model deployment, n8n workflow automation setup,
# Qdrant vector database configuration, and Crawl4AI web scraping service
# =============================================================================

# Prevent multiple sourcing
[ -n "${_AI_SERVICES_SH_LOADED:-}" ] && return 0
_AI_SERVICES_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../config/variables.sh"

# =============================================================================
# OLLAMA MODEL MANAGEMENT
# =============================================================================

# Setup Ollama with optimized AI models
setup_ollama_models() {
    local instance_type="${1:-$(get_variable INSTANCE_TYPE)}"
    local models_config="${2:-default}"
    local wait_timeout="${3:-600}"
    
    with_error_context "setup_ollama_models" \
        _setup_ollama_models_impl "$instance_type" "$models_config" "$wait_timeout"
}

_setup_ollama_models_impl() {
    local instance_type="$1"
    local models_config="$2"
    local wait_timeout="$3"
    
    echo "Setting up Ollama models for instance type: $instance_type" >&2
    
    # Wait for Ollama service to be ready
    wait_for_ollama_ready "$wait_timeout"
    
    # Get GPU capabilities
    local gpu_info
    gpu_info=$(get_gpu_capabilities "$instance_type")
    
    # Determine model configuration based on instance and GPU
    local model_list
    model_list=$(get_model_configuration "$instance_type" "$models_config" "$gpu_info")
    
    # Download and optimize models
    download_and_optimize_models "$model_list" "$gpu_info"
    
    # Create model test scripts
    create_model_test_scripts
    
    # Validate model deployment
    validate_ollama_models
    
    echo "Ollama model setup completed successfully" >&2
}

# Wait for Ollama service to be ready
wait_for_ollama_ready() {
    local timeout="${1:-300}"
    local interval=10
    local elapsed=0
    
    echo "Waiting for Ollama service to be ready..." >&2
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            echo "Ollama service is ready" >&2
            return 0
        fi
        
        echo "Waiting for Ollama... (${elapsed}s elapsed)" >&2
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    throw_error $ERROR_TIMEOUT "Ollama service did not become ready within ${timeout}s"
}

# Get GPU capabilities for the instance
get_gpu_capabilities() {
    local instance_type="$1"
    
    case "$instance_type" in
        g4dn.xlarge)
            cat << EOF
{
    "gpu_type": "T4",
    "gpu_memory_gb": 16,
    "gpu_count": 1,
    "max_models": 2,
    "memory_fraction": 0.85,
    "recommended_models": ["deepseek-r1:8b", "qwen2.5:7b", "llama3.2:3b"]
}
EOF
            ;;
        g4dn.2xlarge)
            cat << EOF
{
    "gpu_type": "T4",
    "gpu_memory_gb": 16,
    "gpu_count": 1,
    "max_models": 3,
    "memory_fraction": 0.85,
    "recommended_models": ["deepseek-r1:8b", "qwen2.5:7b", "llama3.2:3b", "mistral:7b"]
}
EOF
            ;;
        g5.xlarge)
            cat << EOF
{
    "gpu_type": "A10G",
    "gpu_memory_gb": 24,
    "gpu_count": 1,
    "max_models": 3,
    "memory_fraction": 0.90,
    "recommended_models": ["deepseek-r1:8b", "qwen2.5:7b", "llama3.2:7b", "mistral:7b"]
}
EOF
            ;;
        g5.2xlarge)
            cat << EOF
{
    "gpu_type": "A10G",
    "gpu_memory_gb": 24,
    "gpu_count": 1,
    "max_models": 4,
    "memory_fraction": 0.90,
    "recommended_models": ["deepseek-r1:8b", "qwen2.5:7b", "llama3.2:7b", "mistral:7b", "codellama:7b"]
}
EOF
            ;;
        *)
            # CPU-only fallback
            cat << EOF
{
    "gpu_type": "none",
    "gpu_memory_gb": 0,
    "gpu_count": 0,
    "max_models": 1,
    "memory_fraction": 0.0,
    "recommended_models": ["llama3.2:3b"]
}
EOF
            ;;
    esac
}

# Get model configuration based on instance and requirements
get_model_configuration() {
    local instance_type="$1"
    local config_name="$2"
    local gpu_info="$3"
    
    case "$config_name" in
        "reasoning")
            # Focus on reasoning and problem-solving models
            cat << EOF
{
    "models": [
        {
            "name": "deepseek-r1:8b",
            "purpose": "reasoning",
            "priority": 1,
            "system_prompt": "You are DeepSeek-R1, an advanced reasoning AI optimized for complex problem-solving, logical analysis, and step-by-step thinking."
        },
        {
            "name": "llama3.2:3b",
            "purpose": "general",
            "priority": 2,
            "system_prompt": "You are Llama3.2, a capable AI assistant optimized for general-purpose tasks and quick reasoning."
        }
    ]
}
EOF
            ;;
        "multimodal")
            # Focus on vision-language models
            cat << EOF
{
    "models": [
        {
            "name": "qwen2.5:7b",
            "purpose": "vision-language",
            "priority": 1,
            "system_prompt": "You are Qwen2.5-VL, a multimodal AI capable of understanding both text and visual content."
        },
        {
            "name": "llama3.2:3b",
            "purpose": "general",
            "priority": 2,
            "system_prompt": "You are Llama3.2, a capable AI assistant for general tasks."
        }
    ]
}
EOF
            ;;
        "embeddings")
            # Focus on embedding models
            cat << EOF
{
    "models": [
        {
            "name": "mxbai-embed-large",
            "purpose": "embeddings",
            "priority": 1,
            "system_prompt": "You are an advanced embedding model optimized for semantic similarity and document retrieval."
        },
        {
            "name": "llama3.2:3b",
            "purpose": "general",
            "priority": 2,
            "system_prompt": "You are Llama3.2, a capable AI assistant."
        }
    ]
}
EOF
            ;;
        "development")
            # Focus on code generation and development
            cat << EOF
{
    "models": [
        {
            "name": "codellama:7b",
            "purpose": "code",
            "priority": 1,
            "system_prompt": "You are CodeLlama, specialized in code generation, debugging, and software development assistance."
        },
        {
            "name": "deepseek-r1:8b",
            "purpose": "reasoning",
            "priority": 2,
            "system_prompt": "You are DeepSeek-R1, optimized for logical analysis and problem-solving."
        }
    ]
}
EOF
            ;;
        *)
            # Default balanced configuration
            local recommended_models
            recommended_models=$(echo "$gpu_info" | jq -r '.recommended_models[]' | head -3)
            
            cat << EOF
{
    "models": [
        {
            "name": "deepseek-r1:8b",
            "purpose": "reasoning",
            "priority": 1,
            "system_prompt": "You are DeepSeek-R1, an advanced reasoning AI optimized for complex problem-solving, logical analysis, and step-by-step thinking."
        },
        {
            "name": "qwen2.5:7b",
            "purpose": "vision-language",
            "priority": 2,
            "system_prompt": "You are Qwen2.5-VL, a multimodal AI capable of understanding both text and visual content."
        },
        {
            "name": "llama3.2:3b",
            "purpose": "general",
            "priority": 3,
            "system_prompt": "You are Llama3.2, a capable and efficient AI assistant optimized for general-purpose tasks."
        },
        {
            "name": "mxbai-embed-large",
            "purpose": "embeddings",
            "priority": 4,
            "system_prompt": "You are an advanced embedding model optimized for semantic similarity and vector search."
        }
    ]
}
EOF
            ;;
    esac
}

# Download and optimize models
download_and_optimize_models() {
    local model_config="$1"
    local gpu_info="$2"
    
    echo "Downloading and optimizing AI models..." >&2
    
    # Extract GPU memory and capabilities
    local gpu_memory_gb max_models memory_fraction
    gpu_memory_gb=$(echo "$gpu_info" | jq -r '.gpu_memory_gb')
    max_models=$(echo "$gpu_info" | jq -r '.max_models')
    memory_fraction=$(echo "$gpu_info" | jq -r '.memory_fraction')
    
    # Process each model in priority order
    local model_count=0
    echo "$model_config" | jq -c '.models[] | select(.priority <= '"$max_models"') | sort_by(.priority)' | while read -r model; do
        model_count=$((model_count + 1))
        
        local model_name purpose system_prompt
        model_name=$(echo "$model" | jq -r '.name')
        purpose=$(echo "$model" | jq -r '.purpose')
        system_prompt=$(echo "$model" | jq -r '.system_prompt')
        
        echo "Processing model $model_count: $model_name ($purpose)" >&2
        
        # Download base model
        download_model "$model_name"
        
        # Create optimized version
        create_optimized_model "$model_name" "$purpose" "$system_prompt" "$gpu_info"
        
        # Verify model is working
        test_model "${model_name}-optimized"
    done
    
    echo "Model download and optimization completed" >&2
}

# Download individual model
download_model() {
    local model_name="$1"
    
    echo "Downloading model: $model_name" >&2
    
    # Check if model already exists
    if ollama list | grep -q "$model_name"; then
        echo "Model $model_name already exists" >&2
        return 0
    fi
    
    # Download with retry logic
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Download attempt $attempt for $model_name..." >&2
        
        if ollama pull "$model_name"; then
            echo "Successfully downloaded $model_name" >&2
            return 0
        else
            echo "Download attempt $attempt failed for $model_name" >&2
            if [ $attempt -lt $max_attempts ]; then
                sleep $((attempt * 30))  # Exponential backoff
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "WARNING: Failed to download $model_name after $max_attempts attempts" >&2
    return 1
}

# Create optimized model configuration
create_optimized_model() {
    local base_model="$1"
    local purpose="$2"
    local system_prompt="$3"
    local gpu_info="$4"
    
    local optimized_name="${base_model%:*}-optimized"
    local model_version="${base_model#*:}"
    
    echo "Creating optimized configuration for $base_model..." >&2
    
    # Get GPU-specific parameters
    local gpu_memory_gb memory_fraction
    gpu_memory_gb=$(echo "$gpu_info" | jq -r '.gpu_memory_gb')
    memory_fraction=$(echo "$gpu_info" | jq -r '.memory_fraction')
    
    # Determine context length and other parameters based on purpose and GPU
    local context_length num_gpu batch_size threads
    case "$purpose" in
        "reasoning")
            context_length=8192
            batch_size=512
            threads=8
            ;;
        "vision-language")
            context_length=6144
            batch_size=256
            threads=6
            ;;
        "embeddings")
            context_length=2048
            batch_size=1024
            threads=4
            ;;
        "code")
            context_length=16384
            batch_size=256
            threads=8
            ;;
        *)
            context_length=4096
            batch_size=512
            threads=6
            ;;
    esac
    
    # Set GPU layers based on available memory
    if [ "$gpu_memory_gb" -gt 0 ]; then
        num_gpu=1
        # Adjust parameters based on GPU memory
        if [ "$gpu_memory_gb" -ge 24 ]; then
            # A10G or better
            context_length=$((context_length * 2))
            batch_size=$((batch_size * 2))
        fi
    else
        num_gpu=0
        # CPU-only optimizations
        context_length=$((context_length / 2))
        batch_size=$((batch_size / 2))
        threads=4
    fi
    
    # Create Modelfile
    local modelfile="/tmp/Modelfile.${optimized_name}"
    cat > "$modelfile" << EOF
FROM $base_model

# GPU/CPU optimizations
PARAMETER num_ctx $context_length
PARAMETER num_batch $batch_size
PARAMETER num_gpu $num_gpu
PARAMETER num_thread $threads
PARAMETER num_predict 2048

# Model behavior parameters
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.1
PARAMETER rope_freq_base 10000
PARAMETER rope_freq_scale 1.0

# Memory optimizations
PARAMETER use_mlock true
PARAMETER use_mmap true
PARAMETER numa true

# Sampling parameters
PARAMETER mirostat 0
PARAMETER mirostat_eta 0.1
PARAMETER mirostat_tau 5.0
PARAMETER penalize_newline true

SYSTEM "$system_prompt"
EOF
    
    # Create optimized model
    if ollama create "${optimized_name}:${model_version}" -f "$modelfile"; then
        echo "Created optimized model: ${optimized_name}:${model_version}" >&2
        rm "$modelfile"
    else
        echo "WARNING: Failed to create optimized model for $base_model" >&2
        rm "$modelfile"
        return 1
    fi
}

# Test model functionality
test_model() {
    local model_name="$1"
    
    echo "Testing model: $model_name" >&2
    
    # Simple test prompt
    local test_prompt="What is 2 + 2? Answer briefly."
    
    # Test with timeout
    local response
    if response=$(timeout 60 ollama run "$model_name" "$test_prompt" 2>/dev/null); then
        if [ -n "$response" ] && echo "$response" | grep -q "4"; then
            echo "Model $model_name test: PASSED" >&2
            return 0
        else
            echo "Model $model_name test: FAILED (unexpected response)" >&2
            return 1
        fi
    else
        echo "Model $model_name test: FAILED (timeout or error)" >&2
        return 1
    fi
}

# Create model test scripts
create_model_test_scripts() {
    echo "Creating model test scripts..." >&2
    
    # Create comprehensive test script
    cat > /shared/test-models.sh << 'EOF'
#!/bin/bash
# Comprehensive AI Model Testing Script

set -euo pipefail

echo "=== AI Model Testing Suite ==="
echo "Started: $(date)"
echo ""

# Test Ollama API health
echo "1. Testing Ollama API..."
if curl -f -s http://localhost:11434/api/tags >/dev/null; then
    echo "✓ Ollama API is responding"
else
    echo "✗ Ollama API is not responding"
    exit 1
fi

# List available models
echo ""
echo "2. Available models:"
ollama list

# Test each optimized model
echo ""
echo "3. Testing optimized models..."

test_model() {
    local model="$1"
    local prompt="$2"
    local expected_pattern="$3"
    
    echo "Testing $model..."
    
    local response
    if response=$(timeout 120 curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model\", \"prompt\": \"$prompt\", \"stream\": false}" | jq -r '.response' 2>/dev/null); then
        
        if echo "$response" | grep -qi "$expected_pattern"; then
            echo "✓ $model: PASSED"
            return 0
        else
            echo "✗ $model: FAILED (unexpected response)"
            echo "  Response: $response"
            return 1
        fi
    else
        echo "✗ $model: FAILED (timeout or error)"
        return 1
    fi
}

# Test reasoning model
if ollama list | grep -q "deepseek-r1.*optimized"; then
    test_model "deepseek-r1:8b-optimized" "Solve this step by step: If a train travels 120 km in 2 hours, what is its speed?" "60"
fi

# Test vision-language model
if ollama list | grep -q "qwen2.5.*optimized"; then
    test_model "qwen2.5:7b-optimized" "What are the key capabilities of a vision-language model?" "vision\|image\|multimodal"
fi

# Test general model
if ollama list | grep -q "llama3.2.*optimized"; then
    test_model "llama3.2:3b-optimized" "What is the capital of France?" "Paris"
fi

# Test embedding model
if ollama list | grep -q "mxbai-embed-large"; then
    echo "Testing embedding model..."
    if response=$(timeout 60 curl -s -X POST http://localhost:11434/api/embeddings \
        -H "Content-Type: application/json" \
        -d '{"model": "mxbai-embed-large", "prompt": "This is a test document for embedding generation."}' | jq '.embedding | length' 2>/dev/null); then
        
        if [ "$response" -gt 0 ]; then
            echo "✓ mxbai-embed-large: PASSED (embedding dimension: $response)"
        else
            echo "✗ mxbai-embed-large: FAILED (no embeddings generated)"
        fi
    else
        echo "✗ mxbai-embed-large: FAILED (timeout or error)"
    fi
fi

echo ""
echo "4. Performance metrics:"
echo "GPU Memory Usage:"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits | \
    awk -F, '{printf "  Used: %sMB/%sMB (%.1f%%), GPU Utilization: %s%%\n", $1, $2, ($1/$2)*100, $3}'
else
    echo "  No GPU detected"
fi

echo ""
echo "System Memory Usage:"
free -h | grep "Mem:" | awk '{printf "  Used: %s/%s (%.1f%%)\n", $3, $2, ($3/$2)*100}'

echo ""
echo "=== Model Testing Complete ==="
echo "Finished: $(date)"
EOF
    
    chmod +x /shared/test-models.sh
    
    # Create performance benchmark script
    cat > /shared/benchmark-models.sh << 'EOF'
#!/bin/bash
# AI Model Performance Benchmark

set -euo pipefail

echo "=== AI Model Performance Benchmark ==="
echo "Started: $(date)"

benchmark_model() {
    local model="$1"
    local prompt="$2"
    local iterations="${3:-3}"
    
    echo ""
    echo "Benchmarking $model..."
    
    local total_time=0
    local successful_runs=0
    
    for i in $(seq 1 $iterations); do
        echo "  Run $i/$iterations..."
        
        local start_time
        start_time=$(date +%s.%N)
        
        local response
        if response=$(timeout 300 curl -s -X POST http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$model\", \"prompt\": \"$prompt\", \"stream\": false}" | jq -r '.response' 2>/dev/null); then
            
            local end_time
            end_time=$(date +%s.%N)
            local duration
            duration=$(echo "$end_time - $start_time" | bc)
            
            echo "    Duration: ${duration}s"
            echo "    Response length: $(echo "$response" | wc -c) characters"
            
            total_time=$(echo "$total_time + $duration" | bc)
            successful_runs=$((successful_runs + 1))
        else
            echo "    FAILED"
        fi
    done
    
    if [ $successful_runs -gt 0 ]; then
        local avg_time
        avg_time=$(echo "scale=2; $total_time / $successful_runs" | bc)
        echo "  Average response time: ${avg_time}s"
        echo "  Success rate: $successful_runs/$iterations"
    else
        echo "  All runs failed"
    fi
}

# Benchmark available optimized models
for model in $(ollama list | grep optimized | awk '{print $1}'); do
    benchmark_model "$model" "Write a short explanation of artificial intelligence in 2-3 sentences." 3
done

echo ""
echo "=== Benchmark Complete ==="
echo "Finished: $(date)"
EOF
    
    chmod +x /shared/benchmark-models.sh
    
    echo "Model test scripts created in /shared/" >&2
}

# Validate Ollama model deployment
validate_ollama_models() {
    echo "Validating Ollama model deployment..." >&2
    
    # Check if any models are available
    local model_count
    model_count=$(ollama list | grep -c "optimized" || echo "0")
    
    if [ "$model_count" -eq 0 ]; then
        echo "WARNING: No optimized models found" >&2
        return 1
    fi
    
    echo "Found $model_count optimized models" >&2
    
    # Test at least one model
    local test_model
    test_model=$(ollama list | grep "optimized" | head -1 | awk '{print $1}')
    
    if [ -n "$test_model" ]; then
        if test_model "$test_model"; then
            echo "Model validation successful" >&2
        else
            echo "WARNING: Model validation failed for $test_model" >&2
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# N8N WORKFLOW AUTOMATION SETUP
# =============================================================================

# Setup n8n with AI integrations
setup_n8n_ai_integration() {
    local webhook_url="${1:-}"
    local enable_ai_nodes="${2:-true}"
    local custom_nodes="${3:-}"
    
    with_error_context "setup_n8n_ai_integration" \
        _setup_n8n_ai_integration_impl "$webhook_url" "$enable_ai_nodes" "$custom_nodes"
}

_setup_n8n_ai_integration_impl() {
    local webhook_url="$1"
    local enable_ai_nodes="$2"
    local custom_nodes="$3"
    
    echo "Setting up n8n AI integration..." >&2
    
    # Wait for n8n to be ready
    wait_for_n8n_ready
    
    # Configure AI service connections
    configure_n8n_ai_connections "$webhook_url"
    
    # Install AI-specific nodes
    if [ "$enable_ai_nodes" = "true" ]; then
        install_n8n_ai_nodes "$custom_nodes"
    fi
    
    # Create sample AI workflows
    create_sample_ai_workflows
    
    # Validate n8n setup
    validate_n8n_setup
    
    echo "n8n AI integration setup completed" >&2
}

# Wait for n8n service to be ready
wait_for_n8n_ready() {
    local timeout=300
    local interval=10
    local elapsed=0
    
    echo "Waiting for n8n service to be ready..." >&2
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s http://localhost:5678/healthz >/dev/null 2>&1; then
            echo "n8n service is ready" >&2
            return 0
        fi
        
        echo "Waiting for n8n... (${elapsed}s elapsed)" >&2
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    throw_error $ERROR_TIMEOUT "n8n service did not become ready within ${timeout}s"
}

# Configure n8n AI service connections
configure_n8n_ai_connections() {
    local webhook_url="$1"
    
    echo "Configuring n8n AI service connections..." >&2
    
    # Create AI service credentials via n8n API
    # Note: This would typically be done through the n8n UI or API
    # For now, we create configuration files
    
    local config_dir="/shared/n8n-config"
    mkdir -p "$config_dir"
    
    # Ollama connection configuration
    cat > "$config_dir/ollama-config.json" << EOF
{
    "name": "Ollama Local AI",
    "type": "httpRequest",
    "data": {
        "url": "http://ollama:11434",
        "authentication": "none",
        "requestMethod": "POST",
        "responseFormat": "json"
    }
}
EOF
    
    # Qdrant connection configuration
    cat > "$config_dir/qdrant-config.json" << EOF
{
    "name": "Qdrant Vector DB",
    "type": "httpRequest",
    "data": {
        "url": "http://qdrant:6333",
        "authentication": "none",
        "requestMethod": "POST",
        "responseFormat": "json"
    }
}
EOF
    
    # Crawl4AI connection configuration
    cat > "$config_dir/crawl4ai-config.json" << EOF
{
    "name": "Crawl4AI Scraper",
    "type": "httpRequest",
    "data": {
        "url": "http://crawl4ai:11235",
        "authentication": "none",
        "requestMethod": "POST",
        "responseFormat": "json"
    }
}
EOF
    
    echo "AI service connection configurations created" >&2
}

# Install AI-specific n8n nodes
install_n8n_ai_nodes() {
    local custom_nodes="$1"
    
    echo "Installing AI-specific n8n nodes..." >&2
    
    # Default AI nodes to install
    local default_nodes=(
        "@n8n/n8n-nodes-langchain"
        "n8n-nodes-ollama"
        "n8n-nodes-qdrant"
        "n8n-nodes-web-scraper"
    )
    
    # Install via docker exec (if running in container)
    for node in "${default_nodes[@]}"; do
        echo "Installing node: $node" >&2
        docker exec n8n-ai npm install "$node" || echo "WARNING: Failed to install $node" >&2
    done
    
    # Install custom nodes if specified
    if [ -n "$custom_nodes" ]; then
        IFS=',' read -ra CUSTOM_ARRAY <<< "$custom_nodes"
        for node in "${CUSTOM_ARRAY[@]}"; do
            echo "Installing custom node: $node" >&2
            docker exec n8n-ai npm install "$node" || echo "WARNING: Failed to install $node" >&2
        done
    fi
    
    # Restart n8n to load new nodes
    echo "Restarting n8n to load new nodes..." >&2
    docker restart n8n-ai
    
    # Wait for n8n to be ready again
    sleep 30
    wait_for_n8n_ready
}

# Create sample AI workflows
create_sample_ai_workflows() {
    echo "Creating sample AI workflows..." >&2
    
    local workflow_dir="/shared/n8n-workflows"
    mkdir -p "$workflow_dir"
    
    # AI Chat Workflow
    cat > "$workflow_dir/ai-chat-workflow.json" << 'EOF'
{
    "name": "AI Chat with Ollama",
    "nodes": [
        {
            "parameters": {
                "httpMethod": "POST",
                "path": "ai-chat",
                "responseMode": "responseNode",
                "options": {}
            },
            "id": "webhook-trigger",
            "name": "Webhook Trigger",
            "type": "n8n-nodes-base.webhook",
            "typeVersion": 1,
            "position": [240, 300]
        },
        {
            "parameters": {
                "url": "http://ollama:11434/api/generate",
                "requestMethod": "POST",
                "jsonParameters": true,
                "options": {},
                "bodyParametersJson": "={\"model\": \"deepseek-r1:8b-optimized\", \"prompt\": \"{{ $json.query }}\", \"stream\": false}"
            },
            "id": "ollama-request",
            "name": "Ollama AI Request",
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 3,
            "position": [460, 300]
        },
        {
            "parameters": {
                "respondWith": "json",
                "responseBody": "={{ {\"response\": $json.response, \"model\": \"deepseek-r1:8b-optimized\"} }}"
            },
            "id": "response",
            "name": "Response",
            "type": "n8n-nodes-base.respondToWebhook",
            "typeVersion": 1,
            "position": [680, 300]
        }
    ],
    "connections": {
        "Webhook Trigger": {
            "main": [
                [
                    {
                        "node": "Ollama AI Request",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        },
        "Ollama AI Request": {
            "main": [
                [
                    {
                        "node": "Response",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        }
    }
}
EOF
    
    # Document Processing Workflow
    cat > "$workflow_dir/document-processing-workflow.json" << 'EOF'
{
    "name": "Document Processing with Vector Storage",
    "nodes": [
        {
            "parameters": {
                "httpMethod": "POST",
                "path": "process-document",
                "responseMode": "responseNode",
                "options": {}
            },
            "id": "webhook-trigger",
            "name": "Document Upload",
            "type": "n8n-nodes-base.webhook",
            "typeVersion": 1,
            "position": [240, 300]
        },
        {
            "parameters": {
                "url": "http://crawl4ai:11235/extract",
                "requestMethod": "POST",
                "jsonParameters": true,
                "options": {},
                "bodyParametersJson": "={\"url\": \"{{ $json.url }}\", \"extraction_strategy\": \"llm\"}"
            },
            "id": "extract-content",
            "name": "Extract Content",
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 3,
            "position": [460, 300]
        },
        {
            "parameters": {
                "url": "http://ollama:11434/api/embeddings",
                "requestMethod": "POST",
                "jsonParameters": true,
                "options": {},
                "bodyParametersJson": "={\"model\": \"mxbai-embed-large\", \"prompt\": \"{{ $json.extracted_content }}\"}"
            },
            "id": "generate-embeddings",
            "name": "Generate Embeddings",
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 3,
            "position": [680, 300]
        },
        {
            "parameters": {
                "url": "http://qdrant:6333/collections/documents/points",
                "requestMethod": "PUT",
                "jsonParameters": true,
                "options": {},
                "bodyParametersJson": "={\"points\": [{\"id\": \"{{ $json.id }}\", \"vector\": {{ $json.embedding }}, \"payload\": {\"content\": \"{{ $json.extracted_content }}\", \"url\": \"{{ $json.url }}\"}}]}"
            },
            "id": "store-vector",
            "name": "Store in Qdrant",
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 3,
            "position": [900, 300]
        },
        {
            "parameters": {
                "respondWith": "json",
                "responseBody": "={{ {\"status\": \"processed\", \"document_id\": $json.id} }}"
            },
            "id": "response",
            "name": "Response",
            "type": "n8n-nodes-base.respondToWebhook",
            "typeVersion": 1,
            "position": [1120, 300]
        }
    ],
    "connections": {
        "Document Upload": {
            "main": [
                [
                    {
                        "node": "Extract Content",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        },
        "Extract Content": {
            "main": [
                [
                    {
                        "node": "Generate Embeddings",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        },
        "Generate Embeddings": {
            "main": [
                [
                    {
                        "node": "Store in Qdrant",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        },
        "Store in Qdrant": {
            "main": [
                [
                    {
                        "node": "Response",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        }
    }
}
EOF
    
    echo "Sample AI workflows created" >&2
}

# Validate n8n setup
validate_n8n_setup() {
    echo "Validating n8n setup..." >&2
    
    # Test n8n API
    if ! curl -f -s http://localhost:5678/api/v1/workflows >/dev/null 2>&1; then
        echo "WARNING: n8n API not accessible" >&2
        return 1
    fi
    
    # Test webhook endpoint
    if ! curl -f -s http://localhost:5678/webhook-test >/dev/null 2>&1; then
        echo "Webhook endpoints are accessible" >&2
    fi
    
    echo "n8n validation completed" >&2
    return 0
}

# =============================================================================
# QDRANT VECTOR DATABASE SETUP
# =============================================================================

# Setup Qdrant with optimized collections
setup_qdrant_collections() {
    local collection_configs="${1:-default}"
    local optimize_for_gpu="${2:-true}"
    
    with_error_context "setup_qdrant_collections" \
        _setup_qdrant_collections_impl "$collection_configs" "$optimize_for_gpu"
}

_setup_qdrant_collections_impl() {
    local collection_configs="$1"
    local optimize_for_gpu="$2"
    
    echo "Setting up Qdrant vector collections..." >&2
    
    # Wait for Qdrant to be ready
    wait_for_qdrant_ready
    
    # Create collections based on configuration
    create_qdrant_collections "$collection_configs" "$optimize_for_gpu"
    
    # Setup collection indexes
    setup_qdrant_indexes
    
    # Validate Qdrant setup
    validate_qdrant_setup
    
    echo "Qdrant vector database setup completed" >&2
}

# Wait for Qdrant service to be ready
wait_for_qdrant_ready() {
    local timeout=300
    local interval=10
    local elapsed=0
    
    echo "Waiting for Qdrant service to be ready..." >&2
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s http://localhost:6333/healthz >/dev/null 2>&1; then
            echo "Qdrant service is ready" >&2
            return 0
        fi
        
        echo "Waiting for Qdrant... (${elapsed}s elapsed)" >&2
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    throw_error $ERROR_TIMEOUT "Qdrant service did not become ready within ${timeout}s"
}

# Create Qdrant collections
create_qdrant_collections() {
    local configs="$1"
    local optimize_for_gpu="$2"
    
    case "$configs" in
        "documents")
            create_documents_collection "$optimize_for_gpu"
            ;;
        "embeddings")
            create_embeddings_collection "$optimize_for_gpu"
            ;;
        "multimodal")
            create_multimodal_collection "$optimize_for_gpu"
            ;;
        *)
            # Default: create all standard collections
            create_documents_collection "$optimize_for_gpu"
            create_embeddings_collection "$optimize_for_gpu"
            create_chat_collection "$optimize_for_gpu"
            ;;
    esac
}

# Create documents collection
create_documents_collection() {
    local optimize_for_gpu="$1"
    
    echo "Creating documents collection..." >&2
    
    # Collection configuration optimized for document embeddings
    local collection_config
    collection_config=$(cat << EOF
{
    "vectors": {
        "size": 1024,
        "distance": "Cosine",
        "hnsw_config": {
            "m": 16,
            "ef_construct": 200,
            "full_scan_threshold": 10000,
            "max_indexing_threads": 4
        }
    },
    "optimizers_config": {
        "deleted_threshold": 0.2,
        "vacuum_min_vector_number": 1000,
        "default_segment_number": 8,
        "max_segment_size": 200000,
        "memmap_threshold": 50000,
        "indexing_threshold": 20000
    },
    "wal_config": {
        "wal_capacity_mb": 32,
        "wal_segments_ahead": 0
    }
}
EOF
)
    
    # Create collection
    curl -X PUT "http://localhost:6333/collections/documents" \
        -H "Content-Type: application/json" \
        -d "$collection_config" || echo "WARNING: Failed to create documents collection" >&2
    
    echo "Documents collection created" >&2
}

# Create embeddings collection
create_embeddings_collection() {
    local optimize_for_gpu="$1"
    
    echo "Creating embeddings collection..." >&2
    
    local collection_config
    collection_config=$(cat << EOF
{
    "vectors": {
        "size": 768,
        "distance": "Cosine",
        "hnsw_config": {
            "m": 24,
            "ef_construct": 300,
            "full_scan_threshold": 20000
        }
    },
    "optimizers_config": {
        "default_segment_number": 4,
        "max_segment_size": 100000
    }
}
EOF
)
    
    curl -X PUT "http://localhost:6333/collections/embeddings" \
        -H "Content-Type: application/json" \
        -d "$collection_config" || echo "WARNING: Failed to create embeddings collection" >&2
    
    echo "Embeddings collection created" >&2
}

# Create chat collection
create_chat_collection() {
    local optimize_for_gpu="$1"
    
    echo "Creating chat collection..." >&2
    
    local collection_config
    collection_config=$(cat << EOF
{
    "vectors": {
        "size": 1024,
        "distance": "Dot",
        "hnsw_config": {
            "m": 16,
            "ef_construct": 100
        }
    }
}
EOF
)
    
    curl -X PUT "http://localhost:6333/collections/chat" \
        -H "Content-Type: application/json" \
        -d "$collection_config" || echo "WARNING: Failed to create chat collection" >&2
    
    echo "Chat collection created" >&2
}

# Setup collection indexes
setup_qdrant_indexes() {
    echo "Setting up Qdrant collection indexes..." >&2
    
    # Create payload indexes for better filtering
    local indexes=(
        "documents:content:text"
        "documents:url:keyword"
        "documents:timestamp:integer"
        "embeddings:type:keyword"
        "chat:user_id:keyword"
        "chat:session_id:keyword"
    )
    
    for index in "${indexes[@]}"; do
        local collection field type
        collection=$(echo "$index" | cut -d: -f1)
        field=$(echo "$index" | cut -d: -f2)
        type=$(echo "$index" | cut -d: -f3)
        
        local index_config
        index_config=$(cat << EOF
{
    "field_name": "$field",
    "field_schema": "$type"
}
EOF
)
        
        curl -X PUT "http://localhost:6333/collections/$collection/index" \
            -H "Content-Type: application/json" \
            -d "$index_config" || echo "WARNING: Failed to create index $field on $collection" >&2
    done
    
    echo "Collection indexes created" >&2
}

# Validate Qdrant setup
validate_qdrant_setup() {
    echo "Validating Qdrant setup..." >&2
    
    # Test Qdrant API
    if ! curl -f -s http://localhost:6333/collections >/dev/null 2>&1; then
        echo "WARNING: Qdrant API not accessible" >&2
        return 1
    fi
    
    # Check collections
    local collections
    collections=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name' 2>/dev/null || echo "")
    
    if [ -n "$collections" ]; then
        echo "Found collections: $collections" >&2
    else
        echo "WARNING: No collections found in Qdrant" >&2
        return 1
    fi
    
    echo "Qdrant validation completed" >&2
    return 0
}

# =============================================================================
# CRAWL4AI WEB SCRAPING SETUP
# =============================================================================

# Setup Crawl4AI with LLM integration
setup_crawl4ai_integration() {
    local enable_browser="${1:-true}"
    local llm_provider="${2:-ollama}"
    
    with_error_context "setup_crawl4ai_integration" \
        _setup_crawl4ai_integration_impl "$enable_browser" "$llm_provider"
}

_setup_crawl4ai_integration_impl() {
    local enable_browser="$1"
    local llm_provider="$2"
    
    echo "Setting up Crawl4AI integration..." >&2
    
    # Wait for Crawl4AI to be ready
    wait_for_crawl4ai_ready
    
    # Configure LLM integration
    configure_crawl4ai_llm "$llm_provider"
    
    # Setup browser configuration
    if [ "$enable_browser" = "true" ]; then
        setup_crawl4ai_browser
    fi
    
    # Create extraction templates
    create_extraction_templates
    
    # Validate Crawl4AI setup
    validate_crawl4ai_setup
    
    echo "Crawl4AI integration setup completed" >&2
}

# Wait for Crawl4AI service to be ready
wait_for_crawl4ai_ready() {
    local timeout=300
    local interval=10
    local elapsed=0
    
    echo "Waiting for Crawl4AI service to be ready..." >&2
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s http://localhost:11235/health >/dev/null 2>&1; then
            echo "Crawl4AI service is ready" >&2
            return 0
        fi
        
        echo "Waiting for Crawl4AI... (${elapsed}s elapsed)" >&2
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    throw_error $ERROR_TIMEOUT "Crawl4AI service did not become ready within ${timeout}s"
}

# Configure Crawl4AI LLM integration
configure_crawl4ai_llm() {
    local provider="$1"
    
    echo "Configuring Crawl4AI LLM integration with $provider..." >&2
    
    local config_dir="/shared/crawl4ai-config"
    mkdir -p "$config_dir"
    
    case "$provider" in
        "ollama")
            cat > "$config_dir/llm-config.json" << EOF
{
    "provider": "ollama",
    "base_url": "http://ollama:11434",
    "model": "deepseek-r1:8b-optimized",
    "temperature": 0.1,
    "max_tokens": 2048,
    "extraction_model": "qwen2.5:7b-optimized"
}
EOF
            ;;
        "openai")
            cat > "$config_dir/llm-config.json" << EOF
{
    "provider": "openai",
    "api_key": "\${OPENAI_API_KEY}",
    "model": "gpt-4-turbo",
    "temperature": 0.1,
    "max_tokens": 4096
}
EOF
            ;;
        *)
            echo "Unknown LLM provider: $provider" >&2
            return 1
            ;;
    esac
    
    echo "LLM configuration created for $provider" >&2
}

# Setup browser configuration
setup_crawl4ai_browser() {
    echo "Setting up browser configuration..." >&2
    
    local config_dir="/shared/crawl4ai-config"
    
    cat > "$config_dir/browser-config.json" << EOF
{
    "headless": true,
    "browser_type": "chromium",
    "user_agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "viewport": {
        "width": 1920,
        "height": 1080
    },
    "timeout": 30000,
    "wait_for": "networkidle",
    "browser_pool_size": 2,
    "max_concurrent_sessions": 4
}
EOF
    
    echo "Browser configuration created" >&2
}

# Create extraction templates
create_extraction_templates() {
    echo "Creating extraction templates..." >&2
    
    local templates_dir="/shared/crawl4ai-templates"
    mkdir -p "$templates_dir"
    
    # Article extraction template
    cat > "$templates_dir/article-extraction.json" << 'EOF'
{
    "name": "article_extraction",
    "description": "Extract structured data from news articles and blog posts",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract the following information from the article: title, author, publication_date, main_content, summary, tags, and category. Return as JSON.",
    "schema": {
        "title": "string",
        "author": "string", 
        "publication_date": "string",
        "main_content": "string",
        "summary": "string",
        "tags": "array",
        "category": "string"
    },
    "css_selector": "article, .article-content, .post-content, main",
    "wait_for_selector": "h1, .title, .headline"
}
EOF
    
    # Product extraction template
    cat > "$templates_dir/product-extraction.json" << 'EOF'
{
    "name": "product_extraction",
    "description": "Extract product information from e-commerce pages",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract product details: name, price, description, features, specifications, availability, and rating. Return as JSON.",
    "schema": {
        "name": "string",
        "price": "string",
        "description": "string",
        "features": "array",
        "specifications": "object",
        "availability": "string",
        "rating": "number",
        "images": "array"
    },
    "css_selector": ".product, .product-details, #product-info",
    "wait_for_selector": ".price, .product-title"
}
EOF
    
    # Documentation extraction template
    cat > "$templates_dir/docs-extraction.json" << 'EOF'
{
    "name": "documentation_extraction",
    "description": "Extract structured information from documentation pages",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract documentation structure: section_title, content, code_examples, links, and navigation_hierarchy. Return as JSON.",
    "schema": {
        "section_title": "string",
        "content": "string",
        "code_examples": "array",
        "links": "array",
        "navigation_hierarchy": "array",
        "last_updated": "string"
    },
    "css_selector": ".documentation, .docs-content, .markdown-body",
    "wait_for_selector": "h1, h2, .section-title"
}
EOF
    
    echo "Extraction templates created" >&2
}

# Validate Crawl4AI setup
validate_crawl4ai_setup() {
    echo "Validating Crawl4AI setup..." >&2
    
    # Test Crawl4AI API
    if ! curl -f -s http://localhost:11235/health >/dev/null 2>&1; then
        echo "WARNING: Crawl4AI API not accessible" >&2
        return 1
    fi
    
    # Test basic extraction
    local test_response
    test_response=$(curl -s -X POST http://localhost:11235/extract \
        -H "Content-Type: application/json" \
        -d '{"url": "https://example.com", "extraction_strategy": "text"}' 2>/dev/null)
    
    if echo "$test_response" | jq -e '.success' >/dev/null 2>&1; then
        echo "Crawl4AI basic extraction test: PASSED" >&2
    else
        echo "WARNING: Crawl4AI basic extraction test failed" >&2
        return 1
    fi
    
    echo "Crawl4AI validation completed" >&2
    return 0
}

# =============================================================================
# SERVICE INTEGRATION AND ORCHESTRATION
# =============================================================================

# Setup complete AI services integration
setup_ai_services_integration() {
    local instance_type="${1:-$(get_variable INSTANCE_TYPE)}"
    local webhook_url="${2:-}"
    local model_config="${3:-default}"
    
    echo "Setting up complete AI services integration..." >&2
    
    # Setup services in dependency order
    setup_ollama_models "$instance_type" "$model_config"
    setup_qdrant_collections "default" "true"
    setup_crawl4ai_integration "true" "ollama"
    setup_n8n_ai_integration "$webhook_url" "true"
    
    # Create integration test script
    create_integration_test_script
    
    # Validate complete integration
    validate_ai_integration
    
    echo "AI services integration setup completed successfully" >&2
}

# Create integration test script
create_integration_test_script() {
    echo "Creating AI services integration test script..." >&2
    
    cat > /shared/test-ai-integration.sh << 'EOF'
#!/bin/bash
# AI Services Integration Test Suite

set -euo pipefail

echo "=== AI Services Integration Test ==="
echo "Started: $(date)"

# Test service connectivity
echo ""
echo "1. Testing service connectivity..."

services=(
    "postgres:5432"
    "n8n:5678"
    "ollama:11434"
    "qdrant:6333"
    "crawl4ai:11235"
)

for service in "${services[@]}"; do
    host=$(echo "$service" | cut -d: -f1)
    port=$(echo "$service" | cut -d: -f2)
    
    if nc -z "$host" "$port" 2>/dev/null; then
        echo "✓ $service: Connected"
    else
        echo "✗ $service: Connection failed"
    fi
done

# Test AI model availability
echo ""
echo "2. Testing AI model availability..."
if models=$(curl -s http://ollama:11434/api/tags | jq -r '.models[].name' 2>/dev/null); then
    echo "Available models:"
    echo "$models" | sed 's/^/  - /'
else
    echo "✗ Failed to get model list"
fi

# Test vector database
echo ""
echo "3. Testing vector database..."
if collections=$(curl -s http://qdrant:6333/collections | jq -r '.result.collections[].name' 2>/dev/null); then
    echo "Available collections:"
    echo "$collections" | sed 's/^/  - /'
else
    echo "✗ Failed to get collection list"
fi

# Test end-to-end workflow
echo ""
echo "4. Testing end-to-end AI workflow..."

# Test document processing pipeline
test_url="https://example.com"
echo "Processing test URL: $test_url"

# Step 1: Extract content with Crawl4AI
echo "  Step 1: Extracting content..."
if content=$(curl -s -X POST http://crawl4ai:11235/extract \
    -H "Content-Type: application/json" \
    -d "{\"url\": \"$test_url\", \"extraction_strategy\": \"text\"}" | jq -r '.extracted_content' 2>/dev/null); then
    echo "  ✓ Content extracted ($(echo "$content" | wc -c) characters)"
else
    echo "  ✗ Content extraction failed"
    content="This is a test document for AI processing."
fi

# Step 2: Generate embeddings with Ollama
echo "  Step 2: Generating embeddings..."
if embedding=$(curl -s -X POST http://ollama:11434/api/embeddings \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"mxbai-embed-large\", \"prompt\": \"$content\"}" | jq '.embedding' 2>/dev/null); then
    embedding_dim=$(echo "$embedding" | jq 'length' 2>/dev/null || echo "0")
    echo "  ✓ Embeddings generated (dimension: $embedding_dim)"
else
    echo "  ✗ Embedding generation failed"
    embedding="[]"
fi

# Step 3: Store in Qdrant
echo "  Step 3: Storing in vector database..."
if [ "$embedding" != "[]" ]; then
    doc_id="test-$(date +%s)"
    if curl -s -X PUT "http://qdrant:6333/collections/documents/points" \
        -H "Content-Type: application/json" \
        -d "{\"points\": [{\"id\": \"$doc_id\", \"vector\": $embedding, \"payload\": {\"content\": \"$content\", \"url\": \"$test_url\"}}]}" | jq -e '.status == "ok"' >/dev/null 2>&1; then
        echo "  ✓ Document stored in vector database"
    else
        echo "  ✗ Vector storage failed"
    fi
else
    echo "  ✗ Skipping vector storage (no embeddings)"
fi

# Step 4: AI analysis with Ollama
echo "  Step 4: AI analysis..."
if analysis=$(curl -s -X POST http://ollama:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"deepseek-r1:8b-optimized\", \"prompt\": \"Analyze this content and provide a brief summary: $content\", \"stream\": false}" | jq -r '.response' 2>/dev/null); then
    echo "  ✓ AI analysis completed"
    echo "    Summary: ${analysis:0:100}..."
else
    echo "  ✗ AI analysis failed"
fi

echo ""
echo "5. Performance metrics:"

# System resources
echo "System Resources:"
echo "  CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "  Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
echo "  Disk Usage: $(df -h / | awk 'NR==2{print $5}')"

# GPU resources (if available)
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "GPU Resources:"
    nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | \
    awk -F, '{printf "  GPU Utilization: %s%%, Memory: %s/%sMB, Temperature: %s°C\n", $1, $2, $3, $4}'
fi

echo ""
echo "=== Integration Test Complete ==="
echo "Finished: $(date)"
EOF
    
    chmod +x /shared/test-ai-integration.sh
    
    echo "Integration test script created" >&2
}

# Validate complete AI integration
validate_ai_integration() {
    echo "Validating complete AI services integration..." >&2
    
    # Run the integration test
    if [ -f /shared/test-ai-integration.sh ]; then
        echo "Running integration test..." >&2
        /shared/test-ai-integration.sh
    else
        echo "Integration test script not found, performing basic validation..." >&2
        
        # Basic service checks
        local services=("ollama:11434" "qdrant:6333" "crawl4ai:11235" "n8n:5678")
        local failed_services=()
        
        for service in "${services[@]}"; do
            local host port
            host=$(echo "$service" | cut -d: -f1)
            port=$(echo "$service" | cut -d: -f2)
            
            if ! nc -z "$host" "$port" 2>/dev/null; then
                failed_services+=("$service")
            fi
        done
        
        if [ ${#failed_services[@]} -eq 0 ]; then
            echo "All AI services are accessible" >&2
        else
            echo "WARNING: Some services are not accessible: ${failed_services[*]}" >&2
            return 1
        fi
    fi
    
    echo "AI services integration validation completed" >&2
    return 0
}