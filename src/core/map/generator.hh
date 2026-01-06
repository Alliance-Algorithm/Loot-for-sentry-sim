#pragma once
#include "util/pimpl.hh"
#include <expected>
#include <sensor_msgs/msg/point_cloud2.hpp>

namespace rmcs {

class MapGenerator {
    RMCS_PIMPL_DEFINITION(MapGenerator)

public:
    struct Config {
        bool use_2d = false;
    };

    auto init(const Config&) noexcept -> void;

    auto used() noexcept -> bool;

    auto set_pose() noexcept -> void;

    auto generate(const sensor_msgs::msg::PointCloud2&) -> std::expected<void, std::string>;
};

} // namespace rmcs
