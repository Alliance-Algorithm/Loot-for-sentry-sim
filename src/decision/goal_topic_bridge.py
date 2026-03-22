#!/usr/bin/env python3

import threading

import rclpy
from geometry_msgs.msg import PoseStamped
from nav2_msgs.action import NavigateToPose
from rclpy.action.client import ActionClient
from rclpy.node import Node
from rclpy.utilities import ok


class GoalTopicBridge(Node):
    def __init__(self) -> None:
        super().__init__("goal_topic_bridge")
        self._client = ActionClient(self, NavigateToPose, "/navigate_to_pose")
        self._lock = threading.Lock()
        self._current_goal = None
        self._last_goal = None

        self.create_subscription(
            PoseStamped,
            "/move_base_simple/goal",
            self._on_goal,
            10,
        )
        self.create_subscription(PoseStamped, "/goal_pose", self._on_goal, 10)

        self.get_logger().info("goal topic bridge ready")

    def _on_goal(self, msg: PoseStamped) -> None:
        threading.Thread(
            target=self._send_goal,
            args=(msg,),
            daemon=True,
        ).start()

    def _send_goal(self, msg: PoseStamped) -> None:
        self._client.wait_for_server()

        with self._lock:
            current_goal = self._current_goal

        if current_goal is not None:
            cancel_future = current_goal.cancel_goal_async()
            cancel_future.add_done_callback(lambda _: None)

        goal = NavigateToPose.Goal()
        goal.pose = msg
        goal.behavior_tree = ""
        with self._lock:
            self._last_goal = msg

        send_future = self._client.send_goal_async(goal)
        send_future.add_done_callback(self._handle_goal_response)

    def _handle_goal_response(self, future) -> None:
        goal_handle = future.result()
        if goal_handle is None or not goal_handle.accepted:
            self.get_logger().warning("navigate_to_pose goal rejected")
            return

        with self._lock:
            self._current_goal = goal_handle
            last_goal = self._last_goal

        if last_goal is not None:
            self.get_logger().info(
                f"forward goal to navigate_to_pose: "
                f"x={last_goal.pose.position.x:.2f}, "
                f"y={last_goal.pose.position.y:.2f}"
            )


def main() -> None:
    rclpy.init()
    node = GoalTopicBridge()
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
