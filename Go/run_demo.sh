#!/bin/bash
# run_demo.sh
# Automatically sets the library search path (../Binary) and runs a specified Go demo.
# Usage:
#   ./run_demo.sh                    # Interactive selection
#   ./run_demo.sh calc_server        # Run demos/calc_server directly
#   ./run_demo.sh -DemoName calc_server  # Same

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the Binary directory (one level up from the Go directory)
BINARY_PATH="$(realpath "$SCRIPT_DIR/../Binary" 2>/dev/null || echo "")"
if [[ -z "$BINARY_PATH" || ! -d "$BINARY_PATH" ]]; then
    echo "❌ Binary directory not found at $SCRIPT_DIR/../Binary"
    echo "Please ensure the structure is: Go directory and Binary directory are siblings (under API_Hub_Tool/DLL-Build)."
    exit 1
fi

# Add Binary to LD_LIBRARY_PATH (Linux/macOS) for runtime library loading
export LD_LIBRARY_PATH="$BINARY_PATH:$LD_LIBRARY_PATH"
# For macOS, also set DYLD_LIBRARY_PATH
export DYLD_LIBRARY_PATH="$BINARY_PATH:$DYLD_LIBRARY_PATH"
echo "✅ Added library search path: $BINARY_PATH"

# Check if go is available
if ! command -v go &> /dev/null; then
    echo "❌ go command not found. Please install Go and ensure it's in PATH."
    exit 1
fi

DEMO_NAME="$1"

# If no demo name provided, interactively list available demos
if [[ -z "$DEMO_NAME" ]]; then
    DEMOS_DIR="$SCRIPT_DIR/demos"
    if [[ ! -d "$DEMOS_DIR" ]]; then
        echo "❌ demos directory not found: $DEMOS_DIR"
        exit 1
    fi

    # Collect directories with .go files
    mapfile -t SUB_DIRS < <(find "$DEMOS_DIR" -mindepth 1 -maxdepth 1 -type d -exec sh -c 'find "$1" -maxdepth 1 -name "*.go" -print -quit | grep -q .' _ {} \; -print | sort)

    if [[ ${#SUB_DIRS[@]} -eq 0 ]]; then
        echo "❌ No demo directories with Go files found."
        exit 1
    fi

    echo
    echo "Available demos:"
    i=1
    declare -A NAME_MAP
    for dir in "${SUB_DIRS[@]}"; do
        name=$(basename "$dir")
        echo "  $i. $name"
        NAME_MAP[$i]="$name"
        ((i++))
    done

    read -p $'\nEnter number or demo name: ' choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        idx=$((choice))
        if [[ -n "${NAME_MAP[$idx]}" ]]; then
            DEMO_NAME="${NAME_MAP[$idx]}"
        else
            echo "❌ Invalid number."
            exit 1
        fi
    else
        DEMO_NAME="$choice"
    fi
fi

# Verify demo directory exists
DEMO_PATH="$SCRIPT_DIR/demos/$DEMO_NAME"
if [[ ! -d "$DEMO_PATH" ]]; then
    echo "❌ Demo '$DEMO_NAME' does not exist at $DEMO_PATH"
    exit 1
fi

# Check for .go files
if [[ -z $(find "$DEMO_PATH" -maxdepth 1 -name "*.go" -print -quit) ]]; then
    echo "❌ No .go files found in demo '$DEMO_NAME'."
    exit 1
fi

echo
echo "🚀 Running demo: $DEMO_NAME ..."
cd "$DEMO_PATH"
# Execute go run (automatically compiles and runs)
if go run .; then
    echo
    echo "✅ Demo completed."
else
    echo
    echo "❌ Run failed with error code $?."
fi