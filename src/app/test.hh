#pragma once
#include "util/pimpl.hh"

namespace rmcs::app {

class Test final {
    RMCS_PIMPL_DEFINITION(Test)

public:
    auto run() -> void;
};

} // namespace rmcs::app
