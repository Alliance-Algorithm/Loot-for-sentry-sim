return {
	id = "test",
	label = "Test Decision Graph",
	root = { id = "root", label = "test" },

	endpoint = {
		source = "endpoint/test.lua",
		initial = "idle",
	},

	endpoints = {
		{ id = "idle", label = "idle" },
		{ id = "cross_road_zone", label = "cross road" },
		{ id = "cross_rough_terrain", label = "cross rough" },
		{ id = "climb_to_highland", label = "to highland" },
		{ id = "patrol_highland", label = "patrol" },
		{ id = "return_by_one_step", label = "step down" },
		{ id = "resupply", label = "resupply" },
		{ id = "guard_fortress", label = "guard home" },
	},

	endpoint_edges = {
		{ from = "root", to = "idle", label = "boot" },
		{ from = "idle", to = "cross_road_zone", label = "stage started" },
		{ from = "cross_road_zone", to = "cross_rough_terrain", label = "road done" },
		{ from = "cross_rough_terrain", to = "climb_to_highland", label = "rough done" },
		{ from = "climb_to_highland", to = "patrol_highland", label = "arrive highland" },
		{ from = "patrol_highland", to = "return_by_one_step", label = "leave highland" },
		{ from = "return_by_one_step", to = "resupply", label = "need supply" },
		{ from = "return_by_one_step", to = "guard_fortress", label = "guard home" },
		{ from = "resupply", to = "climb_to_highland", label = "ready" },
		{ from = "guard_fortress", to = "climb_to_highland", label = "base safe" },
		{ from = "guard_fortress", to = "resupply", label = "base safe but weak" },
	},

	fsm_declared_edges = {
		{
			source = "endpoint/test.lua",
			edges = {
				{ from = "idle", to = "cross_road_zone", label = "stage started" },
				{ from = "cross_road_zone", to = "cross_rough_terrain", label = "road done" },
				{ from = "cross_rough_terrain", to = "climb_to_highland", label = "rough done" },
				{ from = "climb_to_highland", to = "patrol_highland", label = "arrive highland" },
				{ from = "patrol_highland", to = "return_by_one_step", label = "leave highland" },
				{ from = "return_by_one_step", to = "resupply", label = "need supply" },
				{ from = "return_by_one_step", to = "guard_fortress", label = "guard home" },
				{ from = "resupply", to = "climb_to_highland", label = "ready" },
				{ from = "guard_fortress", to = "climb_to_highland", label = "base safe" },
				{ from = "guard_fortress", to = "resupply", label = "base safe but weak" },
			},
		},
	},
}
