# Local CI/CD Testing Guide

This guide explains how to test your Textelerate CI/CD workflows locally before pushing to GitHub, saving time and iterations.

## Quick Start

### Option 1: Quick Native Testing (Recommended)

For fast local testing without Docker overhead:

```bash
# Quick smoke test (30 seconds)
./scripts/quick-test.sh quick

# Full CI simulation (3-5 minutes)
./scripts/quick-test.sh full
```

### Option 2: Full Docker-based Testing with act

For exact GitHub Actions simulation:

```bash
# Install act (if not already installed)
brew install act  # macOS
# or see installation instructions below

# List available workflows
act --list

# Run a specific job
act --job test --platform ubuntu-latest=catthehacker/ubuntu:act-latest

# Run full CI workflow
act --workflows .github/workflows/ci.yml
```

## Prerequisites

### For Quick Testing
- **Zig**: Version 0.13.0 or later
- **Git**: For version checking

### For act Testing
- **Docker**: Must be running
- **act**: GitHub Actions local runner
- **8GB+ RAM**: For Docker containers
- **Good internet**: First run downloads ~500MB of Docker images
- **Environment file**: Copy `env.act.template` to `.env.act`

## Installation

### Install act

**macOS:**
```bash
brew install act
```

**Linux:**
```bash
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

**Windows:**
```bash
choco install act-cli
# or download from: https://github.com/nektos/act/releases
```

### Verify Installation

```bash
act --version
docker --version
zig version

# Set up environment file for act
cp env.act.template .env.act
```

## Testing Options

### 1. Quick Native Testing

Uses your local Zig installation to run tests quickly without Docker.

#### Available Commands

```bash
# Essential checks (fast)
./scripts/quick-test.sh quick

# Complete CI simulation
./scripts/quick-test.sh full

# Individual components
./scripts/quick-test.sh test        # Run test suite
./scripts/quick-test.sh format      # Check formatting
./scripts/quick-test.sh build       # Build all optimizations
./scripts/quick-test.sh demo        # Run demo
./scripts/quick-test.sh security    # Security checks
./scripts/quick-test.sh benchmark   # Performance test
./scripts/quick-test.sh validate    # Project structure
./scripts/quick-test.sh quality     # Code metrics
```

#### What It Tests

- ✅ **Code Formatting**: `zig fmt --check`
- ✅ **Test Suite**: All 18 tests with both `main.zig` and `root.zig`
- ✅ **Build Matrix**: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall
- ✅ **Demo Execution**: Ensures examples work
- ✅ **Security Scans**: Checks for unsafe operations and secrets
- ✅ **Project Structure**: Validates required files exist
- ✅ **Version Consistency**: Checks semver format and documentation
- ✅ **Code Quality**: Metrics on test coverage and complexity

### 2. Docker-based Testing with act

Provides exact GitHub Actions environment simulation.

#### Basic Usage

```bash
# List all available jobs
act --list

# Run specific job
act --job test

# Run with specific platform
act --job test --platform ubuntu-latest=catthehacker/ubuntu:act-latest

# Run entire workflow
act --workflows .github/workflows/ci.yml

# Simulate different events
act push                    # Push to main
act pull_request           # Pull request
act workflow_dispatch      # Manual trigger
```

#### Advanced Usage

```bash
# Run with custom environment
act --env ZIG_VERSION=0.13.0 --job test

# Run with secrets (for testing release workflow)
act --secret GITHUB_TOKEN=your_token --workflows .github/workflows/release.yml

# Run with matrix strategy (single combination)
act --job test --matrix os:ubuntu-latest --matrix zig-version:0.13.0

# Dry run (show what would execute)
act --job test --platform ubuntu-latest=catthehacker/ubuntu:act-latest --list

# Verbose output for debugging
act --job test --verbose
```

#### Using the Comprehensive Script

```bash
# Check prerequisites
./scripts/test-ci-local.sh check

# Run basic tests (faster)
./scripts/test-ci-local.sh basic

# Run specific job
./scripts/test-ci-local.sh job test
./scripts/test-ci-local.sh job lint
./scripts/test-ci-local.sh job security

# Run full CI workflow (10-15 minutes)
./scripts/test-ci-local.sh full

# Test different events
./scripts/test-ci-local.sh event push
./scripts/test-ci-local.sh event pr
./scripts/test-ci-local.sh event tag

# Test release workflow (dry run)
./scripts/test-ci-local.sh release

# Clean up containers and images
./scripts/test-ci-local.sh cleanup
```

## Workflow Coverage

### Supported Workflows

| Workflow | Quick Test | act Support | Notes |
|----------|------------|-------------|-------|
| **CI/CD Pipeline** | ✅ Full | ✅ Full | Main testing workflow |
| **Release Preparation** | ✅ Partial | ✅ Full | Version validation only in quick |
| **Update Dependencies** | ✅ Partial | ✅ Full | Structure validation only in quick |

### Job Coverage

| Job | Quick Test | act Test | Description |
|-----|------------|----------|-------------|
| `test` | ✅ | ✅ | Run test suite on multiple platforms |
| `lint` | ✅ | ✅ | Code formatting and quality checks |
| `security` | ✅ | ✅ | Security vulnerability scanning |
| `coverage` | ❌ | ✅ | Test coverage analysis |
| `benchmark` | ✅ | ✅ | Performance benchmarking |
| `release` | ❌ | ✅ | Release artifact creation |
| `docs` | ❌ | ✅ | Documentation validation |

## Configuration Files

### `.actrc`
Default configuration for act:
```bash
# Platform mappings
-P ubuntu-latest=catthehacker/ubuntu:act-latest
-P windows-latest=catthehacker/ubuntu:act-latest
-P macos-latest=catthehacker/ubuntu:act-latest

