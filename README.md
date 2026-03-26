# rmcs-navigation (Ai Generated, 不保真)

`rmcs-navigation` 是 RMCS 导航技能包，提供以下能力：

- 基于 Nav2 的路径规划、局部控制与行为树导航链路。
- 与 `point_lio`、`rmcs_local_map`、`livox_ros_driver2` 的集成启动。
- 将 RViz 常用目标话题（`/move_base_simple/goal`、`/goal_pose`）桥接到 Nav2 action（`/navigate_to_pose`）。
- 提供 waypoint 巡航脚本，以及一个供 `rmcs_executor` 加载的导航决策组件插件。

## 目录结构

- `launch/nav2.launch.py`：仅启动 Nav2 + 可选 `rmcs_local_map`。
- `launch/online.launch.py`：在线模式，一键拉起地图、雷达驱动、点云定位和 Nav2。
- `launch/custom.launch.py`：多模式启动（`online` / `bag` / `static`）。
- `launch/follow_waypoints.launch.py`：启动 waypoint 巡航 runner。
- `src/script/goal_topic_bridge.py`：目标话题桥接。
- `src/script/follow_waypoints_runner.py`：按配置文件连续下发 waypoint。
- `src/component/`：`rmcs_executor` 插件组件与决策逻辑（PlanBox）。
- `config/*.yaml`：导航参数、决策参数、waypoint 和运行模式配置。

## 依赖

### 系统/ROS 依赖

- ROS 2 Jazzy（建议在 RMCS devcontainer 内使用）。
- Nav2 相关包：`nav2_map_server`、`nav2_lifecycle_manager`、`nav2_controller`、`nav2_planner`、`nav2_bt_navigator`、`nav2_waypoint_follower`、`nav2_velocity_smoother`。
- TF 与基础消息：`tf2_ros`、`geometry_msgs`、`nav_msgs`、`lifecycle_msgs`。

### RMCS 依赖

- `rmcs_executor`
- `rmcs_msgs`
- `point_lio`
- `rmcs_local_map`
- `livox_ros_driver2`（在线模式需要）

### C++ 构建依赖

- `Eigen3`
- `yaml-cpp`
- `PCL`
- `pluginlib`

## 构建

在 RMCS 开发环境（zsh）中：

```bash
build-rmcs --packages-select point_lio rmcs_local_map rmcs-navigation
```

只构建本包：

```bash
build-rmcs --packages-select rmcs-navigation
```

清理工作区产物：

```bash
clean-rmcs
```

## 使用

### 1) 在线导航（实机）

根据配置名称启动（`rmul` / `rmuc`）：

```bash
ros2 launch rmcs-navigation online.launch.py config_name:=rmul
```

行为：

- 启动全局地图 `map_server`（`/map`）。
- 启动 `livox_ros_driver2` 与 `point_lio`。
- 延时启动 Nav2 与 `goal_topic_bridge.py`。

### 2) 自定义模式启动

```bash
ros2 launch rmcs-navigation custom.launch.py mode:=online
```

可选模式：

- `mode:=online`：实机链路（雷达驱动 + point_lio + Nav2）。
- `mode:=bag`：回放链路（播放 rosbag，默认使用 `/clock`）。
- `mode:=static`：静态本地地图 mock（不启动雷达与 point_lio）。

常用参数：

- `bag_path:=/path/to/your.bag`
- `bag_use_clock:=true|false`
- `local_map_topic:=/local_map`
- `global_map_topic:=/map`

默认参数在 `config/custom.yaml`。

### 3) 仅启动 Nav2（可独立调参）

```bash
ros2 launch rmcs-navigation nav2.launch.py
```

默认读取 `config/nav2.yaml`，并可通过 launch 参数覆盖局部/全局地图 topic。

### 4) waypoint 巡航

```bash
ros2 launch rmcs-navigation follow_waypoints.launch.py
```

默认读取 `config/follow_waypoints.yaml`，可覆盖：

- `follow_waypoints_file`
- `odom_topic`（默认 `/aft_mapped_to_init`）
- `distance_tolerance`
- `yaw_tolerance`

### 5) 目标话题桥接

`goal_topic_bridge.py` 订阅：

- `/move_base_simple/goal`
- `/goal_pose`

并转发到 Nav2 action：

- `/navigate_to_pose`

适合直接用 RViz 的 2D Goal Tool 进行导航测试。

## 配置说明

### 决策配置（`config/rmul.yaml`、`config/rmuc.yaml`）

- `navigation.map_yaml`：全局地图 yaml 路径（相对本包 share 目录或绝对路径）。
- `decision.health_limit` / `health_ready`：回家与巡航切换阈值。
- `decision.bullet_limit` / `bullet_ready`：弹量阈值。
- `decision.home`：补给点。
- `decision.cruise_methods`：巡航点集（如 `aggressive`、`occupation`）。

### 运行模式配置（`config/custom.yaml`）

- `navigation.map_yaml`：全局地图。
- `navigation.local_map_yaml`：`static` 模式下的本地地图 mock。
- `navigation.local_map_mock_topic`：mock 地图发布话题。
- `bag.path` / `bag.use_clock`：bag 回放默认配置。

## 调试与验证

推荐按以下顺序排查导航链路：

```bash
ros2 topic list | rg 'livox|local_map|map'
ros2 param get /laserMapping common.init_pose.translation
ros2 param get /laserMapping common.init_pose.orientation
ros2 run tf2_ros tf2_echo world camera_init
ros2 run tf2_ros tf2_echo aft_mapped base_link
```

重点检查：

- `rmcs_local_map` 与 `point_lio` 订阅同一套雷达 topic。
- 两者使用同一套雷达安装位姿标定参数。
- `world -> base_link` TF 树连通，且坐标系对齐合理。

常见问题：

- `custom.launch.py` 读取配置失败：确认 YAML 路径存在且编码为 UTF-8。
- TF 断树：先检查 `point_lio` 是否正常发布 `camera_init <-> aft_mapped`。

## 作为 rmcs_executor 组件使用

本包导出 pluginlib 组件（见 `plugins.xml`），由 `rmcs_executor` 在机器人配置中加载。组件核心输出接口：

- `/rmcs_navigation/chassis_velocity`
- `/rmcs_navigation/gimbal_velocity`
- `/rmcs_navigation/rotate_chassis`
- `/rmcs_navigation/detect_targets`
- `/rmcs_navigation/start_autoaim`

通常在组件参数中设置 `config_name`（例如 `rmul`）以选择对应决策配置文件。
