#include "cxx/context.hh"

#include <exception>
#include <type_traits>

#include <yaml-cpp/yaml.h>

namespace rmcs::navigation::details {

namespace {

template <typename T>
auto try_sync(Context::InputInterface<T>& input, const YAML::Node& root, const std::string& name)
    -> void {
    if (const auto data = root[name]) {
        auto& to_sync = const_cast<T&>(*input);
        /*^^*/ if constexpr (std::is_enum_v<T>) {
            using U = std::underlying_type_t<T>;
            to_sync = static_cast<T>(data.as<U>());
        } else if constexpr (std::is_constructible_v<T, std::uint8_t>) {
            to_sync = T{data.as<std::uint8_t>()};
        } else {
            to_sync = data.as<T>();
        }
    }
}

template <typename T>
auto make_input(
    rmcs_executor::Component& component, const std::string& name, Context::InputInterface<T>& input,
    bool mock) -> void {
    if (mock) {
        input.make_and_bind_directly();
    } else {
        component.register_input(name, input, false);
    }
}

} // namespace

struct Context::Impl {
    rclcpp::Node& node;
    rmcs_executor::Component& component;
    std::shared_ptr<rclcpp::Subscription<std_msgs::msg::String>> subscription;
};

Context::Context(rclcpp::Node& node, rmcs_executor::Component& component) noexcept
    : pimpl{std::make_unique<Impl>(node, component)} {}

Context::~Context() noexcept = default;

auto Context::init(std::mutex& io_mutex, bool mock) -> void {
    auto& component = pimpl->component;
    auto& subscription = pimpl->subscription;
    auto& node = pimpl->node;

    make_input(component, "/referee/game/stage", game_stage, mock);
    make_input(component, "/referee/game/stage_remain_time", stage_remain_time, mock);
    make_input(component, "/referee/game/sync_timestamp", sync_timestamp, mock);
    make_input(
        component, "/referee/event/ally_big_energy_activation_status",
        ally_big_energy_activation_status, mock);
    make_input(
        component, "/referee/event/ally_small_energy_activation_status",
        ally_small_energy_activation_status, mock);
    make_input(
        component, "/referee/event/ally_fortress_occupation_status",
        ally_fortress_occupation_status, mock);
    make_input(
        component, "/referee/dart/latest_hit_target_total_count",
        dart_latest_hit_target_total_count, mock);

    make_input(component, "/referee/id", robot_id, mock);
    make_input(component, "/referee/shooter/cooling", robot_shooter_cooling, mock);
    make_input(component, "/referee/shooter/heat_limit", robot_shooter_heat_limit, mock);
    make_input(component, "/referee/chassis/power_limit", chassis_power_limit_referee, mock);
    make_input(component, "/referee/chassis/power", chassis_power_referee, mock);
    make_input(component, "/referee/chassis/buffer_energy", chassis_buffer_energy_referee, mock);
    make_input(component, "/referee/chassis/output_status", chassis_output_status, mock);

    make_input(component, "/referee/robots/hp", robots_hp, mock);
    make_input(component, "/referee/ally/hero_hp", ally_hero_hp, mock);
    make_input(component, "/referee/ally/engineer_hp", ally_engineer_hp, mock);
    make_input(component, "/referee/ally/infantry_1_hp", ally_infantry_1_hp, mock);
    make_input(component, "/referee/ally/infantry_2_hp", ally_infantry_2_hp, mock);
    make_input(component, "/referee/ally/outpost/hp", ally_outpost_hp, mock);
    make_input(component, "/referee/ally/base/hp", ally_base_hp, mock);
    make_input(component, "/referee/ally/hero_position_x", ally_hero_position_x, mock);
    make_input(component, "/referee/ally/hero_position_y", ally_hero_position_y, mock);
    make_input(component, "/referee/ally/engineer_position_x", ally_engineer_position_x, mock);
    make_input(component, "/referee/ally/engineer_position_y", ally_engineer_position_y, mock);
    make_input(component, "/referee/ally/infantry_1_position_x", ally_infantry_1_position_x, mock);
    make_input(component, "/referee/ally/infantry_1_position_y", ally_infantry_1_position_y, mock);
    make_input(component, "/referee/ally/infantry_2_position_x", ally_infantry_2_position_x, mock);
    make_input(component, "/referee/ally/infantry_2_position_y", ally_infantry_2_position_y, mock);
    make_input(component, "/referee/current_hp", robot_health, mock);
    make_input(component, "/referee/shooter/bullet_allowance", robot_bullet, mock);
    make_input(component, "/referee/shooter/42mm_bullet_allowance", robot_42mm_bullet, mock);
    make_input(
        component, "/referee/shooter/fortress_17mm_bullet_allowance",
        robot_fortress_17mm_bullet, mock);
    make_input(component, "/referee/remaining_gold_coin", remaining_gold_coin, mock);

    make_input(component, "/referee/shooter/initial_speed", robot_initial_speed, mock);
    make_input(component, "/referee/shooter/shoot_timestamp", robot_shoot_timestamp, mock);

    make_input(
        component, "/referee/sentry/can_confirm_free_revive", sentry_can_confirm_free_revive,
        mock);
    make_input(
        component, "/referee/sentry/can_exchange_instant_revive",
        sentry_can_exchange_instant_revive, mock);
    make_input(component, "/referee/sentry/instant_revive_cost", sentry_instant_revive_cost, mock);
    make_input(
        component, "/referee/sentry/exchanged_bullet_allowance", sentry_exchanged_bullet, mock);
    make_input(
        component, "/referee/sentry/remote_bullet_exchange_count",
        sentry_remote_bullet_exchange_count, mock);
    make_input(
        component, "/referee/sentry/exchangeable_bullet_allowance", sentry_exchangeable_bullet,
        mock);
    make_input(component, "/referee/sentry/mode", sentry_mode, mock);
    make_input(
        component, "/referee/sentry/energy_mechanism_activatable",
        sentry_energy_mechanism_activatable, mock);

    make_input(component, "/remote/switch/right", switch_right, mock);
    make_input(component, "/remote/switch/left", switch_left, mock);
    make_input(component, "/referee/game/red_score", red_score, mock);
    make_input(component, "/referee/game/blue_score", blue_score, mock);

    if (mock) {
        constexpr auto topic = "/rmcs_navigation/context/mock";
        subscription = node.create_subscription<std_msgs::msg::String>(
            topic, 10, [&, this](const std::unique_ptr<std_msgs::msg::String>& msg) {
                auto lock = std::scoped_lock{io_mutex};
                if (auto result = from(msg->data); !result)
                    RCLCPP_ERROR(
                        node.get_logger(), "Context mock failed: %s", result.error().c_str());
            });
    }
}

auto Context::from(const std::string& raw) noexcept -> std::expected<void, std::string> {
    try {
        auto root = YAML::Load(raw);
        if (!root.IsMap())
            return std::unexpected{"context yaml root must be a map"};

        try_sync(game_stage, root, "game_stage");
        try_sync(robot_health, root, "robot_health");
        try_sync(robot_bullet, root, "robot_bullet");
        try_sync(red_score, root, "red_score");
        try_sync(blue_score, root, "blue_score");

        return {};
    } catch (const std::exception& exception) {
        return std::unexpected{exception.what()};
    }
}

} // namespace rmcs::navigation::details
