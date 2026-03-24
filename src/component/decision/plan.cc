#include "component/decision/plan.hh"
#include "component/decision/config.hh"
#include "component/util/fsm.hh"

#include <array>
#include <chrono>
#include <cmath>
#include <experimental/scope>
#include <functional>
#include <utility>

namespace rmcs_navigation {

constexpr auto kNan = std::numeric_limits<double>::quiet_NaN();

struct PlanBox::Impl {
    enum class Mode : std::uint8_t {
        Waiting,
        ToTheHome,
        Cruise,
        END,
    };

    std::function<void(const std::string&)> printer = [](const std::string&) {};

    Information information;

    std::unique_ptr<Config> config;

    rmcs::Fsm<Mode> fsm{Mode::Waiting};

    double goal_x = kNan;
    double goal_y = kNan;

    bool rotate_chassis = false;
    bool gimbal_scanning = false;

    // CONTEXT
    rmcs_msgs::GameStage last_game_stage = rmcs_msgs::GameStage::UNKNOWN;

    std::size_t cruise_index = 0;
    std::string occupation_label = "occupation";
    std::string aggressive_label = "aggressive";

    bool cruise_point_reached = false;
    bool has_cruise_point_reached = false;
    std::chrono::steady_clock::time_point cruise_reached_timestamp{};

    auto select_mode() const noexcept -> Mode {
        using namespace rmcs_msgs;
        auto game_stage = information.game_stage;

        if (last_game_stage == GameStage::PREPARATION && game_stage == GameStage::REFEREE_CHECK) {
            // 触发一次坐标整定，将当前设置为标准的 Home 坐标
            // 发布 world -> odom 的变换
            return Mode::Waiting;
        }
        if (game_stage == GameStage::SETTLING) {
            return Mode::Waiting;
        }

        // 优势不在我，回家补给
        {
            auto situations = std::array{
                information.health < config->health_limit,
                information.bullet < config->bullet_limit,
            };
            if (std::ranges::any_of(situations, std::identity{})) {
                return Mode::ToTheHome;
            }
        }

        // 优势在我，进行巡航进攻
        {
            auto situations = std::array{
                information.health >= config->health_ready,
                information.bullet >= config->bullet_ready,
            };
            if (std::ranges::all_of(situations, std::identity{})) {
                return Mode::Cruise;
            }
        }

        return Mode::Waiting;
    }

    Impl() noexcept {
        // 等待模式，啥也不做
        fsm.use<Mode::Waiting>(
            [this] {
                goal_x = kNan;
                goal_y = kNan;

                rotate_chassis = false;
                gimbal_scanning = false;

                printer("Start Waiting Mode");
            },
            [this] { return select_mode(); });

        // 回家
        fsm.use<Mode::ToTheHome>(
            [this] {
                auto [x, y] = config->home;
                goal_x = x;
                goal_y = y;

                rotate_chassis = true;
                gimbal_scanning = false;

                printer("Start ToTheHome Mode");
            },
            [this] { return select_mode(); });

        // 巡航模式，小陀螺旋转，云台扫描
        fsm.use<Mode::Cruise>(
            [this] {
                cruise_index = 0;
                cruise_reached_timestamp = std::chrono::steady_clock::now();
                rotate_chassis = false;
                gimbal_scanning = false;

                printer("Start Cruise Mode");
            },
            [this] {
                auto& positions = config->cruise_methods.at(occupation_label);

                if (cruise_index >= positions.size()) {
                    cruise_index = 0;
                }

                auto update_goal = [this, &positions] {
                    auto [x, y] = positions.at(cruise_index);
                    goal_x = x;
                    goal_y = y;
                };
                update_goal();

                constexpr auto kTolerance = 0.1;
                auto reached = std::abs(information.current_x - goal_x) < kTolerance
                            && std::abs(information.current_y - goal_y) < kTolerance;

                if (reached && cruise_point_reached == false) {
                    cruise_point_reached = true;
                    cruise_reached_timestamp = std::chrono::steady_clock::now();
                }
                if (reached == false) {
                    cruise_point_reached = false;
                }

                // 自第一个巡航点开始，小陀螺不止
                if (has_cruise_point_reached) {
                    rotate_chassis = true;
                }

                if (cruise_point_reached) {
                    has_cruise_point_reached = true;
                    gimbal_scanning = true;

                    auto interval = config->cruise_interval;
                    auto elapsed = std::chrono::duration<double>(
                        std::chrono::steady_clock::now() - cruise_reached_timestamp);
                    if (elapsed.count() >= interval) {
                        cruise_index = (cruise_index + 1) % positions.size();
                        cruise_point_reached = false;
                        gimbal_scanning = false;
                        update_goal();
                    }
                }

                return select_mode();
            });
    }

    auto do_plan() noexcept {
        fsm.spin_once();
        last_game_stage = information.game_stage;
    }

    auto goal_position() noexcept { return std::tuple{goal_x, goal_y}; }
};

PlanBox::PlanBox() noexcept
    : pimpl{std::make_unique<Impl>()} {}

PlanBox::~PlanBox() noexcept = default;

auto PlanBox::configure(const YAML::Node& config) -> void {
    pimpl->config = std::make_unique<Config>(config);
    pimpl->fsm.start_on(Impl::Mode::Waiting);
}

auto PlanBox::set_printer(std::function<void(const std::string&)> printer) -> void {
    pimpl->printer = std::move(printer);
}

auto PlanBox::goal_position() noexcept -> std::tuple<double, double> {
    return pimpl->goal_position();
}

auto PlanBox::rotate_chassis() const noexcept -> bool { return pimpl->rotate_chassis; }

auto PlanBox::gimbal_scanning() const noexcept -> bool { return pimpl->gimbal_scanning; }

auto PlanBox::do_plan_() noexcept -> void { pimpl->do_plan(); }

auto PlanBox::information_() noexcept -> Information& { return pimpl->information; }

} // namespace rmcs_navigation
