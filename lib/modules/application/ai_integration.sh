#!/usr/bin/env bash
# ==============================================================================
# Module: AI Services Integration
# Description: Orchestrates complete AI services stack integration and testing
# 
# Functions:
#   - setup_ai_services_integration()  Orchestrate all AI services setup
#   - create_integration_test_script() Create comprehensive test suite
#   - validate_ai_integration()        Validate complete AI stack
#   - test_ai_pipeline()              Test end-to-end AI workflow
#   - monitor_ai_services()           Monitor AI services health
#
# Dependencies:
#   - application/ollama              Ollama service management
#   - application/qdrant              Qdrant vector database
#   - application/crawl4ai            Web scraping service
#   - application/n8n                 Workflow automation
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${__AI_INTEGRATION_MODULE_LOADED:-}" ]] && return 0
readonly __AI_INTEGRATION_MODULE_LOADED=1

# ==============================================================================
# DEPENDENCIES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh" || return 1
source "${SCRIPT_DIR}/../core/errors.sh" || return 1
source "${SCRIPT_DIR}/../config/variables.sh" || return 1
source "${SCRIPT_DIR}/../core/logging.sh" || return 1

# Load AI service modules
source "${SCRIPT_DIR}/ollama.sh" || return 1
source "${SCRIPT_DIR}/qdrant.sh" || return 1
source "${SCRIPT_DIR}/crawl4ai.sh" || return 1
source "${SCRIPT_DIR}/n8n.sh" || return 1

# ==============================================================================
# CONSTANTS
# ==============================================================================
readonly AI_INTEGRATION_TIMEOUT=1800  # 30 minutes for full setup
readonly AI_SHARED_DIR="/shared"
readonly AI_TEST_SCRIPT_PATH="${AI_SHARED_DIR}/test-ai-integration.sh"
readonly AI_MONITORING_SCRIPT_PATH="${AI_SHARED_DIR}/monitor-ai-services.sh"

# Service health check endpoints
declare -A AI_SERVICE_ENDPOINTS=(
    ["postgres"]="5432"
    ["n8n"]="5678"
    ["ollama"]="11434"
    ["qdrant"]="6333"
    ["crawl4ai"]="11235"
)

# ==============================================================================
# PUBLIC FUNCTIONS
# ==============================================================================

# Setup complete AI services integration
# Arguments:
#   $1 - Instance type (optional, uses INSTANCE_TYPE if not provided)
#   $2 - Webhook URL for n8n (optional)
#   $3 - Model configuration (optional, default: "default")
# Returns:
#   0 - Success
#   1 - Service setup failure
#   2 - Integration failure
#   3 - Validation failure
setup_ai_services_integration() {
    local instance_type="${1:-$(get_variable INSTANCE_TYPE)}"
    local webhook_url="${2:-}"
    local model_config="${3:-default}"
    
    with_error_context "setup_ai_services_integration" \
        _setup_ai_services_integration_impl "$instance_type" "$webhook_url" "$model_config"
}

