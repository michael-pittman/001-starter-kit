#!/usr/bin/env bash
# ==============================================================================
# Module: Ollama Service Management
# Description: Manages Ollama model deployment, configuration, and optimization
# 
# Functions:
#   - setup_ollama_models()       Configure and deploy AI models
#   - wait_for_ollama_ready()     Wait for service availability
#   - get_gpu_capabilities()      Detect GPU configuration
#   - download_and_optimize_models() Download and configure models
#   - validate_ollama_models()    Verify model deployment
#
# Dependencies:
#   - core/registry              Resource registration
#   - core/errors               Error handling
#   - config/variables          Configuration management
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${__OLLAMA_MODULE_LOADED:-}" ]] && return 0
readonly __OLLAMA_MODULE_LOADED=1

# ==============================================================================
# DEPENDENCIES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh" || return 1
source "${SCRIPT_DIR}/../core/errors.sh" || return 1
source "${SCRIPT_DIR}/../config/variables.sh" || return 1
source "${SCRIPT_DIR}/../core/logging.sh" || return 1

# ==============================================================================
# CONSTANTS
# ==============================================================================
readonly OLLAMA_PORT=11434
readonly OLLAMA_API_URL="http://localhost:${OLLAMA_PORT}/api"
readonly OLLAMA_DEFAULT_TIMEOUT=600
readonly OLLAMA_HEALTH_CHECK_INTERVAL=10

# Model configurations by instance type
declare -A OLLAMA_MODEL_CONFIGS=(
    ["g4dn.xlarge"]="deepseek-r1:8b,qwen2.5:7b"
    ["g5.xlarge"]="deepseek-r1:8b,qwen2.5:7b,llama3.2:3b"
    ["g5.2xlarge"]="deepseek-r1:14b,qwen2.5:14b,llama3.2:7b"
    ["g4ad.xlarge"]="deepseek-r1:8b,qwen2.5:7b"
    ["default"]="deepseek-r1:8b"
)

# ==============================================================================
# PUBLIC FUNCTIONS
# ==============================================================================

# Setup Ollama with optimized AI models
# Arguments:
#   $1 - Instance type (optional, uses INSTANCE_TYPE if not provided)
#   $2 - Models configuration (optional, default: "default")
#   $3 - Wait timeout in seconds (optional, default: 600)
# Returns:
#   0 - Success
#   1 - Service timeout
#   2 - Model download failure
#   3 - Validation failure
setup_ollama_models() {
    local instance_type="${1:-$(get_variable INSTANCE_TYPE)}"
    local models_config="${2:-default}"
    local wait_timeout="${3:-$OLLAMA_DEFAULT_TIMEOUT}"
    
    with_error_context "setup_ollama_models" \
        _setup_ollama_models_impl "$instance_type" "$models_config" "$wait_timeout"
}

# Wait for Ollama service to be ready
# Arguments:
#   $1 - Timeout in seconds (optional, default: 300)
# Returns:
#   0 - Service ready
#   1 - Timeout reached
wait_for_ollama_ready() {
    local timeout="${1:-300}"
    local interval=$OLLAMA_HEALTH_CHECK_INTERVAL
    local elapsed=0
    
    log_info "[OLLAMA] Waiting for service to be ready (timeout: ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s "${OLLAMA_API_URL}/tags" >/dev/null 2>&1; then
            log_info "[OLLAMA] Service is ready"
            return 0
        fi
        
        log_debug "[OLLAMA] Waiting for service... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "[OLLAMA] Service did not become ready within ${timeout}s"
    return 1
}

# Get GPU capabilities for the instance
# Arguments:
#   $1 - Instance type
# Returns:
#   0 - Success
# Output:
#   JSON object with GPU capabilities
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
        g5.xlarge)
            cat << EOF
{
    "gpu_type": "A10G",
    "gpu_memory_gb": 24,
    "gpu_count": 1,
    "max_models": 3,
    "memory_fraction": 0.90,
    "recommended_models": ["deepseek-r1:14b", "qwen2.5:14b", "llama3.2:7b"]
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
    "recommended_models": ["deepseek-r1:14b", "qwen2.5:14b", "llama3.2:7b", "mixtral:8x7b"]
}
EOF
            ;;
        g4ad.xlarge)
            cat << EOF
{
    "gpu_type": "Radeon Pro V520",
    "gpu_memory_gb": 8,
    "gpu_count": 1,
    "max_models": 2,
    "memory_fraction": 0.80,
    "recommended_models": ["deepseek-r1:8b", "qwen2.5:7b"]
}
EOF
            ;;
        *)
            cat << EOF
{
    "gpu_type": "none",
    "gpu_memory_gb": 0,
    "gpu_count": 0,
    "max_models": 1,
    "memory_fraction": 0.50,
    "recommended_models": ["deepseek-r1:8b"]
}
EOF
            ;;
    esac
}

# Download and optimize models
# Arguments:
#   $1 - Comma-separated list of models
#   $2 - GPU info JSON (optional)
# Returns:
#   0 - Success
#   1 - Download failure
download_and_optimize_models() {
    local model_list="$1"
    local gpu_info="${2:-}"
    
    log_info "[OLLAMA] Downloading and optimizing models: $model_list"
    
    # Parse model list
    IFS=',' read -ra models <<< "$model_list"
    
    for model in "${models[@]}"; do
        log_info "[OLLAMA] Pulling model: $model"
        
        if ! docker exec ollama ollama pull "$model" 2>&1; then
            log_error "[OLLAMA] Failed to pull model: $model"
            return 1
        fi
        
        # Register model in resource registry
        register_resource "ollama_model" "$model" "model=$model"
    done
    
    # Configure GPU optimization if available
    if [[ -n "$gpu_info" ]] && command -v jq &>/dev/null; then
        local gpu_memory
        gpu_memory=$(echo "$gpu_info" | jq -r '.gpu_memory_gb // 0')
        
        if [[ "$gpu_memory" -gt 0 ]]; then
            _configure_gpu_optimization "$gpu_info"
        fi
    fi
    
    return 0
}

