#!/usr/bin/env bash
# ==============================================================================
# Module: n8n Workflow Automation
# Description: Manages n8n workflow automation setup, AI integrations, and workflow templates
# 
# Functions:
#   - setup_n8n_ai_integration()    Configure n8n with AI service connections
#   - wait_for_n8n_ready()          Wait for n8n service availability
#   - configure_n8n_ai_connections() Setup AI service credentials
#   - install_n8n_ai_nodes()        Install AI-specific workflow nodes
#   - create_sample_ai_workflows()   Deploy sample AI workflows
#   - validate_n8n_setup()          Verify n8n configuration
#
# Dependencies:
#   - core/registry                 Resource registration
#   - core/errors                  Error handling
#   - config/variables             Configuration management
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${__N8N_MODULE_LOADED:-}" ]] && return 0
readonly __N8N_MODULE_LOADED=1

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
readonly N8N_PORT=5678
readonly N8N_API_URL="http://localhost:${N8N_PORT}"
readonly N8N_HEALTH_ENDPOINT="${N8N_API_URL}/healthz"
readonly N8N_API_V1="${N8N_API_URL}/api/v1"
readonly N8N_DEFAULT_TIMEOUT=300
readonly N8N_HEALTH_CHECK_INTERVAL=10

# Default AI nodes to install
readonly -a N8N_DEFAULT_AI_NODES=(
    "@n8n/n8n-nodes-langchain"
    "n8n-nodes-ollama"
    "n8n-nodes-qdrant"
    "n8n-nodes-web-scraper"
)

# ==============================================================================
# PUBLIC FUNCTIONS
# ==============================================================================

# Setup n8n with AI integrations
# Arguments:
#   $1 - Webhook URL (optional)
#   $2 - Enable AI nodes (optional, default: true)
#   $3 - Custom nodes comma-separated list (optional)
# Returns:
#   0 - Success
#   1 - Service timeout
#   2 - Configuration failure
#   3 - Node installation failure
setup_n8n_ai_integration() {
    local webhook_url="${1:-}"
    local enable_ai_nodes="${2:-true}"
    local custom_nodes="${3:-}"
    
    with_error_context "setup_n8n_ai_integration" \
        _setup_n8n_ai_integration_impl "$webhook_url" "$enable_ai_nodes" "$custom_nodes"
}

# Wait for n8n service to be ready
# Arguments:
#   $1 - Timeout in seconds (optional, default: 300)
# Returns:
#   0 - Service ready
#   1 - Timeout reached
wait_for_n8n_ready() {
    local timeout="${1:-$N8N_DEFAULT_TIMEOUT}"
    local interval=$N8N_HEALTH_CHECK_INTERVAL
    local elapsed=0
    
    log_info "[N8N] Waiting for service to be ready (timeout: ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s "$N8N_HEALTH_ENDPOINT" >/dev/null 2>&1; then
            log_info "[N8N] Service is ready"
            return 0
        fi
        
        log_debug "[N8N] Waiting for service... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "[N8N] Service did not become ready within ${timeout}s"
    return 1
}

# Configure n8n AI service connections
# Arguments:
#   $1 - Webhook URL (optional)
# Returns:
#   0 - Success
#   1 - Configuration failure
configure_n8n_ai_connections() {
    local webhook_url="${1:-}"
    
    log_info "[N8N] Configuring AI service connections..."
    
    # Create configuration directory
    local config_dir="/shared/n8n-config"
    if ! mkdir -p "$config_dir" 2>/dev/null; then
        log_error "[N8N] Failed to create config directory: $config_dir"
        return 1
    fi
    
    # Create service connection configurations
    _create_ollama_config "$config_dir"
    _create_qdrant_config "$config_dir"
    _create_crawl4ai_config "$config_dir"
    
    # Register configurations
    register_resource "n8n_config" "ai_connections" "path=$config_dir"
    
    log_info "[N8N] AI service connection configurations created"
    return 0
}

