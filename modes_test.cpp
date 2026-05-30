#include <cstdint>
#include <cstring>
#include <iostream>
#include <iomanip>
#include <vector>
#include <random>
#include <algorithm>
#include <numeric>
#include <cmath>
#include <fstream>
#include <string>
#include "bench_utils.h"
#include "present80.h"
#include "speck64.h"
#include "aes128.h"
#include "modes.h"

// ============================================================
// Cipher adapter wrappers
// ============================================================

// --- PRESENT-80 adapters ---
// We use a single global instance keyed with the test key
// to avoid passing key material through the void* (simplicity).
// The void* rk is a pointer to a Present80 instance.

static void present_enc(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Present80* c = static_cast<const Present80*>(rk);
    uint64_t pt;
    std::memcpy(&pt, in, 8);
    pt = __builtin_bswap64(pt);
    uint64_t ct = c->encrypt(pt);
    ct = __builtin_bswap64(ct);
    std::memcpy(out, &ct, 8);
}

static void present_dec(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Present80* c = static_cast<const Present80*>(rk);
    uint64_t ct;
    std::memcpy(&ct, in, 8);
    ct = __builtin_bswap64(ct);
    uint64_t pt = c->decrypt(ct);
    pt = __builtin_bswap64(pt);
    std::memcpy(out, &pt, 8);
}

// --- SPECK-64/128 adapters ---
// void* rk is a pointer to Speck64_128

static void speck_enc(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Speck64_128* c = static_cast<const Speck64_128*>(rk);
    uint32_t pt[2], ct[2];
    // little-endian word packing consistent with original test
    std::memcpy(&pt[0], in,   4);
    std::memcpy(&pt[1], in+4, 4);
    c->encrypt(pt, ct);
    std::memcpy(out,   &ct[0], 4);
    std::memcpy(out+4, &ct[1], 4);
}

static void speck_dec(const uint8_t in[8], uint8_t out[8], const void* rk) {
    const Speck64_128* c = static_cast<const Speck64_128*>(rk);
    uint32_t ct[2], pt[2];
    std::memcpy(&ct[0], in,   4);
    std::memcpy(&ct[1], in+4, 4);
    c->decrypt(ct, pt);
    std::memcpy(out,   &pt[0], 4);
    std::memcpy(out+4, &pt[1], 4);
}

// --- AES-128 adapters ---
// void* rk is a pointer to AES128

static void aes_enc(const uint8_t in[16], uint8_t out[16], const void* rk) {
    const AES128* c = static_cast<const AES128*>(rk);
    c->encrypt(in, out);
}

static void aes_dec(const uint8_t in[16], uint8_t out[16], const void* rk) {
    const AES128* c = static_cast<const AES128*>(rk);
    c->decrypt(in, out);
}

// ============================================================
// Self-consistency tests
// ============================================================

static bool test_ctr64_roundtrip(const char* name, const void* rk, Enc64Fn enc) {
    const size_t LEN = 1048576; // 1 MB
    std::mt19937_64 rng(0xECE268);
    std::vector<uint8_t> plain(LEN), cipher(LEN), recovered(LEN);
    for (auto& b : plain) b = rng() & 0xFF;

    uint8_t nonce[4] = {0xDE,0xAD,0xBE,0xEF};
    ctr64_encrypt(plain.data(), cipher.data(),    LEN, nonce, rk, enc);
    ctr64_decrypt(cipher.data(), recovered.data(), LEN, nonce, rk, enc);

    bool ok = (plain == recovered);
    std::cout << "  CTR-64 roundtrip [" << name << "]: " << (ok ? "PASS" : "FAIL") << "\n";
    return ok;
}

