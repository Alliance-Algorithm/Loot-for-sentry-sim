# Lua-Godot 哨兵决策仿真

## 1. 简介

本项目为 **RoboMaster 哨兵机器人** 的自主导航决策系统提供一套离线仿真环境，基于以下两层实现：

- **C++ 仿真 Sidecar** (`sim_sidecar.cc`)：内嵌 Lua 5.4 运行时（通过 sol2 绑定），作为 TCP 服务器承接 Godot 客户端与 Lua 决策脚本之间的双向状态同步与遥控指令转发。
- **Godot 4.6 3D 战场模拟器** (`godot-mock/`)：使用 Jolt Physics 引擎，提供 RMUC 场地模型、NavMesh 导航网格、敌我双机器人（带装甲板受击判定、子弹弹道、云台自瞄/扫描）、补给区、调试 UI 面板，通过 TCP 连接到 C++ Sidecar。

整体架构：**Godot 模拟器 ← TCP → C++ Sidecar (Lua VM) → Lua 决策脚本 (`train-decision.lua`)**。

Lua 端复用了 `rmcs-navigation` 实车导航框架的核心组件（FSM 状态机、协程调度器、blackboard 状态共享、Intent/Task 任务分解），在纯仿真环境下验证哨兵的自主巡航、避险回血、地形通过等决策逻辑。

---

## 2. 环境依赖

### 2.1 编译 C++ Sidecar

| 依赖 | 版本/来源 | 说明 |
|------|----------|------|
| Lua | 5.4 | Lua 运行时 |
| sol2 | v3.5.0 (CMake FetchContent) | C++ Lua 绑定库 |
| yaml-cpp | 系统包 | YAML 配置解析 |
| CMake | 3.28+ | 构建系统 |
| C++ 编译器 | GCC 13+ / Clang 17+ | C++23 标准 |
| ROS 2 | jazzy | 用于构建 C++ Sidecar |

### 2.2 运行 Godot 项目

| 依赖 | 版本 | 说明 |
|------|------|------|
| Godot Engine | 4.6+ | 编辑器或运行时 |
| Jolt Physics | 内置于 Godot 项目 | 物理引擎 |

### 2.3 安装

编译 C++ Sidecar：

```bash
# 进入 rmcs-navigation 目录
cd rmcs_ws/src/rmcs-navigation-deps/rmcs-navigation

colcon build --packages-select rmcs-navigation
source /opt/ros/jazzy/setup.zsh

source install/setup.zsh
```

Godot 编辑器：

