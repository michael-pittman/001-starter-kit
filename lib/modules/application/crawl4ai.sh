#!/usr/bin/env bash
# ==============================================================================
# Module: Crawl4AI Web Scraping Service
# Description: Manages Crawl4AI web scraping service with LLM integration
# 
# Functions:
#   - setup_crawl4ai_integration()    Configure Crawl4AI with LLM support
#   - wait_for_crawl4ai_ready()       Wait for service availability
#   - configure_crawl4ai_llm()        Setup LLM provider integration
#   - setup_crawl4ai_browser()        Configure browser settings
#   - create_extraction_templates()    Deploy extraction templates
#   - validate_crawl4ai_setup()       Verify service configuration
#
# Dependencies:
#   - core/registry                   Resource registration
#   - core/errors                    Error handling
#   - config/variables               Configuration management
# ==============================================================================

# Prevent multiple sourcing
[[ -n "${__CRAWL4AI_MODULE_LOADED:-}" ]] && return 0
readonly __CRAWL4AI_MODULE_LOADED=1

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
readonly CRAWL4AI_PORT=11235
readonly CRAWL4AI_API_URL="http://localhost:${CRAWL4AI_PORT}"
readonly CRAWL4AI_HEALTH_ENDPOINT="${CRAWL4AI_API_URL}/health"
readonly CRAWL4AI_DEFAULT_TIMEOUT=300
readonly CRAWL4AI_HEALTH_CHECK_INTERVAL=10

# Supported LLM providers
readonly -a CRAWL4AI_SUPPORTED_PROVIDERS=(
    "ollama"
    "openai"
    "anthropic"
    "local"
)

# Default browser configuration
readonly CRAWL4AI_DEFAULT_BROWSER="chromium"
readonly CRAWL4AI_DEFAULT_VIEWPORT_WIDTH=1920
readonly CRAWL4AI_DEFAULT_VIEWPORT_HEIGHT=1080

# ==============================================================================
# PUBLIC FUNCTIONS
# ==============================================================================

# Setup Crawl4AI with LLM integration
# Arguments:
#   $1 - Enable browser (true/false, default: true)
#   $2 - LLM provider (ollama/openai/anthropic/local, default: ollama)
# Returns:
#   0 - Success
#   1 - Service timeout
#   2 - Configuration failure
#   3 - Validation failure
setup_crawl4ai_integration() {
    local enable_browser="${1:-true}"
    local llm_provider="${2:-ollama}"
    
    with_error_context "setup_crawl4ai_integration" \
        _setup_crawl4ai_integration_impl "$enable_browser" "$llm_provider"
}

# Wait for Crawl4AI service to be ready
# Arguments:
#   $1 - Timeout in seconds (optional, default: 300)
# Returns:
#   0 - Service ready
#   1 - Timeout reached
wait_for_crawl4ai_ready() {
    local timeout="${1:-$CRAWL4AI_DEFAULT_TIMEOUT}"
    local interval=$CRAWL4AI_HEALTH_CHECK_INTERVAL
    local elapsed=0
    
    log_info "[CRAWL4AI] Waiting for service to be ready (timeout: ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -f -s "$CRAWL4AI_HEALTH_ENDPOINT" >/dev/null 2>&1; then
            log_info "[CRAWL4AI] Service is ready"
            return 0
        fi
        
        log_debug "[CRAWL4AI] Waiting for service... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "[CRAWL4AI] Service did not become ready within ${timeout}s"
    return 1
}

# Configure Crawl4AI LLM integration
# Arguments:
#   $1 - LLM provider (ollama/openai/anthropic/local)
# Returns:
#   0 - Success
#   1 - Invalid provider
#   2 - Configuration failure
configure_crawl4ai_llm() {
    local provider="$1"
    
    # Validate provider
    if ! _is_valid_provider "$provider"; then
        log_error "[CRAWL4AI] Invalid LLM provider: $provider"
        return 1
    fi
    
    log_info "[CRAWL4AI] Configuring LLM integration with $provider..."
    
    local config_dir="/shared/crawl4ai-config"
    if ! mkdir -p "$config_dir" 2>/dev/null; then
        log_error "[CRAWL4AI] Failed to create config directory: $config_dir"
        return 2
    fi
    
    # Create provider-specific configuration
    case "$provider" in
        "ollama")
            _create_ollama_llm_config "$config_dir"
            ;;
        "openai")
            _create_openai_llm_config "$config_dir"
            ;;
        "anthropic")
            _create_anthropic_llm_config "$config_dir"
            ;;
        "local")
            _create_local_llm_config "$config_dir"
            ;;
    esac
    
    # Register configuration
    register_resource "crawl4ai_config" "llm_provider" "provider=$provider"
    
    log_info "[CRAWL4AI] LLM configuration created for $provider"
    return 0
}

