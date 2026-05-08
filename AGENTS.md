# AGENTS.md

## Mission

- 本 skill 用于指导 RMCS 导航相关开发与排障（ROS2 工作区位于 `rmcs_ws`），目标是在**最小改动**前提下快速定位问题并稳定交付可运行结果。
- 面向导航链路（如定位、建图、传感器驱动与进程协同）提供可复现的调试步骤，避免残留进程、环境漂移和“本地可用/远端不可用”的不一致。
- 输出应包含可直接执行的命令与验证标准，默认优先保证系统安全性、正确性和可维护性。

## Global Rules

### 1) 项目通用构建方法

- 对于处在 `rmcs_ws` 下的标准 ROS pkg：

```zsh
# 在 zsh 中，所有环境均已配置完好
build-rmcs

# 如果只编译单个包
build-rmcs --packages-select xxxx
build-rmcs --packages-up-to xxxx

# 清空编译产物
clean-rmcs
```

- 对于 `tool/`、`test/` 这类项目内独立工程：

```zsh
cmake -B build
cmake --build build -j
```

### 2) 通用实现原则

- 实现新需求时，先反思并收敛抽象模型，不要直接在现有实现上堆条件分支、特判、补丁式接口和临时状态。
- 核心层只保留稳定且最小的职责；具体 feature 应尽量通过组合、封装和上层策略自然派生。
- 如果为了支持一个新需求而不得不持续修改核心运行时、扩展底层协议、增加跨层语义耦合，说明模型边界大概率已经错了，应先重构抽象，再实现需求。
- 不要为了短期可用，把一次性需求沉淀为长期复杂度；宁可先把模型做对，也不要继续在屎山上叠屎山。

### 3) C++ 语言风格

- 构造和声明变量

```
# 使用大括号构造和类型后置
auto var = T { };
```

## Debugging SOP

### 1) 导航相关调试方法

- 使用 `tmux` 管理导航进程；这些进程容易遗留，或因死锁变为僵尸进程。

### 2) 远端调试与重启 SOP（`ssh-remote command`）

#### A. 统一环境加载

- 所有远端 ROS 指令都先 `source` 环境，避免参数/节点不可见。
- 本仓库环境文件只有：`~/env_setup.bash` 与 `~/env_setup.zsh`（无 `~/env_setup.sh`）。
- 统一使用 `bash -lc` 执行远端命令：

```zsh
ssh-remote command "bash -lc 'source ~/env_setup.bash && ros2 node list'"
```

#### B. 标准重启流程（避免残留）

```zsh
wait-sync
ssh-remote command "bash -lc '
  source ~/env_setup.bash
  service rmcs stop
  sleep 2
  service rmcs stop || true
  service rmcs start
'"
```

- 重启后立即检查关键节点是否单实例在线：

```zsh
ssh-remote command "bash -lc '
  source ~/env_setup.bash
  ros2 node list | rg "/controller_server|/planner_server|/bt_navigator"
'"
```

#### C. `tmux` 日志查看 SOP

- 列出会话：`ssh-remote command "bash -lc 'tmux list-sessions'"`
- 在线查看：`ssh-remote command "bash -lc 'tmux attach -t navigation'"`
- 非交互抓取最近日志：

```zsh
ssh-remote command "bash -lc 'tmux capture-pane -t navigation -p -S -120'"
```

#### D. 清理重复实例（重要）

- 出现同名节点重复、控制异常或“看起来死掉”时，先清理残留再启动：

```zsh
ssh-remote command "bash -lc '
  source ~/env_setup.bash
  service rmcs stop
  tmux kill-session -t navigation 2>/dev/null || true
  pkill -f "ros2 launch rmcs-navigation" || true
  sleep 2
  service rmcs start
'"
```

### 3) 导航调参与验证 SOP

#### A. 单次调参闭环（必须）

1. 仅修改 `rmcs-navigation/config/motion.yaml`。
2. `wait-sync` 同步到远端。
3. 按“标准重启流程”重启。
4. 用 `ros2 param get` 回读关键参数，确认已加载。
5. 复现实车场景验证，不并行改多组参数。

#### B. 最小验证清单

- 生命周期：

```zsh
ssh-remote command "bash -lc '
  source ~/env_setup.bash
  ros2 lifecycle get /planner_server
  ros2 lifecycle get /controller_server
  ros2 lifecycle get /bt_navigator
'"
```

- 控制输出非 NaN：

```zsh
ssh-remote command "bash -lc '
  source ~/env_setup.bash
  ros2 topic echo /cmd_vel --once
'"
```

- 关键参数已加载（示例）：

```zsh
ssh-remote command "bash -lc '
  source ~/env_setup.bash
  ros2 param get /controller_server FollowPath.plugin
  ros2 param get /controller_server FollowPath.CostCritic.consider_footprint
  ros2 param get /local_costmap/local_costmap inflation_layer.inflation_radius
'"
```

