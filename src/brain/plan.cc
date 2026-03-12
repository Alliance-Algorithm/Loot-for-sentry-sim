#include "brain/plan.hh"
#include "brain/rule.hh"

#include <functional>
#include <unordered_map>

namespace rmcs {

constexpr auto kNan = std::numeric_limits<double>::quiet_NaN();

struct PlanBox::Impl {
    Information information;

    std::unique_ptr<brain::Rule> rule;

    std::unordered_map<std::string_view, std::function<void()>> plan_map;

    double goal_x = kNan;
    double goal_y = kNan;

    std::string_view to_the_home{"to_the_home"};
    std::string_view cruise_mode{"cruise_mode"};

    Impl() noexcept {
        plan_map[to_the_home] = [] {};
        plan_map[cruise_mode] = [] {};
    }

    auto do_plan() const noexcept {
        auto health = information.health;
        if (health < rule->limit.health) {
            return to_the_home;
        }

        auto bullet = information.bullet;
        if (bullet < rule->limit.bullet) {
            return to_the_home;
        }

        return cruise_mode;
    }

    auto goal_position() noexcept {
        // ......
        return std::tuple{goal_x, goal_y};
    }
};

PlanBox::PlanBox() noexcept
    : pimpl{std::make_unique<Impl>()} {}

PlanBox::~PlanBox() noexcept = default;

auto PlanBox::set_rule(const YAML::Node& rule) -> void {
    pimpl->rule = std::make_unique<brain::Rule>(rule);
}

auto PlanBox::goal_position() noexcept -> std::tuple<double, double> {
    return pimpl->goal_position();
}

auto PlanBox::do_plan_() noexcept -> void { pimpl->do_plan(); }
auto PlanBox::information_() noexcept -> Information& { return pimpl->information; }

} // namespace rmcs