# Setup browser configuration
# Returns:
#   0 - Success
#   1 - Configuration failure
setup_crawl4ai_browser() {
    log_info "[CRAWL4AI] Setting up browser configuration..."
    
    local config_dir="/shared/crawl4ai-config"
    if ! mkdir -p "$config_dir" 2>/dev/null; then
        log_error "[CRAWL4AI] Failed to create config directory"
        return 1
    fi
    
    cat > "$config_dir/browser-config.json" << EOF
{
    "headless": true,
    "browser_type": "$CRAWL4AI_DEFAULT_BROWSER",
    "user_agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "viewport": {
        "width": $CRAWL4AI_DEFAULT_VIEWPORT_WIDTH,
        "height": $CRAWL4AI_DEFAULT_VIEWPORT_HEIGHT
    },
    "timeout": 30000,
    "wait_for": "networkidle",
    "browser_pool_size": 2,
    "max_concurrent_sessions": 4,
    "stealth_mode": true,
    "block_resources": ["font", "image"],
    "cache_enabled": true,
    "cache_ttl": 3600
}
EOF
    
    # Register configuration
    register_resource "crawl4ai_config" "browser" "type=$CRAWL4AI_DEFAULT_BROWSER"
    
    log_info "[CRAWL4AI] Browser configuration created"
    return 0
}

# Create extraction templates for common use cases
# Returns:
#   0 - Success
#   1 - Creation failure
create_extraction_templates() {
    log_info "[CRAWL4AI] Creating extraction templates..."
    
    local templates_dir="/shared/crawl4ai-templates"
    if ! mkdir -p "$templates_dir" 2>/dev/null; then
        log_error "[CRAWL4AI] Failed to create templates directory"
        return 1
    fi
    
    # Create various extraction templates
    _create_article_extraction_template "$templates_dir"
    _create_product_extraction_template "$templates_dir"
    _create_documentation_extraction_template "$templates_dir"
    _create_social_media_extraction_template "$templates_dir"
    _create_research_paper_extraction_template "$templates_dir"
    
    # Register templates
    register_resource "crawl4ai_templates" "extraction" "path=$templates_dir"
    
    log_info "[CRAWL4AI] Extraction templates created"
    return 0
}

# Validate Crawl4AI setup
# Returns:
#   0 - Validation successful
#   1 - Health check failure
#   2 - Extraction test failure
validate_crawl4ai_setup() {
    log_info "[CRAWL4AI] Validating setup..."
    
    # Test health endpoint
    if ! curl -f -s "$CRAWL4AI_HEALTH_ENDPOINT" >/dev/null 2>&1; then
        log_error "[CRAWL4AI] Health check failed"
        return 1
    fi
    
    # Test basic extraction capability
    if ! _test_basic_extraction; then
        log_error "[CRAWL4AI] Basic extraction test failed"
        return 2
    fi
    
    # Test LLM extraction if configured
    if [[ -f "/shared/crawl4ai-config/llm-config.json" ]]; then
        if ! _test_llm_extraction; then
            log_warning "[CRAWL4AI] LLM extraction test failed (non-critical)"
        fi
    fi
    
    log_info "[CRAWL4AI] Validation completed successfully"
    return 0
}

# ==============================================================================
# PRIVATE FUNCTIONS
# ==============================================================================

# Implementation of setup_crawl4ai_integration
_setup_crawl4ai_integration_impl() {
    local enable_browser="$1"
    local llm_provider="$2"
    
    log_info "[CRAWL4AI] Setting up integration..."
    
    # Wait for service
    if ! wait_for_crawl4ai_ready; then
        throw_error $ERROR_TIMEOUT "Crawl4AI service timeout"
    fi
    
    # Configure LLM
    if ! configure_crawl4ai_llm "$llm_provider"; then
        throw_error $ERROR_CONFIG_INVALID "Failed to configure LLM provider"
    fi
    
    # Setup browser if enabled
    if [[ "$enable_browser" == "true" ]]; then
        if ! setup_crawl4ai_browser; then
            log_warning "[CRAWL4AI] Browser configuration failed"
        fi
    fi
    
    # Create templates
    if ! create_extraction_templates; then
        log_warning "[CRAWL4AI] Some templates failed to create"
    fi
    
    # Validate setup
    if ! validate_crawl4ai_setup; then
        log_warning "[CRAWL4AI] Validation detected some issues"
    fi
    
    log_info "[CRAWL4AI] Integration setup completed"
}

