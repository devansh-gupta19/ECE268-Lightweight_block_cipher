# ECE268 Lightweight Block Cipher Project

This project implements two lightweight block ciphers: **PRESENT-80** and **SPECK-64/128**, with support for both CPU and GPU (CUDA) execution.

## Project Structure

- `present80.cpp` - CPU implementation of PRESENT-80
- `present80.cu` - GPU/CUDA implementation of PRESENT-80
- `speck64.cpp` - CPU implementation of SPECK-64/128
- `CMakeLists.txt` - Build configuration with compiler options
- `present80.cpp` and `speck64.cpp` - Test implementations

## Prerequisites

### For CPU-only builds:
- CMake 3.10 or later
- C++17 compatible compiler (GCC, Clang, or MSVC)

### For CUDA builds:
- CMake 3.10 or later
- NVIDIA CUDA Toolkit (10.0 or later)
- NVIDIA GPU with compute capability 3.0 or later

## Building the Project

Use CMake to configure and build. You can control two options:

| Option | Default | Values |
|--------|---------|--------|
| `USE_CUDA` | `ON` | `ON` (CUDA) / `OFF` (CPU) |
| `CIPHER_SELECTION` | `PRESENT80` | `PRESENT80` / `SPECK64` |

### Build Variants

#### 1. CPU PRESENT-80 (default)
```bash
mkdir build && cd build
cmake -DUSE_CUDA=OFF -DCIPHER_SELECTION=PRESENT80 ..
make
./block_cipher
```

#### 2. CPU SPECK-64/128
```bash
mkdir build && cd build
cmake -DUSE_CUDA=OFF -DCIPHER_SELECTION=SPECK64 ..
make
./block_cipher
```

#### 3. CUDA PRESENT-80
```bash
mkdir build && cd build
cmake -DUSE_CUDA=ON -DCIPHER_SELECTION=PRESENT80 ..
make
./block_cipher
```

#### 4. CUDA SPECK-64/128
```bash
mkdir build && cd build
cmake -DUSE_CUDA=ON -DCIPHER_SELECTION=SPECK64 ..
make
./block_cipher
```

### Quick Reference

**CPU builds (fastest to configure):**
```bash
cmake -DUSE_CUDA=OFF ..
```

**CUDA builds (requires NVIDIA CUDA Toolkit):**
```bash
cmake -DUSE_CUDA=ON ..
```

**Select cipher:**
```bash
cmake -DCIPHER_SELECTION=PRESENT80 ..   # or SPECK64
```

## Algorithm Overview

### PRESENT-80
- **Block size:** 64 bits
- **Key size:** 80 bits
- **Rounds:** 31
- **Operations:** S-box substitution + P-layer permutation
- **Design:** SPN (Substitution-Permutation Network)

### SPECK-64/128
- **Block size:** 64 bits (32-bit words)
- **Key size:** 128 bits
- **Rounds:** 27
- **Operations:** ARX (Add-Rotate-Xor)
- **Design:** Feistel-based ARX cipher

## Performance

The CUDA variant encrypts 1,048,576 blocks (~8 MB) in parallel, with performance reported in:
- Milliseconds elapsed
- GB/s throughput
- Million blocks/second

## Testing

Each implementation includes verification:
- Single block encryption/decryption with test vectors
- Round-trip verification (plaintext → encrypt → decrypt → plaintext)
- For CUDA: Batch verification of all 1M+ blocks for correctness

## Compilation Flags

- `-O3` - Aggressive optimization
- `-Wall` - Enable all warnings
- `-g` - Debug symbols
- `-std=c++17` - C++17 standard
