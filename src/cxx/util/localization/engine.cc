#include "cxx/util/localization/engine.hh"
#include "cxx/util/node_mixin.hh"

#include <pcl/io/pcd_io.h>
#include <pcl/kdtree/kdtree_flann.h>
#include <pcl/point_cloud.h>
#include <pcl/point_types.h>
#include <pcl/registration/ndt.h>

#include <pcl_conversions/pcl_conversions.h>
#include <rclcpp/logging.hpp>
#include <rclcpp/subscription.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>

#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>

namespace rmcs::navigation {

struct Localization::Impl {
    Config config;
    LoggerWrap<rclcpp::Node> logging;

    struct Context {
        using Point = pcl::PointXYZ;
        using Cloud = pcl::PointCloud<Point>;

        std::shared_ptr<rclcpp::Subscription<sensor_msgs::msg::PointCloud2>> subscription;
        std::atomic<bool> is_collecting = false;
        std::mutex collected_mutex;

        std::shared_ptr<Cloud> map = std::make_shared<Cloud>();
        std::shared_ptr<Cloud> collected = std::make_shared<Cloud>();

        explicit Context(Config& config) {
            const auto& filename = config.map_filename;
            if (pcl::io::loadPCDFile<Point>(filename, *map) != 0)
                throw std::runtime_error{"Couldn't read " + filename};

            auto& rclcpp = config.rclcpp;
            subscription = rclcpp.create_subscription<sensor_msgs::msg::PointCloud2>(
                config.topic_registered, 10,
                [this](const std::unique_ptr<sensor_msgs::msg::PointCloud2>& msg) {
                    if (!is_collecting.load(std::memory_order_relaxed)) return;

                    auto received = Cloud {};
                    pcl::fromROSMsg(*msg, received);

                    auto lock = std::scoped_lock { collected_mutex };
                    *collected += received;
                });
        }
    } context;

    pcl::NormalDistributionsTransform<Context::Point, Context::Point> engine;

    explicit Impl(Localization::Config config)
        : config{std::move(config)}
        , logging{config.rclcpp}
        , context{config} {

        engine.setTransformationEpsilon(config.ndt_result_epsilon); // 收敛判定阈值
        engine.setStepSize(config.ndt_step_size);                   // More-Thuente 线搜索最大步长
        engine.setResolution(config.ndt_resolution);                // NDT 网格分辨率
        engine.setMaximumIterations(config.ndt_max_iterations);     // 最大迭代次数
    }

    static auto extract_submap(const Context::Cloud& map, const Eigen::Vector3d& center,
        double radius) -> std::shared_ptr<Context::Cloud> {
        auto map_shared = map.makeShared();
        auto kd_tree = pcl::KdTreeFLANN<Context::Point> {};
        kd_tree.setInputCloud(map_shared);

        auto indices = std::vector<int> {};
        auto distances = std::vector<float> {};
        const auto query = Context::Point {
            static_cast<float>(center.x()),
            static_cast<float>(center.y()),
            static_cast<float>(center.z()),
        };
        kd_tree.radiusSearch(query, static_cast<float>(radius), indices, distances);

        auto submap = std::make_shared<Context::Cloud>();
        submap->reserve(indices.size());
        for (const auto index : indices) {
            submap->push_back(map[index]);
        }
        return submap;
    }

    auto start_collecting(std::chrono::seconds seconds) -> std::expected<void, std::string> {
        if (context.is_collecting.exchange(true, std::memory_order_relaxed)) {
            return std::unexpected { "already collecting point cloud" };
        }

        {
            auto lock = std::scoped_lock { context.collected_mutex };
            context.collected->clear();
        }

        std::thread { [this, seconds] {
            std::this_thread::sleep_for(seconds);
            context.is_collecting.store(false, std::memory_order_relaxed);
        } }
            .detach();

        return {};
    }

    auto start_localizing(const Eigen::Isometry3d& initial_solution)
        -> std::future<std::expected<Eigen::Isometry3d, std::string>> {
        return std::async(std::launch::async, [this, initial_solution] {
            try {
                auto scan = std::make_shared<Context::Cloud>();
                {
                    auto lock = std::scoped_lock { context.collected_mutex };
                    *scan = *context.collected;
                }

                if (scan->empty()) {
                    return std::expected<Eigen::Isometry3d, std::string> {
                        std::unexpected { "collected cloud is empty" }
                    };
                }

                constexpr auto submap_radius = 25.0;
                auto submap = extract_submap(*context.map, initial_solution.translation(), submap_radius);
                if (submap->empty()) {
                    return std::expected<Eigen::Isometry3d, std::string> {
                        std::unexpected { "extracted submap is empty" }
                    };
                }

                engine.setInputTarget(submap);
                engine.setInputSource(scan);

                auto aligned = Context::Cloud {};
                const auto initial_guess = initial_solution.matrix().cast<float>();
                engine.align(aligned, initial_guess);

                if (!engine.hasConverged()) {
                    return std::expected<Eigen::Isometry3d, std::string> {
                        std::unexpected { "ndt failed to converge" }
                    };
                }

                const auto transform = engine.getFinalTransformation().cast<double>();
                auto result = Eigen::Isometry3d::Identity();
                result.matrix() = transform;

                RCLCPP_INFO(config.rclcpp.get_logger(), "Localization converged, fitness score: %.6f",
                    engine.getFitnessScore());

                return std::expected<Eigen::Isometry3d, std::string> { result };
            } catch (const std::exception& e) {
                return std::expected<Eigen::Isometry3d, std::string> {
                    std::unexpected { std::string { "localization exception: " } + e.what() }
                };
            }
        });
    }
};

Localization::Localization(Config config)
    : pimpl{std::make_unique<Impl>(std::move(config))} {}

Localization::~Localization() noexcept = default;

auto Localization::start_collecting(std::chrono::seconds seconds)
    -> std::expected<void, std::string> {
    return pimpl->start_collecting(seconds);
}

auto Localization::start_localizing(const Eigen::Isometry3d& initial_solution)
    -> std::future<std::expected<Eigen::Isometry3d, std::string>> {
    return pimpl->start_localizing(initial_solution);
}

} // namespace rmcs::navigation
