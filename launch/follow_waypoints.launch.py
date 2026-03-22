import os

from ament_index_python.packages import (
    get_package_share_directory,
)
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def generate_launch_description():
    navigation_share = get_package_share_directory("rmcs-navigation")

    return LaunchDescription([
        DeclareLaunchArgument(
            "follow_waypoints_file",
            default_value=os.path.join(
                navigation_share,
                "config",
                "follow_waypoints.yaml",
            ),
        ),
        DeclareLaunchArgument(
            "odom_topic",
            default_value="/aft_mapped_to_init",
        ),
        DeclareLaunchArgument("distance_tolerance", default_value="0.25"),
        DeclareLaunchArgument("yaw_tolerance", default_value="0.35"),
        Node(
            package="rmcs-navigation",
            executable="follow_waypoints_runner.py",
            name="follow_waypoints_runner",
            output="screen",
            parameters=[{
                "config_file": LaunchConfiguration("follow_waypoints_file"),
                "odom_topic": LaunchConfiguration("odom_topic"),
                "distance_tolerance": ParameterValue(
                    LaunchConfiguration("distance_tolerance"),
                    value_type=float,
                ),
                "yaw_tolerance": ParameterValue(
                    LaunchConfiguration("yaw_tolerance"),
                    value_type=float,
                ),
            }],
        ),
    ])
