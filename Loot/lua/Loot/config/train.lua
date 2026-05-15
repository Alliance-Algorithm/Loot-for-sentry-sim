return {
	id = "train",
	label = "Train Decision Graph",
	root = { id = "root", label = "train" },

	endpoint = {
		source = "endpoint/train.lua",
		initial = "idle",
	},

	endpoints = {
		{ id = "idle", label = "idle" },
		{ id = "getout", label = "getout" },
		{ id = "cruise", label = "cruise" },
		{ id = "chase", label = "chase" },
		{ id = "escape_to_home", label = "escape" },
	},

	endpoint_edges = {
		{ from = "root", to = "idle", label = "boot" },
		{ from = "idle", to = "getout", label = "order start" },
		{ from = "getout", to = "cruise", label = "out done" },
		{ from = "cruise", to = "chase", label = "auto aim" },
		{ from = "chase", to = "cruise", label = "target lost" },
		{ from = "cruise", to = "escape_to_home", label = "recover" },
		{ from = "chase", to = "escape_to_home", label = "recover" },
		{ from = "escape_to_home", to = "cruise", label = "ready" },
	},

	fsm_declared_edges = {
		{
			source = "endpoint/train.lua",
			edges = {
				{ from = "idle", to = "getout", label = "order start" },
				{ from = "idle", to = "cruise", label = "ready" },
				{ from = "getout", to = "cruise", label = "out done" },
				{ from = "cruise", to = "chase", label = "auto aim" },
				{ from = "chase", to = "cruise", label = "target lost" },
				{ from = "cruise", to = "escape_to_home", label = "recover" },
				{ from = "chase", to = "escape_to_home", label = "recover" },
				{ from = "escape_to_home", to = "cruise", label = "ready" },
			},
		},
	},

	intents = {
		{
			id = "getout",
			label = "GetoutIntent",
			endpoint = "getout",
			edge_label = "path",
			source = "intent/getout.lua",
			phases = {
				{ id = "navigate", label = "navigate waypoints" },
			},
		},
		{
			id = "cruise",
			label = "CruiseIntent",
			endpoint = "cruise",
			edge_label = "patrol",
			source = "intent/cruise.lua",
			phases = {
				{ id = "patrol", label = "patrol highland" },
			},
		},
		{
			id = "chase",
			label = "ChaseIntent",
			endpoint = "chase",
			edge_label = "lock target",
			source = "intent/chase.lua",
			phases = {
				{ id = "hold", label = "hold and aim" },
			},
		},
		{
			id = "escape_to_home",
			label = "EscapeToHomeIntent",
			endpoint = "escape_to_home",
			edge_label = "recover",
			source = "intent/escape-to-home.lua",
			phases = {
				{ id = "return", label = "return home" },
			},
		},
	},
}
