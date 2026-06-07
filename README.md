# ECE268 Lightweight Block Cipher Project

This project implements three lightweight block ciphers: **PRESENT-80**, **SPECK-64/128**, and **AES**, with support for both CPU and GPU (CUDA) execution. It includes benchmarking utilities, mode of operation tests, and performance analysis tools.

## Project Structure

```
├── PRESENT80/
│   ├── present80.cpp       - CPU implementation
│   ├── present80.cu        - GPU/CUDA implementation
│   └── present80.h         - Header file
├── SPECK64_128/
│   ├── speck64.cpp         - CPU implementation
│   ├── speck64.cu          - GPU/CUDA implementation
│   └── speck64.h           - Header file
├── AES/
│   ├── aes.cpp             - CPU implementation
│   ├── aes.cu              - GPU/CUDA implementation
│   └── aes128.h            - Header file
├── CMakeLists.txt          - Build configuration
├── modes.cpp/modes.h       - Block cipher modes (ECB, CBC, CTR, etc.)
├── modes_test.cpp          - Comprehensive mode testing
├── bench_utils.h           - Benchmarking utilities
├── cpu_bench.cpp           - CPU benchmarking harness
├── build_and_run_all.sh    - Build and run all executables
├── measure_ptx.sh          - PTX code analysis script
└── docs/                   - Documentation and reports
```

## Prerequisites

### For CPU-only builds:
- CMake 3.10 or later
- C++17 compatible compiler (GCC, Clang, or MSVC)

### For CUDA builds:
- CMake 3.10 or later
- NVIDIA CUDA Toolkit (10.0 or later)
- NVIDIA GPU with compute capability 3.0 or later

## Building the Project

### Automatic Build and Run (Recommended)

The easiest way to build and run all 11 executables is to use the provided build script:

```bash
./build_and_run_all.sh
```

This script will:
1. Create a `build/` directory
2. Run CMake configuration
3. Compile all 11 executables
4. Execute each one and capture output
5. Save all outputs to `run_outputs/` directory

**Output files created:**
- `run_outputs/cmake_output.log` - CMake configuration output
- `run_outputs/make_output.log` - Build compilation output
- `run_outputs/<executable>_output.log` - Output from each executable

### Manual Build

Alternatively, you can build manually using CMake:

```bash
mkdir build && cd build
cmake ..
make -j$(nproc)
```

## Executables

The build creates 11 executables:

| Executable | Description |
|-----------|-------------|
| `cpu_bench` | Comprehensive CPU benchmarking for all three ciphers (PRESENT-80, SPECK-64/128, AES) with metrics collection |
| `present80_ecb_cpu` | PRESENT-80 CPU implementation with ECB mode benchmarks |
| `present80_ecb_gpu` | PRESENT-80 GPU/CUDA implementation with ECB mode benchmarks |
| `present80_ctr_gpu` | PRESENT-80 GPU/CUDA implementation with CTR (Counter) mode benchmarks |
| `speck64_ecb_cpu` | SPECK-64/128 CPU implementation with ECB mode benchmarks |
| `speck64_ecb_gpu` | SPECK-64/128 GPU/CUDA implementation with ECB mode benchmarks |
| `speck64_ctr_gpu` | SPECK-64/128 GPU/CUDA implementation with CTR (Counter) mode benchmarks |
| `aes_ecb_cpu` | AES CPU implementation with ECB mode benchmarks |
| `aes_ecb_gpu` | AES GPU/CUDA implementation with ECB mode benchmarks |
| `aes_ctr_gpu` | AES GPU/CUDA implementation with CTR (Counter) mode benchmarks |
| `modes_test` | Comprehensive block cipher modes (ECB, CBC, CTR) testing on CPU |

Each executable performs:
- Encryption/decryption with test vectors
- Round-trip verification (plaintext → encrypt → decrypt → plaintext)
- Performance benchmarking (throughput, cycles per block)

### GPU CTR Mode Implementation

The GPU implementations include **CTR (Counter) mode** for `present80_ctr_gpu`, `speck64_ctr_gpu`, and `aes_ctr_gpu`. CTR mode is ideal for GPU parallelization because:
- Each block encryption is **independent** with only the counter incrementing
- All blocks can be encrypted in **parallel** on CUDA threads
- No data dependencies between blocks, enabling optimal GPU utilization

### Why CBC Mode is Not Implemented for GPU

**CBC (Cipher Block Chaining) mode is not included for GPU implementations** due to fundamental parallelization constraints:
- CBC mode requires each block's ciphertext to depend on the **previous ciphertext block**
- This creates a **sequential dependency chain** that prevents parallel processing
- The dependency enforces strict ordering: block $i$ cannot be encrypted until block $i-1$ has completed
- For GPU acceleration, this sequential nature eliminates the benefit of parallel execution

