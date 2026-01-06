#include "app/rmuc.hh"
#include "app/rmul.hh"
#include "app/test.hh"

template <class App>
auto run() noexcept try {
    auto app = App{};
    app.run();
} catch (...) {
    // ...
}

auto main() -> int {
    using namespace rmcs;

    auto app_name = std::string{};

    if (app_name == "test")
        run<app::Test>();

    // if (app_name == "rmuc")
    //     run<app::Rmuc>();
    //
    // if (app_name == "rmul")
    //     run<app::Rmul>();
}
