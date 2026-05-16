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
		{ id = "advance", label = "advance" },
		{ id = "combat", label = "combat" },
		{ id = "escape", label = "escape" },
	},

	endpoint_edges = {
		{ from = "root", to = "idle", label = "boot" },
		{ from = "idle", to = "advance", label = "stage started" },
		{ from = "advance", to = "combat", label = "route ready" },
		{ from = "advance", to = "escape", label = "need recover" },
		{ from = "advance", to = "escape", label = "route failed" },
		{ from = "combat", to = "escape", label = "need recover" },
		{ from = "combat", to = "escape", label = "combat failed" },
		{ from = "escape", to = "combat", label = "recover ready" },
		{ from = "advance", to = "idle", label = "stage stopped" },
		{ from = "combat", to = "idle", label = "stage stopped" },
		{ from = "escape", to = "idle", label = "stage stopped" },
	},

	fsm_declared_edges = {
		{
			source = "endpoint/test.lua",
			edges = {
				{ from = "idle", to = "advance", label = "stage started" },
				{ from = "advance", to = "combat", label = "route ready" },
				{ from = "advance", to = "escape", label = "need recover" },
				{ from = "advance", to = "escape", label = "route failed" },
				{ from = "combat", to = "escape", label = "need recover" },
				{ from = "combat", to = "escape", label = "combat failed" },
				{ from = "escape", to = "combat", label = "recover ready" },
				{ from = "advance", to = "idle", label = "stage stopped" },
				{ from = "combat", to = "idle", label = "stage stopped" },
				{ from = "escape", to = "idle", label = "stage stopped" },
			},
		},
		{
			source = "intent/getout.lua",
			edges = {
				{ from = "navigate", to = "done", label = "route finished" },
				{ from = "navigate", to = "failed", label = "missing waypoint" },
			},
		},
		{
			source = "intent/cruise.lua",
			edges = {
				{ from = "patrol", to = "failed", label = "missing patrol point" },
			},
		},
		{
			source = "intent/chase.lua",
			edges = {},
		},
		{
			source = "intent/escape-to-home.lua",
			edges = {},
		},
	},

	intents = {
		{
			id = "idle",
			label = "IdleIntent",
			endpoint = "idle",
			edge_label = "hold",
			source = "intent/idle.lua",
			phases = {
				{ id = "hold", label = "hold" },
			},
		},
		{
			id = "getout",
			label = "GetoutIntent",
			endpoint = "advance",
			edge_label = "route",
			source = "intent/getout.lua",
			phases = {
				{ id = "navigate", label = "navigate waypoints" },
			},
		},
		{
			id = "cruise",
			label = "CruiseIntent",
			endpoint = "combat",
			edge_label = "default",
			source = "intent/cruise.lua",
			phases = {
				{ id = "patrol", label = "patrol highland" },
			},
		},
		{
			id = "chase",
			label = "ChaseIntent",
			endpoint = "combat",
			edge_label = "autoaim",
			source = "intent/chase.lua",
			phases = {
				{ id = "hold", label = "hold and aim" },
			},
		},
		{
			id = "escape_to_home",
			label = "EscapeIntent",
			endpoint = "escape",
			edge_label = "recover",
			source = "intent/escape-to-home.lua",
			phases = {
				{ id = "return", label = "return home" },
			},
		},
	},
}
