#pragma once
#include "params.hh"
#include <Eigen/Geometry>
#include <algorithm>

namespace rmcs::navigation {

struct RoadController {
    explicit RoadController(const ControllerParams& params = {})
        : params_{params} {}

    auto update_speed(Eigen::Vector2d speed) -> void { speed_ = speed; }

    auto update_toward(Eigen::Vector2d vector) -> void {
        if (vector.squaredNorm() > 1e-12)
            vector.normalize();
        toward_ = vector;
    }

    auto update_yaw(double yaw) -> void { yaw_ = yaw; }

    auto generate_command() const -> Eigen::Vector4d {
        auto forward = toward_;
        if (forward.squaredNorm() < 1e-12)
            forward = Eigen::Vector2d{1.0, 0.0};

        auto right = Eigen::Vector2d{-forward.y(), forward.x()};

        auto para = speed_.dot(forward);
        auto perp = speed_.dot(right);

        perp = std::clamp(perp, -params_.road_max_perp, params_.road_max_perp);
        filtered_perp_ += params_.road_filter_alpha * (perp - filtered_perp_);

        auto chassis = para * forward + filtered_perp_ * right;

        auto target_yaw = direction_to_yaw(toward_);
        auto yaw_speed = compute_gimbal_yaw_speed(
            target_yaw, yaw_, params_.gimbal_kp, params_.gimbal_speed_max,
            params_.gimbal_tolerance);

        return Eigen::Vector4d{chassis.x(), chassis.y(), yaw_speed, 0.0};
    }

private:
    ControllerParams params_;
    Eigen::Vector2d speed_ = Eigen::Vector2d::Zero();
    Eigen::Vector2d toward_ = Eigen::Vector2d{1.0, 0.0};
    double yaw_ = 0.0;
    mutable double filtered_perp_ = 0.0;
};

} // namespace rmcs::navigation
