# RMCS 导航调参与排障复盘（全向模型，DWB/MPPI，远端联调 SOP）

> 本文是本轮对话全过程的技术复盘，覆盖：
> - 现象、根因、试错路径（成功/失败都记录）
> - RMCS 远端重启与验证 SOP（含踩坑）
> - 全向底盘（Omni）下 DWB/MPPI 的调参经验
> - 坐标系与地图融合的边界条件
> - 已落地提交与后续建议

---

## 1. 问题背景与核心诉求

本轮调试的原始问题有三类：

1. **接近目标点时龟速**：终点前长时间低速微调。
2. **局部最优卡死**：
   - 全局路径与障碍近似垂直时，机器人止步不前；
   - U 型/夹角障碍中会卡住，绕障意愿不足。
3. **行为链路一致性**：
   - 目标抢占不及时；
   - 部分改动导致导航启动失败、节点生命周期异常、重复实例冲突。

额外约束：

- 机器人是**全向舵轮模型**，不应引入“前进方向偏好”型调参。
- `local_map` 为极限响应链路，直接来自传感器处理，**frame 为 `base_link`**，不依赖 TF。
- 用户强调：局部最优核心是“寻路层问题”，不是简单防撞问题。

---

## 2. 本轮关键结论（先看这个）

### 2.1 全向模型调参原则

- Omni 底盘下，不应保留 `PreferForwardCritic` 这类偏置。
- `vx_std` 与 `vy_std` 应对称（各向同性），避免人为制造轴向偏好。

### 2.2 地图融合与坐标系结论

- `local_map(base_link)` 直接叠加到 `global_costmap(world)` 的 `StaticLayer`，会造成“全局图被局部窗口覆盖”（典型变成 `400x400`），进而出现：
  - `Goal outside bounds`
  - `Start occupied`
  - 远目标不可达/频繁 abort
- `global_costmap` 若使用 `VoxelLayer` 订阅点云，点云 frame 必须能稳定变换到 `global_frame`。
  - 例如点云 `frame_id=odom` 时，需要可用的 `world <-> odom` TF。

### 2.3 目前有效但仍不完美

- 通过 MPPI 各向同性调参，**垂直障碍场景已有改善**（可慢速绕行）。
- **U 型极端退化场景仍可能卡死**，说明仅启发式局部控制仍有上限。

---

## 3. 远端 RMCS 调试 SOP（已验证）

## 3.1 环境与命令约定

- 远端有效环境文件是：`~/env_setup.bash`（不是 `~/env_setup.sh`）。
- 常用远端执行模板：

```bash
ssh-remote command "bash -lc 'source ~/env_setup.bash && <your command>'"
```

### 3.2 重启 SOP（稳定版）

```bash
ssh-remote command "bash -lc 'source ~/env_setup.bash && service rmcs stop; sleep 2; service rmcs stop || true; service rmcs start'"
```

说明：重复 stop 是为处理守护进程偶发残留。

### 3.3 生命周期检查 SOP

```bash
ssh-remote command "bash -lc 'source ~/env_setup.bash && \
ros2 lifecycle get /bt_navigator && \
ros2 lifecycle get /planner_server && \
ros2 lifecycle get /controller_server'"
```

### 3.4 参数回读 SOP（确认“真生效”）

```bash
ssh-remote command "bash -lc 'source ~/env_setup.bash && ros2 param get /controller_server FollowPath.vx_std'"
ssh-remote command "bash -lc 'source ~/env_setup.bash && ros2 param get /global_costmap/global_costmap plugins'"
```

### 3.5 进程冲突排查 SOP

历史上多次出现“同名节点重复实例”导致行为异常。处理步骤：

```bash
ssh-remote command "bash -lc 'source ~/env_setup.bash && service rmcs stop; \
pkill -f "ros2 launch rmcs-navigation" || true; \
pkill -f nav2_bt_navigator || true; \
pkill -f nav2_planner || true; \
pkill -f nav2_controller || true; \
sleep 2; service rmcs start'"
```

### 3.6 同步流程踩坑

- `sync-remote` 是阻塞命令，且常用于持续同步模式；
- 若用户已经在管理同步，不应抢占执行；
- 协同模式优先 `wait-sync`。

