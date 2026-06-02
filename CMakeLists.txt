cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME block_cipher)

# Initialize with C++
project(${PROJECT_NAME} LANGUAGES CXX)

# --- Configuration Options ---

# Option 1: Hardware Acceleration (CUDA vs CPU)
option(USE_CUDA "Compile option to use CUDA" OFF)

# Option 2: Cipher Selection (PRESENT80 vs SPECK64)
#set(CIPHER_SELECTION "PRESENT80" CACHE STRING "Select the block cipher to compile (PRESENT80 or SPECK64)")
set(CIPHER_SELECTION "SPECK64" CACHE STRING "Select the block cipher to compile (PRESENT80 or SPECK64)")
# This property restricts the GUI/ccmake input to these specific strings
set_property(CACHE CIPHER_SELECTION PROPERTY STRINGS "PRESENT80" "SPECK64")

# --- Compiler Settings ---

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Wall -g")

# --- Source Selection Logic ---

if (USE_CUDA)
    set(BUILD_TYPE_MSG "GPU (CUDA)")
    # CUDA Setup — find nvcc in PATH if not at the hardcoded path
    find_program(NVCC_EXECUTABLE nvcc PATHS /usr/local/cuda/bin /usr/bin NO_DEFAULT_PATH)
    if(NOT NVCC_EXECUTABLE)
        find_program(NVCC_EXECUTABLE nvcc)
    endif()
    set(CMAKE_CUDA_COMPILER "${NVCC_EXECUTABLE}")
    find_package(CUDA 10.0 REQUIRED)
    set(CMAKE_CUDA_ARCHITECTURES native)
    enable_language(CUDA)

    # CUDA Source Routing
    if (CIPHER_SELECTION STREQUAL "SPECK64")
        set(SOURCES ./speck64.cu)
    else()
        set(SOURCES ./present80.cu)
    endif()

else()
    set(BUILD_TYPE_MSG "CPU")
    # Baseline C++ Source Routing
    if (CIPHER_SELECTION STREQUAL "SPECK64")
        set(SOURCES ./speck64.cpp)
    else()
        set(SOURCES ./present80.cpp)
    endif()
endif()

# --- Build Configuration Message ---
message(STATUS "========================================")
message(STATUS "Block Cipher Build Configuration")
message(STATUS "========================================")
message(STATUS "Build Type:     ${BUILD_TYPE_MSG}")
message(STATUS "Cipher:         ${CIPHER_SELECTION}")
message(STATUS "========================================")


# --- Build Target ---

# Add the executable
add_executable(${PROJECT_NAME})
target_sources(${PROJECT_NAME} PRIVATE ${SOURCES})

# target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)

# AES baseline (CPU only, always built)
add_executable(aes_baseline aes_baseline.cpp modes.cpp)
target_compile_options(aes_baseline PRIVATE -O3 -Wall -std=c++17)

# Modes test (CPU only, always built)
add_executable(modes_test modes_test.cpp modes.cpp)
target_compile_options(modes_test PRIVATE -O3 -Wall -std=c++17)
