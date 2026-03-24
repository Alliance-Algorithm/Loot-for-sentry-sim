#include "component/decision/plan.hh"
#include "component/decision/config.hh"

#include <array>
#include <experimental/scope>
#include <functional>
#include <unordered_map>

namespace rmcs_navigation {

constexpr auto kNan = std::numeric_limits<double>::quiet_NaN();

struct PlanBox::Impl {
    enum class Mode : std::uint8_t {
        Waiting = 0,
        ToTheHome = 1,
        Cruise = 2,
    };

    struct ModeHash {
        auto operator()(const Mode mode) const noexcept -> std::size_t {
            return static_cast<std::size_t>(mode);
        }
    };

    Information information;

    std::unique_ptr<Config> config;

    std::unordered_map<Mode, std::function<void()>, ModeHash> plan_map;

    double goal_x = kNan;
    double goal_y = kNan;

    Mode last_mode = Mode::Waiting;

    bool rotation_chassis = false;
    bool gimbal_scanning = false;

    // CONTEXT
    rmcs_msgs::GameStage last_game_stage = rmcs_msgs::GameStage::UNKNOWN;

    std::size_t cruise_index = 0;
    std::string occupation_label = "occupation";
    std::string aggressive_label = "aggressive";

    bool cruise_point_reached = false;

    Impl() noexcept {
        // 等待模式，啥也不做
        plan_map[Mode::Waiting] = [this] {
            goal_x = kNan;
            goal_y = kNan;

            rotation_chassis = false;
            gimbal_scanning = false;
        };

        // 回家
        plan_map[Mode::ToTheHome] = [this] {
            auto [x, y] = config->home;
            goal_x = x;
            goal_y = y;

            rotation_chassis = true;
            gimbal_scanning = false;
        };

        // 巡航模式，小陀螺旋转，云台扫描
        plan_map[Mode::Cruise] = [this] {
            // TODO:
            // Switch Cruise Method
            auto kDefault = occupation_label;

            const auto& positions = config->cruise_methods.at(kDefault);
            const auto length = positions.size();

            if (last_mode != Mode::Cruise) {
                cruise_index = 0;
            }
            if (cruise_index >= length) {
                cruise_index = 0;
            }

            auto [x, y] = positions.at(cruise_index);
            goal_x = x;
            goal_y = y;

            // 到达第一个巡航点开始，小陀螺，直到比赛结束
            if (cruise_point_reached) {
                rotation_chassis = true;
                gimbal_scanning = true;
            }

            constexpr auto kTolerance = 0.1;
            if (std::abs(information.current_x - goal_x) < kTolerance
                && std::abs(information.current_y - goal_y) < kTolerance) {
                cruise_index += 1;
                cruise_point_reached = true;
            }
        };
    }

    auto do_plan() noexcept {
        auto mode = Mode::Waiting;

        do {
            using namespace rmcs_msgs;
            auto game_stage = information.game_stage;
            auto on_exit = std::experimental::scope_exit{
                [=, this] { last_game_stage = game_stage; },
            };
            if (last_game_stage == GameStage::PREPARATION
                && game_stage == GameStage::REFEREE_CHECK) {
                mode = Mode::Waiting;
                // TODO:
                // 将当前点设置为 Home，依靠发布 world -> odom 的变换
                break;
            }

            if (game_stage == GameStage::SETTLING) {
                rotation_chassis = false;
                gimbal_scanning = false;
                break;
            }

            // 状态不佳
            {
                auto situations = std::array{
                    information.health < config->health_limit,
                    information.bullet < config->bullet_limit,
                };
                if (std::ranges::any_of(situations, std::identity{})) {
                    mode = Mode::ToTheHome;
                    break;
                }
            }

            // 血量和弹药都恢复到 Ready 线上
            {
                auto situations = std::array{
                    information.health >= config->health_ready,
                    information.bullet >= config->bullet_ready,
                };
                if (std::ranges::all_of(situations, std::identity{})) {
                    mode = Mode::Cruise;
                    break;
                }
            }

        } while (false);

        auto& function = plan_map.at(mode);
        std::invoke(function);

        last_mode = mode;
    }

    auto goal_position() noexcept { return std::tuple{goal_x, goal_y}; }
};

PlanBox::PlanBox() noexcept
    : pimpl{std::make_unique<Impl>()} {}

PlanBox::~PlanBox() noexcept = default;

auto PlanBox::configure(const YAML::Node& config) -> void {
    pimpl->config = std::make_unique<Config>(config);
}

auto PlanBox::goal_position() noexcept -> std::tuple<double, double> {
    return pimpl->goal_position();
}

auto PlanBox::rotation_chassis() const noexcept -> bool { return pimpl->rotation_chassis; }

auto PlanBox::gimbal_scanning() const noexcept -> bool { return pimpl->gimbal_scanning; }

auto PlanBox::do_plan_() noexcept -> void { pimpl->do_plan(); }

auto PlanBox::information_() noexcept -> Information& { return pimpl->information; }

} // namespace rmcs_navigation
