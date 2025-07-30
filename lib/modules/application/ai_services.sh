#!/usr/bin/env bash
# ==============================================================================
# Module: AI Services (Compatibility Wrapper)
# Description: Backward compatibility wrapper for refactored AI service modules
#              Maintains existing function signatures while delegating to
#              specialized modules
# 
# This module provides backward compatibility by wrapping the new modular
# AI service implementations. All original functions are preserved.
#
# New modular structure:
#   - ollama.sh       - Ollama model management
#   - n8n.sh          - n8n workflow automation
#   - qdrant.sh       - Qdrant vector database
#   - crawl4ai.sh     - Crawl4AI web scraping
#   - ai_integration.sh - Service orchestration
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${_AI_SERVICES_SH_LOADED:-}" ]] && return 0
readonly _AI_SERVICES_SH_LOADED=1

# ==============================================================================
# DEPENDENCIES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load modular AI service implementations
source "${SCRIPT_DIR}/ollama.sh" || return 1
source "${SCRIPT_DIR}/n8n.sh" || return 1
source "${SCRIPT_DIR}/qdrant.sh" || return 1
source "${SCRIPT_DIR}/crawl4ai.sh" || return 1
source "${SCRIPT_DIR}/ai_integration.sh" || return 1

# Load core modules for backward compatibility
source "${SCRIPT_DIR}/../core/registry.sh" || return 1
source "${SCRIPT_DIR}/../core/errors.sh" || return 1
source "${SCRIPT_DIR}/../config/variables.sh" || return 1

# ==============================================================================
# BACKWARD COMPATIBILITY NOTICE
# ==============================================================================
# This file now acts as a compatibility wrapper. The actual implementations
# have been moved to separate modules for better maintainability:
# - ollama.sh, n8n.sh, qdrant.sh, crawl4ai.sh, ai_integration.sh
#
# All original function signatures are preserved for backward compatibility.
# New code should use the modular imports directly.
# ==============================================================================

# ==============================================================================
# OLLAMA MODEL MANAGEMENT - Backward Compatibility
# ==============================================================================

# All Ollama functions are already exposed by ollama.sh
# The following are additional wrapper functions for complete compatibility

# Get model configuration based on instance type
get_model_configuration() {
    local instance_type="$1"
    local models_config="${2:-default}"
    local gpu_info="${3:-}"
    
    # Map to new implementation
    case "$models_config" in
        "default")
            echo "${OLLAMA_MODEL_CONFIGS[$instance_type]:-${OLLAMA_MODEL_CONFIGS[default]}}"
            ;;
        *)
            echo "$models_config"
            ;;
    esac
}

# ==============================================================================
# N8N WORKFLOW AUTOMATION - Backward Compatibility
# ==============================================================================

# All n8n functions are already exposed by n8n.sh
# No additional wrappers needed

# ==============================================================================
# QDRANT VECTOR DATABASE - Backward Compatibility
# ==============================================================================

# Additional wrapper for multimodal collection (new in refactored version)
create_multimodal_collection() {
    local optimize_for_gpu="${1:-true}"
    
    # This is a new function in the refactored version
    # Call it directly from qdrant.sh
    create_multimodal_collection "$optimize_for_gpu"
}

# ==============================================================================
# CRAWL4AI WEB SCRAPING - Backward Compatibility
# ==============================================================================

# All Crawl4AI functions are already exposed by crawl4ai.sh
# No additional wrappers needed

# ==============================================================================
# SERVICE INTEGRATION - Backward Compatibility
# ==============================================================================

# The main integration function maintains the same signature
# It's already exposed by ai_integration.sh

# Additional backward compatibility functions

# Create integration test script (original name)
create_integration_test_script() {
    # Delegate to new module
    create_integration_test_script
}

# Validate AI integration (original name)
validate_ai_integration() {
    # Delegate to new module
    validate_ai_integration
}

# ==============================================================================
# DEPRECATED FUNCTIONS
# ==============================================================================

# These functions existed in the original but are now internal (_prefixed)
# We provide wrappers for backward compatibility

_setup_ollama_models_impl() {
    echo "WARNING: _setup_ollama_models_impl is deprecated. Use setup_ollama_models instead." >&2
    setup_ollama_models "$@"
}

_setup_n8n_ai_integration_impl() {
    echo "WARNING: _setup_n8n_ai_integration_impl is deprecated. Use setup_n8n_ai_integration instead." >&2
    setup_n8n_ai_integration "$@"
}

_setup_qdrant_collections_impl() {
    echo "WARNING: _setup_qdrant_collections_impl is deprecated. Use setup_qdrant_collections instead." >&2
    setup_qdrant_collections "$@"
}

_setup_crawl4ai_integration_impl() {
    echo "WARNING: _setup_crawl4ai_integration_impl is deprecated. Use setup_crawl4ai_integration instead." >&2
    setup_crawl4ai_integration "$@"
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================

# Notify about the refactoring (can be disabled by setting AI_SERVICES_QUIET=1)
if [[ "${AI_SERVICES_QUIET:-0}" != "1" ]] && [[ "${AI_SERVICES_NOTIFIED:-0}" != "1" ]]; then
    export AI_SERVICES_NOTIFIED=1
    echo "INFO: ai_services.sh has been refactored into modular components." >&2
    echo "INFO: This compatibility wrapper maintains all original functions." >&2
    echo "INFO: For new code, consider importing specific modules directly:" >&2
    echo "INFO:   - ollama.sh, n8n.sh, qdrant.sh, crawl4ai.sh, ai_integration.sh" >&2
fi

# Log successful loading
[[ -n "${DEBUG:-}" ]] && echo "[AI_SERVICES] Compatibility wrapper loaded successfully" >&2