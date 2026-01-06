from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():

    pointcloud_to_laserscan_node = Node(
        package='pointcloud_to_laserscan',
        executable='pointcloud_to_laserscan_node',
        name='pointcloud_to_laserscan',
        remappings=[
            ('cloud_in', '/cloud_registered_undistort'),
            ('scan', '/scan')
        ],
        parameters=[{
            'use_sim_time': True,
            'target_frame': 'camera_init',
            'transform_tolerance': 0.01,
            'min_height': 0.1,
            'max_height': 1.0,
            'angle_min': -3.1415,
            'angle_max': 3.1415,
            'angle_increment': 0.0087,
            'scan_time': 0.1,
            'range_min': 0.2,
            'range_max': 30.0,
            'use_inf': True,
            'inf_epsilon': 1.0,
        }]
    )

    return LaunchDescription([
        pointcloud_to_laserscan_node,
    ])
