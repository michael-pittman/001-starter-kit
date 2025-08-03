#!/bin/bash
# Simple test for Unity service dependencies

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required files
source "$PROJECT_ROOT/lib/unity/core/unity-core.sh"
source "$PROJECT_ROOT/lib/unity/core/service-dependency-resolver.sh"

echo "=== Unity Service Dependency Test ==="
echo

# Test 1: Initialize systems
echo "Test 1: Initializing Unity core..."
unity_init
if [[ $? -eq 0 ]]; then
    echo "✓ Unity core initialized"
else
    echo "✗ Unity core initialization failed"
fi

echo
echo "Test 2: Testing dependency resolver..."
init_dependency_resolver

# Define test dependencies
register_service_dependencies "service-a" "service-b" "service-c"
register_service_dependencies "service-b" "service-d"
register_service_dependencies "service-c" "service-d"
register_service_dependencies "service-d"

# Validate dependencies
if validate_service_dependencies; then
    echo "✓ Dependency validation passed"
else
    echo "✗ Dependency validation failed"
fi

# Get initialization order
echo
echo "Test 3: Getting initialization order..."
order=$(get_service_initialization_order)
echo "Initialization order: $order"

# Test Unity service dependencies
echo
echo "Test 4: Testing Unity service dependencies..."
init_dependency_resolver
define_unity_service_dependencies

if validate_service_dependencies; then
    echo "✓ Unity service dependencies are valid"
    unity_order=$(get_service_initialization_order)
    echo "Unity services initialization order: $unity_order"
else
    echo "✗ Unity service dependencies have cycles"
fi

# Test actual service registration
echo
echo "Test 5: Testing service registration..."

# Create temp directory for test services
TEST_DIR="/tmp/unity-dep-test-$$"
mkdir -p "$TEST_DIR/services"

# Create simple test service
cat > "$TEST_DIR/services/test-service.sh" << 'EOF'
#!/bin/bash
init_test_service() {
    echo "Test service initialized"
    return 0
}
EOF

# Register and initialize
unity_register_service "test" "$TEST_DIR/services/test-service.sh" "test" ""
if unity_initialize_service "test"; then
    echo "✓ Service initialized successfully"
else
    echo "✗ Service initialization failed"
fi

# Cleanup
rm -rf "$TEST_DIR"

echo
echo "=== Test Complete ==="