---

## 4. 全过程调参与试错记录（按阶段）

## 4.1 阶段 A：先解决终点龟速（成功）

核心改动（DWB 时代）：

- `general_goal_checker.xy_goal_tolerance: 0.1 -> 0.2`
- `FollowPath.xy_goal_tolerance: 0.1 -> 0.2`
- `FollowPath.sim_time: 2.5 -> 1.2`

效果：

- 终点前“龟速微调”显著改善。

对应提交：`80a4649`。

---

## 4.2 阶段 B：DWB 面对局部最优（大量试错，收益有限）

尝试过的方向：

- 调 `min_speed_xy`、`PathDist`、`PathAlign`、`GoalDist`；
- 加 `BaseObstacle`，改 `ObstacleFootprint` 权重；
- 调 `sim_time`、采样密度（`vx_samples/vy_samples`）；
- 调 `inflation_radius` 与 `cost_scaling_factor`。

典型失败现象：

- 速度掉到约 0.3~0.5，绕障仍无明显改善；
- 避障变差，擦碰障碍；
- 对称场景仍止步不前。

结论：

- 仅靠 DWB 权重博弈难稳定跨越“垂直障碍 + U 型陷阱”。

---

## 4.3 阶段 C：切 MPPI（初期出现启动/数值问题）

早期切换问题：

- `Optimizer fail to compute path` 频发；
- `cmd_vel` 出现 NaN。

关键根因与修复：

1. **旋转维度全零导致数值奇异**
   - 错误配置：`wz_max=0` 且 `wz_std=0`。
   - 修复：给极小 epsilon（如 `0.001`）避免奇异，控制上近似 0。

2. **参数类型错误导致生命周期失败**
   - `FollowPath.CostCritic.near_collision_cost` 必须是整数，不可写成浮点。

3. **代价地图膨胀半径小于内接半径**
   - 会导致碰撞风险警告甚至规划质量下降。

4. **footprint 碰撞检查不生效/不一致**
   - `CostCritic.consider_footprint=true` 时，costmap 必须提供有效 footprint。

---

## 4.4 阶段 D：行为树与恢复链（有价值但不是主因）

做过的改造：

- 增加 `behavior_server`（BackUp/DriveOnHeading/Wait，无 Spin）；
- 调小 progress checker（4s）以更快触发恢复；
- 自定义 `motion.xml` 恢复链。

后续复盘结论：

- 本轮核心提升并非来自恢复链，而是“寻路输入是否正确反映障碍”。
- 对目标抢占不及时的回归，通过恢复 `GoalUpdated` 分支可修复。

---

## 4.5 阶段 E：地图融合探索（成败关键）

### 4.5.1 错误做法（会误导）

- 将 `/local_map`（`base_link`）当 `global_costmap` 的 `StaticLayer` 叠加。

后果：

- 全局代价图被局部窗口覆盖（从 2000x2000 退化为约 400x400）；
- 报错：`Goal outside bounds`、`Start occupied`；
- 虽然有时“偶然绕过去”，但几何位置是错的，不可用。

### 4.5.2 点云融合方案（理论可行，需 TF 条件）

- 使用 `global_costmap` 的 `VoxelLayer` 订阅点云（如 `/cloud_registered_undistort`）；
- 但该点云 frame 为 `odom`，全局为 `world`；
- 若 `world<->odom` TF 不可用/不稳定，障碍不会正确写入全局图。

---

## 5. 全向 Omni 的 MPPI 调参经验（本轮沉淀）

## 5.1 原则

1. 不用前进偏置（移除 `PreferForwardCritic`）。
2. `vx_std == vy_std`（各向同性）。
3. 通过 `temperature / batch_size / time_steps` 调探索，不引入方向偏见。
4. `CostCritic` 以 footprint 为准，保证安全边界一致。

## 5.2 已验证有效的方向（当前 main）

- `vx_std=vy_std=0.55`
- `temperature=0.34`
- `time_steps=50`
- `batch_size=1400`
- `regenerate_noises=true`
- `retry_attempt_limit=6`
- critics: `Constraint + Cost + Goal + PathAlign + PathFollow`

效果：

