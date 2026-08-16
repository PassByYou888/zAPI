#!/bin/bash
# check_all.sh
# One-click build check for all client and server demos.
# Automatically enables CGO and sets the library path.

set -e

# Enable CGO (required for cross-platform)
export CGO_ENABLED=1

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we are in the correct directory
if [[ ! -d "$SCRIPT_DIR/api_hub" || ! -d "$SCRIPT_DIR/demos" ]]; then
    echo "❌ Please run this script from the Go root (containing api_hub and demos folders)."
    exit 1
fi

echo "========================================"
echo "🔍 Full check of all demos (client + server)"
echo "========================================"
echo

# Display environment info
go version
echo "CGO_ENABLED: $(go env CGO_ENABLED)"
echo

# Tidy dependencies
echo "📦 Running go mod tidy..."
go mod tidy

PASS=0
FAIL=0
LOG=""

# Function to build a given package
test_build() {
    local name="$1"
    local path="$2"
    echo -n "🔨 Building $name ... "
    # Use a temporary file for the output binary
    local tmp_bin=$(mktemp -p /tmp test_build_XXXXXX)
    if go build -o "$tmp_bin" "$path" 2>&1; then
        echo "✅ PASS"
        ((PASS++))
        rm -f "$tmp_bin"
    else
        echo "❌ FAIL"
        ((FAIL++))
        LOG+="\n--- FAIL: $name ---\n$(go build -o "$tmp_bin" "$path" 2>&1)\n"
    fi
}

# 1. Build the core api_hub package
test_build "api_hub (package)" "./api_hub"

# 2. Build all demo subdirectories
echo
echo "📂 Checking demos subdirectories..."
for dir in "$SCRIPT_DIR"/demos/*/; do
    # Check if there is at least one .go file
    if [[ -n $(find "$dir" -maxdepth 1 -name "*.go" -print -quit) ]]; then
        test_build "$(basename "$dir")" "$dir"
    fi
done

echo
echo "========================================"
echo "📊 Total: $((PASS+FAIL)) items"
echo "✅ Pass: $PASS"
echo "❌ Fail: $FAIL"

if [[ $FAIL -eq 0 ]]; then
    echo "🎉 All demos compiled successfully!"
else
    echo
    echo "📋 Detailed failure log (copy to AI for diagnosis):"
    echo "----------------------------------------"
    echo -e "$LOG"
    echo "----------------------------------------"
    echo "💡 Hint: Ensure CGO is enabled (CGO_ENABLED=1)."
fi