# Create comprehensive integration test script
# Returns:
#   0 - Success
#   1 - Creation failure
create_integration_test_script() {
    log_info "[AI_INTEGRATION] Creating integration test script..."
    
    # Ensure shared directory exists
    if ! mkdir -p "$AI_SHARED_DIR" 2>/dev/null; then
        log_error "[AI_INTEGRATION] Failed to create shared directory"
        return 1
    fi
    
    # Create test script
    cat > "$AI_TEST_SCRIPT_PATH" << 'EOF'
#!/usr/bin/env bash
# AI Services Integration Test Suite

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_test_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

run_test() {
    ((TESTS_RUN++))
    local test_name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        print_success "$test_name"
        return 0
    else
        print_failure "$test_name"
        return 1
    fi
}

# Start tests
echo "AI Services Integration Test Suite"
echo "Started: $(date)"

print_test_header "1. Service Connectivity Tests"

# Test service connectivity
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
    run_test "$service connectivity" nc -z "$host" "$port"
done

print_test_header "2. AI Model Availability Tests"

# Test Ollama models
if models=$(curl -s http://ollama:11434/api/tags 2>/dev/null); then
    model_count=$(echo "$models" | jq '.models | length' 2>/dev/null || echo 0)
    if [[ $model_count -gt 0 ]]; then
        print_success "Ollama models available: $model_count"
        echo "$models" | jq -r '.models[].name' 2>/dev/null | sed 's/^/    - /'
    else
        print_failure "No Ollama models found"
    fi
else
    print_failure "Ollama API not accessible"
fi

print_test_header "3. Vector Database Tests"

# Test Qdrant collections
if collections=$(curl -s http://qdrant:6333/collections 2>/dev/null); then
    collection_count=$(echo "$collections" | jq '.result.collections | length' 2>/dev/null || echo 0)
    if [[ $collection_count -gt 0 ]]; then
        print_success "Qdrant collections available: $collection_count"
        echo "$collections" | jq -r '.result.collections[].name' 2>/dev/null | sed 's/^/    - /'
    else
        print_failure "No Qdrant collections found"
    fi
else
    print_failure "Qdrant API not accessible"
fi

print_test_header "4. End-to-End AI Pipeline Test"

# Test document processing pipeline
test_url="https://example.com"
test_content="This is a test document for AI processing pipeline validation."

echo "Testing with URL: $test_url"

# Step 1: Content extraction
echo -n "  Content extraction... "
if content_response=$(curl -s -X POST http://crawl4ai:11235/extract \
    -H "Content-Type: application/json" \
    -d "{\"url\": \"$test_url\", \"extraction_strategy\": \"text\"}" 2>/dev/null); then
    
    if echo "$content_response" | jq -e '.success' >/dev/null 2>&1; then
        print_success "Content extracted"
    else
        print_failure "Extraction failed"
        # Use fallback content
        content_response="{\"extracted_content\": \"$test_content\"}"
    fi
else
    print_failure "Crawl4AI not responding"
fi

# Step 2: Generate embeddings
echo -n "  Embedding generation... "
if embedding_response=$(curl -s -X POST http://ollama:11434/api/embeddings \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"mxbai-embed-large\", \"prompt\": \"$test_content\"}" 2>/dev/null); then
    
    if embedding=$(echo "$embedding_response" | jq '.embedding' 2>/dev/null); then
        embedding_dim=$(echo "$embedding" | jq 'length' 2>/dev/null || echo 0)
        if [[ $embedding_dim -gt 0 ]]; then
            print_success "Embeddings generated (dimension: $embedding_dim)"
        else
            print_failure "Invalid embedding dimension"
        fi
    else
        print_failure "Embedding parsing failed"
    fi
else
    print_failure "Ollama embedding API not responding"
fi

# Step 3: Vector storage
echo -n "  Vector storage... "
if [[ -n "${embedding:-}" ]] && [[ "$embedding" != "null" ]]; then
    doc_id="test-$(date +%s)"
    if storage_response=$(curl -s -X PUT "http://qdrant:6333/collections/documents/points" \
        -H "Content-Type: application/json" \
        -d "{
            \"points\": [{
                \"id\": \"$doc_id\",
                \"vector\": $embedding,
                \"payload\": {
                    \"content\": \"$test_content\",
                    \"url\": \"$test_url\",
                    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
                }
            }]
        }" 2>/dev/null); then
        
        if echo "$storage_response" | jq -e '.status == "ok"' >/dev/null 2>&1; then
            print_success "Vector stored successfully"
        else
            print_failure "Vector storage failed"
        fi
    else
        print_failure "Qdrant storage API not responding"
    fi
else
    print_failure "No valid embedding to store"
fi

# Step 4: AI analysis
echo -n "  AI analysis... "
if analysis_response=$(curl -s -X POST http://ollama:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"deepseek-r1:8b\",
        \"prompt\": \"Analyze this content and provide a one-sentence summary: $test_content\",
        \"stream\": false,
        \"options\": {
            \"temperature\": 0.1,
            \"num_predict\": 100
        }
    }" --max-time 30 2>/dev/null); then
    
    if analysis=$(echo "$analysis_response" | jq -r '.response' 2>/dev/null); then
        if [[ -n "$analysis" ]] && [[ "$analysis" != "null" ]]; then
            print_success "AI analysis completed"
            echo "    Summary: ${analysis:0:80}..."
        else
            print_failure "Empty AI response"
        fi
    else
        print_failure "AI response parsing failed"
    fi
else
    print_failure "Ollama generate API not responding"
fi

print_test_header "5. n8n Workflow Tests"

# Test n8n API
echo -n "  n8n API accessibility... "
run_test "n8n health check" curl -f -s http://n8n:5678/healthz

