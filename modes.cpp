#include "modes.h"
#include <cstdint>
#include <cstring>
#include <algorithm>

// CTR-64 keystream: encrypt counter blocks, XOR plaintext

void ctr64_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t nonce[4], const void* rk, Enc64Fn enc) {
    uint8_t ctr_block[8], keystream[8];
    uint32_t counter = 0;
    size_t offset = 0;
    while (offset < len) {
        // nonce (4 bytes) || counter (4 bytes, little-endian)
        std::memcpy(ctr_block, nonce, 4);
        ctr_block[4] =  counter        & 0xff;
        ctr_block[5] = (counter >>  8) & 0xff;
        ctr_block[6] = (counter >> 16) & 0xff;
        ctr_block[7] = (counter >> 24) & 0xff;
        enc(ctr_block, keystream, rk);
        size_t block_len = std::min<size_t>(8, len - offset);
        for (size_t i = 0; i < block_len; i++) out[offset+i] = in[offset+i] ^ keystream[i];
        offset += block_len;
        counter++;
    }
}

void ctr64_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t nonce[4], const void* rk, Enc64Fn enc) {
    ctr64_encrypt(in, out, len, nonce, rk, enc);
}

// CBC-64: XOR plaintext with prior ciphertext block before encrypt

void cbc64_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t iv[8], const void* rk, Enc64Fn enc) {
    uint8_t prev[8], temp[8];
    std::memcpy(prev, iv, 8);
    size_t nblocks = len / 8;
    for (size_t i = 0; i < nblocks; i++) {
        for (int j = 0; j < 8; j++) temp[j] = in[i*8+j] ^ prev[j];
        enc(temp, out + i*8, rk);
        std::memcpy(prev, out + i*8, 8);
    }
}

// CBC decrypt is parallelizable: each block depends on prior ciphertext, not prior plaintext
void cbc64_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t iv[8], const void* rk, Dec64Fn dec) {
    uint8_t prev[8], temp[8];
    std::memcpy(prev, iv, 8);
    size_t nblocks = len / 8;
    for (size_t i = 0; i < nblocks; i++) {
        dec(in + i*8, temp, rk);
        for (int j = 0; j < 8; j++) out[i*8+j] = temp[j] ^ prev[j];
        std::memcpy(prev, in + i*8, 8);
    }
}

// ============================================================
// CTR-128
// nonce: 8 bytes; counter: 8 bytes little-endian appended after nonce
// ============================================================

void ctr128_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t nonce[8], const void* rk, Enc128Fn enc) {
    uint8_t ctr_block[16], keystream[16];
    uint64_t counter = 0;
    size_t offset = 0;
    while (offset < len) {
        std::memcpy(ctr_block, nonce, 8);
        // counter as little-endian 8 bytes
        for (int i = 0; i < 8; i++)
            ctr_block[8+i] = (counter >> (i*8)) & 0xff;
        enc(ctr_block, keystream, rk);
        size_t block_len = std::min<size_t>(16, len - offset);
        for (size_t i = 0; i < block_len; i++) out[offset+i] = in[offset+i] ^ keystream[i];
        offset += block_len;
        counter++;
    }
}

void ctr128_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t nonce[8], const void* rk, Enc128Fn enc) {
    ctr128_encrypt(in, out, len, nonce, rk, enc);
}

// ============================================================
// CBC-128: 16-byte IV, sequential chaining on encrypt
// ============================================================

void cbc128_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t iv[16], const void* rk, Enc128Fn enc) {
    uint8_t prev[16], temp[16];
    std::memcpy(prev, iv, 16);
    size_t nblocks = len / 16;
    for (size_t i = 0; i < nblocks; i++) {
        for (int j = 0; j < 16; j++) temp[j] = in[i*16+j] ^ prev[j];
        enc(temp, out + i*16, rk);
        std::memcpy(prev, out + i*16, 16);
    }
}

void cbc128_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t iv[16], const void* rk, Dec128Fn dec) {
    uint8_t prev[16], temp[16];
    std::memcpy(prev, iv, 16);
    size_t nblocks = len / 16;
    for (size_t i = 0; i < nblocks; i++) {
        dec(in + i*16, temp, rk);
        for (int j = 0; j < 16; j++) out[i*16+j] = temp[j] ^ prev[j];
        std::memcpy(prev, in + i*16, 16);
    }
}
