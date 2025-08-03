#!/bin/bash
# Unity Documentation Search Tool
# Search and browse Unity documentation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SEARCH_INDEX="$DOCS_DIR/.search-index"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Build search index if not exists
build_index() {
    echo -e "${BLUE}Building search index...${NC}"
    
    > "$SEARCH_INDEX"
    
    # Index all markdown files
    find "$DOCS_DIR" -name "*.md" -type f | while read -r file; do
        # Extract headers and key content
        grep -n -E "^#{1,3} |^- \*\*.*\*\*:|function.*\(\)" "$file" | while IFS=: read -r line_num content; do
            echo "${file}:${line_num}:${content}" >> "$SEARCH_INDEX"
        done
        
        # Extract code examples
        awk '/^```/ {if (in_code) {in_code=0} else {in_code=1; getline; lang=$1}} 
             in_code && /unity|bash/ {print FILENAME":"NR":"$0}' "$file" >> "$SEARCH_INDEX"
    done
    
    echo -e "${GREEN}Search index built successfully!${NC}"
}

# Search function
search_docs() {
    local query="$1"
    local case_sensitive="${2:-false}"
    local max_results="${3:-20}"
    
    if [[ ! -f "$SEARCH_INDEX" ]]; then
        build_index
    fi
    
    local grep_opts="-i"
    if [[ "$case_sensitive" == "true" ]]; then
        grep_opts=""
    fi
    
    echo -e "${BLUE}Searching for: ${YELLOW}$query${NC}"
    echo ""
    
    local results=$(grep $grep_opts "$query" "$SEARCH_INDEX" | head -n "$max_results")
    
    if [[ -z "$results" ]]; then
        echo "No results found."
        return 1
    fi
    
    # Display results
    local count=0
    while IFS=: read -r file line_num content; do
        ((count++))
        local rel_path="${file#$DOCS_DIR/}"
        
        echo -e "${GREEN}[$count]${NC} ${CYAN}$rel_path${NC}:${YELLOW}$line_num${NC}"
        echo "    $content"
        echo ""
    done <<< "$results"
    
    echo -e "${BLUE}Found $count results${NC}"
}

# Interactive search
interactive_search() {
    clear
    echo -e "${BLUE}Unity Documentation Search${NC}"
    echo "Type 'q' to quit, 'h' for help"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}Search> ${NC}"
        read -r query
        
        case "$query" in
            q|quit|exit)
                echo "Goodbye!"
                break
                ;;
            h|help)
                show_help
                ;;
            rebuild)
                build_index
                ;;
            "")
                continue
                ;;
            *)
                search_docs "$query"
                echo ""
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF

${BLUE}Unity Documentation Search Help${NC}

${GREEN}Commands:${NC}
  q, quit    - Exit search
  h, help    - Show this help
  rebuild    - Rebuild search index

${GREEN}Search Tips:${NC}
  - Use partial words: "deploy" finds "deployment", "deploy", etc.
  - Search functions: "unity_aws" finds all AWS service functions
  - Search by type: "Tutorial", "Example:", "function"
  - Case insensitive by default

${GREEN}Examples:${NC}
  spot instance     - Find spot instance documentation
  unity_config_get  - Find config function documentation
  Tutorial          - Find all tutorials
  plugin develop    - Find plugin development guides

EOF
}

# Browse by category
browse_category() {
    local category="$1"
    
    case "$category" in
        tutorials)
            find "$DOCS_DIR" -name "*tutorial*" -o -name "*guide*" | sort
            ;;
        api)
            find "$DOCS_DIR/api" -name "*.md" | sort
            ;;
        migration)
            find "$DOCS_DIR/migration" -name "*.md" | sort
            ;;
        examples)
            find "$DOCS_DIR/../examples" -name "*.sh" | sort
            ;;
        *)
            echo "Unknown category: $category"
            echo "Available: tutorials, api, migration, examples"
            ;;
    esac
}

# Main function
main() {
    case "${1:-interactive}" in
        search)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Usage: $0 search <query>"
                exit 1
            fi
            search_docs "$@"
            ;;
        interactive|i)
            interactive_search
            ;;
        build|rebuild)
            build_index
            ;;
        browse)
            browse_category "${2:-tutorials}"
            ;;
        help|h)
            show_help
            ;;
        *)
            echo "Usage: $0 {search <query>|interactive|build|browse <category>|help}"
            exit 1
            ;;
    esac
}

# Run main
main "$@"