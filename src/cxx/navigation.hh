#pragma once
#include "util/pimpl.hh"

#include <rclcpp/node.hpp>

namespace rmcs::navigation::details {

class Navigation {
    RMCS_PIMPL_DEFINITION(Navigation)
public:
    explicit Navigation(rclcpp::Node& node) noexcept;

    auto move(double x, double y) -> void;
};

} // namespace rmcs::navigation::details
