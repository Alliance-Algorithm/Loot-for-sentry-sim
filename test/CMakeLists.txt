# https://github.com/Kitware/CMake/blob/master/Help/dev/experimental.rst
set(CMAKE_EXPERIMENTAL_CXX_IMPORT_STD "d0edc3af-4c50-42ea-a356-e2862fe7a444")

cmake_minimum_required(VERSION 4.0.2)
project(rmcs-navigation)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_BUILD_TYPE "Debug")

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

set(SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../src")
include_directories(${SOURCE_DIR})

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_gtest REQUIRED)

ament_add_gtest(fsm_test fsm.cc)
target_sources(
    fsm_test
    PUBLIC FILE_SET CXX_MODULES
        BASE_DIRS ${SOURCE_DIR}
        FILES ${SOURCE_DIR}/util/fsm.ccm
)
