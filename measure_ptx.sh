#!/usr/bin/env bash
# Measures compiled PTX text size, cubin binary size, and SASS instruction count
# for the PRESENT-80 and SPECK-64 CUDA kernels.
# Usage: ./measure_ptx.sh
# Output: printed to stdout and saved to logs/ptx_size_<timestamp>.log

set -e
ARCH=sm_89
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p logs
TS=$(date +%Y%m%d_%H%M%S)
OUT="logs/ptx_size_${TS}.log"

{
  echo "=== PTX / Cubin Size Report ==="
  echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "arch: $ARCH"
  echo "nvcc: $(nvcc --version | grep release | awk '{print $5}' | tr -d ',')"
  echo "---"

  for CU in present80 speck64; do
    echo ""
    echo "--- ${CU}.cu ---"

    # PTX (human-readable IR)
    nvcc -arch=$ARCH --ptx "${CU}.cu" -o "/tmp/${CU}_meas.ptx" 2>/dev/null
    ptx_bytes=$(wc -c < "/tmp/${CU}_meas.ptx")
    ptx_lines=$(wc -l < "/tmp/${CU}_meas.ptx")
    echo "${CU}_ptx_bytes: $ptx_bytes"
    echo "${CU}_ptx_lines: $ptx_lines"

    # Cubin (binary)
    nvcc -arch=$ARCH --cubin "${CU}.cu" -o "/tmp/${CU}_meas.cubin" 2>/dev/null
    cubin_bytes=$(stat -c%s "/tmp/${CU}_meas.cubin")
    echo "${CU}_cubin_bytes: $cubin_bytes"

    # SASS instruction count (if cuobjdump available)
    if command -v cuobjdump &>/dev/null; then
      sass_instr=$(cuobjdump -sass "/tmp/${CU}_meas.cubin" 2>/dev/null | grep -c '/\*' || echo 0)
      echo "${CU}_sass_instructions: $sass_instr"
    else
      echo "${CU}_sass_instructions: cuobjdump_not_available"
    fi

    # Cleanup temp files
    rm -f "/tmp/${CU}_meas.ptx" "/tmp/${CU}_meas.cubin"
  done

} | tee "$OUT"

echo ""
echo "Log saved to: $OUT"