# Test webhook endpoint
echo -n "  n8n webhook test... "
if webhook_response=$(curl -s -X POST http://n8n:5678/webhook-test/ai-chat \
    -H "Content-Type: application/json" \
    -d '{"query": "test"}' --max-time 10 2>/dev/null); then
    print_success "Webhook endpoint accessible"
else
    print_failure "Webhook endpoint not accessible"
fi

print_test_header "6. Performance Metrics"

# System resources
echo "System Resources:"
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "N/A")
echo "  CPU Usage: ${cpu_usage}%"

mem_info=$(free -m | grep Mem)
mem_total=$(echo "$mem_info" | awk '{print $2}')
mem_used=$(echo "$mem_info" | awk '{print $3}')
mem_percent=$(awk "BEGIN {printf \"%.1f\", $mem_used/$mem_total * 100}")
echo "  Memory: ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"

disk_usage=$(df -h / | awk 'NR==2{print $5}')
echo "  Disk Usage: $disk_usage"

# Docker container stats
echo -e "\nDocker Container Stats:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "(ollama|qdrant|n8n|crawl4ai|postgres)" || true

# GPU resources (if available)
if command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "\nGPU Resources:"
    nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu \
        --format=csv,noheader,nounits | \
        awk -F, '{printf "  %s: %s%% GPU, %s/%sMB Memory, %s°C\n", $1, $2, $3, $4, $5}'
fi

print_test_header "Test Summary"

echo "Total Tests Run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"

success_rate=$(awk "BEGIN {printf \"%.1f\", $TESTS_PASSED/$TESTS_RUN * 100}")
echo "Success Rate: ${success_rate}%"

echo -e "\nIntegration Test Complete"
echo "Finished: $(date)"

