#include "component/decision/plan.hh"

#include <array>
#include <cmath>
#include <gtest/gtest.h>
#include <thread>
#include <yaml-cpp/yaml.h>

namespace {

auto setup_plan_box(rmcs::navigation::PlanBox& plan_box, double cruise_interval = 9999.0) -> void {
    auto config = YAML::Node{YAML::NodeType::Map};
    config["health_limit"] = 100;
    config["health_ready"] = 300;
    config["bullet_limit"] = 10;
    config["bullet_ready"] = 50;
    config["home"] = std::array{1.2, 6.3};
    config["cruise_interval"] = cruise_interval;
    config["cruise_methods"]["occupation"].push_back(std::array{5.0, 3.0});
    config["cruise_methods"]["occupation"].push_back(std::array{7.0, 3.0});

    plan_box.configure(config);
}

auto fetch_command(rmcs::navigation::PlanBox& plan_box) -> rmcs::navigation::PlanBox::Command {
    auto command = rmcs::navigation::PlanBox::Command{};
    plan_box.fetch_command(
        [&](const rmcs::navigation::PlanBox::Command& value) { command = value; });
    return command;
}

auto update(
    rmcs::navigation::PlanBox& plan_box, rmcs_msgs::GameStage stage, double x, double y,
    std::uint16_t health, std::uint16_t bullet) {
    plan_box.update_information([&](rmcs::navigation::PlanBox::Information& info) {
        info.game_stage = stage;
        info.current_x = x;
        info.current_y = y;
        info.health = health;
        info.bullet = bullet;
    });
}

auto enter_started_stage(rmcs::navigation::PlanBox& plan_box) -> void {
    constexpr auto kNeutralHealth = std::uint16_t{200};
    constexpr auto kNeutralBullet = std::uint16_t{20};

    update(plan_box, rmcs_msgs::GameStage::PREPARATION, 0.0, 0.0, kNeutralHealth, kNeutralBullet);
    update(plan_box, rmcs_msgs::GameStage::REFEREE_CHECK, 0.0, 0.0, kNeutralHealth, kNeutralBullet);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, kNeutralHealth, kNeutralBullet);
}

TEST(PlanBox, KeepWaitingWhenResourcesAreBetweenThresholds) {
    auto plan_box = rmcs::navigation::PlanBox{};
    setup_plan_box(plan_box);
    enter_started_stage(plan_box);

    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 200, 20);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 200, 20);

    auto command = fetch_command(plan_box);
    EXPECT_TRUE(std::isnan(command.goal_x));
    EXPECT_TRUE(std::isnan(command.goal_y));
    EXPECT_FALSE(command.rotate_chassis);
    EXPECT_FALSE(command.detect_targets);
}

TEST(PlanBox, GoHomeWhenResourcesAreLow) {
    auto plan_box = rmcs::navigation::PlanBox{};
    setup_plan_box(plan_box);
    enter_started_stage(plan_box);

    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 50, 20);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 50, 20);

    auto command = fetch_command(plan_box);
    EXPECT_NEAR(command.goal_x, 1.2, 1e-6);
    EXPECT_NEAR(command.goal_y, 6.3, 1e-6);
    EXPECT_TRUE(command.rotate_chassis);
    EXPECT_FALSE(command.detect_targets);
}

TEST(PlanBox, CruiseEnablesScanningThenRotationAfterFirstPointReached) {
    auto plan_box = rmcs::navigation::PlanBox{};
    setup_plan_box(plan_box);
    enter_started_stage(plan_box);

    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 400, 80);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 400, 80);

    auto command = fetch_command(plan_box);
    EXPECT_NEAR(command.goal_x, 5.0, 1e-6);
    EXPECT_NEAR(command.goal_y, 3.0, 1e-6);
    EXPECT_FALSE(command.detect_targets);
    EXPECT_FALSE(command.rotate_chassis);

    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);
    command = fetch_command(plan_box);
    EXPECT_TRUE(command.detect_targets);
    EXPECT_TRUE(command.rotate_chassis);

    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);
    command = fetch_command(plan_box);
    EXPECT_TRUE(command.detect_targets);
    EXPECT_TRUE(command.rotate_chassis);
}

TEST(PlanBox, CruiseSwitchesToNextPointAfterOneSecondInterval) {
    using namespace std::chrono_literals;

    auto plan_box = rmcs::navigation::PlanBox{};
    setup_plan_box(plan_box, 1.0);
    enter_started_stage(plan_box);

    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 400, 80);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 400, 80);

    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);

    std::this_thread::sleep_for(900ms);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);
    auto command = fetch_command(plan_box);
    EXPECT_NEAR(command.goal_x, 5.0, 1e-6);
    EXPECT_NEAR(command.goal_y, 3.0, 1e-6);

    std::this_thread::sleep_for(200ms);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);
    command = fetch_command(plan_box);
    EXPECT_NEAR(command.goal_x, 7.0, 1e-6);
    EXPECT_NEAR(command.goal_y, 3.0, 1e-6);
    EXPECT_FALSE(command.detect_targets);
}

TEST(PlanBox, CruiseJitterDoesNotTriggerMultipleTasks) {
    using namespace std::chrono_literals;

    auto plan_box = rmcs::navigation::PlanBox{};
    setup_plan_box(plan_box, 1.0);
    enter_started_stage(plan_box);

    // Initial cruise state
    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 400, 80);

    // Reach point
    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);
    auto command = fetch_command(plan_box);
    EXPECT_NEAR(command.goal_x, 5.0, 1e-6);

    // Jitter: leave and re-enter point within merge window (500ms)
    std::this_thread::sleep_for(100ms);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 0.0, 0.0, 400, 80);
    std::this_thread::sleep_for(100ms);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);

    // Should still be waiting for the first interval, haven't switched yet
    command = fetch_command(plan_box);
    EXPECT_NEAR(command.goal_x, 5.0, 1e-6);

    // Wait for interval to finish
    std::this_thread::sleep_for(900ms);
    update(plan_box, rmcs_msgs::GameStage::STARTED, 5.0, 3.0, 400, 80);
    command = fetch_command(plan_box);

    // Should have switched to next point
    EXPECT_NEAR(command.goal_x, 7.0, 1e-6);
}

} // namespace
