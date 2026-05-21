cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME block_cipher)

# Initialize with C++
project(${PROJECT_NAME} LANGUAGES CXX)

option(USE_CUDA "Compile option to use CUDA" ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O4 -Wall -g")

if (USE_CUDA)
    set(CMAKE_CUDA_COMPILER "/usr/local/cuda/bin/nvcc")
    find_package(CUDA 10.0 REQUIRED)
    set(CMAKE_CUDA_ARCHITECTURES native)
    enable_language(CUDA)
    set(SOURCES
        ./present80.cu)
else()
    set(SOURCES
        ./present80.cpp)
endif()

# Add the executable
add_executable(${PROJECT_NAME})
target_sources(${PROJECT_NAME} PRIVATE ${SOURCES})
#target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)