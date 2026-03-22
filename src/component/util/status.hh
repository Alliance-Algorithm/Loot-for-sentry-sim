#pragma once
#include <rmcs_msgs/game_stage.hpp>
#include <rmcs_msgs/robot_id.hpp>
#include <yaml-cpp/yaml.h>

#include <cstdint>
#include <string>
#include <unordered_map>

namespace rmcs_navigation {

enum class RobotStatus : std::uint8_t {
    Unknown,
    Normal,
    Invincible,
    Deaded,
};

auto to_string(rmcs_msgs::GameStage stage) noexcept -> std::string {
    using rmcs_msgs::GameStage;
    switch (stage) {
    case GameStage::NOT_START: return "NotStart";
    case GameStage::PREPARATION: return "Preparation";
    case GameStage::REFEREE_CHECK: return "RefereeCheck";
    case GameStage::COUNTDOWN: return "Countdown";
    case GameStage::STARTED: return "Started";
    case GameStage::SETTLING: return "Settling";
    case GameStage::UNKNOWN: return "Unknown";
    }
    return "Unknown";
}
auto to_string(RobotStatus status) noexcept -> std::string {
    switch (status) {
    case RobotStatus::Unknown: return "Unknown";
    case RobotStatus::Normal: return "Normal";
    case RobotStatus::Invincible: return "Invincible";
    case RobotStatus::Deaded: return "Deaded";
    }
    return "Unknown";
}

struct Status {
    rmcs_msgs::GameStage game_stage;

    std::unordered_map<rmcs_msgs::RobotId, RobotStatus> robot_status;

    int health = 0;
    int bullet = 0;

    bool is_invincible = false;

    auto string() const -> std::string {
        auto yaml = YAML::Node{};
        yaml["game_stage"] = to_string(game_stage);

        auto robot_yaml = YAML::Node{};
        for (const auto& [robot_id, status] : robot_status) {
            const auto key = static_cast<int>(static_cast<std::uint8_t>(robot_id));
            robot_yaml[key] = to_string(status);
        }
        yaml["robot_status"] = robot_yaml;

        yaml["health"] = health;
        yaml["bullet"] = bullet;
        yaml["is_invincible"] = is_invincible;

        return YAML::Dump(yaml);
    }
};

} // namespace rmcs_navigation
