#pragma once

#include <chrono>

namespace rmcs::navigation {

class BoolEdgeTrigger {
public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    using Duration = Clock::duration;

    explicit BoolEdgeTrigger(Duration merge_window = std::chrono::milliseconds{500})
        : merge_window_{merge_window > Duration::zero() ? merge_window : Duration::zero()} {
        reset(false);
    }

    auto reset(bool initial_level = false) noexcept -> void {
        last_level_ = initial_level;
        pending_trigger_ = false;
        ever_triggered_ = false;
        cooldown_until_ = TimePoint::min();
    }

    auto reset_edge_only(bool initial_level = false) noexcept -> void {
        last_level_ = initial_level;
        pending_trigger_ = false;
        cooldown_until_ = TimePoint::min();
    }

    auto spin(bool level, TimePoint now = Clock::now()) noexcept -> void {
        auto rising_edge = !last_level_ && level;
        if (rising_edge && now >= cooldown_until_) {
            pending_trigger_ = true;
            ever_triggered_ = true;
            cooldown_until_ = now + merge_window_;
        }
        last_level_ = level;
    }

    [[nodiscard]] auto has_triggered() const noexcept -> bool { return pending_trigger_; }
    [[nodiscard]] auto ever_triggered() const noexcept -> bool { return ever_triggered_; }

    auto consume_trigger() noexcept -> bool {
        auto value = pending_trigger_;
        pending_trigger_ = false;
        return value;
    }

private:
    Duration merge_window_{};
    bool last_level_ = false;
    bool pending_trigger_ = false;
    bool ever_triggered_ = false;
    TimePoint cooldown_until_ = TimePoint::min();
};

} // namespace rmcs::navigation