static bool test_cbc64_roundtrip(const char* name, const void* rk, Enc64Fn enc, Dec64Fn dec) {
    const size_t LEN = 1048576;
    std::mt19937_64 rng(0xECE268 + 1);
    std::vector<uint8_t> plain(LEN), cipher(LEN), recovered(LEN);
    for (auto& b : plain) b = rng() & 0xFF;

    uint8_t iv[8] = {0x01,0x23,0x45,0x67,0x89,0xAB,0xCD,0xEF};
    cbc64_encrypt(plain.data(), cipher.data(),    LEN, iv, rk, enc);
    cbc64_decrypt(cipher.data(), recovered.data(), LEN, iv, rk, dec);

    bool ok = (plain == recovered);
    std::cout << "  CBC-64 roundtrip [" << name << "]: " << (ok ? "PASS" : "FAIL") << "\n";
    return ok;
}

static bool test_ctr128_roundtrip(const char* name, const void* rk, Enc128Fn enc) {
    const size_t LEN = 1048576;
    std::mt19937_64 rng(0xECE268 + 2);
    std::vector<uint8_t> plain(LEN), cipher(LEN), recovered(LEN);
    for (auto& b : plain) b = rng() & 0xFF;

    uint8_t nonce[8] = {0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77};
    ctr128_encrypt(plain.data(), cipher.data(),    LEN, nonce, rk, enc);
    ctr128_decrypt(cipher.data(), recovered.data(), LEN, nonce, rk, enc);

    bool ok = (plain == recovered);
    std::cout << "  CTR-128 roundtrip [" << name << "]: " << (ok ? "PASS" : "FAIL") << "\n";
    return ok;
}

static bool test_cbc128_roundtrip(const char* name, const void* rk, Enc128Fn enc, Dec128Fn dec) {
    const size_t LEN = 1048576;
    std::mt19937_64 rng(0xECE268 + 3);
    std::vector<uint8_t> plain(LEN), cipher(LEN), recovered(LEN);
    for (auto& b : plain) b = rng() & 0xFF;

    uint8_t iv[16] = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                      0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};
    cbc128_encrypt(plain.data(), cipher.data(),    LEN, iv, rk, enc);
    cbc128_decrypt(cipher.data(), recovered.data(), LEN, iv, rk, dec);

    bool ok = (plain == recovered);
    std::cout << "  CBC-128 roundtrip [" << name << "]: " << (ok ? "PASS" : "FAIL") << "\n";
    return ok;
}

// ============================================================
// Throughput benchmarks (1,048,576 block encryptions per mode)
// ============================================================

static void bench_ctr64(const char* name, const void* rk, Enc64Fn enc) {
    const size_t NBLOCKS = 1048576;
    const size_t LEN     = NBLOCKS * 8;
    std::vector<uint8_t> in(LEN, 0xA5), out(LEN);
    uint8_t nonce[4] = {0x01,0x02,0x03,0x04};

    // Warmup
    ctr64_encrypt(in.data(), out.data(), 8*1024, nonce, rk, enc);

    Timer t; t.start();
    ctr64_encrypt(in.data(), out.data(), LEN, nonce, rk, enc);
    double sec = t.elapsed_sec();
    double mbps = (LEN / (1024.0*1024.0)) / sec;
    std::cout << "  CTR-64 throughput [" << name << "]: " << std::fixed << std::setprecision(2) << mbps << " MB/s\n";
}

static void bench_cbc64(const char* name, const void* rk, Enc64Fn enc) {
    const size_t NBLOCKS = 1048576;
    const size_t LEN     = NBLOCKS * 8;
    std::vector<uint8_t> in(LEN, 0xA5), out(LEN);
    uint8_t iv[8] = {0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08};

    // Warmup
    cbc64_encrypt(in.data(), out.data(), 8*1024, iv, rk, enc);

    Timer t; t.start();
    cbc64_encrypt(in.data(), out.data(), LEN, iv, rk, enc);
    double sec = t.elapsed_sec();
    double mbps = (LEN / (1024.0*1024.0)) / sec;
    std::cout << "  CBC-64 throughput [" << name << "]: " << std::fixed << std::setprecision(2) << mbps << " MB/s\n";
}

