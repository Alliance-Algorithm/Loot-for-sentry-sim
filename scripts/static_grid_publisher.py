#!/usr/bin/env python3

import rclpy
from nav_msgs.msg import OccupancyGrid
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
from rclpy.utilities import ok


class StaticGridPublisher(Node):
    def __init__(self) -> None:
        super().__init__("static_grid_publisher")

        self.declare_parameter("frame_id", "base_link")
        self.declare_parameter("topic", "/map")
        self.declare_parameter("resolution", 0.02)
        self.declare_parameter("width", 505)
        self.declare_parameter("height", 505)
        self.declare_parameter("map_mode", "empty")

        self.frame_id = self.get_parameter(
            "frame_id").get_parameter_value().string_value
        self.topic = self.get_parameter(
            "topic").get_parameter_value().string_value
        self.resolution = self.get_parameter(
            "resolution").get_parameter_value().double_value
        self.width = self.get_parameter(
            "width").get_parameter_value().integer_value
        self.height = self.get_parameter(
            "height").get_parameter_value().integer_value
        self.map_mode = self.get_parameter(
            "map_mode").get_parameter_value().string_value

        qos = QoSProfile(depth=1)
        qos.reliability = ReliabilityPolicy.RELIABLE
        qos.durability = DurabilityPolicy.TRANSIENT_LOCAL

        self.publisher = self.create_publisher(
            OccupancyGrid,
            self.topic,
            qos,
        )
        self.timer = self.create_timer(0.5, self.publish_grid)

    def mark_rect(self, data, x_min, x_max, y_min, y_max) -> None:
        origin_x = -(self.width * self.resolution) / 2.0
        origin_y = -(self.height * self.resolution) / 2.0

        grid_x_min = max(0, int((x_min - origin_x) / self.resolution))
        grid_x_max = min(
            self.width - 1,
            int((x_max - origin_x) / self.resolution),
        )
        grid_y_min = max(0, int((y_min - origin_y) / self.resolution))
        grid_y_max = min(
            self.height - 1,
            int((y_max - origin_y) / self.resolution),
        )

        for gy in range(grid_y_min, grid_y_max + 1):
            row_offset = gy * self.width
            for gx in range(grid_x_min, grid_x_max + 1):
                data[row_offset + gx] = 100

    def publish_grid(self) -> None:
        msg = OccupancyGrid()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.frame_id
        msg.info.resolution = self.resolution
        msg.info.width = self.width
        msg.info.height = self.height
        msg.info.origin.position.x = -(self.width * self.resolution) / 2.0
        msg.info.origin.position.y = -(self.height * self.resolution) / 2.0
        msg.info.origin.orientation.w = 1.0
        msg.data = [0] * (self.width * self.height)

        if self.map_mode == "demo":
            self.mark_rect(msg.data, -0.4, 0.4, 0.8, 3.2)
            self.mark_rect(msg.data, -2.8, -1.6, 1.6, 2.2)
            self.mark_rect(msg.data, 1.6, 2.8, -2.2, -1.6)
            self.mark_rect(msg.data, 1.2, 2.0, 2.2, 3.2)
            self.mark_rect(msg.data, -2.0, -1.2, -3.2, -2.0)

        self.publisher.publish(msg)


def main() -> None:
    rclpy.init()
    node = StaticGridPublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
