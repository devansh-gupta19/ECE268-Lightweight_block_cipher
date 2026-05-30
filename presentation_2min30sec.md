# Claude Design Prompt: 2.5-Minute Presentation
# "Lightweight Block Ciphers for Constrained Devices: PRESENT-80 vs SPECK-64 vs AES"

---

## Instructions for Claude Design

Create a **5-slide academic presentation deck** for a **2.5-minute in-class talk** (ECE268 GPU Cryptography, UCSD, June 4, 2026). Style: clean, technical, dark-background preferred. Each slide has ONE headline message. Use exact numbers as written — do not round. Include log-scale charts where indicated. Font: monospace or technical sans-serif.

---

## Slide 1: Hook — "Not All Lightweight Ciphers Are Lightweight"

**Headline:** Two ciphers with the same job description run 94× apart in software.

**Content:**
- Both PRESENT-80 and SPECK-64/128 are ISO "lightweight" block ciphers for IoT/RFID
- In our measured CPU benchmark (AMD Ryzen 7 8845HS, g++ -O3):
  - **SPECK-64/128: 225.5 MB/s**
  - **PRESENT-80: 2.4 MB/s**
  - Gap: **~94×** — same category, same 64-bit block size
- Root cause: algorithm family (ARX vs. SPN with bit-permutation) decides everything in software

**Visual Design:** Giant centered "**94×**" in accent color. Two cipher labels flanking it: "PRESENT-80  ←  94×  →  SPECK-64". Subtitle below: *"Same block size. Same IoT target. Measured on identical hardware."*

**Speaker time:** ~20 seconds. Open cold — no preamble.

---

## Slide 2: What We Built

**Headline:** Three from-scratch ciphers, two on GPU, two modes each — apples-to-apples.

**Content table:**

| Cipher | Structure | Block | Key | Rounds | CPU | GPU | Validation |
|--------|-----------|-------|-----|--------|-----|-----|------------|
| PRESENT-80 | SPN | 64-bit | 80-bit | 31 | ✓ | ✓ | 4 CHES-2007 vectors |
| SPECK-64/128 | ARX | 64-bit | 128-bit | 27 | ✓ | ✓ | NSA official vector |
| AES-128 | SPN | 128-bit | 128-bit | 10 | ✓ | — | 2 FIPS-197 vectors |

- Modes implemented: **CTR** (parallelizable) + **CBC** (sequential) for all three
- GPU: RTX 4070 Laptop (sm_89), nvcc -O3 | CPU: Ryzen 7 8845HS @ 3.8 GHz, g++ -O3
- **No third-party crypto libraries. All from scratch.**

**Visual Design:** 3-column cipher card strip (one card per cipher), each with a small structural icon: PRESENT = nested boxes (S-box + permutation), SPECK = two arrows (rotate/add), AES = 4×4 grid. Green checkmarks for validation.

**Speaker time:** ~20 seconds. Do not read the table aloud; gesture at it and say "validated, all from scratch."

---

## Slide 3: The Headline Results

**Headline:** SPECK wins software; even our naive AES beats PRESENT; GPU lifts both but SPECK stays on top.

**CPU throughput (ECB mode, 8 MB bulk, single core):**

| Cipher | Cyc/byte | ECB MB/s | CTR MB/s | CBC MB/s |
|--------|----------|----------|----------|----------|
| PRESENT-80 | **1,496** | 2.4 | 0.69 | 0.67 |
| SPECK-64/128 | **16** | 225.5 | 209.6 | 148.5 |
| AES-128 (no AES-NI) | **340** | 10.6 | 10.4 | 10.8 |

**GPU throughput (kernel only, 1M blocks = 8 MB, RTX 4070 Laptop):**

| Cipher | GPU Enc GB/s | GPU Speedup vs CPU |
|--------|--------------|-------------------|
| PRESENT-80 | 1.22 | ~508× |
| SPECK-64/128 | **11.16** | ~49× |

**Visual Design:** Two-panel bar chart. Left panel: "CPU MB/s" — **log scale** (PRESENT at 2.4 is otherwise invisible). Right panel: "GPU GB/s". Annotate "94×" between SPECK and PRESENT bars on CPU panel. Annotate "~9× gap remains" on GPU panel.