# Check if provider is valid
_is_valid_provider() {
    local provider="$1"
    for valid_provider in "${CRAWL4AI_SUPPORTED_PROVIDERS[@]}"; do
        if [[ "$provider" == "$valid_provider" ]]; then
            return 0
        fi
    done
    return 1
}

# Create Ollama LLM configuration
_create_ollama_llm_config() {
    local config_dir="$1"
    
    cat > "$config_dir/llm-config.json" << 'EOF'
{
    "provider": "ollama",
    "base_url": "http://ollama:11434",
    "model": "deepseek-r1:8b",
    "temperature": 0.1,
    "max_tokens": 2048,
    "extraction_model": "qwen2.5:7b",
    "embedding_model": "mxbai-embed-large",
    "timeout": 60000,
    "retry_attempts": 3,
    "streaming": false
}
EOF
}

# Create OpenAI LLM configuration
_create_openai_llm_config() {
    local config_dir="$1"
    
    cat > "$config_dir/llm-config.json" << 'EOF'
{
    "provider": "openai",
    "api_key": "${OPENAI_API_KEY}",
    "model": "gpt-4-turbo",
    "temperature": 0.1,
    "max_tokens": 4096,
    "extraction_model": "gpt-4-turbo",
    "embedding_model": "text-embedding-3-large",
    "timeout": 60000,
    "retry_attempts": 3
}
EOF
}

# Create Anthropic LLM configuration
_create_anthropic_llm_config() {
    local config_dir="$1"
    
    cat > "$config_dir/llm-config.json" << 'EOF'
{
    "provider": "anthropic",
    "api_key": "${ANTHROPIC_API_KEY}",
    "model": "claude-3-opus-20240229",
    "temperature": 0.1,
    "max_tokens": 4096,
    "timeout": 60000,
    "retry_attempts": 3
}
EOF
}

# Create local LLM configuration
_create_local_llm_config() {
    local config_dir="$1"
    
    cat > "$config_dir/llm-config.json" << 'EOF'
{
    "provider": "local",
    "extraction_strategy": "css",
    "use_readability": true,
    "clean_html": true,
    "remove_scripts": true,
    "remove_styles": true
}
EOF
}

# Create article extraction template
_create_article_extraction_template() {
    local templates_dir="$1"
    
    cat > "$templates_dir/article-extraction.json" << 'EOF'
{
    "name": "article_extraction",
    "description": "Extract structured data from news articles and blog posts",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract the following information from the article: title, author, publication_date, main_content, summary (max 200 words), tags, and category. Return as JSON.",
    "schema": {
        "title": "string",
        "author": "string",
        "publication_date": "string",
        "main_content": "string",
        "summary": "string",
        "tags": "array",
        "category": "string",
        "url": "string",
        "image_url": "string"
    },
    "css_selector": "article, .article-content, .post-content, main",
    "wait_for_selector": "h1, .title, .headline",
    "remove_selectors": [".ads", ".sidebar", ".comments", ".related-posts"],
    "timeout": 30000
}
EOF
}

# Create product extraction template
_create_product_extraction_template() {
    local templates_dir="$1"
    
    cat > "$templates_dir/product-extraction.json" << 'EOF'
{
    "name": "product_extraction",
    "description": "Extract product information from e-commerce pages",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract product details: name, price, currency, description, features (as array), specifications (as key-value pairs), availability, rating (0-5), review_count, and images. Return as JSON.",
    "schema": {
        "name": "string",
        "price": "number",
        "currency": "string",
        "description": "string",
        "features": "array",
        "specifications": "object",
        "availability": "string",
        "rating": "number",
        "review_count": "integer",
        "images": "array",
        "sku": "string",
        "brand": "string"
    },
    "css_selector": ".product, .product-details, #product-info",
    "wait_for_selector": ".price, .product-title",
    "remove_selectors": [".recommendations", ".recently-viewed"],
    "screenshot": true
}
EOF
}

