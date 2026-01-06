#include "generator.hh"

using namespace rmcs;

struct MapGenerator::Impl {
    Config config;

    auto generate(const sensor_msgs::msg::PointCloud2& scan) {}
};

MapGenerator::MapGenerator() noexcept
    : pimpl{std::make_unique<Impl>()} {}

MapGenerator::~MapGenerator() noexcept = default;
