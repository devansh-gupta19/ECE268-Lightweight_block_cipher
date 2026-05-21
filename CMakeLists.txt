cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME block_cipher)
# Project name
project(${PROJECT_NAME})

option(USE_CUDA "Compile option to use CUDA" OFF)

if (USE_CUDA)
    set(CMAKE_CUDA_COMPILER "/usr/local/cuda/bin/nvcc")
    find_package(CUDA 10.0 REQUIRED)
    project(xact-build LANGUAGES CXX CUDA)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O4 -std=c++17 -Wall -g")
    set(SOURCES
        ./present80.cpp)
else()
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O4 -Wall -g")
    set(SOURCES
        ./present80.cpp)
endif()

# Add the executable
add_executable(${PROJECT_NAME})
target_sources(${PROJECT_NAME} PRIVATE ${SOURCES})
#target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)