#!/bin/bash

# Quick Local Testing Script for Textelerate
# This script provides fast local testing without Docker overhead

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Zig is installed
check_zig() {
    if ! command -v zig &> /dev/null; then
        print_error "Zig is not installed. Please install Zig first."
        exit 1
    fi
    print_success "Zig is installed: $(zig version)"
}

# Run all tests locally (mimics CI test job)
run_tests() {
    print_status "Running test suite locally..."

    echo "1. Running main tests..."
    zig test src/main.zig

    echo "2. Running library tests..."
    zig test src/root.zig

    print_success "All tests passed!"
}

# Check code formatting (mimics CI lint job)
check_formatting() {
    print_status "Checking code formatting..."

    if zig fmt --check src/; then
        print_success "Code formatting is correct"
    else
        print_error "Code formatting issues found. Run 'zig fmt src/' to fix."
        return 1
    fi
}

# Build with all optimization levels (mimics CI build job)
build_all_optimizations() {
    print_status "Building with all optimization levels..."

    echo "1. Building Debug..."
    zig build -Doptimize=Debug

    echo "2. Building ReleaseSafe..."
    zig build -Doptimize=ReleaseSafe

    echo "3. Building ReleaseFast..."
    zig build -Doptimize=ReleaseFast

    echo "4. Building ReleaseSmall..."
    zig build -Doptimize=ReleaseSmall

    print_success "All builds successful!"
}

# Run demo (mimics CI demo step)
run_demo() {
    print_status "Running demo..."
    zig run src/main.zig
    print_success "Demo completed successfully!"
}

# Security checks (mimics CI security job)
run_security_checks() {
    print_status "Running security checks..."

    # Check for potentially unsafe operations
    if grep -r "unsafe\|@ptrCast\|@alignCast" src/ 2>/dev/null; then
        print_warning "Found potentially unsafe operations (review needed)"
    else
        print_success "No obvious unsafe operations found"
    fi

    # Check for hardcoded secrets
    if grep -r -i "password\|secret\|key.*=\|token.*=" src/ 2>/dev/null; then
        print_error "Potential secrets found in source code"
        return 1
    else
        print_success "No hardcoded secrets detected"
    fi

    # Build with safety checks
    print_status "Building with safety checks..."
    zig build -Doptimize=ReleaseSafe

    print_success "Security checks passed!"
}

# Performance benchmark (mimics CI benchmark job)
run_benchmark() {
    print_status "Running performance benchmark..."

    echo "Building optimized version..."
    zig build -Doptimize=ReleaseFast

    echo "Running timed demo..."
    time zig run src/main.zig

    print_success "Benchmark completed!"
}

# Validate project structure
validate_project() {
    print_status "Validating project structure..."

    # Check required files
    local required_files=(
        "README.md"
        "VERSION"
        "build.zig"
        "src/main.zig"
        "src/root.zig"
        "src/error.zig"
        ".github/workflows/ci.yml"
    )

    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            echo "✅ $file exists"
        else
            print_error "$file missing"
            return 1
        fi
    done

    # Check version consistency
    local version=$(cat VERSION)
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
        print_success "Version format is valid: $version"
    else
        print_error "Invalid version format in VERSION file"
        return 1
    fi

    # Check if version is in README
    if grep -q "$version" README.md; then
        print_success "Version is documented in README"
    else
        print_warning "Version not found in README"
    fi

    print_success "Project structure validation passed!"
}

# Get code quality metrics
check_code_quality() {
    print_status "Analyzing code quality..."

    # Count lines of code
    local total_lines=$(find src/ -name "*.zig" -exec wc -l {} + | tail -1 | awk '{print $1}')
    echo "📊 Total lines of code: $total_lines"

    # Count test cases
    local test_count=$(grep -r "test \"" src/ | wc -l)
    echo "🧪 Total test cases: $test_count"

    # Calculate rough test coverage ratio
    if [ $total_lines -gt 0 ]; then
        local coverage_ratio=$((test_count * 100 / (total_lines / 50)))
        echo "📈 Estimated test coverage: ~$coverage_ratio%"

        if [ $coverage_ratio -lt 30 ]; then
            print_warning "Low test coverage detected"
        else
            print_success "Good test coverage"
        fi
    fi

    print_success "Code quality analysis completed!"
}

# Run comprehensive local CI simulation
run_full_ci() {
    print_status "Running full CI simulation locally..."
    print_warning "This will take a few minutes..."

    check_zig
    validate_project
    check_formatting
    run_tests
    build_all_optimizations
    run_demo
    run_security_checks
    run_benchmark
    check_code_quality

    print_success "🎉 Full CI simulation completed successfully!"
    echo ""
    echo "✅ All checks passed - your code is ready for CI/CD!"
}

# Quick smoke test (essential checks only)
run_quick_test() {
    print_status "Running quick smoke test..."

    check_zig
    check_formatting
    run_tests
    zig build

    print_success "🚀 Quick test passed!"
}

# Show help
show_help() {
    echo "Textelerate Quick Local Testing Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  quick       - Quick smoke test (formatting, tests, build)"
    echo "  full        - Full CI simulation (all checks)"
    echo "  test        - Run test suite only"
    echo "  format      - Check code formatting"
    echo "  build       - Build with all optimization levels"
    echo "  demo        - Run the demo"
    echo "  security    - Run security checks"
    echo "  benchmark   - Run performance benchmark"
    echo "  validate    - Validate project structure"
    echo "  quality     - Check code quality metrics"
    echo "  help        - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 quick           # Fast essential checks"
    echo "  $0 full            # Complete CI simulation"
    echo "  $0 test            # Just run tests"
    echo "  $0 format          # Check formatting only"
    echo ""
    echo "This script mimics GitHub Actions CI/CD locally without Docker."
}

# Main script logic
main() {
    local command=${1:-help}

    case $command in
        "quick")
            run_quick_test
            ;;
        "full")
            run_full_ci
            ;;
        "test")
            check_zig
            run_tests
            ;;
        "format")
            check_zig
            check_formatting
            ;;
        "build")
            check_zig
            build_all_optimizations
            ;;
        "demo")
            check_zig
            run_demo
            ;;
        "security")
            check_zig
            run_security_checks
            ;;
        "benchmark")
            check_zig
            run_benchmark
            ;;
        "validate")
            validate_project
            ;;
        "quality")
            check_code_quality
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main with all arguments
main "$@"
