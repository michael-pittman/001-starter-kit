#!/usr/bin/env bash
# ==============================================================================
# Module: Qdrant Vector Database
# Description: Manages Qdrant vector database setup, collections, and indexes
# 
# Functions:
#   - setup_qdrant_collections()    Create and configure vector collections
#   - wait_for_qdrant_ready()       Wait for Qdrant service availability
#   - create_qdrant_collections()   Create various collection types
#   - setup_qdrant_indexes()        Configure collection indexes
#   - validate_qdrant_setup()       Verify Qdrant configuration
#
# Dependencies:
#   - core/registry                 Resource registration
#   - core/errors                  Error handling
#   - config/variables             Configuration management
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${__QDRANT_MODULE_LOADED:-}" ]] && return 0
readonly __QDRANT_MODULE_LOADED=1

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
readonly QDRANT_PORT=6333
readonly QDRANT_GRPC_PORT=6334
readonly QDRANT_API_URL="http://localhost:${QDRANT_PORT}"
readonly QDRANT_HEALTH_ENDPOINT="${QDRANT_API_URL}/healthz"
readonly QDRANT_DEFAULT_TIMEOUT=300
readonly QDRANT_HEALTH_CHECK_INTERVAL=10

# Collection vector sizes
readonly QDRANT_VECTOR_SIZE_LARGE=1024
readonly QDRANT_VECTOR_SIZE_MEDIUM=768
readonly QDRANT_VECTOR_SIZE_SMALL=384

# Default HNSW parameters
readonly QDRANT_HNSW_M_DEFAULT=16
readonly QDRANT_HNSW_EF_CONSTRUCT_DEFAULT=200

# ==============================================================================
# PUBLIC FUNCTIONS
# ==============================================================================

# Setup Qdrant with optimized collections
# Arguments:
#   $1 - Collection configurations (default/documents/embeddings/multimodal)
#   $2 - Optimize for GPU (true/false, default: true)
# Returns:
#   0 - Success
#   1 - Service timeout
#   2 - Collection creation failure
#   3 - Validation failure
setup_qdrant_collections() {
    local collection_configs="${1:-default}"
    local optimize_for_gpu="${2:-true}"
    
    with_error_context "setup_qdrant_collections" \
        _setup_qdrant_collections_impl "$collection_configs" "$optimize_for_gpu"
}

# Wait for Qdrant service to be ready
# Arguments:
#   $1 - Timeout in seconds (optional, default: 300)
# Returns:
#   0 - Service ready
#   1 - Timeout reached
wait_for_qdrant_ready() {
    local timeout="${1:-$QDRANT_DEFAULT_TIMEOUT}"
    local interval=$QDRANT_HEALTH_CHECK_INTERVAL
    local elapsed=0
    
    log_info "[QDRANT] Waiting for service to be ready (timeout: ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s "$QDRANT_HEALTH_ENDPOINT" >/dev/null 2>&1; then
            log_info "[QDRANT] Service is ready"
            return 0
        fi
        
        log_debug "[QDRANT] Waiting for service... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "[QDRANT] Service did not become ready within ${timeout}s"
    return 1
}

# Create Qdrant collections based on configuration
# Arguments:
#   $1 - Configuration type (default/documents/embeddings/multimodal)
#   $2 - Optimize for GPU (true/false)
# Returns:
#   0 - Success
#   1 - Creation failure
create_qdrant_collections() {
    local configs="$1"
    local optimize_for_gpu="$2"
    
    log_info "[QDRANT] Creating collections: $configs"
    
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
    
    return $?
}

