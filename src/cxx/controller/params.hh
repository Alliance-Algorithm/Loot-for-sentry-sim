#pragma once
#include <Eigen/Geometry>
#include <algorithm>
#include <cmath>
#include <numbers>
#include <tuple>

namespace rmcs::navigation {

struct ControllerParams {
    double gimbal_kp = 0.5;
    double gimbal_speed_max = 1.0;
    double gimbal_tolerance = std::numbers::pi_v<double> / 18.0;

    double road_max_perp = 0.3;
    double road_filter_alpha = 0.1;

    double step_min_speed = 0.5;
    double step_smooth_alpha = 0.08;

    double slope_max_accel = 0.5;
};

inline auto compute_gimbal_yaw_speed(
    double target_yaw, double current_yaw, double kp, double speed_max, double tolerance)
    -> double {
    if (!std::isfinite(target_yaw) || !std::isfinite(current_yaw))
        return 0.0;

    auto error = std::remainder(target_yaw - current_yaw, 2.0 * std::numbers::pi_v<double>);
    if (std::abs(error) <= tolerance)
        return 0.0;

    return std::clamp(kp * error, -speed_max, speed_max);
}

inline auto direction_to_yaw(const Eigen::Vector2d& vector) -> double {
    if (vector.squaredNorm() < 1e-12)
        return std::numeric_limits<double>::quiet_NaN();
    return std::atan2(vector.y(), vector.x());
}

} // namespace rmcs::navigation