# Install AI-specific n8n nodes
# Arguments:
#   $1 - Custom nodes comma-separated list (optional)
# Returns:
#   0 - Success
#   1 - Installation failure
install_n8n_ai_nodes() {
    local custom_nodes="${1:-}"
    
    log_info "[N8N] Installing AI-specific nodes..."
    
    # Install default AI nodes
    local install_failed=false
    for node in "${N8N_DEFAULT_AI_NODES[@]}"; do
        log_info "[N8N] Installing node: $node"
        if ! docker exec n8n-ai npm install "$node" 2>&1; then
            log_warning "[N8N] Failed to install node: $node"
            install_failed=true
        fi
    done
    
    # Install custom nodes if specified
    if [[ -n "$custom_nodes" ]]; then
        IFS=',' read -ra CUSTOM_ARRAY <<< "$custom_nodes"
        for node in "${CUSTOM_ARRAY[@]}"; do
            node=$(echo "$node" | xargs)  # Trim whitespace
            log_info "[N8N] Installing custom node: $node"
            if ! docker exec n8n-ai npm install "$node" 2>&1; then
                log_warning "[N8N] Failed to install custom node: $node"
                install_failed=true
            fi
        done
    fi
    
    # Restart n8n to load new nodes
    log_info "[N8N] Restarting service to load new nodes..."
    if ! docker restart n8n-ai 2>&1; then
        log_error "[N8N] Failed to restart service"
        return 1
    fi
    
    # Wait for service to be ready again
    sleep 30
    if ! wait_for_n8n_ready; then
        return 1
    fi
    
    if [[ "$install_failed" == "true" ]]; then
        log_warning "[N8N] Some nodes failed to install, but continuing..."
    fi
    
    return 0
}

# Create sample AI workflows
# Returns:
#   0 - Success
#   1 - Creation failure
create_sample_ai_workflows() {
    log_info "[N8N] Creating sample AI workflows..."
    
    local workflow_dir="/shared/n8n-workflows"
    if ! mkdir -p "$workflow_dir" 2>/dev/null; then
        log_error "[N8N] Failed to create workflow directory: $workflow_dir"
        return 1
    fi
    
    # Create AI chat workflow
    _create_ai_chat_workflow "$workflow_dir"
    
    # Create document processing workflow
    _create_document_processing_workflow "$workflow_dir"
    
    # Create RAG workflow
    _create_rag_workflow "$workflow_dir"
    
    # Register workflows
    register_resource "n8n_workflow" "sample_workflows" "path=$workflow_dir"
    
    log_info "[N8N] Sample AI workflows created"
    return 0
}

# Validate n8n setup
# Returns:
#   0 - Validation successful
#   1 - Validation failure
validate_n8n_setup() {
    log_info "[N8N] Validating setup..."
    
    # Test health endpoint
    if ! curl -f -s "$N8N_HEALTH_ENDPOINT" >/dev/null 2>&1; then
        log_error "[N8N] Health check failed"
        return 1
    fi
    
    # Test API endpoint
    if ! curl -f -s "${N8N_API_V1}/workflows" >/dev/null 2>&1; then
        log_warning "[N8N] API endpoint not accessible (may require authentication)"
    fi
    
    # Test webhook endpoint
    local test_webhook="${N8N_API_URL}/webhook-test"
    if curl -f -s "$test_webhook" >/dev/null 2>&1; then
        log_info "[N8N] Webhook endpoints are accessible"
    fi
    
    log_info "[N8N] Validation completed"
    return 0
}

# ==============================================================================
# PRIVATE FUNCTIONS
# ==============================================================================

# Implementation of setup_n8n_ai_integration
_setup_n8n_ai_integration_impl() {
    local webhook_url="$1"
    local enable_ai_nodes="$2"
    local custom_nodes="$3"
    
    log_info "[N8N] Setting up AI integration..."
    
    # Wait for service
    if ! wait_for_n8n_ready; then
        throw_error $ERROR_TIMEOUT "n8n service timeout"
    fi
    
    # Configure AI connections
    if ! configure_n8n_ai_connections "$webhook_url"; then
        throw_error $ERROR_CONFIG_INVALID "Failed to configure AI connections"
    fi
    
    # Install AI nodes if enabled
    if [[ "$enable_ai_nodes" == "true" ]]; then
        if ! install_n8n_ai_nodes "$custom_nodes"; then
            log_warning "[N8N] Some AI nodes failed to install"
        fi
    fi
    
    # Create sample workflows
    if ! create_sample_ai_workflows; then
        log_warning "[N8N] Failed to create sample workflows"
    fi
    
    # Validate setup
    if ! validate_n8n_setup; then
        log_warning "[N8N] Validation detected some issues"
    fi
    
    log_info "[N8N] AI integration setup completed"
}

