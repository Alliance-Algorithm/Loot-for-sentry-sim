#pragma once

#include <chrono>
#include <optional>

namespace rmcs::navigation {

template <typename T>
class ValueEnterDetector {
public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    using Duration = Clock::duration;

    ValueEnterDetector() = default;
    explicit ValueEnterDetector(const T& target)
        : target_{target} {}

    // 设置目标触发信号
    auto set_signal(const T& target) noexcept -> void { target_ = target; }

    // 开启防抖：指定时间窗口。默认是关闭的（Duration::zero()）
    auto enable_debounce(Duration window) noexcept -> void { debounce_duration_ = window; }

    // 状态更新并检测
    auto spin(const T& current, TimePoint now = Clock::now()) noexcept -> bool {
        auto triggered = false;

        if (!last_.has_value()) {
            triggered = (current == target_);
        } else {
            triggered = (*last_ != target_ && current == target_);
        }

        last_ = current;

        // 若满足触发条件，则进一步判断防抖逻辑
        if (triggered) {
            if (debounce_duration_ > Duration::zero()) {
                if (now >= cooldown_until_) {
                    cooldown_until_ = now + debounce_duration_;
                    return true;
                } else {
                    // 处于防抖冷却期内，合并（忽略）本次触发
                    return false;
                }
            }
            return true; // 防抖未开启，直接触发
        }

        return false;
    }

    auto reset() noexcept -> void {
        last_.reset();
        cooldown_until_ = TimePoint::min();
    }

private:
    T target_{};
    std::optional<T> last_{};

    Duration debounce_duration_{Duration::zero()};
    TimePoint cooldown_until_ = TimePoint::min();
};

} // namespace rmcs::navigation
