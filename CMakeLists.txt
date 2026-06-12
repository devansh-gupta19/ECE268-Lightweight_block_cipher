cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME block_cipher)

# Initialize with C++ and CUDA
project(${PROJECT_NAME} LANGUAGES CXX)

# --- Compiler Settings ---

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Wall -g")

# --- CUDA Setup (native arch, nvcc -O3 for all GPU targets) ---
find_program(NVCC_EXECUTABLE nvcc PATHS /usr/local/cuda/bin /usr/bin NO_DEFAULT_PATH)
if(NOT NVCC_EXECUTABLE)
    find_program(NVCC_EXECUTABLE nvcc)
endif()
set(CMAKE_CUDA_COMPILER "${NVCC_EXECUTABLE}")
find_package(CUDA 10.0 REQUIRED)
set(CMAKE_CUDA_ARCHITECTURES native)
enable_language(CUDA)

# --- Build Message ---
message(STATUS "========================================")
message(STATUS "Block Cipher - Building All Targets")
message(STATUS "========================================")
message(STATUS "Building 11 executables:")
message(STATUS "  1. present80_ecb_cpu")
message(STATUS "  2. present80_ecb_gpu")
message(STATUS "  3. present80_ctr_gpu")
message(STATUS "  4. speck64_ecb_cpu")
message(STATUS "  5. speck64_ecb_gpu")
message(STATUS "  6. speck64_ctr_gpu")
message(STATUS "  7. aes_ecb_cpu")
message(STATUS "  8. aes_ecb_gpu")
message(STATUS "  9. aes_ctr_gpu")
message(STATUS " 10. modes_test")
message(STATUS " 11. cpu_bench")
message(STATUS "========================================")

# --- PRESENT80 CPU (ECB) ---
add_executable(present80_ecb_cpu ./PRESENT80/present80.cpp)
target_compile_options(present80_ecb_cpu PRIVATE -O3 -Wall -std=c++17)
target_include_directories(present80_ecb_cpu PRIVATE ./PRESENT80/)

# --- PRESENT80 GPU (ECB) ---
add_executable(present80_ecb_gpu ./PRESENT80/present80_ecb.cu)
set_target_properties(present80_ecb_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(present80_ecb_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(present80_ecb_gpu PRIVATE ./PRESENT80/)

# --- PRESENT80 GPU (CTR) ---
add_executable(present80_ctr_gpu ./PRESENT80/present80_ctr.cu)
set_target_properties(present80_ctr_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(present80_ctr_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(present80_ctr_gpu PRIVATE ./PRESENT80/)

# --- SPECK64 CPU (ECB) ---
add_executable(speck64_ecb_cpu ./SPECK64_128/speck64.cpp)
target_compile_options(speck64_ecb_cpu PRIVATE -O3 -Wall -std=c++17)
target_include_directories(speck64_ecb_cpu PRIVATE ./SPECK64_128/)

# --- SPECK64 GPU (ECB) ---
add_executable(speck64_ecb_gpu ./SPECK64_128/speck64_ecb.cu)
set_target_properties(speck64_ecb_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(speck64_ecb_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(speck64_ecb_gpu PRIVATE ./SPECK64_128/)

# --- SPECK64 GPU (CTR) ---
add_executable(speck64_ctr_gpu ./SPECK64_128/speck64_ctr.cu)
set_target_properties(speck64_ctr_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(speck64_ctr_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(speck64_ctr_gpu PRIVATE ./SPECK64_128/)

# --- AES CPU (ECB) ---
add_executable(aes_ecb_cpu ./AES/aes.cpp)
target_compile_options(aes_ecb_cpu PRIVATE -O3 -Wall -std=c++17)
target_include_directories(aes_ecb_cpu PRIVATE ./AES/)

# --- AES GPU (ECB) ---
add_executable(aes_ecb_gpu ./AES/aes_ecb.cu)
set_target_properties(aes_ecb_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(aes_ecb_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(aes_ecb_gpu PRIVATE ./AES/)

# --- AES GPU (CTR) ---
add_executable(aes_ctr_gpu ./AES/aes_ctr.cu)
set_target_properties(aes_ctr_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(aes_ctr_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(aes_ctr_gpu PRIVATE ./AES/)

# --- Modes Test (CPU: ECB/CTR/CBC roundtrip per cipher) ---
add_executable(modes_test modes_test.cpp modes.cpp)
target_compile_options(modes_test PRIVATE -O3 -Wall -std=c++17)
target_include_directories(modes_test PRIVATE ./PRESENT80/ ./SPECK64_128/ ./AES/)

# --- CPU Benchmarks ---
add_executable(cpu_bench cpu_bench.cpp modes.cpp)
target_compile_options(cpu_bench PRIVATE -O3 -Wall -std=c++17)
target_include_directories(cpu_bench PRIVATE ./PRESENT80/ ./SPECK64_128/ ./AES/)