# Create Ollama configuration
_create_ollama_config() {
    local config_dir="$1"
    
    cat > "$config_dir/ollama-config.json" << 'EOF'
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
}

# Create Qdrant configuration
_create_qdrant_config() {
    local config_dir="$1"
    
    cat > "$config_dir/qdrant-config.json" << 'EOF'
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
}

# Create Crawl4AI configuration
_create_crawl4ai_config() {
    local config_dir="$1"
    
    cat > "$config_dir/crawl4ai-config.json" << 'EOF'
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
}

# Create AI chat workflow
_create_ai_chat_workflow() {
    local workflow_dir="$1"
    
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
                "bodyParametersJson": "={\"model\": \"deepseek-r1:8b\", \"prompt\": \"{{ $json.query }}\", \"stream\": false}"
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
                "responseBody": "={{ {\"response\": $json.response, \"model\": \"deepseek-r1:8b\"} }}"
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
}

# Create document processing workflow
_create_document_processing_workflow() {
    local workflow_dir="$1"
    
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
}

# Create RAG (Retrieval Augmented Generation) workflow
_create_rag_workflow() {
    local workflow_dir="$1"
    
    cat > "$workflow_dir/rag-workflow.json" << 'EOF'
{
    "name": "RAG - Retrieval Augmented Generation",
    "nodes": [
        {
            "parameters": {
                "httpMethod": "POST",
                "path": "rag-query",
                "responseMode": "responseNode",
                "options": {}
            },
            "id": "webhook-trigger",
            "name": "Query Trigger",
            "type": "n8n-nodes-base.webhook",
            "typeVersion": 1,
            "position": [240, 300]
        },
        {
            "parameters": {
                "url": "http://ollama:11434/api/embeddings",
                "requestMethod": "POST",
                "jsonParameters": true,
                "options": {},
                "bodyParametersJson": "={\"model\": \"mxbai-embed-large\", \"prompt\": \"{{ $json.query }}\"}"
            },
            "id": "query-embedding",
            "name": "Generate Query Embedding",
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 3,
            "position": [460, 300]
        },
        {
            "parameters": {
                "url": "http://qdrant:6333/collections/documents/points/search",
                "requestMethod": "POST",
                "jsonParameters": true,
                "options": {},
                "bodyParametersJson": "={\"vector\": {{ $json.embedding }}, \"limit\": 5, \"with_payload\": true}"
            },
            "id": "vector-search",
            "name": "Search Similar Documents",
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 3,
            "position": [680, 300]
        },
        {
            "parameters": {
                "url": "http://ollama:11434/api/generate",
                "requestMethod": "POST",
                "jsonParameters": true,
                "options": {},
                "bodyParametersJson": "={\"model\": \"deepseek-r1:8b\", \"prompt\": \"Based on the following context:\\n\\n{{ $json.result[0].payload.content }}\\n\\nAnswer the question: {{ $('Query Trigger').item.json.query }}\", \"stream\": false}"
            },
            "id": "generate-answer",
            "name": "Generate Answer",
            "type": "n8n-nodes-base.httpRequest",
            "typeVersion": 3,
            "position": [900, 300]
        },
        {
            "parameters": {
                "respondWith": "json",
                "responseBody": "={{ {\"answer\": $json.response, \"sources\": $('Search Similar Documents').item.json.result} }}"
            },
            "id": "response",
            "name": "Response",
            "type": "n8n-nodes-base.respondToWebhook",
            "typeVersion": 1,
            "position": [1120, 300]
        }
    ],
    "connections": {
        "Query Trigger": {
            "main": [
                [
                    {
                        "node": "Generate Query Embedding",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        },
        "Generate Query Embedding": {
            "main": [
                [
                    {
                        "node": "Search Similar Documents",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        },
        "Search Similar Documents": {
            "main": [
                [
                    {
                        "node": "Generate Answer",
                        "type": "main",
                        "index": 0
                    }
                ]
            ]
        },
        "Generate Answer": {
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
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================
log_debug "[N8N] Module loaded successfully"