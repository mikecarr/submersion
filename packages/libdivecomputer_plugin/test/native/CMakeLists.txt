cmake_minimum_required(VERSION 3.18)
project(libdc_wrapper_tests LANGUAGES C)

set(WRAPPER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../macos/Classes")
set(LIBDC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/libdivecomputer")
set(CONFIG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../macos/config")

# Test the wrapper struct definitions and sentinel conventions.
add_executable(test_dive_converter
    test_dive_converter.c
)
target_include_directories(test_dive_converter PRIVATE
    ${WRAPPER_DIR}
    ${LIBDC_DIR}/include
    ${CONFIG_DIR}
)

add_executable(test_serial_callbacks
    test_serial_callbacks.c
)
target_include_directories(test_serial_callbacks PRIVATE
    ${WRAPPER_DIR}
    ${LIBDC_DIR}/include
    ${CONFIG_DIR}
)

add_executable(test_descriptor_matcher
    test_descriptor_matcher.c
)
target_include_directories(test_descriptor_matcher PRIVATE
    ${WRAPPER_DIR}
    ${LIBDC_DIR}/include
    ${CONFIG_DIR}
)

# Integration test: links the real libdivecomputer descriptor table so it
# exercises libdc_descriptor_match end-to-end (BLE name -> descriptor). The
# minimal source set below is everything the matcher transitively needs from
# libdivecomputer.
add_executable(test_descriptor_match_integration
    test_descriptor_match_integration.c
    ${WRAPPER_DIR}/libdc_wrapper.c
    ${LIBDC_DIR}/src/descriptor.c
    ${LIBDC_DIR}/src/iterator.c
    ${LIBDC_DIR}/src/array.c
    ${LIBDC_DIR}/src/platform.c
    ${LIBDC_DIR}/src/version.c
)
target_include_directories(test_descriptor_match_integration PRIVATE
    ${WRAPPER_DIR}
    ${LIBDC_DIR}/include
    ${CONFIG_DIR}
)

enable_testing()
add_test(NAME test_dive_converter COMMAND test_dive_converter)
add_test(NAME test_serial_callbacks COMMAND test_serial_callbacks)
add_test(NAME test_descriptor_matcher COMMAND test_descriptor_matcher)
add_test(NAME test_descriptor_match_integration COMMAND test_descriptor_match_integration)
