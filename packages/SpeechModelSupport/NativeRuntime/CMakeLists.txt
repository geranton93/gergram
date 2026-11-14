cmake_minimum_required(VERSION 3.20)
project(GergramWhisperRuntime LANGUAGES C CXX)

set(WHISPER_SOURCE "" CACHE PATH "Local whisper.cpp v1.9.5 source checkout")
option(GERGRAM_WHISPER_ASAN "Compile the runtime and tests with Address Sanitizer" OFF)
include(CTest)
include(VerifyWhisperSource.cmake)

if(NOT APPLE OR NOT CMAKE_OSX_ARCHITECTURES MATCHES "^(arm64|x86_64)$")
    message(FATAL_ERROR "Set CMAKE_OSX_ARCHITECTURES to one macOS architecture (arm64 or x86_64)")
endif()
if(GERGRAM_WHISPER_ASAN)
    add_compile_options(-fsanitize=address -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address)
endif()

foreach(option IN ITEMS BUILD_SHARED_LIBS WHISPER_BUILD_IS_DEV WHISPER_BUILD_EXAMPLES WHISPER_BUILD_TESTS
        WHISPER_BUILD_SERVER WHISPER_USE_SYSTEM_GGML WHISPER_USE_SYSTEM_LLAMA WHISPER_COREML WHISPER_OPENVINO
        WHISPER_ANEFORGE WHISPER_VITISAI WHISPER_FLEXMLRT
        GGML_METAL GGML_OPENMP GGML_OPENMP_FETCH GGML_BLAS GGML_ACCELERATE GGML_NATIVE GGML_CCACHE GGML_BACKEND_DL
        GGML_CUDA GGML_HIP GGML_VULKAN GGML_WEBGPU GGML_OPENCL GGML_CANN GGML_SYCL GGML_RPC
        GGML_CPU_ALL_VARIANTS GGML_CPU_KLEIDIAI GGML_CPU_HBM GGML_BUILD_TESTS GGML_BUILD_EXAMPLES
        GGML_SSE42 GGML_AVX GGML_AVX2 GGML_AVX_VNNI GGML_BMI2 GGML_FMA GGML_F16C)
    set(${option} OFF CACHE BOOL "Fixed for the offline CPU runtime" FORCE)
endforeach()
set(GGML_CPU ON CACHE BOOL "Enable the CPU runtime" FORCE)
set(FETCHCONTENT_FULLY_DISCONNECTED ON)

add_subdirectory("${verifiedWhisperSource}" whisper EXCLUDE_FROM_ALL)
add_library(GergramWhisperRuntime STATIC WhisperRuntime.cpp)
target_compile_features(GergramWhisperRuntime PRIVATE cxx_std_17)
target_include_directories(GergramWhisperRuntime PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(GergramWhisperRuntime PRIVATE whisper)

if(BUILD_TESTING)
    add_executable(GergramWhisperRuntimeTests WhisperRuntimeTests.cpp)
    target_compile_features(GergramWhisperRuntimeTests PRIVATE cxx_std_17)
    target_link_libraries(GergramWhisperRuntimeTests PRIVATE GergramWhisperRuntime)
    add_test(NAME GergramWhisperRuntimeTests COMMAND GergramWhisperRuntimeTests
        "${verifiedWhisperSource}/models/for-tests-ggml-tiny.bin")
endif()