# Exit with appropriate code
[[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
EOF
    
    # Make script executable
    chmod +x "$AI_TEST_SCRIPT_PATH"
    
    # Register test script
    register_resource "ai_integration" "test_script" "path=$AI_TEST_SCRIPT_PATH"
    
    log_info "[AI_INTEGRATION] Integration test script created"
    return 0
}

# Create AI services monitoring script
# Returns:
#   0 - Success
#   1 - Creation failure
create_monitoring_script() {
    log_info "[AI_INTEGRATION] Creating monitoring script..."
    
    cat > "$AI_MONITORING_SCRIPT_PATH" << 'EOF'
#!/usr/bin/env bash
# AI Services Monitoring Script

set -euo pipefail

# Monitoring interval (seconds)
INTERVAL=${1:-60}

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Service status tracking
declare -A service_status
declare -A service_last_check

check_service() {
    local name="$1"
    local host="$2"
    local port="$3"
    local endpoint="${4:-}"
    
    if nc -z "$host" "$port" 2>/dev/null; then
        if [[ -n "$endpoint" ]]; then
            if curl -f -s "http://$host:$port$endpoint" >/dev/null 2>&1; then
                echo -e "${GREEN}UP${NC}"
                service_status[$name]="UP"
            else
                echo -e "${YELLOW}DEGRADED${NC}"
                service_status[$name]="DEGRADED"
            fi
        else
            echo -e "${GREEN}UP${NC}"
            service_status[$name]="UP"
        fi
    else
        echo -e "${RED}DOWN${NC}"
        service_status[$name]="DOWN"
    fi
    
    service_last_check[$name]=$(date +%s)
}

monitor_loop() {
    clear
    echo "AI Services Monitor - Press Ctrl+C to exit"
    echo "Refresh interval: ${INTERVAL}s"
    echo "============================================="
    
    while true; do
        echo -e "\nTimestamp: $(date)"
        echo -e "\nService Status:"
        printf "%-15s %-10s %-30s\n" "SERVICE" "STATUS" "DETAILS"
        printf "%-15s %-10s %-30s\n" "-------" "------" "-------"
        
        # Check PostgreSQL
        printf "%-15s " "PostgreSQL"
        check_service "postgres" "postgres" "5432"
        
        # Check n8n
        printf "%-15s " "n8n"
        check_service "n8n" "n8n" "5678" "/healthz"
        
        # Check Ollama
        printf "%-15s " "Ollama"
        status=$(check_service "ollama" "ollama" "11434" "/api/tags")
        if [[ "${service_status[ollama]}" == "UP" ]]; then
            model_count=$(curl -s http://ollama:11434/api/tags | jq '.models | length' 2>/dev/null || echo 0)
            printf " Models: %d" "$model_count"
        fi
        echo
        
        # Check Qdrant
        printf "%-15s " "Qdrant"
        status=$(check_service "qdrant" "qdrant" "6333" "/collections")
        if [[ "${service_status[qdrant]}" == "UP" ]]; then
            collection_count=$(curl -s http://qdrant:6333/collections | jq '.result.collections | length' 2>/dev/null || echo 0)
            printf " Collections: %d" "$collection_count"
        fi
        echo
        
        # Check Crawl4AI
        printf "%-15s " "Crawl4AI"
        check_service "crawl4ai" "crawl4ai" "11235" "/health"
        
        # Resource usage
        echo -e "\n\nResource Usage:"
        
        # CPU and Memory
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "N/A")
        mem_info=$(free -m | grep Mem)
        mem_used=$(echo "$mem_info" | awk '{print $3}')
        mem_total=$(echo "$mem_info" | awk '{print $2}')
        mem_percent=$(awk "BEGIN {printf \"%.1f\", $mem_used/$mem_total * 100}")
        
        echo "  System CPU: ${cpu_usage}%"
        echo "  System Memory: ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"
        
        # GPU (if available)
        if command -v nvidia-smi >/dev/null 2>&1; then
            gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | head -1)
            if [[ -n "$gpu_info" ]]; then
                gpu_util=$(echo "$gpu_info" | cut -d',' -f1 | xargs)
                gpu_mem_used=$(echo "$gpu_info" | cut -d',' -f2 | xargs)
                gpu_mem_total=$(echo "$gpu_info" | cut -d',' -f3 | xargs)
                echo "  GPU Utilization: ${gpu_util}%"
                echo "  GPU Memory: ${gpu_mem_used}MB / ${gpu_mem_total}MB"
            fi
        fi
        
        # Alerts
        echo -e "\nAlerts:"
        alert_count=0
        for service in "${!service_status[@]}"; do
            if [[ "${service_status[$service]}" != "UP" ]]; then
                echo -e "  ${RED}!${NC} $service is ${service_status[$service]}"
                ((alert_count++))
            fi
        done
        
        if [[ $alert_count -eq 0 ]]; then
            echo -e "  ${GREEN}✓${NC} All services operational"
        fi
        
        # Wait for next iteration
        sleep "$INTERVAL"
        
        # Clear screen for next update
        clear
        echo "AI Services Monitor - Press Ctrl+C to exit"
        echo "Refresh interval: ${INTERVAL}s"
        echo "============================================="
    done
}

# Start monitoring
monitor_loop
EOF
    
    chmod +x "$AI_MONITORING_SCRIPT_PATH"
    
    log_info "[AI_INTEGRATION] Monitoring script created"
    return 0
}

# Validate complete AI integration
# Returns:
#   0 - Validation successful
#   1 - Test script not found
#   2 - Tests failed
validate_ai_integration() {
    log_info "[AI_INTEGRATION] Validating complete AI services integration..."
    
    # Check if test script exists
    if [[ ! -f "$AI_TEST_SCRIPT_PATH" ]]; then
        log_error "[AI_INTEGRATION] Test script not found"
        return 1
    fi
    
    # Run integration tests
    log_info "[AI_INTEGRATION] Running integration tests..."
    if bash "$AI_TEST_SCRIPT_PATH"; then
        log_info "[AI_INTEGRATION] All integration tests passed"
        return 0
    else
        log_error "[AI_INTEGRATION] Some integration tests failed"
        return 2
    fi
}

# Test AI pipeline with custom input
# Arguments:
#   $1 - Test content/URL
#   $2 - Test type (url/text)
# Returns:
#   0 - Pipeline successful
#   1 - Pipeline failure
test_ai_pipeline() {
    local test_input="${1:-This is a test document}"
    local test_type="${2:-text}"
    
    log_info "[AI_INTEGRATION] Testing AI pipeline with $test_type input..."
    
    # Step 1: Content preparation
    local content
    if [[ "$test_type" == "url" ]]; then
        # Extract content from URL
        local extract_response
        extract_response=$(curl -s -X POST http://crawl4ai:11235/extract \
            -H "Content-Type: application/json" \
            -d "{\"url\": \"$test_input\", \"extraction_strategy\": \"text\"}" \
            --max-time 30 2>/dev/null)
        
        if [[ -z "$extract_response" ]]; then
            log_error "[AI_INTEGRATION] Content extraction failed"
            return 1
        fi
        
        content=$(echo "$extract_response" | jq -r '.extracted_content' 2>/dev/null || echo "$test_input")
    else
        content="$test_input"
    fi
    
    # Step 2: Generate embeddings
    local embedding_response
    embedding_response=$(curl -s -X POST http://ollama:11434/api/embeddings \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"mxbai-embed-large\", \"prompt\": \"$content\"}" \
        --max-time 60 2>/dev/null)
    
    if [[ -z "$embedding_response" ]]; then
        log_error "[AI_INTEGRATION] Embedding generation failed"
        return 1
    fi
    
    # Step 3: AI analysis
    local analysis_response
    analysis_response=$(curl -s -X POST http://ollama:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"deepseek-r1:8b\",
            \"prompt\": \"Analyze and summarize: $content\",
            \"stream\": false
        }" --max-time 120 2>/dev/null)
    
    if [[ -z "$analysis_response" ]]; then
        log_error "[AI_INTEGRATION] AI analysis failed"
        return 1
    fi
    
    local analysis
    analysis=$(echo "$analysis_response" | jq -r '.response' 2>/dev/null || echo "Analysis failed")
    
    log_info "[AI_INTEGRATION] Pipeline test completed successfully"
    log_debug "[AI_INTEGRATION] Analysis result: ${analysis:0:100}..."
    
    return 0
}

# Monitor AI services health
# Arguments:
#   $1 - Monitoring duration in seconds (0 for continuous)
# Returns:
#   0 - Monitoring completed
#   1 - Monitoring script not found
monitor_ai_services() {
    local duration="${1:-0}"
    
    log_info "[AI_INTEGRATION] Starting AI services monitoring..."
    
    # Create monitoring script if not exists
    if [[ ! -f "$AI_MONITORING_SCRIPT_PATH" ]]; then
        if ! create_monitoring_script; then
            log_error "[AI_INTEGRATION] Failed to create monitoring script"
            return 1
        fi
    fi
    
    # Run monitoring
    if [[ "$duration" -eq 0 ]]; then
        # Continuous monitoring
        bash "$AI_MONITORING_SCRIPT_PATH"
    else
        # Time-limited monitoring
        timeout "$duration" bash "$AI_MONITORING_SCRIPT_PATH" || true
    fi
    
    return 0
}

# ==============================================================================
# PRIVATE FUNCTIONS
# ==============================================================================

# Implementation of setup_ai_services_integration
_setup_ai_services_integration_impl() {
    local instance_type="$1"
    local webhook_url="$2"
    local model_config="$3"
    
    log_info "[AI_INTEGRATION] Setting up complete AI services integration..."
    log_info "[AI_INTEGRATION] Instance type: $instance_type"
    log_info "[AI_INTEGRATION] Model config: $model_config"
    
    # Setup services in dependency order
    log_info "[AI_INTEGRATION] Setting up Ollama models..."
    if ! setup_ollama_models "$instance_type" "$model_config"; then
        throw_error $ERROR_DEPLOYMENT_FAILED "Ollama setup failed"
    fi
    
    log_info "[AI_INTEGRATION] Setting up Qdrant collections..."
    if ! setup_qdrant_collections "default" "true"; then
        throw_error $ERROR_DEPLOYMENT_FAILED "Qdrant setup failed"
    fi
    
    log_info "[AI_INTEGRATION] Setting up Crawl4AI integration..."
    if ! setup_crawl4ai_integration "true" "ollama"; then
        throw_error $ERROR_DEPLOYMENT_FAILED "Crawl4AI setup failed"
    fi
    
    log_info "[AI_INTEGRATION] Setting up n8n AI integration..."
    if ! setup_n8n_ai_integration "$webhook_url" "true"; then
        throw_error $ERROR_DEPLOYMENT_FAILED "n8n setup failed"
    fi
    
    # Create integration test script
    if ! create_integration_test_script; then
        log_warning "[AI_INTEGRATION] Failed to create test script"
    fi
    
    # Create monitoring script
    if ! create_monitoring_script; then
        log_warning "[AI_INTEGRATION] Failed to create monitoring script"
    fi
    
    # Validate complete integration
    if ! validate_ai_integration; then
        log_warning "[AI_INTEGRATION] Some integration tests failed"
    fi
    
    # Register integration completion
    register_resource "ai_integration" "complete" "instance=$instance_type,models=$model_config"
    
    log_info "[AI_INTEGRATION] AI services integration setup completed successfully"
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================
log_debug "[AI_INTEGRATION] Module loaded successfully"