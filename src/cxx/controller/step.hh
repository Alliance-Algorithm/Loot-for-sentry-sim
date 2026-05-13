#pragma once
#include "params.hh"
#include <Eigen/Geometry>
#include <algorithm>

namespace rmcs::navigation {

struct StepController {
    explicit StepController(const ControllerParams& params = {})
        : params_{params} {}

    auto update_speed(Eigen::Vector2d speed) -> void { speed_ = speed; }

    auto update_toward(Eigen::Vector2d vector) -> void {
        if (vector.squaredNorm() > 1e-12)
            vector.normalize();
        toward_ = vector;
    }

    auto update_yaw(double yaw) -> void { yaw_ = yaw; }

    auto generate_command() const -> Eigen::Vector4d {
        auto target = speed_;
        auto norm = target.norm();

        if (norm > 1e-6 && norm < params_.step_min_speed)
            target = target / norm * params_.step_min_speed;

        smoothed_speed_ += params_.step_smooth_alpha * (target - smoothed_speed_);

        auto target_yaw = direction_to_yaw(toward_);
        auto yaw_speed = compute_gimbal_yaw_speed(
            target_yaw, yaw_, params_.gimbal_kp, params_.gimbal_speed_max,
            params_.gimbal_tolerance);

        return Eigen::Vector4d{
            smoothed_speed_.x(), smoothed_speed_.y(), yaw_speed, 0.0};
    }

private:
    ControllerParams params_;
    Eigen::Vector2d speed_ = Eigen::Vector2d::Zero();
    Eigen::Vector2d toward_ = Eigen::Vector2d{1.0, 0.0};
    double yaw_ = 0.0;
    mutable Eigen::Vector2d smoothed_speed_ = Eigen::Vector2d::Zero();
};

} // namespace rmcs::navigation