#### C. 常见致命错误速查

- `parameter ... has invalid type`：严格按插件参数类型填写（例如 `near_collision_cost` 必须是整数，不能写浮点）。
- `inflation radius ... smaller than inscribed radius`：`inflation_radius` 必须不小于 footprint 内接半径，否则碰撞风险警告且规划质量下降。
- `Action server is inactive`：通常是 lifecycle bringup 失败，先看 `controller_server` 配置错误。
- `Optimizer fail to compute path`：优先检查代价地图、footprint、参数是否加载正确，再做权重调参。常见根因是 MPPI 旋转维度全零导致数值奇异（见下文 5.1.D）。
- `Goal Coordinates ... outside bounds`：全局代价图尺寸被意外覆盖（如错误融合局部图导致 2000x2000 退化为 400x400），远目标超界。详见下文 5.2。
- `Start occupied`：局部图错误融合导致起点落入占据区，或膨胀半径+footprint 组合过保守。
- `consider_footprint ... no robot footprint provided`：`CostCritic.consider_footprint=true` 时，costmap 必须显式配置 footprint。

### 4) 雷达适配 SOP（topic + 变换）

- 先确认系统实际发布的雷达话题（常见如 `/livox/lidar_192_168_100_120` 与 `/livox/imu_192_168_100_120`），不要假设是 `/livox/lidar`。

#### A. 话题适配（必须一致）

- `rmcs_local_map`：修改 `rmcs_ws/src/skills/rmcs_local_map/config/local_map.yaml`
  - `lidar.lid_topic`
  - `lidar.imu_topic`
- `point_lio`：修改 `rmcs_ws/src/skills/point_lio/config/mid360.yaml`
  - `common.lid_topic`
  - `common.imu_topic`
- 原则：`rmcs_local_map` 与 `point_lio` 必须订阅同一套雷达 topic（同一 IP 后缀）。

#### B. 雷达到底盘装配位姿适配

- `rmcs_local_map`：写入 `rmcs_ws/src/skills/rmcs_local_map/config/local_map.yaml`
  - `lidar.lidar_translation: [x, y, z]`
  - `lidar.lidar_orientation: [yaw, pitch, roll]`（单位：度）
- `point_lio`：写入 `rmcs_ws/src/skills/point_lio/config/mid360.yaml`
  - `common.init_pose.translation: [x, y, z]`
  - `common.init_pose.orientation: [yaw, pitch, roll]`（单位：度，表示 `base_link -> lidar_link`）
- 原则：`rmcs_local_map` 与 `point_lio` 的雷达装配位姿必须来自同一套标定数据。

#### C. 验证步骤

- 构建（zsh）：

```zsh
build-rmcs --packages-select point_lio rmcs_local_map rmcs-navigation
```

- 启动后检查：
  - `ros2 topic list | rg 'livox|local_map|map'` 确认订阅/发布链路存在。
  - `ros2 param get /laserMapping common.init_pose.translation` 与 `common.init_pose.orientation` 确认参数加载正确。
  - `ros2 run tf2_ros tf2_echo world camera_init` 检查安装位姿是否为期望值。
  - `ros2 run tf2_ros tf2_echo aft_mapped base_link` 检查是否仅有 `Z` 平移。
  - 对齐检查以同一 frame 进行（优先 `base_link`），避免跨 frame 误判为“轴错位”。

#### E. 常见故障

- TF 断树：若 `world` 与 `base_link` 不连通，先确认 `point-lio` 是否正常发布 `odom → base_link`，再检查 `world → odom` 静态 TF 是否起效。

---

## 导航调参经验沉淀

> 以下内容来自多轮实车联调的复盘，覆盖全向底盘 MPPI 调参、地图融合踩坑、DWB 迁移教训以及已知局限。

### 5) 全向底盘（Omni）MPPI 调参

#### A. 核心原则

全向舵轮底盘没有"前进方向"的概念，调参时必须保持**各向同性**：

- **禁止** `PreferForwardCritic` 等带方向偏置的评价器。
- `vx_std` 和 `vy_std` 必须对称（当前值 `0.55`），不要人为制造某个轴的探索偏好。
- 通过 `temperature`、`batch_size`、`time_steps` 调节探索广度，而非引入方向偏见。
- `CostCritic` 以 footprint 碰撞检查为准（`consider_footprint: true`），保证安全边界与底盘实际形状一致。

#### B. 当前有效参数基线

```yaml
# motion.yaml — FollowPath 核心参数
motion_model: "Omni"
vx_std: 0.55          # == vy_std，各向同性
vy_std: 0.55
temperature: 0.34     # 越低越贪心，越高越探索
time_steps: 50
batch_size: 1400
regenerate_noises: true
retry_attempt_limit: 6
critics: [ConstraintCritic, CostCritic, GoalCritic, PathAlignCritic, PathFollowCritic]
```

