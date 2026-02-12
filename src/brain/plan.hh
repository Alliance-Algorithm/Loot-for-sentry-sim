#pragma once
#include "util/pimpl.hh"

namespace rmcs {

struct PlanBox final {
    RMCS_PIMPL_DEFINITION(PlanBox)

public:
    struct Information {
        double health = 0.0;
        std::uint16_t bullet = 0;
    };

    template <std::invocable<Information&> F>
    auto update_information(F&& function) noexcept {
        std::forward<F>(function)(information_());
    }

private:
    auto information_() -> Information&;
};

} // namespace rmcs
