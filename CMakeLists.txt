cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME block_cipher)

# Initialize with C++
project(${PROJECT_NAME} LANGUAGES CXX)

# --- Configuration Options ---

# Option 1: Hardware Acceleration (CUDA vs CPU)
option(USE_CUDA "Compile option to use CUDA" ON)

# Option 2: Cipher Selection (PRESENT80 vs SPECK64)
set(CIPHER_SELECTION "PRESENT80" CACHE STRING "Select the block cipher to compile (PRESENT80 or SPECK64)")
# This property restricts the GUI/ccmake input to these specific strings
set_property(CACHE CIPHER_SELECTION PROPERTY STRINGS "PRESENT80" "SPECK64")

# --- Compiler Settings ---

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
# Note: Replaced -O4 with -O3 as GCC/Clang do not have an -O4 optimization level
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -Wall -g")

# --- Source Selection Logic ---

if (USE_CUDA)
    # CUDA Setup
    set(CMAKE_CUDA_COMPILER "/usr/local/cuda/bin/nvcc")
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
    # Baseline C++ Source Routing
    if (CIPHER_SELECTION STREQUAL "SPECK64")
        set(SOURCES ./speck64.cpp)
    else()
        set(SOURCES ./present80.cpp)
    endif()
endif()

# --- Build Target ---

# Add the executable
add_executable(${PROJECT_NAME})
target_sources(${PROJECT_NAME} PRIVATE ${SOURCES})

# target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)