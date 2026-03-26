#include "component/util/bool_edge_trigger.hh"

#include <chrono>
#include <gtest/gtest.h>

namespace {

using namespace std::chrono_literals;

TEST(BoolEdgeTrigger, MergesRisingEdgesWithinWindow) {
    auto trigger = rmcs::navigation::BoolEdgeTrigger{500ms};
    auto now = rmcs::navigation::BoolEdgeTrigger::TimePoint{};

    trigger.spin(false, now);
    EXPECT_FALSE(trigger.consume_trigger());

    trigger.spin(true, now);
    EXPECT_TRUE(trigger.consume_trigger());
    EXPECT_TRUE(trigger.ever_triggered());
    EXPECT_FALSE(trigger.consume_trigger());

    trigger.spin(false, now + 100ms);
    trigger.spin(true, now + 200ms);
    EXPECT_FALSE(trigger.consume_trigger());

    trigger.spin(false, now + 600ms);
    trigger.spin(true, now + 700ms);
    EXPECT_TRUE(trigger.consume_trigger());
    EXPECT_TRUE(trigger.ever_triggered());
}

TEST(BoolEdgeTrigger, ResetClearsPendingState) {
    auto trigger = rmcs::navigation::BoolEdgeTrigger{500ms};
    auto now = rmcs::navigation::BoolEdgeTrigger::TimePoint{};

    trigger.spin(true, now);
    ASSERT_TRUE(trigger.has_triggered());

    trigger.reset();
    EXPECT_FALSE(trigger.has_triggered());
    EXPECT_FALSE(trigger.ever_triggered());
    EXPECT_FALSE(trigger.consume_trigger());
}

TEST(BoolEdgeTrigger, EverTriggeredPersistsAfterConsume) {
    auto trigger = rmcs::navigation::BoolEdgeTrigger{500ms};
    auto now = rmcs::navigation::BoolEdgeTrigger::TimePoint{};

    trigger.spin(true, now);
    EXPECT_TRUE(trigger.consume_trigger());
    EXPECT_TRUE(trigger.ever_triggered());
    EXPECT_FALSE(trigger.has_triggered());
}

TEST(BoolEdgeTrigger, ResetEdgeOnlyPreservesEverTriggered) {
    auto trigger = rmcs::navigation::BoolEdgeTrigger{500ms};
    auto now = rmcs::navigation::BoolEdgeTrigger::TimePoint{};

    trigger.spin(true, now);
    ASSERT_TRUE(trigger.ever_triggered());
    ASSERT_TRUE(trigger.consume_trigger());

    trigger.reset_edge_only();
    EXPECT_TRUE(trigger.ever_triggered());
    EXPECT_FALSE(trigger.has_triggered());
    EXPECT_FALSE(trigger.consume_trigger());

    // Should still detect edges after reset_edge_only
    trigger.spin(false, now + 100ms);
    trigger.spin(true, now + 200ms);
    EXPECT_TRUE(trigger.consume_trigger());
}

} // namespace
