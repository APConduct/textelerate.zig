#!/bin/bash

# Textelerate CI/CD Local Testing Script
# This script uses 'act' to run GitHub Actions workflows locally for testing

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if act is installed
check_act_installed() {
    if ! command -v act &> /dev/null; then
        print_error "act is not installed. Please install it first:"
        echo "  macOS: brew install act"
        echo "  Linux: curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
        echo "  Windows: choco install act-cli"
        exit 1
    fi
    print_success "act is installed: $(act --version)"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    print_success "Docker is running"
}

# Function to list available workflows
list_workflows() {
    print_status "Available workflows:"
    act --list
}

# Function to run basic tests (fast subset)
run_basic_tests() {
    print_status "Running basic CI tests (fast subset)..."

    # Run just the test job on ubuntu with minimal setup
    act \
        --job test \
        --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
        --env ZIG_VERSION=0.13.0 \
        --matrix os:ubuntu-latest \
        --matrix zig-version:0.13.0 \
        --artifact-server-path /tmp/artifacts \
        --verbose
}

# Function to run specific job
run_job() {
    local job_name=$1
    if [ -z "$job_name" ]; then
        print_error "No job name provided"
        echo "Usage: $0 job <job_name>"
        echo "Available jobs: test, lint, security, coverage, benchmark"
        exit 1
    fi

    print_status "Running job: $job_name"
    act --job "$job_name" --platform ubuntu-latest=catthehacker/ubuntu:act-latest
}

# Function to run full CI workflow
run_full_ci() {
    print_status "Running full CI workflow..."
    print_warning "This may take 10-15 minutes..."

    # Run the main CI workflow
    act \
        --workflows .github/workflows/ci.yml \
        --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
        --env ZIG_VERSION=0.13.0 \
        --artifact-server-path /tmp/artifacts
}

# Function to test release workflow (dry run)
test_release_workflow() {
    print_status "Testing release workflow (dry run)..."

    # Create a fake tag event
    act \
        --workflows .github/workflows/release.yml \
        --eventpath <(echo '{"inputs":{"version_type":"patch","prerelease":false,"draft":true}}') \
        --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
        --env ZIG_VERSION=0.13.0 \
        --dry-run
}

# Function to test dependency update workflow
test_deps_workflow() {
    print_status "Testing dependency update workflow..."

    act \
        --workflows .github/workflows/update-deps.yml \
        --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
        --env ZIG_VERSION=0.13.0
}

# Function to run linting and formatting checks
run_lint_checks() {
    print_status "Running lint and formatting checks..."

    act \
        --job lint \
        --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
        --env ZIG_VERSION=0.13.0
}

# Function to run security scans
run_security_scans() {
    print_status "Running security scans..."

    act \
        --job security \
        --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
        --env ZIG_VERSION=0.13.0
}

# Function to simulate different events
simulate_event() {
    local event_type=$1
    case $event_type in
        "push")
            print_status "Simulating push event to main branch..."
            act push --platform ubuntu-latest=catthehacker/ubuntu:act-latest
            ;;
        "pr")
            print_status "Simulating pull request event..."
            act pull_request --platform ubuntu-latest=catthehacker/ubuntu:act-latest
            ;;
        "tag")
            print_status "Simulating tag push event..."
            act \
                --eventpath <(echo '{"ref":"refs/tags/v0.1.1"}') \
                --platform ubuntu-latest=catthehacker/ubuntu:act-latest
            ;;
        *)
            print_error "Unknown event type: $event_type"
            echo "Available events: push, pr, tag"
            exit 1
            ;;
    esac
}

# Function to clean up act artifacts and containers
cleanup() {
    print_status "Cleaning up act artifacts and containers..."

    # Remove act containers
    docker ps -a --filter "label=act" -q | xargs -r docker rm -f

    # Remove act images (optional - comment out to keep for faster subsequent runs)
    # docker images --filter "reference=catthehacker/*" -q | xargs -r docker rmi -f

    # Clean up temporary artifacts
    rm -rf /tmp/artifacts

    print_success "Cleanup completed"
}

# Function to show help
show_help() {
    echo "Textelerate CI/CD Local Testing Script"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  check       - Check prerequisites (act, docker)"
    echo "  list        - List available workflows and jobs"
    echo "  basic       - Run basic tests (fast)"
    echo "  job <name>  - Run specific job (test, lint, security, etc.)"
    echo "  full        - Run full CI workflow"
    echo "  release     - Test release workflow (dry run)"
    echo "  deps        - Test dependency update workflow"
    echo "  lint        - Run linting and formatting checks"
    echo "  security    - Run security scans"
    echo "  event <type> - Simulate event (push, pr, tag)"
    echo "  cleanup     - Clean up containers and artifacts"
    echo "  help        - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 check                    # Check prerequisites"
    echo "  $0 basic                    # Run basic tests"
    echo "  $0 job test                 # Run only test job"
    echo "  $0 lint                     # Run formatting checks"
    echo "  $0 event push               # Simulate push to main"
    echo "  $0 cleanup                  # Clean up after testing"
    echo ""
    echo "Options:"
    echo "  --verbose   - Enable verbose output"
    echo "  --dry-run   - Show what would be executed without running"
}

# Main script logic
main() {
    local command=${1:-help}

    case $command in
        "check")
            check_act_installed
            check_docker
            print_success "All prerequisites are met!"
            ;;
        "list")
            check_act_installed
            list_workflows
            ;;
        "basic")
            check_act_installed
            check_docker
            run_basic_tests
            ;;
        "job")
            check_act_installed
            check_docker
            run_job "$2"
            ;;
        "full")
            check_act_installed
            check_docker
            run_full_ci
            ;;
        "release")
            check_act_installed
            check_docker
            test_release_workflow
            ;;
        "deps")
            check_act_installed
            check_docker
            test_deps_workflow
            ;;
        "lint")
            check_act_installed
            check_docker
            run_lint_checks
            ;;
        "security")
            check_act_installed
            check_docker
            run_security_scans
            ;;
        "event")
            check_act_installed
            check_docker
            simulate_event "$2"
            ;;
        "cleanup")
            cleanup
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

# Run main function with all arguments
main "$@"
