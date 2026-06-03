cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME block_cipher)

# Initialize with C++ and CUDA
project(${PROJECT_NAME} LANGUAGES CXX)

# --- Compiler Settings ---

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Wall -g")

# --- CUDA Setup ---
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
message(STATUS "Building 7 executables:")
message(STATUS "  1. present80_cpu")
message(STATUS "  2. present80_gpu")
message(STATUS "  3. speck64_cpu")
message(STATUS "  4. speck64_gpu")
message(STATUS "  5. aes_cpu")
message(STATUS "  6. aes_gpu")
message(STATUS "  7. modes_test")
message(STATUS "========================================")

# --- PRESENT80 CPU ---
add_executable(present80_cpu ./PRESENT80/present80.cpp)
target_compile_options(present80_cpu PRIVATE -O3 -Wall -std=c++17)
target_include_directories(present80_cpu PRIVATE ./PRESENT80/)

# --- PRESENT80 GPU ---
add_executable(present80_gpu ./PRESENT80/present80.cu)
set_target_properties(present80_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(present80_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(present80_gpu PRIVATE ./PRESENT80/)

# --- SPECK64 CPU ---
add_executable(speck64_cpu ./SPECK64_128/speck64.cpp)
target_compile_options(speck64_cpu PRIVATE -O3 -Wall -std=c++17)
target_include_directories(speck64_cpu PRIVATE ./SPECK64_128/)

# --- SPECK64 GPU ---
add_executable(speck64_gpu ./SPECK64_128/speck64.cu)
set_target_properties(speck64_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(speck64_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(speck64_gpu PRIVATE ./SPECK64_128/)

# --- AES CPU ---
add_executable(aes_cpu ./AES/aes.cpp)
target_compile_options(aes_cpu PRIVATE -O3 -Wall -std=c++17)
target_include_directories(aes_cpu PRIVATE ./AES/)

# --- AES GPU ---
add_executable(aes_gpu ./AES/aes.cu)
set_target_properties(aes_gpu PROPERTIES LANGUAGE CUDA)
target_compile_options(aes_gpu PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: -O3 -Xcompiler -Wall>)
target_include_directories(aes_gpu PRIVATE ./AES/)

# --- Modes Test ---
add_executable(modes_test modes_test.cpp modes.cpp)
target_compile_options(modes_test PRIVATE -O3 -Wall -std=c++17)
target_include_directories(modes_test PRIVATE ./PRESENT80/ ./SPECK64_128/ ./AES/)