# Default settings
--platform ubuntu-latest=catthehacker/ubuntu:act-latest
--env GITHUB_TOKEN=fake_token_for_local_testing
--verbose
--pull=false
```

### `.env.act`
Environment variables for local testing:
```bash
# Copy the template file first
cp env.act.template .env.act

# Then customize as needed
GITHUB_TOKEN=fake_token_for_local_testing
GITHUB_REPOSITORY=yourusername/textelerate
ZIG_VERSION=0.13.0
CI=true
GITHUB_ACTIONS=true
LOCAL_TESTING=true

# Note: .env.act is in .gitignore for security
```

## Troubleshooting

### Common Issues

### Docker Issues
```bash
# Docker not running
Error: Docker is not running
Solution: Start Docker Desktop

# Permission denied
Error: permission denied while trying to connect to Docker
Solution: Add user to docker group or run with sudo

# Platform architecture warnings
Warning: You are using Apple M-series chip
Solution: Add --container-architecture linux/amd64

# Missing environment file
Error: environment file not found
Solution: cp env.act.template .env.act
```

#### act Issues
```bash
# Unknown flags
Error: unknown flag: --dry-run
Solution: Check act version, some flags are version-specific

# Image pull failures
Error: failed to pull image
Solution: Check internet connection, try --pull=true

# Memory issues
Error: container killed (OOMKilled)
Solution: Increase Docker memory limit to 8GB+
```

#### Zig Issues
```bash
# Zig version mismatch
Error: zig version not compatible
Solution: Install Zig 0.13.0 or later

# Build failures
Error: build failed
Solution: Run ./scripts/quick-test.sh format first
```

### Performance Tips

#### For act
1. **Use --pull=false** after first run to avoid re-downloading images
2. **Limit matrix combinations** for faster testing
3. **Use --container-architecture linux/amd64** on M1 Macs
4. **Clean up regularly** with `./scripts/test-ci-local.sh cleanup`

#### For Quick Testing
1. **Use quick command** for fast iteration
2. **Run specific components** instead of full suite when debugging
3. **Check formatting first** before running tests

## Example Workflows

### Pre-Commit Testing
```bash
# Quick validation before committing
./scripts/quick-test.sh quick

# If quick test passes, optionally run full test
./scripts/quick-test.sh full
```

### Pre-Push Testing
```bash
# Test the main CI workflow that will run on GitHub
act --job test --job lint --job security
```

### Release Testing
```bash
# Validate release preparation locally
./scripts/quick-test.sh validate

# Test release workflow (requires Docker)
act --workflows .github/workflows/release.yml --eventpath events/release.json
```

### Debugging Failed CI
```bash
# Run the exact job that failed
act --job failing_job_name --verbose

# Check specific step
act --job test --step "Run tests"
```

## Integration with Development

### VS Code Integration

Add to `.vscode/tasks.json`:
```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Quick Test",
            "type": "shell",
            "command": "./scripts/quick-test.sh quick",
            "group": "test",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            }
        }
    ]
}
```

### Git Hooks

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
echo "Running pre-commit tests..."
./scripts/quick-test.sh quick
```

### Makefile Integration

```makefile
.PHONY: test-quick test-full test-ci

test-quick:
	./scripts/quick-test.sh quick

test-full:
	./scripts/quick-test.sh full

test-ci:
	act --job test --job lint --job security
```

## Comparison: Quick vs act

| Aspect | Quick Testing | act Testing |
|--------|---------------|-------------|
| **Speed** | ⚡ Fast (30s-5min) | 🐌 Slower (5-15min) |
| **Accuracy** | 🎯 High for basic checks | 🔬 Exact GitHub simulation |
| **Resource Usage** | 💚 Low (native) | 🔴 High (Docker) |
| **Setup** | ✅ Zero setup | ⚙️ Docker + act required |
| **Platform Testing** | ❌ Local only | ✅ Multi-platform |
| **Matrix Testing** | ❌ No | ✅ Full matrix support |
| **Secrets Testing** | ❌ No | ✅ Yes |

## Best Practices

### Development Workflow
1. **Use quick testing** during development iterations
2. **Run act testing** before important commits
3. **Test both workflows** before releases
4. **Clean up regularly** to save disk space

### CI/CD Strategy
1. **Test locally first** to catch issues early
2. **Use matrix testing** to verify cross-platform compatibility
3. **Validate secrets** and environment variables
4. **Test edge cases** like different Zig versions

### Debugging Strategy
1. **Start with quick test** to isolate Zig-specific issues
2. **Use act verbose mode** for detailed debugging
3. **Test individual jobs** rather than full workflows
4. **Check logs carefully** for specific error messages

## Resources

- **act Documentation**: https://github.com/nektos/act
- **GitHub Actions Documentation**: https://docs.github.com/en/actions
- **Zig Documentation**: https://ziglang.org/documentation/
- **Docker Documentation**: https://docs.docker.com/

## Contributing

When contributing to Textelerate:

1. **Set up environment**: `cp env.act.template .env.act`
2. **Run local tests first**: `./scripts/quick-test.sh quick`
3. **Validate with act**: `act --job test --job lint`
4. **Check all platforms**: Use matrix testing for cross-platform changes
5. **Update tests**: Add tests for new features
6. **Update documentation**: Keep this guide current
7. **Never commit secrets**: `.env.act` is in `.gitignore` for a reason

---

**💡 Pro Tip**: Start with quick testing for fast feedback, then use act for comprehensive validation before pushing to GitHub. This approach gives you the best of both worlds: speed during development and accuracy before deployment.