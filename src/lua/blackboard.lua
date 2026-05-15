local function PointPair(points)
	return {
		ours = { x = points[1][1], y = points[1][2] },
		them = { x = points[2][1], y = points[2][2] },
	}
end

local function create_default_blackboard()
	local last_our_dart_nmber_of_hits = nil

	local result = {
		-- Dynamic Information
		user = {
			health = 0,
			bullet = 0,
			chassis_power_limit = 0,

			chassis_power = 0,
			chassis_buffer_energy = 0,
			chassis_output_status = false,
			shooter_cooling = 0,
			shooter_heat_limit = 0,
			bullet_42mm = 0,
			fortress_17mm_bullet = 0,
			initial_speed = 0,
			shoot_timestamp = 0,

			x = 0,
			y = 0,
			yaw = 0,
			auto_aim_should_control = false,
		},
		game = {
			stage = "UNKNOWN",
			sync_timestamp = 0,

			outpost_health = 0,
			base_health = 0,

			hero_health = 0,
			infantry_1_health = 0,
			infantry_2_health = 0,
			engineer_health = 0,

			hero_position = { x = 0.0, y = 0.0 },
			infantry_1_position = { x = 0.0, y = 0.0 },
			infantry_2_position = { x = 0.0, y = 0.0 },
			engineer_position = { x = 0.0, y = 0.0 },

			remaining_time = 0,
			gold_coin = 0,
			exchangeable_ammunition_quantity = 0,

			our_dart_number_of_hits = 0,
			our_dart_nmber_of_hits = 0,
			fortress_occupied = false,
			big_energy_mechanism_activated = false,
			small_energy_mechanism_activated = false,
			robot_id = 0,
			can_confirm_free_revive = false,
			can_exchange_instant_revive = false,
			instant_revive_cost = 0,
			exchanged_bullet = 0,
			remote_bullet_exchange_count = 0,
			sentry_mode = 0,
			target_mode = 3,
			energy_mechanism_activatable = false,
		},
		map_command = {
			x = 0,
			y = 0,
			keyboard = 0,
			target_robot_id = 0,
			source = 0,
			sequence = 0,
		},
		play = {
			rswitch = "UNKNOWN",
			lswitch = "UNKNOWN",
		},
		meta = {
			timestamp = 0, -- 秒
			fsm_state = "unknown",
			fsm_return_stage = "before_fluctuant",
		},

		-- Static Information
		rule = {
			decision = "auxiliary",

			-- 状态类规则

			health_limit = 30,
			health_ready = 400,
			bullet_limit = 0,
			bullet_ready = 0,

			time_of_the_competition_red_line = 90,
			exchangeable_ammunition_quantity_red_line = 1000,
			gold_coin_red_line = 400,
			outpost_health_red_line = 1500,
			base_health_red_line = 2000,
			hero_health_ready_red_line = 50,
			infantry_1_health_ready_red_line = 50,
			infantry_2_health_ready_red_line = 50,
			engineer_health_ready_red_line = 50,

			-- 坐标类规则
			-- 定义顺序：ours = 0，them = 1

			-- 普通地形坐标
			fortress = PointPair { { 0, 0 }, { 0, 0 } },          -- 堡垒
			resupply_zone = PointPair { { 0, 0 }, { 0, 0 } },     -- 补给点
			road_zone_begin = PointPair { { 2.1, 0.5 }, { 0, 0 } }, -- 公路区
			road_zone_way_point_0 = PointPair { { 3.9, -0.7 }, { 0, 0 } },
			road_zone_way_point_1 = PointPair { { 1.3, -1.2 }, { 0, 0 } }, -- 公路区中途点1
			road_zone_way_point_2 = PointPair { { 1.3, -2.5 }, { 0, 0 } }, -- 公路区中途点2
			road_zone_final = PointPair { { 5.7, -2.6 }, { 0, 0 } },
			road_zone_final0 = PointPair { { 5.7, -2.6 }, { 0, 0 } },
			launch_ramp_begin = PointPair { { 0, 0 }, { 0, 0 } }, -- 飞坡
			launch_ramp_final = PointPair { { 0, 0 }, { 0, 0 } },
			outpost_resupply = PointPair { { 0, 0 }, { 0, 0 } }, -- 前哨站补给点
			assembly_zone = PointPair { { 0, 0 }, { 0, 0 } },

			-- 中心高地巡航点（非 PointPair，单点）
			center_highland_point1 = { x = 5.9, y = 0.6 },
			center_highland_point2 = { x = 5.8, y = 2.1 },

			-- 特殊跨越地形坐标
			road_tunnel_begin = PointPair { { 0, 0 }, { 0, 0 } },   -- 公路隧道
			road_tunnel_final = PointPair { { 0, 0 }, { 0, 0 } },
			one_step_begin = PointPair { { 0, 0 }, { 0, 0 } },      -- 一级台阶
			one_step_final = PointPair { { 0, 0 }, { 0, 0 } },
			two_step_begin = PointPair { { 0, 0 }, { 0, 0 } },      -- 二级台阶
			two_step_final = PointPair { { 0, 0 }, { 0, 0 } },
			common_elevated_ground_begin = PointPair { { 0, 0 }, { 0, 0 } }, -- 普通高地（飞坡起点那个高地）
			common_elevated_ground_final = PointPair { { 0, 0 }, { 0, 0 } },
			rough_terrain_begin = PointPair { { 0, 0 }, { 0, 0 } }, -- 起伏路段
			rough_terrain_final = PointPair { { 1.5, 0 }, { 0, 0 } },
		},
	}

	result.getter = {
		rswitch = function()
			return result.play.rswitch
		end,
		lswitch = function()
			return result.play.lswitch
		end,
	}

	result.condition = {
		low_health = function()
			return result.user.health < result.rule.health_limit
		end,
		low_bullet = function()
			return result.user.bullet < result.rule.bullet_limit
		end,
		health_ready = function()
			return result.user.health >= result.rule.health_ready
		end,
		bullet_ready = function()
			return result.user.bullet >= result.rule.bullet_ready
		end,

		--- @param target {x: number, y: number}
		--- @param tolerance? number|{x: number, y: number}
		near = function(target, tolerance)
			local x_diff = math.abs(target.x - result.user.x)
			local y_diff = math.abs(target.y - result.user.y)

			if type(tolerance) == "number" then
				return x_diff <= tolerance and y_diff <= tolerance
			end

			local limit = tolerance or { x = 0.05, y = 0.05 }
			return x_diff <= limit.x and y_diff <= limit.y
		end,
	}

	return result
end

local blackboard_singleton = create_default_blackboard()

local BlackboardDetails = {}
function BlackboardDetails.singleton()
	return blackboard_singleton
end

return BlackboardDetails