Therefore, GPU implementations focus on **ECB and CTR modes**, where blocks can be processed independently in parallel. CBC mode remains available exclusively in the `modes_test` CPU implementation for correctness verification and testing purposes.

## Algorithm Overview

### PRESENT-80
- **Block size:** 64 bits
- **Key size:** 80 bits
- **Rounds:** 31
- **Operations:** S-box substitution + P-layer permutation
- **Design:** SPN (Substitution-Permutation Network)
- **Use case:** Lightweight IoT and embedded systems

### SPECK-64/128
- **Block size:** 64 bits (32-bit words)
- **Key size:** 128 bits
- **Rounds:** 27
- **Operations:** ARX (Add-Rotate-Xor)
- **Design:** Feistel-based ARX cipher
- **Use case:** High performance lightweight encryption

### AES (Advanced Encryption Standard)
- **Block size:** 128 bits
- **Key size:** 128 bits (AES-128)
- **Rounds:** 10
- **Operations:** SubBytes, ShiftRows, MixColumns, AddRoundKey
- **Design:** SPN (Substitution-Permutation Network)
- **Use case:** Standard encryption, comparison baseline

## Modes of Operation

The `modes_test` executable implements and tests the following modes:
- **ECB** (Electronic Codebook) - Basic block-by-block encryption
- **CBC** (Cipher Block Chaining) - Chained mode with IV
- **CTR** (Counter) - Stream cipher mode with counter

## Performance Testing

### CPU Benchmarking
The `cpu_bench.cpp` utility benchmarks CPU implementations with:
- Throughput measurement in GB/s
- Cycles per block analysis
- Cache behavior profiling

### GPU Benchmarking
GPU implementations benchmark:
- Parallel encryption of 1,048,576+ blocks
- GPU throughput in MB/s
- Million blocks per second
- CUDA kernel optimization metrics

### Batch Processing
- CPU: Sequential block encryption
- GPU: Parallel batch encryption on NVIDIA CUDA devices

## Usage Examples

### Run Individual Executable
```bash
./build/present80_ecb_cpu
./build/speck64_ctr_gpu
./build/aes_ecb_gpu
./build/modes_test
```

### View Results from Batch Run
```bash
# After running build_and_run_all.sh
cat run_outputs/present80_ecb_cpu_output.log
cat run_outputs/speck64_ctr_gpu_output.log
cat run_outputs/aes_ecb_gpu_output.log
cat run_outputs/modes_test_output.log
```

### Analyze PTX Code (GPU Optimization)
```bash
./measure_ptx.sh
```

## Project Files Reference

- **bench_utils.h** - Utility functions for performance benchmarking
- **cpu_bench.cpp** - CPU-specific benchmarking harness
- **measure_ptx.sh** - Script to analyze NVIDIA PTX assembly code
- **presentation_10min.md** - 10-minute project presentation
- **presentation_2min30sec.md** - 2.5-minute project summary
- **docs/progress_report.tex** - Detailed progress report and analysis
- **figures/generate_figures.py** - Python script for generating performance graphs

## Build Requirements

- **CMake:** 3.10 or later
- **C++ Compiler:** GCC/Clang with C++17 support
- **CUDA (for GPU support):** NVIDIA CUDA Toolkit 10.0+
- **GPU Memory:** 1GB+ recommended for large batch processing

## Build Artifacts

After building with `build_and_run_all.sh`, the following structure is created:
```
build/
├── present80_ecb_cpu
├── present80_ecb_gpu
├── present80_ctr_gpu
├── speck64_ecb_cpu
├── speck64_ecb_gpu
├── speck64_ctr_gpu
├── aes_ecb_cpu
├── aes_ecb_gpu
├── aes_ctr_gpu
├── modes_test
├── cpu_bench
└── CMakeFiles/

run_outputs/
├── cmake_output.log
├── make_output.log
├── present80_ecb_cpu_output.log
├── present80_ecb_gpu_output.log
├── present80_ctr_gpu_output.log
├── speck64_ecb_cpu_output.log
├── speck64_ecb_gpu_output.log
├── speck64_ctr_gpu_output.log
├── aes_ecb_cpu_output.log
├── aes_ecb_gpu_output.log
├── aes_ctr_gpu_output.log
├── modes_test_output.log
└── cpu_bench_output.log
```

## Notes

- Ensure NVIDIA drivers are installed and compatible with your CUDA Toolkit version
- Use `cmake .. -DCMAKE_BUILD_TYPE=Release` for production builds
- The `build_and_run_all.sh` script automatically parallelizes builds using all available CPU cores
- GPU implementations require NVIDIA CUDA capability 3.0 or higher
- Test output verification ensures correctness of all encryption/decryption operations
