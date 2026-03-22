#pragma once
#include <cstdint>
#include <yaml-cpp/yaml.h>

namespace rmcs::brain {

struct Limit {
    std::uint16_t health = 0;
    std::uint16_t bullet = 0;

    explicit Limit(const YAML::Node& config) {
        health = config["health"].as<std::uint16_t>();
        bullet = config["bullet"].as<std::uint16_t>();
    }
};
struct Battlefield {
    using Point = std::tuple<double, double>;
    Point home;
    std::vector<Point> cruise_points;

    explicit Battlefield(const YAML::Node& config) {
        const auto node = config["home"];
        home = Point{
            node[0].as<double>(),
            node[1].as<double>(),
        };
        for (const auto& point : config["cruise_points"]) {
            auto tuple = Point{
                point[0].as<double>(),
                point[1].as<double>(),
            };
            cruise_points.emplace_back(tuple);
        }
    }
};
struct Rule {
    Limit limit;
    Battlefield battlefield;

    explicit Rule(const YAML::Node& config)
        : limit{config["limit"]}
        , battlefield{config["battlefield"]} {}
};

} // namespace rmcs::brain
