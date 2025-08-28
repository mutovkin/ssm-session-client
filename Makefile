all: tidy build

demo: run

tidy:
	go mod tidy
# go mod vendor

generate:
	go generate ./...

build: generate
	go build -v ./...

install-tools:
	go install github.com/segmentio/golines@latest
	go install golang.org/x/tools/cmd/goimports@latest
	go install mvdan.cc/gofumpt@latest

fmt:
	gofumpt -w .
	golines -w .
	goimports -w .

lint:
	@golangci-lint run

mod-upgrade:
	go get -u ./...

modernize:
	go run golang.org/x/tools/gopls/internal/analysis/modernize/cmd/modernize@latest -fix -test ./...

test:
	go test -v ./...

clean: clean-examples
	@echo "Cleaning project..."
	@go clean ./...
	@echo "Project cleaned"

benchmark:
	go test -bench . -benchmem  ./...

.PHONY: all benchmark tidy generate build clean install-tools fmt lint mod-upgrade test clean-examples tidy-examples build-examples 

# Tidy Go modules in example subdirectories
# Scans examples/ directory for go.mod files and runs 'go mod tidy' on each
#
# Process flow:
#   1. find examples -name "go.mod" -exec dirname {} \;
#      - Finds all go.mod files under examples/
#      - dirname {} extracts the directory containing each go.mod
#      - Example: examples/auth-demo/go.mod → examples/auth-demo
#
#   2. sort: Ensures consistent ordering of directories
#
#   3. For each directory with go.mod:
#      - cd into the directory
#      - Run 'go mod tidy' to clean up dependencies
#      - cd back to original directory (cd - > /dev/null)
#      - Report success or failure
#
# Error handling: Continue processing other modules if one fails
# This is important for CI/CD pipelines where partial failures shouldn't stop the build
tidy-examples:
	@echo "Tidying examples modules..."
	@for dir in $$(find examples -name "go.mod" -exec dirname {} \; | sort); do \
		echo "Tidying $$dir..."; \
		if cd $$dir && go mod tidy && cd - > /dev/null; then \
			echo "✅ $$dir tidied successfully"; \
		else \
			echo "❌ Failed to tidy $$dir"; \
		fi; \
	done

# Build examples from subdirectories with go.mod files
# This target scans the examples/ directory structure and builds each subdirectory as a separate binary
#
# Directory scanning logic:
#   1. find examples -mindepth 1 -maxdepth 1 -type d
#      - Finds all immediate subdirectories under examples/
#      - mindepth 1: Skip the examples/ directory itself
#      - maxdepth 1: Don't recurse into subdirectories
#      - Example paths: examples/auth-demo, examples/s3-tools
#
#   2. For directories with go.mod: Build as Go module
#      - cd into directory, run go build with module-aware mode
#      - Output binary to ../../bin/example-{dirname}
#
#   3. For directories with .go files but no go.mod: Build as package
#      - cd into directory, run go build . (current package)
#      - Output binary to ../../bin/example-{dirname}
#
# Binary naming convention: example-{directory-name}
#   - examples/auth-demo/ → bin/example-auth-demo
#   - examples/s3-tools/ → bin/example-s3-tools
#
# Error handling: Continue building other examples if one fails
build-examples: generate tidy-examples
	@echo "Creating bin directory..."
	@mkdir -p bin
	@echo "Building examples as binaries..."
	@# Build individual example subdirectories
	@for dir in $$(find examples -mindepth 1 -maxdepth 1 -type d); do \
		if [ -f "$$dir/go.mod" ]; then \
			dirname=$$(basename "$$dir"); \
			echo "Building example-$$dirname from $$dir..."; \
			if cd $$dir && go build -o ../../bin/example-$$dirname ./... && cd - > /dev/null; then \
				echo "✅ example-$$dirname built successfully"; \
			else \
				echo "❌ Failed to build example-$$dirname"; \
			fi; \
		elif [ -n "$$(find "$$dir" -name "*.go" -type f)" ]; then \
			dirname=$$(basename "$$dir"); \
			echo "Building example-$$dirname from $$dir..."; \
			if cd $$dir && go build -o ../../bin/example-$$dirname . && cd - > /dev/null; then \
				echo "✅ example-$$dirname built successfully"; \
			else \
				echo "❌ Failed to build example-$$dirname"; \
			fi; \
		fi; \
	done

# Clean up example binaries and artifacts
# Removes compiled binaries and executables from examples to save space
#
# Cleanup operations:
#   1. rm -rf bin/example-*
#      - Removes all example binaries from bin/ directory
#      - Pattern: bin/example-auth-demo, bin/example-s3-tools, etc.
#
#   2. find examples -type f -name "*.exe" -delete
#      - Removes Windows executables (.exe files) from examples/
#      - 2>/dev/null: Suppresses "no files found" errors
#      - || true: Continues even if find command fails
#
#   3. find examples -type f -perm +111 ! -name "*.go" ! -name "*.mod" ! -name "*.sum" ! -name "*.log" -delete
#      - Finds executable files (permission +111) in examples/
#      - Excludes: .go source files, go.mod/go.sum, .log files
#      - Targets: Compiled binaries without .exe extension (Linux/macOS)
#      - perm +111: Files with execute permission for user, group, or other
#
# This is useful for:
#   - Cleaning up before commits (avoid checking in binaries)
#   - Freeing disk space during development
#   - Preparing clean builds in CI/CD
clean-examples:
	@echo "Cleaning example binaries..."
	@rm -rf bin/example-*
	@find examples -type f -name "*.exe" -delete 2>/dev/null || true
	@find examples -type f -perm +111 ! -name "*.go" ! -name "*.mod" ! -name "*.sum" ! -name "*.log" -delete 2>/dev/null || true
	@echo "Example binaries cleaned"