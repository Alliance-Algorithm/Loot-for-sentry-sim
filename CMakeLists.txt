cmake_minimum_required(VERSION 3.30)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 23)

set(CMAKE_POLICY_DEFAULT_CMP0167 OLD)
set(CMAKE_POLICY_DEFAULT_CMP0144 NEW)

project(rmcs-navigation)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(Eigen3 REQUIRED)
find_package(yaml-cpp REQUIRED)
find_package(rclcpp REQUIRED)
find_package(PCL REQUIRED)

find_package(geometry_msgs REQUIRED)
find_package(rmcs_msgs REQUIRED)
find_package(ament_index_cpp REQUIRED)

find_package(rmcs_executor REQUIRED)

# file(GLOB_RECURSE PROJECT_SOURCE
#     CONFIGURE_DEPENDS
#     ${PROJECT_SOURCE_DIR}/src/*.cpp
#     ${PROJECT_SOURCE_DIR}/src/*.cxx
#     ${PROJECT_SOURCE_DIR}/src/*.cc
# )
# file(GLOB_RECURSE PROJECT_MODULE
#     CONFIGURE_DEPENDS
#     ${PROJECT_SOURCE_DIR}/src/*.cppm
#     ${PROJECT_SOURCE_DIR}/src/*.cxxm
#     ${PROJECT_SOURCE_DIR}/src/*.ccm
# )
# include_directories(
#     src
#     ${sensor_msgs_INCLUDE_DIRS}
# )
#
# add_executable(
#     app
#     ${PROJECT_SOURCE}
# )
# target_sources(
#     app
#     PUBLIC FILE_SET CXX_MODULES FILES
#         ${PROJECT_MODULE}
# )
# target_link_libraries(
#     app
#     rclcpp::rclcpp
#     ${sensor_msgs_LIBRARIES}
# )

# RMCS Component
add_library(${PROJECT_NAME}_brain SHARED)
target_sources(
    ${PROJECT_NAME}_brain
    PRIVATE
        src/brain.cc
        src/brain/plan.cc
)
target_include_directories(
    ${PROJECT_NAME}_brain
    PRIVATE
        ${PROJECT_SOURCE_DIR}/src/
        ${rmcs_executor_INCLUDE_DIRS}
        ${geometry_msgs_INCLUDE_DIRS}
        ${rmcs_msgs_INCLUDE_DIRS}
        ${ament_index_cpp_INCLUDE_DIRS}
)
target_link_libraries(
    ${PROJECT_NAME}_brain
    rclcpp::rclcpp
    ament_index_cpp::ament_index_cpp
    yaml-cpp::yaml-cpp
    ${rmcs_executor_LIBRARIES}
    ${geometry_msgs_LIBRARIES}
    ${rmcs_msgs_LIBRARIES}
)
find_package(pluginlib REQUIRED)
pluginlib_export_plugin_description_file(
    rmcs_executor plugins.xml
)

include(cmake/version.cmake)
include(cmake/export.cmake)