- 垂直障碍场景有改善（可慢速绕行）。
- U 型极端退化仍可能卡住（启发式局部最优上限）。

---

## 6. footprint 与几何一致性经验

用户给定真实底盘：**正方形，斜边（对角线）0.7**。

换算：

- 半边长 = `0.7 / (2 * sqrt(2)) ≈ 0.2475`

配置采用：

```yaml
footprint: "[[0.2475, 0.2475], [0.2475, -0.2475], [-0.2475, -0.2475], [-0.2475, 0.2475]]"
```

注意：

- `inflation_radius` 至少不小于内接半径附近，否则会触发警告并影响规划保守性。

---

## 7. 关键报错速查表

### 7.1 `Goal Coordinates ... outside bounds`

常见根因：

- 全局代价图尺寸被局部图覆盖（400x400），远目标超界。

### 7.2 `Start occupied`

常见根因：

- 局部错误融合导致起点落入占据区；
- 膨胀与 footprint 组合过保守。

### 7.3 `Optimizer fail to compute path`

常见根因：

- MPPI 配置奇异（如旋转维度全零）；
- 轨迹全不可行（代价或约束过严）。

### 7.4 `near_collision_cost type` 报错

- 参数类型必须是整数。

### 7.5 `consider_footprint ... no robot footprint provided`

- 开启 footprint 碰撞检查时，costmap 需显式 footprint。

---

## 8. 当前文件状态（本轮结束时）

### 8.1 关键配置文件

- `config/motion.yaml`
- `config/motion.xml`
- `launch/motion.launch.yaml`
- `config/sensor.yaml`
- `launch/sensor.launch.yaml`

### 8.2 当前 main 上已提交的导航相关提交

- `80a4649` `fix(nav): relax final approach to avoid slow crawl near goal`
- `b2708cf` `fix(nav): tighten MPPI collision costs and footprint safety`
- `f7089bf` `fix(nav): restore MPPI speed while keeping footprint safety`
- `4c6eb29` `tune(nav): apply isotropic MPPI settings for omni chassis`
- `f064078` `tune(nav): improve omni MPPI exploration for local minima`
- `f2e5b75` `chore(nav): align sensor launch defaults and map subscription QoS`

---

## 9. 本轮“可复制”验证命令模板

### 9.1 生命周期与关键参数

```bash
ssh-remote command "bash -lc 'source ~/env_setup.bash && \
ros2 lifecycle get /bt_navigator && \
ros2 lifecycle get /planner_server && \
ros2 lifecycle get /controller_server'"

ssh-remote command "bash -lc 'source ~/env_setup.bash && \
ros2 param get /controller_server FollowPath.vx_std && \
ros2 param get /controller_server FollowPath.vy_std && \
ros2 param get /controller_server FollowPath.critics'"
```

### 9.2 代价图尺寸与 frame

```bash
ssh-remote command "bash -lc 'source ~/env_setup.bash && ros2 topic echo /global_costmap/costmap --once'"
ssh-remote command "bash -lc 'source ~/env_setup.bash && ros2 topic echo /local_map --once'"
```

重点检查：

- `global_costmap/costmap.info.width/height` 是否仍为全局图尺寸；
- `local_map.header.frame_id` 是否为 `base_link`（当前设计如此）。

---

## 10. 后续建议（针对 U 型极端退化）

用户已明确方向：

- 单纯局部启发式仍可能卡在极端局部最优。
- 下一步更稳的是增加“局部脱困寻路”触发机制（例如 >1s 无进展触发一次短程额外寻路）。

建议实现路径（后续工作，不在本轮提交内）：

1. 保留当前 MPPI 各向同性配置作为基线。
2. 新增“无进展检测”触发器（速度接近 0 且未到达）。
3. 触发时调用一次短程脱困寻路（局部子目标/局部路径）。
4. 成功后回主链；失败再走清图/重发。

---

## 11. 本文档核心一句话总结

本轮最大经验是：

- **全向底盘先做 MPPI 各向同性，再谈绕障意愿；**
- **地图融合必须尊重 frame 语义（base_link 局部图不能直接当 world 全局图覆盖）；**
- **远端联调必须流程化（环境、重启、生命周期、参数回读、重复实例清理）**，否则很容易被“假生效”误导。
