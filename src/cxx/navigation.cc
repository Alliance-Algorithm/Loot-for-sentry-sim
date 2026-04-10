#include "navigation.hh"
#include "util/logger_mixin.hh"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <optional>

#include <geometry_msgs/msg/pose_stamped.hpp>
#include <nav2_msgs/action/navigate_to_pose.hpp>
#include <rclcpp_action/rclcpp_action.hpp>

namespace rmcs::navigation::details {

struct Navigation::Impl {
    using GoalAction = nav2_msgs::action::NavigateToPose;
    using GoalHandle = rclcpp_action::ClientGoalHandle<GoalAction>;

    struct Goal final {
        double x;
        double y;
    };

    explicit Impl(rclcpp::Node& node)
        : node{node}
        , logger{node}
        , client{rclcpp_action::create_client<GoalAction>(&node, "/navigate_to_pose")} {}

    ~Impl() {
        auto current_handle = current_goal_handle;
        current_goal_handle.reset();
        goal_active = false;

        if (current_handle)
            client->async_cancel_goal(current_handle);
    }

    auto move(double x, double y) -> void {
        auto goal = Goal{.x = x, .y = y};
        if (!client->wait_for_action_server(std::chrono::seconds{1})) {
            logger.warn("navigate_to_pose action server is not available");
            return;
        }

        auto cancel_handle = GoalHandle::SharedPtr{};
        auto request_id = std::uint64_t{};
        if (goal_active && active_goal.has_value() && equal(*active_goal, goal)) {
            return;
        }

        active_goal = goal;
        goal_active = true;
        request_id = ++latest_request_id;
        cancel_handle = current_goal_handle;
        current_goal_handle.reset();

        if (cancel_handle) {
            logger.info("replace active navigation goal with x={}, y={}", goal.x, goal.y);
            client->async_cancel_goal(cancel_handle);
        }

        send_goal(goal, request_id);
    }

private:
    static constexpr auto kGoalEpsilon = 1e-6;

    static auto equal(const Goal& lhs, const Goal& rhs) -> bool {
        return std::abs(lhs.x - rhs.x) <= kGoalEpsilon && std::abs(lhs.y - rhs.y) <= kGoalEpsilon;
    }

    auto send_goal(const Goal& goal, std::uint64_t request_id) -> void {
        auto message = GoalAction::Goal{};
        message.pose.header.frame_id = "world";
        message.pose.header.stamp = node.now();
        message.pose.pose.position.x = goal.x;
        message.pose.pose.position.y = goal.y;
        message.pose.pose.orientation.w = 1.0;

        auto options = rclcpp_action::Client<GoalAction>::SendGoalOptions{};
        options.goal_response_callback = [&, this](const GoalHandle::SharedPtr& handle) {
            if (!handle) {
                if (request_id == latest_request_id)
                    goal_active = false;
                logger.warn("navigate_to_pose goal rejected: x={}, y={}", goal.x, goal.y);
                return;
            }

            auto should_cancel = false;
            if (request_id != latest_request_id) {
                should_cancel = true;
            } else {
                current_goal_handle = handle;
            }

            if (should_cancel) {
                client->async_cancel_goal(handle);
                return;
            }

            logger.info("send navigation goal: x={}, y={}", goal.x, goal.y);
        };
        client->async_send_goal(message, options);
    }

    rclcpp::Node& node;
    LoggerWrap<rclcpp::Node> logger;
    rclcpp_action::Client<GoalAction>::SharedPtr client;
    std::optional<Goal> active_goal;
    GoalHandle::SharedPtr current_goal_handle;
    std::uint64_t latest_request_id = 0;
    bool goal_active = false;
};

Navigation::Navigation(rclcpp::Node& node) noexcept
    : pimpl{std::make_unique<Impl>(node)} {}

Navigation::~Navigation() noexcept = default;

auto Navigation::move(double x, double y) -> void { pimpl->move(x, y); }

} // namespace rmcs::navigation::details