# Validate Ollama model deployment
# Returns:
#   0 - All models valid
#   1 - Validation failure
validate_ollama_models() {
    log_info "[OLLAMA] Validating model deployment..."
    
    # Get list of loaded models
    local models_json
    if ! models_json=$(curl -s "${OLLAMA_API_URL}/tags" 2>/dev/null); then
        log_error "[OLLAMA] Failed to query model list"
        return 1
    fi
    
    # Check if models are loaded
    if command -v jq &>/dev/null; then
        local model_count
        model_count=$(echo "$models_json" | jq '.models | length')
        
        if [[ "$model_count" -eq 0 ]]; then
            log_error "[OLLAMA] No models loaded"
            return 1
        fi
        
        log_info "[OLLAMA] Found $model_count loaded models"
        
        # Test each model
        echo "$models_json" | jq -r '.models[].name' | while read -r model; do
            if ! _test_model_response "$model"; then
                log_error "[OLLAMA] Model test failed: $model"
                return 1
            fi
        done
    else
        # Fallback validation without jq
        if ! echo "$models_json" | grep -q '"name"'; then
            log_error "[OLLAMA] No models found in response"
            return 1
        fi
    fi
    
    log_info "[OLLAMA] Model validation completed successfully"
    return 0
}

# Create model test scripts
create_model_test_scripts() {
    local script_dir="/opt/ai-stack/scripts"
    
    log_info "[OLLAMA] Creating model test scripts..."
    
    # Ensure directory exists
    docker exec ollama mkdir -p "$script_dir" 2>/dev/null || true
    
    # Create test script
    docker exec ollama bash -c "cat > $script_dir/test-models.sh << 'EOF'
#!/bin/bash
# Test all loaded Ollama models

echo 'Testing Ollama models...'

# Get list of models
models=\$(ollama list | tail -n +2 | awk '{print \$1}')

for model in \$models; do
    echo -n \"Testing \$model... \"
    
    # Simple test prompt
    response=\$(ollama run \$model 'Say hello' --verbose 2>&1)
    
    if [ \$? -eq 0 ]; then
        echo \"OK\"
    else
        echo \"FAILED\"
        echo \"Error: \$response\"
    fi
done

echo 'Model testing complete'
EOF"
    
    # Make executable
    docker exec ollama chmod +x "$script_dir/test-models.sh"
    
    log_info "[OLLAMA] Test scripts created"
}

# ==============================================================================
# PRIVATE FUNCTIONS
# ==============================================================================

# Implementation of setup_ollama_models
_setup_ollama_models_impl() {
    local instance_type="$1"
    local models_config="$2"
    local wait_timeout="$3"
    
    log_info "[OLLAMA] Setting up models for instance type: $instance_type"
    
    # Wait for service
    if ! wait_for_ollama_ready "$wait_timeout"; then
        throw_error $ERROR_TIMEOUT "Ollama service timeout"
    fi
    
    # Get GPU capabilities
    local gpu_info
    gpu_info=$(get_gpu_capabilities "$instance_type")
    
    # Determine model list
    local model_list="${OLLAMA_MODEL_CONFIGS[$instance_type]:-${OLLAMA_MODEL_CONFIGS[default]}}"
    
    # Override with custom config if provided
    if [[ "$models_config" != "default" ]]; then
        model_list="$models_config"
    fi
    
    # Download models
    if ! download_and_optimize_models "$model_list" "$gpu_info"; then
        throw_error $ERROR_DEPLOYMENT_FAILED "Model download failed"
    fi
    
    # Create test scripts
    create_model_test_scripts
    
    # Validate deployment
    if ! validate_ollama_models; then
        throw_error $ERROR_VALIDATION_FAILED "Model validation failed"
    fi
    
    log_info "[OLLAMA] Model setup completed successfully"
}

# Configure GPU optimization settings
_configure_gpu_optimization() {
    local gpu_info="$1"
    
    if ! command -v jq &>/dev/null; then
        return 0
    fi
    
    local gpu_memory
    local memory_fraction
    
    gpu_memory=$(echo "$gpu_info" | jq -r '.gpu_memory_gb // 0')
    memory_fraction=$(echo "$gpu_info" | jq -r '.memory_fraction // 0.85')
    
    # Set environment variables for GPU optimization
    docker exec ollama bash -c "
        echo 'OLLAMA_GPU_MEMORY_FRACTION=$memory_fraction' >> /etc/environment
        echo 'OLLAMA_NUM_GPU=1' >> /etc/environment
    "
    
    log_info "[OLLAMA] Configured GPU optimization (memory: ${gpu_memory}GB, fraction: $memory_fraction)"
}

# Test model response
_test_model_response() {
    local model="$1"
    local test_prompt="Say 'test successful' in 5 words or less"
    
    log_debug "[OLLAMA] Testing model response: $model"
    
    # Send test request
    local response
    response=$(curl -s -X POST "${OLLAMA_API_URL}/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model\", \"prompt\": \"$test_prompt\", \"stream\": false}" \
        --max-time 30 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        return 1
    fi
    
    # Check for response field
    if echo "$response" | grep -q '"response"'; then
        log_debug "[OLLAMA] Model $model responded successfully"
        return 0
    fi
    
    return 1
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================
log_debug "[OLLAMA] Module loaded successfully"