- 从 [Godot 官网](https://godotengine.org/) 下载 Godot 4.6+ 版本
- 用 Godot 编辑器打开 `godot-mock/project.godot`

---

## 3. Quick Start

### 3.1 启动 Lua Sidecar

```bash
./install/lib/rmcs-navigation/rmcs-navigation-sim-sidecar \
    --host 0.0.0.0 \
    --port 34567 \
    --endpoint train-decision
```

### 3.2 启动 Godot 模拟器

1. 用 Godot 编辑器打开 `godot-mock/project.godot`
2. 点击 **Run** (F5) 启动 `battlefiled.tscn` 主场景
3. Godot 将自动连接到 `127.0.0.1:34567` 的 C++ Sidecar
4. 连接成功后，左上角会出现 `Lua Sim v1` 调试面板

### 3.3 运行仿真

1. 点击 Godot 调试面板，按回车键，仿真程序运行，Lua和godot双段信息共享
2. Lua 端将进入 `idle → start_cruise → keep_cruise` FSM 状态机
3. AI 机器人（灰色）会自动沿 NavMesh 导航到目标点
4. 敌方机器人（红色）可用 WASD 操控，J 键射击，空格跳跃

### 3.4 仿真控制

- **手动操控敌方**：WASD 移动，J 射击，空格跳跃，Tab 切换视角
- **调试面板**：查看 blackboard 所有字段，实时编辑 HP/Bullet/Stage/Switch
- **补给区**：AI 进入补给区后自动回血/回弹（超控 Lua 端 blackboard）
- **云台模式**：Lua 可通过 `sim.gimbal_dominator` 指令切换 `scan` (扫描) / `auto` (自动瞄准) / `manual` (手动)

---

## 4. 现有功能

### 4.1 Lua 决策仿真

模拟实车部署的完整决策流水线：

| 模块 | 文件 | 功能 |
|------|------|------|
| **FSM 状态机** | `endpoint/train-decision.lua` | 五状态流转：idle → start_cruise → keep_cruise → escape → recover |
| **开始巡航** | `intent/start-cruise-train.lua` | 调用 `task/crossing-road-zone-train.lua`，从当前位置→公路区起点→公路区终点 |
| **持续巡航** | `intent/keep-cruise.lua` | 调用 `task/cruise-in-central-highlands.lua`，在中央高地两点间按固定周期往返导航 |
| **避险回家** | `intent/escape-to-home.lua` | 血量/弹药不足时自动导航回补给区，支持导航队列回溯（判断是否需要先下台阶） |
| **协程调度器** | `util/scheduler.lua` | 基于协程的任务编排：`append_task` / `yield` / `sleep` / `wait_until` |
| **Blackboard 同步** | `blackboard_sync.lua` | 6 个分节（user/game/play/meta/rule/result）的深拷贝快照与递归合并 |
| **导航任务** | `task/navigate-to-point.lua` | 单点导航，支持容差/超时参数 |
| **条件判断** | `blackboard.lua` | 暴露 `condition.low_health()`、`condition.low_bullet()`、`condition.near()` 等 |
| **动作层** | `action.lua` | `navigate()`、`update_chassis_vel()`、`switch_topic_forward()` 等运行时 API |

### 4.2 FSM 状态流转

```text
idle ──(收到 start 命令 & 游戏已开始)──→ start_cruise
start_cruise ──(任务完成)──→ keep_cruise
start_cruise ──(血/弹不足)──→ escape
keep_cruise ──(血/弹不足)──→ escape
escape ──(抵达补给点)──→ recover
recover ──(血量 & 弹药充足)──→ start_cruise
```

### 4.3 TCP 协议

| 方向 | 消息类型 | 说明 |
|------|---------|------|
| Godot → C++ | `sim.hello` | 握手 (protocol=1, mode=lua_sim_v1) |
| Godot → C++ | `sim.input` | 周期性上报机器人位姿 (x, y, yaw) 和资源 (health, bullet) |
| C++ → Godot | `sim.blackboard` | 全量同步 blackboard（带 `bb_rev` 版本号去重） |
| C++ → Godot | `sim.decision_state` | 决策状态快照 |
| C++ → Godot | `sim.nav_target` | 导航目标点更新 |
| C++ → Godot | `sim.chassis_mode` | 底盘模式 (idle/spin) |
| C++ → Godot | `sim.gimbal_dominator` | 云台控制源 (manual/scan/auto) |
| C++ → Godot | `sim.gimbal_direction` | 云台手动朝向 |
| C++ → Godot | `sim.chassis_vel` | 底盘速度超控 |
| Godot → C++ | `sim.override_mode` | 超控模式开关 |
| Godot → C++ | `sim.override_patch` | 超控补丁（手动修改 blackboard 值） |
| Godot → C++ | `sim.command` | 控制命令 (start_decision) |
| C++ → Godot | `sim.log` | Lua 日志透传 |

---

## 5. TODO List

- [ ] **高地/起伏路段物理**：上一级台阶（`go-down-onestep.lua` 等 task 已编写但未在 Godot 中完整体现），起伏路段未搭建
- [ ] **死亡/复活可视化**：AI 机器人死亡后 hide + 复活时 respawn，当前仅停止移动，无视觉特效
- [ ] **灵活射击**：当前由人工操控的 Enemy无法旋转视角功能，Lua自主控制机器人发射机构无法灵活瞄准
