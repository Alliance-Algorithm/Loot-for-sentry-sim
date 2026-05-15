return {
	id = "competition-test",
	label = "Competition Test Decision Graph",
	root = { id = "root", label = "competition" },

	endpoint = {
		source = "endpoint/competition-test.lua",
		initial = "idle",
	},

	endpoints = {
		{ id = "idle", label = "idle" },
		{ id = "active", label = "active" },
		{ id = "escape", label = "escape" },
		{ id = "recover", label = "recover" },
	},

	endpoint_edges = {
		{ from = "root", to = "idle", label = "boot" },
		{ from = "idle", to = "active", label = "stage started" },
		{ from = "active", to = "escape", label = "low resource" },
		{ from = "escape", to = "recover", label = "escape success" },
		{ from = "recover", to = "active", label = "resource ready" },
	},

	fsm_declared_edges = {
		{
			source = "endpoint/competition-test.lua",
			edges = {
				{ from = "idle", to = "active", label = "stage started" },
				{ from = "active", to = "escape", label = "low resource" },
				{ from = "escape", to = "recover", label = "escape success" },
				{ from = "recover", to = "active", label = "resource ready" },
			},
		},
		{
			source = "intent/competion/start-cruise.lua",
			edges = {
				{ from = "to_fluctuant_begin", to = "done", label = "already after fluctuant" },
				{ from = "to_fluctuant_begin", to = "crossing_fluctuant", label = "reach fluctuant" },
				{ from = "to_fluctuant_begin", to = "failed", label = "navigation failed" },
				{ from = "crossing_fluctuant", to = "done", label = "cross success" },
				{ from = "crossing_fluctuant", to = "failed", label = "cross failed" },
			},
		},
		{
			source = "intent/competion/keep-cruise.lua",
			edges = {
				{ from = "cruising", to = "failed", label = "job failed" },
			},
		},
		{
			source = "intent/competion/guard-home.lua",
			edges = {
				{ from = "descend_onestep", to = "occupy_fortress", label = "target fortress" },
				{ from = "descend_onestep", to = "cruise_in_front_of_base", label = "target base front" },
				{ from = "descend_onestep", to = "failed", label = "descend failed" },
				{ from = "occupy_fortress", to = "descend_onestep", label = "after fluctuant" },
				{ from = "occupy_fortress", to = "cruise_in_front_of_base", label = "target changed" },
				{ from = "occupy_fortress", to = "failed", label = "occupy failed" },
				{ from = "cruise_in_front_of_base", to = "descend_onestep", label = "after fluctuant" },
				{ from = "cruise_in_front_of_base", to = "occupy_fortress", label = "target changed" },
				{ from = "cruise_in_front_of_base", to = "failed", label = "cruise failed" },
			},
		},
		{
			source = "intent/competion/forward-press.lua",
			edges = {
				{ from = "one_step", to = "done", label = "timeout" },
				{ from = "one_step", to = "hold", label = "one step success" },
				{ from = "one_step", to = "failed", label = "one step failed" },
				{ from = "two_step", to = "done", label = "timeout or success" },
				{ from = "two_step", to = "failed", label = "two step failed" },
				{ from = "hold", to = "done", label = "timeout" },
			},
		},
		{
			source = "intent/competion/escape-to-home.lua",
			edges = {
				{ from = "descend_onestep", to = "to_resupply", label = "reach lower region" },
				{ from = "descend_onestep", to = "failed", label = "job failed" },
				{ from = "cross_fluctuant", to = "to_resupply", label = "reach road region" },
				{ from = "cross_fluctuant", to = "failed", label = "job failed" },
				{ from = "to_resupply", to = "done", label = "arrived" },
				{ from = "to_resupply", to = "failed", label = "navigation failed" },
			},
		},
	},

	intents = {
		{
			id = "start_cruise",
			label = "StartCruiseIntent",
			endpoint = "active",
			edge_label = "before fluctuant",
			source = "intent/competion/start-cruise.lua",
			phases = {
				{ id = "to_fluctuant_begin", label = "to fluctuant" },
				{ id = "crossing_fluctuant", label = "cross fluctuant" },
			},
		},
		{
			id = "keep_cruise",
			label = "KeepCruiseIntent",
			endpoint = "active",
			edge_label = "default cruise",
			source = "intent/competion/keep-cruise.lua",
			phases = {
				{ id = "cruising", label = "cruising" },
			},
		},
		{
			id = "guard_home",
			label = "GuardHomeIntent",
			endpoint = "active",
			edge_label = "guard condition",
			source = "intent/competion/guard-home.lua",
			phases = {
				{ id = "descend_onestep", label = "descend onestep" },
				{ id = "occupy_fortress", label = "occupy fortress" },
				{ id = "cruise_in_front_of_base", label = "base front" },
			},
		},
		{
			id = "forward_press",
			label = "ForwardPressIntent",
			endpoint = "active",
			edge_label = "press window",
			source = "intent/competion/forward-press.lua",
			phases = {
				{ id = "one_step", label = "one step" },
				{ id = "two_step", label = "two step" },
			},
		},
		{
			id = "escape",
			label = "EscapeToHomeIntent",
			endpoint = "escape",
			edge_label = "run intent",
			source = "intent/competion/escape-to-home.lua",
			phases = {
				{ id = "descend_onestep", label = "descend onestep" },
				{ id = "cross_fluctuant", label = "cross fluctuant" },
				{ id = "to_resupply", label = "to resupply" },
			},
		},
	},
}
