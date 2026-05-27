#include <iostream>
#include <cstdint>
#include <iomanip>

class Speck64_128 {
private:
    // SPECK-64/128 utilizes 27 rounds
    static constexpr int ROUNDS = 27;
    uint32_t round_keys[ROUNDS];

    // Circular Right Shift
    // Note: Modern compilers automatically optimize this idiom into a single 
    // native CPU rotation instruction (e.g., ROR on ARM/x86).
    static inline uint32_t ROTR32(uint32_t x, int r) {
        return (x >> r) | (x << (32 - r));
    }

    // Circular Left Shift
    static inline uint32_t ROTL32(uint32_t x, int r) {
        return (x << r) | (x >> (32 - r));
    }

    // Core ARX Encryption Round Function (x = Left word, y = Right word)
    static inline void ER(uint32_t& x, uint32_t& y, uint32_t k) {
        x = (ROTR32(x, 8) + y) ^ k;
        y = ROTL32(y, 3) ^ x;
    }

    // Inverse ARX Decryption Round Function
    static inline void DR(uint32_t& x, uint32_t& y, uint32_t k) {
        y = ROTR32(y ^ x, 3);
        x = ROTL32((x ^ k) - y, 8);
    }

public:
    // Initializes the cipher by expanding the 128-bit key into 27 round keys
    void expandKey(const uint32_t K[4]) {
        uint32_t b = K[0];
        // a[3] acts as a rolling window for the upper words of the key
        uint32_t a[3] = {K[1], K[2], K[3]}; 

        round_keys[0] = b;
        for (uint32_t i = 0; i < ROUNDS - 1; ++i) {
            // The key schedule utilizes the exact same ARX round function
            ER(a[i % 3], b, i);
            round_keys[i + 1] = b;
        }
    }

    // Encrypts a 64-bit block
    // Pt[1] = Left word, Pt[0] = Right word
    void encrypt(const uint32_t Pt[2], uint32_t Ct[2]) const {
        Ct[0] = Pt[0];
        Ct[1] = Pt[1];
        for (int i = 0; i < ROUNDS; ++i) {
            ER(Ct[1], Ct[0], round_keys[i]);
        }
    }

    // Decrypts a 64-bit block
    // Ct[1] = Left word, Ct[0] = Right word
    void decrypt(const uint32_t Ct[2], uint32_t Pt[2]) const {
        Pt[0] = Ct[0];
        Pt[1] = Ct[1];
        for (int i = ROUNDS - 1; i >= 0; --i) {
            DR(Pt[1], Pt[0], round_keys[i]);
        }
    }
};

// --- Test Implementation ---
int main() {
    Speck64_128 cipher;

    // Official NSA Test Vector for SPECK-64/128
    uint32_t key[4] = {0x03020100, 0x0b0a0908, 0x13121110, 0x1b1a1918};
    uint32_t pt[2]  = {0x7475432d, 0x3b726574}; // pt[0]=Right, pt[1]=Left
    uint32_t ct[2]  = {0, 0};
    uint32_t dec[2] = {0, 0};

    // 1. Key Expansion
    cipher.expandKey(key);

    // 2. Encryption
    cipher.encrypt(pt, ct);

    // 3. Decryption
    cipher.decrypt(ct, dec);

    // 4. Verification Output
    std::cout << std::hex << std::setfill('0');
    std::cout << "--- SPECK-64/128 Test ---" << std::endl;
    std::cout << "Plaintext:  " << std::setw(8) << pt[1] << " " << std::setw(8) << pt[0] << std::endl;
    std::cout << "Ciphertext: " << std::setw(8) << ct[1] << " " << std::setw(8) << ct[0] << std::endl;
    std::cout << "Decrypted:  " << std::setw(8) << dec[1] << " " << std::setw(8) << dec[0] << std::endl;

    if (ct[1] == 0x8c6fa548 && ct[0] == 0x454e028b) {
        std::cout << "\n[SUCCESS] Ciphertext matches the official test vector." << std::endl;
    } else {
        std::cout << "\n[FAILED] Ciphertext does not match." << std::endl;
    }

    return 0;
}