static void bench_ctr128(const char* name, const void* rk, Enc128Fn enc) {
    const size_t NBLOCKS = 1048576;
    const size_t LEN     = NBLOCKS * 16;
    std::vector<uint8_t> in(LEN, 0xA5), out(LEN);
    uint8_t nonce[8] = {0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08};

    // Warmup
    ctr128_encrypt(in.data(), out.data(), 16*1024, nonce, rk, enc);

    Timer t; t.start();
    ctr128_encrypt(in.data(), out.data(), LEN, nonce, rk, enc);
    double sec = t.elapsed_sec();
    double mbps = (LEN / (1024.0*1024.0)) / sec;
    std::cout << "  CTR-128 throughput [" << name << "]: " << std::fixed << std::setprecision(2) << mbps << " MB/s\n";
}

static void bench_cbc128(const char* name, const void* rk, Enc128Fn enc) {
    const size_t NBLOCKS = 1048576;
    const size_t LEN     = NBLOCKS * 16;
    std::vector<uint8_t> in(LEN, 0xA5), out(LEN);
    uint8_t iv[16] = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                      0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};

    // Warmup
    cbc128_encrypt(in.data(), out.data(), 16*1024, iv, rk, enc);

    Timer t; t.start();
    cbc128_encrypt(in.data(), out.data(), LEN, iv, rk, enc);
    double sec = t.elapsed_sec();
    double mbps = (LEN / (1024.0*1024.0)) / sec;
    std::cout << "  CBC-128 throughput [" << name << "]: " << std::fixed << std::setprecision(2) << mbps << " MB/s\n";
}

// ============================================================
// main
// ============================================================

int main() {
    bool all_pass = true;

    // ---- PRESENT-80 ----
    {
        std::array<uint8_t,10> pkey = {0x01,0x23,0x45,0x67,0x89,0xAB,0xCD,0xEF,0x01,0x23};
        Present80 present(pkey);
        const void* rk = &present;

        std::cout << "=== PRESENT-80 modes ===\n";
        all_pass &= test_ctr64_roundtrip("PRESENT-80", rk, present_enc);
        all_pass &= test_cbc64_roundtrip("PRESENT-80", rk, present_enc, present_dec);
        bench_ctr64("PRESENT-80", rk, present_enc);
        bench_cbc64("PRESENT-80", rk, present_enc);
    }

    // ---- SPECK-64/128 ----
    {
        Speck64_128 speck;
        uint32_t skey[4] = {0x03020100, 0x0b0a0908, 0x13121110, 0x1b1a1918};
        speck.expandKey(skey);
        const void* rk = &speck;

        std::cout << "=== SPECK-64/128 modes ===\n";
        all_pass &= test_ctr64_roundtrip("SPECK-64", rk, speck_enc);
        all_pass &= test_cbc64_roundtrip("SPECK-64", rk, speck_enc, speck_dec);
        bench_ctr64("SPECK-64", rk, speck_enc);
        bench_cbc64("SPECK-64", rk, speck_enc);
    }

    // ---- AES-128 ----
    {
        uint8_t akey[16] = {0x2b,0x7e,0x15,0x16,0x28,0xae,0xd2,0xa6,
                            0xab,0xf7,0x15,0x88,0x09,0xcf,0x4f,0x3c};
        AES128 aes(akey);
        const void* rk = &aes;

        std::cout << "=== AES-128 modes ===\n";
        all_pass &= test_ctr128_roundtrip("AES-128", rk, aes_enc);
        all_pass &= test_cbc128_roundtrip("AES-128", rk, aes_enc, aes_dec);
        bench_ctr128("AES-128", rk, aes_enc);
        bench_cbc128("AES-128", rk, aes_enc);
    }

    std::cout << "\n";
    if (all_pass) {
        std::cout << "ALL MODES TESTS PASSED\n";
        return 0;
    } else {
        std::cout << "FAIL: one or more modes roundtrip tests failed\n";
        return 1;
    }
}