效果：垂直障碍场景可慢速绕行。U 型极端退化场景仍可能卡住（这是启发式局部规划器的固有上限，见 5.5）。

#### C. Footprint 几何计算

底盘为正方形，斜边（对角线）0.7 m：

```
半边长 = 0.7 / (2 × √2) ≈ 0.2475
footprint: "[[0.2475, 0.2475], [0.2475, -0.2475], [-0.2475, -0.2475], [-0.2475, 0.2475]]"
```

`inflation_radius` 至少不小于 footprint 内接半径（~0.2475），否则会触发警告并降低规划保守性。

#### D. MPPI 启动阶段常见坑

1. **旋转维度全零 → NaN / Optimizer fail**
   - `wz_max=0` 且 `wz_std=0` 会导致数值奇异。
   - 正确做法：给极小 epsilon（如 `0.001`），控制上近似零旋转但不触发奇异。
2. **参数类型错误 → lifecycle 失败**
   - `near_collision_cost` 必须是整数，写成浮点会导致 controller_server 无法 activate。
3. **膨胀半径 < 内接半径 → 规划退化**
   - 碰撞检查精度下降，路径可能擦碰障碍。

### 6) 地图融合与坐标系

#### A. 绝对禁止的做法

不要将 `local_map`（frame=`base_link`）作为 `global_costmap` 的 `StaticLayer` 叠加。

后果：
- 全局代价图被局部窗口覆盖（从原始 2000x2000 退化为 ~400x400）。
- 出现 `Goal outside bounds`、`Start occupied`、远目标不可达等一系列问题。
- 偶尔"看起来绕过去了"只是几何巧合，位置是错的，不可用。

根本原因：`base_link` 是随车移动的局部坐标系，直接写入 `world` 坐标系的全局图会破坏全局图的空间语义。

#### B. 点云融合方案（需满足 TF 条件）

若需要将实时障碍物写入全局代价图：

- 使用 `global_costmap` 的 `VoxelLayer` 订阅点云。
- 点云 frame 必须能稳定变换到 `global_frame`（`world`）。
- 例如点云 `frame_id=odom` 时，需要 `world <-> odom` 的 TF 持续可用且稳定。

#### C. 代价图尺寸验证

调试时务必回读代价图尺寸，确认全局图未被污染：

```zsh
ssh-remote command "bash -lc 'source ~/env_setup.bash && ros2 topic echo /global_costmap/costmap --once'"
```

重点检查 `info.width/height` 是否仍为全局图的预期尺寸。

### 7) DWB → MPPI 迁移教训

在切换到 MPPI 之前，曾在 DWB 上做了大量尝试：

- 调过 `min_speed_xy`、`PathDist`、`PathAlign`、`GoalDist` 权重。
- 加过 `BaseObstacle`、`ObstacleFootprint`。
- 调过 `sim_time`、采样密度（`vx_samples/vy_samples`）。
- 调过 `inflation_radius`、`cost_scaling_factor`。

**结论：DWB 的权重博弈无法稳定解决"垂直障碍 + U 型陷阱"场景。** 速度掉到 0.3~0.5 时绕障仍无改善，对称场景直接卡死。MPPI 的随机采样机制天然比 DWB 的确定性网格采样更适合全向底盘的高维探索。

如果未来遇到类似"调了一堆 DWB 权重还是卡"的情况，优先考虑换控制器，而非继续在 DWB 上微调。

### 8) 行为树与恢复链

当前行为树（`motion.xml`）的核心设计：

- `NavigateRecovery` 顶层包裹，失败后进入全局恢复。
- 恢复策略只保留**清图**（`ClearEntireCostmap`），不使用 `Spin`（全向底盘无意义）。
- `GoalUpdated` 分支保证新目标可以随时打断恢复流程，避免目标抢占不及时。
- `progress_checker` 设为 4s，更快触发恢复而非长时间卡在原地。

经验：**恢复链不是解决局部最优的核心手段**，真正的改善来自"局部规划器是否正确感知障碍 + 采样空间是否足够"。恢复链只是兜底。

### 9) 已知局限与后续方向

**U 型极端退化**：当障碍形成 U 型包围时，MPPI 的有限步长采样可能无法找到绕出路径，机器人会卡住。这是所有基于采样的局部规划器的固有上限。

可行的改进方向：

1. 保留当前 MPPI 各向同性配置作为基线。
2. 新增**无进展检测**触发器（速度接近零且未到达目标）。
3. 触发时调用一次短程局部寻路（计算局部子目标或局部路径）引导脱困。
4. 脱困成功后回到正常导航链；失败则走清图重发。

此方案尚未实现，记录于此作为后续迭代参考。
