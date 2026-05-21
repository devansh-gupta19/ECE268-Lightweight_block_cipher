# ECE268-Lightweight_block_cipher 
## PRESENT-80 Block Cipher

A C++ implementation of the **PRESENT-80** lightweight block cipher with optional **CUDA GPU parallelization** for high-throughput bulk encryption.

---

### What is PRESENT-80?

PRESENT is an ultra-lightweight block cipher designed for constrained environments such as RFID tags, embedded systems, and IoT devices. It was proposed by Bogdanov et al. in 2007 and is standardized under **ISO/IEC 29192-2**.

| Parameter       | Value         |
|----------------|---------------|
| Block size      | 64 bits       |
| Key size        | 80 bits       |
| Number of rounds| 31 + final key addition (32 round keys total) |
| Structure       | Substitution–Permutation Network (SPN) |

#### Algorithm Overview

Each of the 31 rounds applies three operations in order:

1. **`addRoundKey`** — XOR the 64-bit state with the current 64-bit round key
2. **`sBoxLayer`** — Apply a 4-bit S-box to each of the 16 nibbles of the state
3. **`pLayer`** — Permute the 64 state bits using the fixed permutation `P(i) = (16·i) mod 63`, with bit 63 fixed

After round 31, a final `addRoundKey` is applied (no S-box or P-layer).

#### Key Schedule

The 80-bit key register is updated each round by:
1. Rotating left by 61 positions
2. Applying the S-box to the top 4 bits (K[79:76])
3. XORing the 5-bit round counter into bits K[19:15]

---

### Project Structure

```
.
├── present80.cpp       # Single-threaded CPU implementation
├── present80.cu        # CUDA GPU-parallel implementation
├── CMakeLists.txt      # Build system (supports CPU and CUDA builds)
└── README.md
```

---

### CPU vs GPU Implementation

| Feature                  | CPU (`present80.cpp`)         | GPU (`present80.cu`)                  |
|--------------------------|-------------------------------|---------------------------------------|
| Parallelism              | Single block at a time        | Thousands of blocks simultaneously    |
| Key schedule             | Computed per cipher instance  | Computed once on CPU, uploaded to GPU |
| Round key storage        | Stack array                   | `__constant__` memory (cached)        |
| Typical throughput       | ~1–5 M blocks/s (single core) | ~500–1000 M blocks/s (modern GPU)     |
| Use case                 | Single-value encryption       | Bulk ECB-mode encryption              |


### Build Instructions

#### 1. Clone and create a build directory

```bash
git clone <repository-url>
cd block_cipher
mkdir build && cd build
```

#### 2. Configure and build

**Without CUDA (CPU only) (default):**
```bash
cmake -DUSE_CUDA=OFF .
cmake --build .
```

**Explicitly enable CUDA:**
```bash
cmake -DUSE_CUDA=ON .
cmake --build .
```
---

### Running

```bash
./block_cipher
```


### Known Test Vectors

These are the standard PRESENT-80 test vectors from the original paper for verifying correctness:

| Key (hex)              | Plaintext (hex)    | Ciphertext (hex)     |
|------------------------|--------------------|----------------------|
| `00000000000000000000` | `0000000000000000` | `5579C1387B228445`   |
| `FFFFFFFFFFFFFFFFFFFF` | `0000000000000000` | `E72C46C0F5945049`   |
| `00000000000000000000` | `FFFFFFFFFFFFFFFF` | `A112FFC72F68417B`   |
| `FFFFFFFFFFFFFFFFFFFF` | `FFFFFFFFFFFFFFFF` | `3333DCD3213210D2`   |

---

### References

- Bogdanov et al., *"PRESENT: An Ultra-Lightweight Block Cipher"*, CHES 2007. [PDF](https://link.springer.com/chapter/10.1007/978-3-540-74735-2_31)
- ISO/IEC 29192-2:2019 — Information security: Lightweight cryptography