# Create documents collection
# Arguments:
#   $1 - Optimize for GPU (true/false)
# Returns:
#   0 - Success
#   1 - Creation failure
create_documents_collection() {
    local optimize_for_gpu="$1"
    
    log_info "[QDRANT] Creating documents collection..."
    
    # Adjust parameters based on GPU optimization
    local hnsw_m=$QDRANT_HNSW_M_DEFAULT
    local hnsw_ef_construct=$QDRANT_HNSW_EF_CONSTRUCT_DEFAULT
    local indexing_threads=4
    
    if [[ "$optimize_for_gpu" == "true" ]]; then
        hnsw_m=24
        hnsw_ef_construct=300
        indexing_threads=8
    fi
    
    # Collection configuration
    local collection_config
    collection_config=$(cat << EOF
{
    "vectors": {
        "size": $QDRANT_VECTOR_SIZE_LARGE,
        "distance": "Cosine",
        "hnsw_config": {
            "m": $hnsw_m,
            "ef_construct": $hnsw_ef_construct,
            "full_scan_threshold": 10000,
            "max_indexing_threads": $indexing_threads
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
    if curl -X PUT "${QDRANT_API_URL}/collections/documents" \
        -H "Content-Type: application/json" \
        -d "$collection_config" 2>&1; then
        log_info "[QDRANT] Documents collection created"
        register_resource "qdrant_collection" "documents" "vector_size=$QDRANT_VECTOR_SIZE_LARGE"
        return 0
    else
        log_error "[QDRANT] Failed to create documents collection"
        return 1
    fi
}

# Create embeddings collection
# Arguments:
#   $1 - Optimize for GPU (true/false)
# Returns:
#   0 - Success
#   1 - Creation failure
create_embeddings_collection() {
    local optimize_for_gpu="$1"
    
    log_info "[QDRANT] Creating embeddings collection..."
    
    local hnsw_m=24
    local hnsw_ef_construct=300
    
    local collection_config
    collection_config=$(cat << EOF
{
    "vectors": {
        "size": $QDRANT_VECTOR_SIZE_MEDIUM,
        "distance": "Cosine",
        "hnsw_config": {
            "m": $hnsw_m,
            "ef_construct": $hnsw_ef_construct,
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
    
    if curl -X PUT "${QDRANT_API_URL}/collections/embeddings" \
        -H "Content-Type: application/json" \
        -d "$collection_config" 2>&1; then
        log_info "[QDRANT] Embeddings collection created"
        register_resource "qdrant_collection" "embeddings" "vector_size=$QDRANT_VECTOR_SIZE_MEDIUM"
        return 0
    else
        log_error "[QDRANT] Failed to create embeddings collection"
        return 1
    fi
}

# Create chat collection
# Arguments:
#   $1 - Optimize for GPU (true/false)
# Returns:
#   0 - Success
#   1 - Creation failure
create_chat_collection() {
    local optimize_for_gpu="$1"
    
    log_info "[QDRANT] Creating chat collection..."
    
    local collection_config
    collection_config=$(cat << EOF
{
    "vectors": {
        "size": $QDRANT_VECTOR_SIZE_LARGE,
        "distance": "Dot",
        "hnsw_config": {
            "m": 16,
            "ef_construct": 100
        }
    }
}
EOF
)
    
    if curl -X PUT "${QDRANT_API_URL}/collections/chat" \
        -H "Content-Type: application/json" \
        -d "$collection_config" 2>&1; then
        log_info "[QDRANT] Chat collection created"
        register_resource "qdrant_collection" "chat" "vector_size=$QDRANT_VECTOR_SIZE_LARGE"
        return 0
    else
        log_error "[QDRANT] Failed to create chat collection"
        return 1
    fi
}

# Create multimodal collection for images and text
# Arguments:
#   $1 - Optimize for GPU (true/false)
# Returns:
#   0 - Success
#   1 - Creation failure
create_multimodal_collection() {
    local optimize_for_gpu="$1"
    
    log_info "[QDRANT] Creating multimodal collection..."
    
    local collection_config
    collection_config=$(cat << EOF
{
    "vectors": {
        "text": {
            "size": $QDRANT_VECTOR_SIZE_MEDIUM,
            "distance": "Cosine"
        },
        "image": {
            "size": $QDRANT_VECTOR_SIZE_LARGE,
            "distance": "Cosine"
        }
    },
    "hnsw_config": {
        "m": 32,
        "ef_construct": 400
    }
}
EOF
)
    
    if curl -X PUT "${QDRANT_API_URL}/collections/multimodal" \
        -H "Content-Type: application/json" \
        -d "$collection_config" 2>&1; then
        log_info "[QDRANT] Multimodal collection created"
        register_resource "qdrant_collection" "multimodal" "type=multi-vector"
        return 0
    else
        log_error "[QDRANT] Failed to create multimodal collection"
        return 1
    fi
}

# Setup collection indexes for better filtering
# Returns:
#   0 - Success
#   1 - Index creation failure
setup_qdrant_indexes() {
    log_info "[QDRANT] Setting up collection indexes..."
    
    # Define indexes to create
    local -a indexes=(
        "documents:content:text"
        "documents:url:keyword"
        "documents:timestamp:integer"
        "documents:source:keyword"
        "embeddings:type:keyword"
        "embeddings:model:keyword"
        "chat:user_id:keyword"
        "chat:session_id:keyword"
        "chat:timestamp:integer"
    )
    
    local failed=0
    for index in "${indexes[@]}"; do
        local collection field type
        collection=$(echo "$index" | cut -d: -f1)
        field=$(echo "$index" | cut -d: -f2)
        type=$(echo "$index" | cut -d: -f3)
        
        if _create_index "$collection" "$field" "$type"; then
            log_debug "[QDRANT] Created index: $collection.$field"
        else
            log_warning "[QDRANT] Failed to create index: $collection.$field"
            ((failed++))
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        log_warning "[QDRANT] Some indexes failed to create ($failed failures)"
        return 1
    fi
    
    log_info "[QDRANT] All indexes created successfully"
    return 0
}

# Validate Qdrant setup
# Returns:
#   0 - Validation successful
#   1 - Validation failure
validate_qdrant_setup() {
    log_info "[QDRANT] Validating setup..."
    
    # Test API accessibility
    if ! curl -f -s "${QDRANT_API_URL}/collections" >/dev/null 2>&1; then
        log_error "[QDRANT] API not accessible"
        return 1
    fi
    
    # Check collections
    local collections_response
    if ! collections_response=$(curl -s "${QDRANT_API_URL}/collections" 2>/dev/null); then
        log_error "[QDRANT] Failed to retrieve collections"
        return 1
    fi
    
    # Parse collections if jq is available
    if command -v jq &>/dev/null; then
        local collections
        collections=$(echo "$collections_response" | jq -r '.result.collections[].name' 2>/dev/null || echo "")
        
        if [[ -n "$collections" ]]; then
            log_info "[QDRANT] Found collections: $(echo "$collections" | tr '\n' ' ')"
        else
            log_warning "[QDRANT] No collections found"
            return 1
        fi
        
        # Validate each collection
        echo "$collections" | while read -r collection; do
            if ! _validate_collection "$collection"; then
                log_error "[QDRANT] Collection validation failed: $collection"
                return 1
            fi
        done
    else
        # Basic validation without jq
        if echo "$collections_response" | grep -q '"collections"'; then
            log_info "[QDRANT] Collections endpoint responded successfully"
        else
            log_error "[QDRANT] Invalid collections response"
            return 1
        fi
    fi
    
    log_info "[QDRANT] Validation completed successfully"
    return 0
}

# ==============================================================================
# PRIVATE FUNCTIONS
# ==============================================================================

# Implementation of setup_qdrant_collections
_setup_qdrant_collections_impl() {
    local collection_configs="$1"
    local optimize_for_gpu="$2"
    
    log_info "[QDRANT] Setting up vector collections..."
    
    # Wait for service
    if ! wait_for_qdrant_ready; then
        throw_error $ERROR_TIMEOUT "Qdrant service timeout"
    fi
    
    # Create collections
    if ! create_qdrant_collections "$collection_configs" "$optimize_for_gpu"; then
        throw_error $ERROR_DEPLOYMENT_FAILED "Failed to create collections"
    fi
    
    # Setup indexes
    if ! setup_qdrant_indexes; then
        log_warning "[QDRANT] Some indexes failed to create"
    fi
    
    # Validate setup
    if ! validate_qdrant_setup; then
        throw_error $ERROR_VALIDATION_FAILED "Qdrant validation failed"
    fi
    
    log_info "[QDRANT] Vector database setup completed"
}

# Create an index on a collection field
_create_index() {
    local collection="$1"
    local field="$2"
    local type="$3"
    
    local index_config
    index_config=$(cat << EOF
{
    "field_name": "$field",
    "field_schema": "$type"
}
EOF
)
    
    curl -X PUT "${QDRANT_API_URL}/collections/$collection/index" \
        -H "Content-Type: application/json" \
        -d "$index_config" >/dev/null 2>&1
}

# Validate a specific collection
_validate_collection() {
    local collection="$1"
    
    # Get collection info
    local collection_info
    if ! collection_info=$(curl -s "${QDRANT_API_URL}/collections/$collection" 2>/dev/null); then
        return 1
    fi
    
    # Check if collection exists and is ready
    if echo "$collection_info" | grep -q '"status":"green"'; then
        log_debug "[QDRANT] Collection $collection is healthy"
        return 0
    else
        log_warning "[QDRANT] Collection $collection is not healthy"
        return 1
    fi
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================
log_debug "[QDRANT] Module loaded successfully"