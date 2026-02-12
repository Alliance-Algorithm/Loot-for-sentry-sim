#!/usr/bin/env python3

import threading

import rclpy
from action_msgs.msg import GoalStatus
from geometry_msgs.msg import PointStamped, PoseStamped
from lifecycle_msgs.msg import Transition
from lifecycle_msgs.srv import ChangeState, GetState
from nav2_msgs.action import ComputePathToPose, FollowPath
from rclpy.action.client import ActionClient
from rclpy.node import Node


class DebugGoalBridge(Node):
    def __init__(self) -> None:
        super().__init__("debug_goal_bridge")

        self.declare_parameter("goal_frame", "body")
        self.goal_frame = self.get_parameter(
            "goal_frame").get_parameter_value().string_value

        self.compute_path_client = ActionClient(
            self, ComputePathToPose, "/compute_path_to_pose")
        self.follow_path_client = ActionClient(
            self, FollowPath, "/follow_path")

        self._lock = threading.Lock()
        self._busy = False
        self._current_compute_handle = None
        self._current_follow_handle = None
        self._pending_goal = None

        self.create_subscription(
            PoseStamped, "/goal_pose", self.on_goal_pose, 10)
        self.create_subscription(
            PoseStamped, "/move_base_simple/goal", self.on_goal_pose, 10)
        self.create_subscription(
            PointStamped, "/clicked_point", self.on_clicked_point, 10)

        self.get_logger().info(
            f"debug goal bridge ready, publish PoseStamped"
            f"/PointStamped in frame '{self.goal_frame}'"
        )

    def ensure_nav_stack_ready(self) -> None:
        for node_name in ("planner_server", "controller_server"):
            self.wait_lifecycle_node(node_name)
            self.activate_lifecycle_node(node_name)

        self.compute_path_client.wait_for_server()
        self.follow_path_client.wait_for_server()

    def wait_lifecycle_node(self, node_name: str) -> None:
        get_state = self.create_client(GetState, f"/{node_name}/get_state")
        change_state = self.create_client(
            ChangeState, f"/{node_name}/change_state")
        get_state.wait_for_service()
        change_state.wait_for_service()

    def activate_lifecycle_node(self, node_name: str) -> None:
        state = self.get_lifecycle_state(node_name)
        if state == "unconfigured":
            self.change_lifecycle_state(
                node_name, Transition.TRANSITION_CONFIGURE)
            state = self.get_lifecycle_state(node_name)

        if state == "inactive":
            self.change_lifecycle_state(
                node_name, Transition.TRANSITION_ACTIVATE)

    def get_lifecycle_state(self, node_name: str) -> str:
        client = self.create_client(GetState, f"/{node_name}/get_state")
        request = GetState.Request()
        future = client.call_async(request)
        result = self.wait_future(future)
        if result is None:
            raise RuntimeError(
                f"failed to get lifecycle state for {node_name}")
        return result.current_state.label

    def change_lifecycle_state(
        self,
        node_name: str,
        transition_id: int,
    ) -> None:
        client = self.create_client(ChangeState, f"/{node_name}/change_state")
        request = ChangeState.Request()
        request.transition.id = transition_id
        future = client.call_async(request)
        result = self.wait_future(future)
        if result is None or not result.success:
            raise RuntimeError(
                f"failed to change lifecycle state for {node_name}")

    def wait_future(self, future):
        event = threading.Event()
        future.add_done_callback(lambda _: event.set())
        event.wait()
        return future.result()

    def on_clicked_point(self, msg: PointStamped) -> None:
        pose = PoseStamped()
        pose.header = msg.header
        pose.pose.position.x = msg.point.x
        pose.pose.position.y = msg.point.y
        pose.pose.position.z = msg.point.z
        pose.pose.orientation.w = 1.0
        self.on_goal_pose(pose)

    def on_goal_pose(self, msg: PoseStamped) -> None:
        if msg.header.frame_id != self.goal_frame:
            self.get_logger().warning(
                f"ignore goal in frame '{
                    msg.header.frame_id}', expected '{self.goal_frame}'"
            )
            return

        with self._lock:
            if self._busy:
                self._pending_goal = msg
                threading.Thread(target=self._preempt_and_restart,
                                 daemon=True).start()
                return
            self._busy = True

        threading.Thread(target=self._run_goal_thread,
                         args=(msg,), daemon=True).start()

    def _run_goal_thread(self, msg: PoseStamped) -> None:
        try:
            self.run_goal(msg)
        finally:
            with self._lock:
                self._current_compute_handle = None
                self._current_follow_handle = None
                next_goal = self._pending_goal
                self._pending_goal = None
                if next_goal is None:
                    self._busy = False
                    return
            self.run_goal(next_goal)

    def _preempt_and_restart(self) -> None:
        self.cancel_active_goals()

    def cancel_active_goals(self) -> None:
        self.get_logger().info("preempt current goal")
        with self._lock:
            compute_handle = self._current_compute_handle
            follow_handle = self._current_follow_handle
        if compute_handle is not None:
            self.wait_future(compute_handle.cancel_goal_async())
            with self._lock:
                if self._current_compute_handle is compute_handle:
                    self._current_compute_handle = None
        if follow_handle is not None:
            self.wait_future(follow_handle.cancel_goal_async())
            with self._lock:
                if self._current_follow_handle is follow_handle:
                    self._current_follow_handle = None

    def run_goal(self, goal_pose: PoseStamped) -> None:
        self.ensure_nav_stack_ready()

        compute_goal = ComputePathToPose.Goal()
        compute_goal.goal = goal_pose
        compute_goal.start.header.frame_id = self.goal_frame
        compute_goal.start.pose.orientation.w = 1.0
        compute_goal.use_start = True

        self.get_logger().info(
            f"compute path to ({goal_pose.pose.position.x:.2f}, {
                goal_pose.pose.position.y:.2f})"
        )

        compute_future = self.compute_path_client.send_goal_async(compute_goal)
        compute_handle = self.wait_future(compute_future)
        if compute_handle is None or not compute_handle.accepted:
            self.get_logger().error("compute path goal rejected")
            return
        with self._lock:
            self._current_compute_handle = compute_handle

        compute_result_future = compute_handle.get_result_async()
        compute_result = self.wait_future(compute_result_future).result
        with self._lock:
            if self._current_compute_handle is compute_handle:
                self._current_compute_handle = None
        if compute_result.error_code != ComputePathToPose.Result.NONE:
            self.get_logger().error(f"compute path failed: {
                compute_result.error_code}")
            return

        follow_goal = FollowPath.Goal()
        follow_goal.path = compute_result.path

        self.get_logger().info(f"follow path with {
            len(compute_result.path.poses)} poses")
        follow_future = self.follow_path_client.send_goal_async(follow_goal)
        follow_handle = self.wait_future(follow_future)
        if follow_handle is None or not follow_handle.accepted:
            self.get_logger().error("follow path goal rejected")
            return
        with self._lock:
            self._current_follow_handle = follow_handle

        follow_result_future = follow_handle.get_result_async()
        follow_result = self.wait_future(follow_result_future)
        with self._lock:
            if self._current_follow_handle is follow_handle:
                self._current_follow_handle = None

        if follow_result.status == GoalStatus.STATUS_SUCCEEDED:
            self.get_logger().info("follow path succeeded")
            return

        self.get_logger().warning(
            f"follow path ended with status {
                follow_result.status}, error_code "
            f"{follow_result.result.error_code}"
        )


def main() -> None:
    rclpy.init()
    node = DebugGoalBridge()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
