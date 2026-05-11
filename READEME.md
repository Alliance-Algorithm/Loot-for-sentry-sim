<h1 align="center">
  $\color{#0072ff}{\small \textsf{Lua Sim For Sentry}}$
</h1>

<!-- Section 1 -->
## $\color{#0072ff}{\textsf{I. Integrating into Your Project}}$
> **1. Clone this repository with LFS (Important!)**
>
> **2. Import the project in Godot (Lua GDEExtension + LuaJIT Asset required!)**
> 
> **3. Add sim to rmcs-navigation/src.**
<br/>

<!-- Section 2 -->
## $\color{#02aab0}{\textsf{II. How to Use Loot}}$
> **1. Add one Loot config for each endpoint.**
>
> Loot finds FSMs by Lua source path, then builds the runtime graph from config.
> Add the config under:

```lua
-- rmcs-navigation/src/sim/Loot/lua/Loot/config/<endpoint-name>.lua

return {
  id = "<endpoint-name>",
  label = "My Endpoint",

  endpoint = {
    source = "endpoint/<endpoint-name>.lua",
    initial = "idle",
  },

  endpoints = {
    { id = "idle", label = "idle" },
    { id = "active", label = "active" },
  },

  endpoint_edges = {
    { from = "root", to = "idle", label = "boot" },
    { from = "idle", to = "active", label = "start" },
  },

  intents = {
    {
      id = "new_intent",
      label = "NewIntent",
      endpoint = "active",
      edge_label = "run",
      source = "intent/new-intent.lua",
      phases = {
        { id = "phase_a", label = "phase A" },
      },
    },
  },

  fsm_declared_edges = {
    {
      source = "intent/new-intent.lua",
      edges = {
        { from = "phase_a", to = "done", label = "done" },
        { from = "phase_a", to = "failed", label = "failed" },
      },
    },
  },
}
```
**2. Add new intents and tasks normally.**
> optional `fsm_declared_edges` to the endpoint config. Loot will observe its FSM
> passively through `util.fsm`.

<!-- Section 3 -->
## $\color{#6a11cb}{\textsf{III. Running the Simulation}}$
> **1. Launch the sidecar in Lua.**
```bash
build/rmcs-navigation/rmcs-navigation-sim-sidecar --endpoint competition-test # your endpoint name
```
> **2. Press F5 (Run) to start Godot project.**
<br/>

# <p align="center">$\Huge {\textsf{Made for RoboMaster Sentry Simulation}}$</p>
