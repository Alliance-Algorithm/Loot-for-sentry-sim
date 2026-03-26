#pragma once

#include <chrono>
#include <deque>
#include <functional>
#include <utility>

namespace rmcs::navigation {

class DelayedTaskQueue {
public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    using Duration = Clock::duration;
    using Callback = std::function<void()>;

    auto push(Duration delay, Callback callback) -> void {
        if (!callback) {
            return;
        }

        if (delay <= Duration::zero()) {
            callback();
            return;
        }

        tasks_.push_back(
            Task{
                .delay = delay,
                .on_finish = std::move(callback),
            });
    }

    auto spin(TimePoint now = Clock::now()) -> void {
        while (!tasks_.empty()) {
            auto& task = tasks_.front();
            if (!task.started) {
                task.started = true;
                task.started_at = now;
            }

            if (now - task.started_at < task.delay) {
                break;
            }

            auto callback = std::move(task.on_finish);
            tasks_.pop_front();
            if (callback) {
                callback();
            }
        }
    }

    auto clear() noexcept -> void { tasks_.clear(); }

    [[nodiscard]] auto empty() const noexcept -> bool { return tasks_.empty(); }

private:
    struct Task {
        Duration delay{};
        Callback on_finish;
        bool started = false;
        TimePoint started_at{};
    };

    std::deque<Task> tasks_;
};

} // namespace rmcs::navigation