**Speaker time:** ~45 seconds. This is the core slide. Walk left to right: CPU first, GPU second. Land: *"PRESENT's 508× GPU speedup looks great — until you see the absolute number still trails SPECK by 9×."*

---

## Slide 4: Why — Algorithm Family Is Everything

**Headline:** PRESENT's bit permutation is one wire in silicon; it's 64 shift-mask ops on a CPU register.

**Content:**

- **PRESENT bit-permutation:** Each of 64 bits moves to position `(16×i) mod 63` — free in hardware (just route a wire), but on a CPU requires 64 individual mask+shift operations per round × 31 rounds
- **SPECK ARX round:** `x = ROR(x,8) + y ⊕ k;  y = ROL(y,3) ⊕ x` — 3 native CPU instructions, no table lookups, no memory accesses

**Cycles per byte on CPU:**
- PRESENT-80: **1,496 cyc/byte** — 93× more work than SPECK
- SPECK-64: **16 cyc/byte** — 3 CPU ops × 27 rounds
- AES-128: **340 cyc/byte** (table-based MixColumns; needs AES-NI to be competitive)

**Hardware gate count (published papers):**
- PRESENT-80: **~1,570 GE** (Bogdanov et al., CHES 2007)
- SPECK-64: **~1,280 GE** (Beaulieu et al., NSA 2013)
- AES-128: **~3,400 GE** (serialized, Satoh et al.)

**Visual Design:** Two-row comparison. Top row: "Cycles/byte" horizontal bars (log scale). Bottom row: "Gate equivalents" horizontal bars (linear). Color-highlight the INVERSION: PRESENT loses on CPU but wins in hardware. Label the bars with exact numbers.

**Speaker time:** ~30 seconds. The one-liner to deliver: *"Bit permutation is free in silicon and expensive in software. That's the whole 94× story."*

---

## Slide 5: So What — Pick the Right Tool

**Headline:** "Lightweight" is a target, not a label — match the cipher to the silicon you have.

**Decision guide:**

| Deployment Target | Best Choice | Why |
|-------------------|-------------|-----|
| MCU / software (no crypto HW) | **SPECK** | 21× faster than AES, 94× faster than PRESENT |
| ASIC / RFID / <2,000 GE budget | **PRESENT** | ~1,570 GE, smallest footprint |
| Bulk encryption on GPU (CTR mode) | **SPECK** | 11.16 GB/s kernel throughput |
| Frequent re-keying in IoT | **SPECK** | Key schedule is negligible vs AES's 553 cycles |
| General secure default | AES-128 | Most analyzed; use with AES-NI hardware |

**One-sentence takeaway:** *In software, pick SPECK. In silicon, PRESENT earns its name. AES needs its hardware acceleration to compete.*

**Visual Design:** Clean decision flowchart: 3 branches — "Silicon-constrained → PRESENT", "Software / MCU → SPECK", "Bulk / cloud → SPECK (CTR, 11.16 GB/s)". At the bottom: single bold box reading *"Algorithm family > round count > key size."*

**Speaker time:** ~25 seconds. Read the takeaway line slowly. Then stop.

---

## Deck Metadata for Claude Design

- **Aspect ratio:** 16:9 widescreen
- **Color scheme:** Dark background (#0f1117 or deep navy), white body text, accent color: electric blue or orange for key numbers
- **Font:** JetBrains Mono or Inter for headlines; system sans for body
- **Logo / watermark:** ECE268 UCSD in bottom-right corner of every slide
- **Slide numbers:** Bottom-center
- **Total runtime:** 2 minutes 30 seconds across 5 slides

## Sources (actual log files)
- CPU benchmarks: `logs/cpu_bench_20260530_022059.log`
- GPU PRESENT-80: `logs/gpu_present80_20260530_*.log`
- GPU SPECK-64: `logs/gpu_speck64_1M_20260530_*.log`
- Summary: `logs/benchmark_summary_20260530_022200.log`