# Create documentation extraction template
_create_documentation_extraction_template() {
    local templates_dir="$1"
    
    cat > "$templates_dir/docs-extraction.json" << 'EOF'
{
    "name": "documentation_extraction",
    "description": "Extract structured information from documentation pages",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract documentation structure: section_title, content (preserve formatting), code_examples (with language), links (internal/external), and navigation_hierarchy. Return as JSON.",
    "schema": {
        "section_title": "string",
        "content": "string",
        "code_examples": [{
            "language": "string",
            "code": "string",
            "description": "string"
        }],
        "links": [{
            "text": "string",
            "url": "string",
            "type": "string"
        }],
        "navigation_hierarchy": "array",
        "last_updated": "string",
        "version": "string"
    },
    "css_selector": ".documentation, .docs-content, .markdown-body",
    "wait_for_selector": "h1, h2, .section-title",
    "preserve_formatting": true
}
EOF
}

# Create social media extraction template
_create_social_media_extraction_template() {
    local templates_dir="$1"
    
    cat > "$templates_dir/social-media-extraction.json" << 'EOF'
{
    "name": "social_media_extraction",
    "description": "Extract social media posts and engagement metrics",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract post content, author info, timestamp, engagement metrics (likes, shares, comments), hashtags, mentions, and media URLs. Return as JSON.",
    "schema": {
        "post_id": "string",
        "author": {
            "username": "string",
            "display_name": "string",
            "verified": "boolean"
        },
        "content": "string",
        "timestamp": "string",
        "engagement": {
            "likes": "integer",
            "shares": "integer",
            "comments": "integer"
        },
        "hashtags": "array",
        "mentions": "array",
        "media": [{
            "type": "string",
            "url": "string"
        }],
        "url": "string"
    },
    "wait_for_selector": ".post, .tweet, .status",
    "screenshot": true,
    "scroll_behavior": "smooth"
}
EOF
}

# Create research paper extraction template
_create_research_paper_extraction_template() {
    local templates_dir="$1"
    
    cat > "$templates_dir/research-paper-extraction.json" << 'EOF'
{
    "name": "research_paper_extraction",
    "description": "Extract metadata and content from academic papers",
    "extraction_strategy": "llm",
    "llm_instruction": "Extract paper metadata: title, authors, abstract, keywords, publication details, DOI, citations. For content: introduction summary, methodology, results, conclusion. Return as JSON.",
    "schema": {
        "title": "string",
        "authors": [{
            "name": "string",
            "affiliation": "string"
        }],
        "abstract": "string",
        "keywords": "array",
        "publication": {
            "journal": "string",
            "year": "integer",
            "volume": "string",
            "pages": "string"
        },
        "doi": "string",
        "citations": "integer",
        "sections": {
            "introduction": "string",
            "methodology": "string",
            "results": "string",
            "conclusion": "string"
        },
        "references_count": "integer"
    },
    "wait_for_selector": ".abstract, #abstract",
    "pdf_extraction": true
}
EOF
}

# Test basic extraction functionality
_test_basic_extraction() {
    local test_response
    test_response=$(curl -s -X POST "${CRAWL4AI_API_URL}/extract" \
        -H "Content-Type: application/json" \
        -d '{"url": "https://example.com", "extraction_strategy": "text"}' \
        --max-time 30 2>/dev/null)
    
    if [[ -z "$test_response" ]]; then
        return 1
    fi
    
    # Check response structure
    if command -v jq &>/dev/null; then
        if echo "$test_response" | jq -e '.success' >/dev/null 2>&1; then
            log_debug "[CRAWL4AI] Basic extraction test passed"
            return 0
        fi
    else
        # Fallback check without jq
        if echo "$test_response" | grep -q '"success"'; then
            return 0
        fi
    fi
    
    return 1
}

# Test LLM extraction functionality
_test_llm_extraction() {
    local test_response
    test_response=$(curl -s -X POST "${CRAWL4AI_API_URL}/extract" \
        -H "Content-Type: application/json" \
        -d '{
            "url": "https://example.com",
            "extraction_strategy": "llm",
            "llm_instruction": "Extract the main heading from the page"
        }' \
        --max-time 60 2>/dev/null)
    
    if [[ -z "$test_response" ]]; then
        return 1
    fi
    
    # Check for successful LLM extraction
    if echo "$test_response" | grep -q '"extraction_strategy":"llm"'; then
        log_debug "[CRAWL4AI] LLM extraction test passed"
        return 0
    fi
    
    return 1
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================
log_debug "[CRAWL4AI] Module loaded successfully"