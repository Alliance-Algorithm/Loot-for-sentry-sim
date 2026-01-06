#include "test.hh"
#include "util/fsm.hh"

using namespace rmcs::app;

enum class Status {
    NO_ACTION,
    COMMAND_MODE,
    CRUISE_MODE,
    END,
};

struct Test::Impl {
    auto run() {
        auto fsm = Fsm{Status::NO_ACTION};
        // ...
    }
};

auto Test::run() -> void { pimpl->run(); }

Test::Test() noexcept
    : pimpl{std::make_unique<Impl>()} {}

Test::~Test() noexcept = default;
