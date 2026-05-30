#pragma once
#include <cstdint>
#include <cstring>
#include <algorithm>

// Generic 64-bit block cipher adapter
using Enc64Fn = void(*)(const uint8_t in[8], uint8_t out[8], const void* rk);
using Dec64Fn = void(*)(const uint8_t in[8], uint8_t out[8], const void* rk);

// Generic 128-bit block cipher adapter
using Enc128Fn = void(*)(const uint8_t in[16], uint8_t out[16], const void* rk);
using Dec128Fn = void(*)(const uint8_t in[16], uint8_t out[16], const void* rk);

// CTR mode for 64-bit block ciphers
// nonce: 4-byte nonce; counter is 4-byte little-endian starting at 0
void ctr64_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t nonce[4], const void* rk, Enc64Fn enc);
// CTR decrypt = CTR encrypt (same function)
void ctr64_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t nonce[4], const void* rk, Enc64Fn enc);

// CBC mode for 64-bit block ciphers (IV = 8-byte block)
void cbc64_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t iv[8], const void* rk, Enc64Fn enc);
void cbc64_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                   const uint8_t iv[8], const void* rk, Dec64Fn dec);

// CTR mode for 128-bit block ciphers (AES)
void ctr128_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t nonce[8], const void* rk, Enc128Fn enc);
void ctr128_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t nonce[8], const void* rk, Enc128Fn enc);

// CBC mode for 128-bit block ciphers (AES)
void cbc128_encrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t iv[16], const void* rk, Enc128Fn enc);
void cbc128_decrypt(const uint8_t* in, uint8_t* out, size_t len,
                    const uint8_t iv[16], const void* rk, Dec128Fn dec);
