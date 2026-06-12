#!/bin/bash

# Build and run all cipher benchmarks; logs land in run_outputs/

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/run_outputs"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "Building All Executables"
echo "========================================"

# Clean and build
if [ -d "$BUILD_DIR" ]; then
    echo "[*] Cleaning previous build..."
    rm -rf "$BUILD_DIR"
fi

echo "[*] Creating build directory..."
mkdir -p "$BUILD_DIR"

echo "[*] Running CMake..."
cd "$BUILD_DIR"
cmake .. > "$OUTPUT_DIR/cmake_output.log" 2>&1

echo "[*] Building with make..."
make -j$(nproc) > "$OUTPUT_DIR/make_output.log" 2>&1

echo "[*] Build completed successfully!"
echo ""

# Define executables to run
EXECUTABLES=(
    "present80_ecb_cpu"
    "present80_ecb_gpu"
    "present80_ctr_gpu"
    "speck64_ecb_cpu"
    "speck64_ecb_gpu"
    "speck64_ctr_gpu"
    "aes_ecb_cpu"
    "aes_ecb_gpu"
    "aes_ctr_gpu"
    "modes_test"
    "cpu_bench"
)

echo "========================================"
echo "Running All Executables"
echo "========================================"
echo "[*] Run started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Full benchmark batch: per-cipher sweeps, modes_test, cpu_bench aggregate
for exe in "${EXECUTABLES[@]}"; do
    if [ -f "$BUILD_DIR/$exe" ]; then
        OUTPUT_FILE="$OUTPUT_DIR/${exe}_output.log"
        echo "[*] Running $exe..."
        if "$BUILD_DIR/$exe" > "$OUTPUT_FILE" 2>&1; then
            echo "    ✓ Success - output saved to $OUTPUT_FILE"
        else
            EXIT_CODE=$?
            echo "    ✗ Failed with exit code $EXIT_CODE - output saved to $OUTPUT_FILE"
        fi
    else
        echo "[!] Executable not found: $exe"
    fi
done

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Output files saved to: $OUTPUT_DIR"
echo ""
echo "Generated output files:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "To view results:"
echo "  cat $OUTPUT_DIR/<executable>_output.log"
