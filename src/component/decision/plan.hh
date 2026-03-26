#pragma once

#include "component/util/pimpl.hh"

#include <concepts>
#include <cstdint>
#include <expected>
#include <functional>
#include <limits>
#include <rmcs_msgs/game_stage.hpp>
#include <yaml-cpp/yaml.h>

namespace rmcs::navigation {
constexpr auto kNan = std::numeric_limits<double>::quiet_NaN();

struct PlanBox final {
    RMCS_PIMPL_DEFINITION(PlanBox)

public:
    struct Information {
        rmcs_msgs::GameStage game_stage = rmcs_msgs::GameStage::UNKNOWN;

        double current_x = kNan;
        double current_y = kNan;

        double enemy_x = kNan;
        double enemy_y = kNan;

        std::uint16_t health = 0;
        std::uint16_t bullet = 0;
    };
    struct Command {
        double goal_x = kNan;
        double goal_y = kNan;

        bool rotate_chassis = false;
        bool enable_autoaim = false;
        bool detect_targets = false;
    };

    auto configure(const YAML::Node&) -> std::expected<void, std::string>;

    auto set_logging(std::function<void(const std::string&)>) -> void;

    template <std::invocable<Information&> F>
    auto update_information(F&& function) noexcept {
        std::forward<F>(function)(information_());
        do_plan_();
    }

    template <std::invocable<const Command&> F>
    auto fetch_command(F&& function) noexcept {
        std::forward<F>(function)(command_());
    }

private:
    auto do_plan_() noexcept -> void;
    auto information_() noexcept -> Information&;
    auto command_() noexcept -> const Command&;
};

} // namespace rmcs::navigation
