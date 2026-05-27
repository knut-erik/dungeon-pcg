# Dungeon-PCG: Technical Overview

## Abstract

This document provides a comprehensive technical description of the procedural dungeon generation system implemented in Godot 4. The system is designed to produce structurally valid, navigable, and strategically diverse 3D dungeons suitable for use as reinforcement learning training environments. It achieves this through a two-phase logical-to-physical generation pipeline, a modular room architecture built on Godot's resource system, a rule-based graph rewriting process for structural layout, and a directional A\* corridor routing algorithm with zone-aware collision avoidance. The system is intentionally built for extensibility: individual room types, corridor behaviors, and progression mechanics can each be modified or replaced without altering the generation pipeline.

---

## 1. System Goals and Requirements

### 1.1 Functional Requirements

The dungeon system must satisfy the following functional requirements:

| Requirement | Description |
|---|---|
| **Diverse generation** | Each dungeon run should produce structurally distinct layouts with varied room sizes, shapes, elevations, and spatial configurations. |
| **Solvability** | Every generated dungeon must be completable: the player must be able to reach the boss room, and any locked door must have a reachable key. |
| **Navigability** | All rooms must be physically connected by routed corridors; the AI agent must be able to walk from any room to any other room on the main path. |
| **Sufficient complexity** | Dungeons must contain enough structural variety (branching paths, elevation changes, locks and keys, loops) to serve as non-trivial training environments. |

### 1.2 Business / Application Requirements

The primary purpose of the system is to produce **training environments for reinforcement learning agents**. This imposes constraints beyond those of a standard game dungeon generator:

- Generated worlds must be **structurally reproducible given a seed**, so experiments can be validated and reproduced.
- Individual parameters (number of rooms, branching, elevation frequency, room sizes) must be **externally configurable** without modifying code.
- The system must produce environments that cover a **range of difficulty and structural complexity**, to avoid overfitting agents to a single dungeon topology.
- All interactive gameplay mechanics (keys, locks, doors, triggers) must expose **queryable metadata** so agent controllers can reason about them programmatically.

### 1.3 Technical Quality Requirements

The system must be:

- **Non-fragile**: generation must not silently produce broken dungeons (disconnected rooms, missing corridors, unreachable keys).
- **Extensible**: adding new room types, mechanics, or graph rules must not require changes to the core pipeline.
- **Validated**: errors should be caught and reported, not silently ignored.

---

## 2. Architecture Overview

The system is organised into three layers that together implement a **logical-to-physical generation pipeline**:

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1 – Logical Graph (GraphRewriter)                        │
│  Produces a directed graph of abstract rooms and connections    │
│  with semantic edge types and gameplay metadata.                │
└──────────────────────────────┬──────────────────────────────────┘
                               │  LogicalGraph
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 2 – Physical Placement (DungeonGenerator)                │
│  Instantiates room scenes, places them in 3D space with AABB    │
│  collision avoidance, and maps logical edges to gateway pairs.  │
└──────────────────────────────┬──────────────────────────────────┘
                               │  PhysicalConnection[]
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 3 – Corridor Routing (CorridorNetwork)                   │
│  Routes corridors between gateways using directional A*,        │
│  injects stair rooms for elevation changes, and generates       │
│  floor, ceiling, and wall geometry via CSG.                     │
└─────────────────────────────────────────────────────────────────┘
```

Each layer is independently testable and replaceable. The interfaces between layers are well-defined data structures (`LogicalGraph`, `PhysicalConnection[]`) rather than function calls, which means the graph rewriting strategy, the room placement strategy, and the corridor routing strategy can each evolve independently.

---

## 3. Layer 1: Logical Graph Generation

### 3.1 Graph Structure

The logical graph is a directed graph of `LogicalNode` and `LogicalEdge` objects defined in [DungeonGenerator/GraphRewriting/LogicalGraph.gd](DungeonGenerator/GraphRewriting/LogicalGraph.gd), [LogicalNode.gd](DungeonGenerator/GraphRewriting/LogicalNode.gd), and [LogicalEdge.gd](DungeonGenerator/GraphRewriting/LogicalEdge.gd).

**`LogicalNode`** carries:
- `id` — unique string identifier
- `assigned_tags` — semantic role labels (e.g., `"Entrance"`, `"Boss"`, `"Alive"`, `"Key"`, `"Locked"`)
- `blueprint` — a `RoomBlueprint` resource linking to a concrete room scene
- `custom_data` — arbitrary key-value metadata (e.g., `delta_y` for stair height, `key_id`, `lock_id`)

**`LogicalEdge`** carries:
- `edge_type` — one of `"main_path"`, `"locked"`, `"key_branch"`, `"boss_return"`, `"secret"`, or `"scene_transition"`
- `requirements` — dictionary of gameplay preconditions (e.g., `{ "key_id": "key_X" }`)
- `effects` — dictionary of gameplay consequences (e.g., `{ "grants_key_id": "key_X" }`)
- `custom_data` — component spawn descriptors for lock/key instantiation
- `routing_zone` — `"pre_lock"` or `"post_lock"`, used to prevent corridor sequence-breaking

This semantic richness in the graph is what allows subsequent layers to make informed decisions: the room placement layer uses tags to select blueprints; the corridor routing layer uses routing zones to enforce separation; the lock/key instantiation layer reads edge descriptors to spawn the correct components.

### 3.2 Graph Rewriting

Graph rewriting is implemented in [DungeonGenerator/GraphRewriting/GraphRewriter.gd](DungeonGenerator/GraphRewriting/GraphRewriter.gd). The generation process starts from a minimal two-node graph (Entrance → Boss) and expands it through sequential rule applications:

```
Start:    [Entrance] ──main_path──▶ [Boss]

After Rule_InsertChallenge × N:
          [Entrance] ──▶ [Challenge₁] ──▶ ... ──▶ [ChallengeN] ──▶ [Boss]

After Rule_LockAndKey:
          [Entrance] ──▶ ... ──▶ [KeyRoom]
                     └──▶ ... ──▶ [LockRoom] ──locked──▶ [Boss]

After Boss Return (optional):
          [Boss] ──boss_return──▶ [Entrance]  (false door blocks until boss defeated)
```

Each rule in [DungeonGenerator/GraphRewriting/](DungeonGenerator/GraphRewriting/) implements a `can_apply()` guard and an `apply()` transformer. `can_apply()` checks preconditions on the current graph before the rule fires, making rule application safe. Rules insert nodes using `LogicalGraph.insert_node_between()`, which atomically splices a new node into an existing edge, maintaining graph integrity.

**`Rule_InsertChallenge`** ([Rule_InsertChallenge.gd](DungeonGenerator/GraphRewriting/Rule_InsertChallenge.gd)) picks a random edge from the main path and inserts a new `"Alive"`-tagged room into it. The number of applications is controlled by the `num_challenges` export parameter.

**`Rule_LockAndKey`** ([Rule_LockAndKey.gd](DungeonGenerator/GraphRewriting/Rule_LockAndKey.gd)) finds the node with an outgoing edge to the Boss, inserts a `"Locked"` room before the Boss, and branches a `"Key"` room as a dead-end off the pre-boss node. It stamps unique `key_id` and `lock_id` strings onto the edge requirements and the component descriptors, establishing a data-driven link between the physical key pickup and the hinge door that it unlocks.

**`Rule_EnsureElevation`** ([Rule_EnsureElevation.gd](DungeonGenerator/GraphRewriting/Rule_EnsureElevation.gd)) annotates nodes with `delta_y` values, which the physical placement layer uses to determine when to inject stair rooms.

### 3.3 Diversity Guarantees from the Graph

The graph rewriting process directly supports the diversity requirement by:

1. **Controlled branching**: `num_challenges` is a configurable integer, so dungeon length and complexity are tunable at the editor level without code changes.
2. **Guaranteed structural variety**: Every dungeon always contains at minimum one lock, one key, one branching path, and an optional return loop. No two runs produce the same node sequence because challenge insertion picks random intermediate nodes.
3. **Semantic tag diversity**: Tags like `"Alive"`, `"Key"`, `"Locked"`, `"Boss"` are matched against blueprint `possible_tags` during room selection, so structurally different graph positions draw from different room pools.

---

## 4. Layer 2: Physical Room Placement

### 4.1 The RoomBaseObjects Architecture

The central abstraction enabling the plug-and-play workflow is the family of base classes in [DungeonGenerator/Rooms/RoomBaseObjects/](DungeonGenerator/Rooms/RoomBaseObjects/). Every room scene in the game must have a root node that extends `_BaseRoom`. This contract allows the generation pipeline to interact with any room type through a stable interface, regardless of how that room generates its internal geometry.

**`_BaseRoom`** ([DungeonGenerator/Rooms/RoomComponents/_BaseRoom.gd](DungeonGenerator/Rooms/RoomComponents/_BaseRoom.gd)) defines:

- `get_world_aabbs() -> Array[AABB]` — returns the room's collision footprint in world space, extracted from child `Area3D` nodes. This is consumed by the placement layer's overlap detection and the corridor routing layer's obstacle avoidance.
- `get_gateways() -> Array[Gateway]` — discovers all `Gateway` nodes in the scene tree.
- `claim_gateway_for_edge(edge, as_source) -> Gateway` — role-aware gateway allocation. Prefers gateways whose `role` property matches the edge's `preferred_from_gateway_role` or `preferred_to_gateway_role` field. Falls back to any available gateway.
- `setup_room(rng, logic_node)` — **async** method that subclasses override to configure their geometry. Receives the `RandomNumberGenerator` and the `LogicalNode` (including its `blueprint` and `custom_data`), so rooms can read their own parameters and any generation-time metadata.

**`Gateway`** ([DungeonGenerator/Rooms/RoomBaseObjects/Scenes/Gateway.gd](DungeonGenerator/Rooms/RoomBaseObjects/Scenes/Gateway.gd)) is a `Node3D` placed at each doorway in a room scene. Each gateway has:
- `gateway_id` — unique label within the room
- `role` — semantic slot name (e.g., `"entrance"`, `"exit"`, `"locked_exit"`, `"loop_return"`)
- `max_connections` — how many edges may share this gateway
- Boolean filters: `allows_lock`, `allows_secret`, `allows_loop`, `allows_scene_transition`
- `connected_edges` — tracks claimed edges to enforce connection limits

This means a room designer can define gateways with specific semantics. A room can have a `"locked_exit"` gateway that only accepts locked edges, ensuring the hinge door always appears at the correct opening and faces the correct direction.

### 4.2 The Resource System: RoomBlueprint and RoomParameter

The plug-and-play parameter system is built on two Godot `Resource` subclasses defined in [DungeonGenerator/Rooms/RoomComponents/](DungeonGenerator/Rooms/RoomComponents/).

**`RoomBlueprint`** ([RoomBlueprint.gd](DungeonGenerator/Rooms/RoomComponents/RoomBlueprint.gd)) is a data-only resource that describes one room type:

```gdscript
@export var room_scene: PackedScene          # The room prefab to instantiate
@export var possible_tags: Array[String]     # Roles this blueprint can fill
@export var width_param: RoomParameter       # Width distribution
@export var length_param: RoomParameter      # Length distribution
@export var enemy_density_param: RoomParameter
```

**`RoomParameter`** ([RoomParameter.gd](DungeonGenerator/Rooms/RoomComponents/RoomParameter.gd)) is a scalar distribution:

```gdscript
@export var min_value: float
@export var max_value: float
@export var probability_curve: Curve         # Optional bias curve
```

Sampling works as follows:

```gdscript
func sample(rng: RandomNumberGenerator) -> float:
    var t = rng.randf()
    var weight = probability_curve.sample(t) if probability_curve else t
    return lerp(min_value, max_value, weight)
```

The `Curve` resource acts as a probability density function. A designer can make a room that is usually mid-sized but occasionally very small or very large by shaping the curve accordingly, entirely in the Godot editor without touching code.

**Concrete parameter resources** are stored as `.tres` files in the room's own folder (e.g., [DungeonGenerator/Rooms/RoomLibrary/BaseRoom/](DungeonGenerator/Rooms/RoomLibrary/BaseRoom/)), keeping each room's configuration self-contained.

**Adding a new room type** requires only:
1. Create a `.tscn` scene with a root extending `_BaseRoom`
2. Implement `setup_room()` to configure geometry from `logic_node.blueprint`
3. Create a `RoomBlueprint.tres` resource pointing to the scene
4. Assign `RoomParameter.tres` resources for each dimension
5. Drag the blueprint into the `room_library` array in the `DungeonGenerator` inspector

No code changes to the generation pipeline are required.

### 4.3 Room Placement Algorithm

The `DungeonGenerator` ([DungeonGenerator/DungeonGenerator.gd](DungeonGenerator/DungeonGenerator.gd)) performs physical placement by BFS traversal of the logical graph. For each node:

1. The room scene is instantiated and `setup_room()` is awaited, allowing async geometry construction (important for CSG-based rooms).
2. A target Y elevation is computed. A 30% random chance applies a delta of ±4.0–8.0 units to create floor-level variation. Key-branch edges are forced to stay at the parent's Y because their corridors must junction with main-path corridors.
3. Preferred placement positions are tested in order: eight cardinal and diagonal directions at distances of 18, 24, 30, 36, 44, and 52 units from the parent room. The first non-overlapping position wins.
4. Overlap detection uses a **7-unit margin** around each room AABB. This margin ensures the corridor routing layer always has lane space between adjacent rooms.
5. If no preferred position succeeds, a radial fallback expands the search radius until placement succeeds.

This combination of directional preference and radial fallback ensures placement always succeeds while still tending to produce layouts where rooms are spread out in navigable patterns rather than piled up.

---

## 5. Layer 3: Corridor Routing

### 5.1 Multi-Phase Routing Strategy

The `CorridorNetwork` ([DungeonGenerator/Corridors/CorridorNetwork.gd](DungeonGenerator/Corridors/CorridorNetwork.gd)) runs in two phases:

**Phase 1** routes all main-path and locked-edge connections (i.e., connections that are not key-branches). Stair rooms are injected here for connections with a Y delta greater than 0.1 units.

**Phase 2** routes key-branch connections after all main-path corridors are committed. Each key-branch finds the nearest committed main-path corridor at its elevation and connects to it as a junction, ensuring the key room can always be reached from the main path.

This sequencing matters for correctness: if key-branch routing ran first, there would be no committed main-path corridors to junction into, and the key room would be isolated.

### 5.2 Directional A\* Search

Each corridor segment is routed by a 2D grid-based A\* search operating on a grid with `GRID_SCALE = 2.0` (one grid unit = 0.5 world units, giving sub-metre precision). The algorithm:

- **Constrains the first step** to exit in the gateway's outbound direction, ensuring corridors leave rooms perpendicularly.
- **Uses an approach-cell goal**: instead of routing to the destination gateway directly, the search targets the cell one step beyond the gateway. The final step is appended after the search completes. This guarantees corridors arrive orthogonally at the destination as well.
- **Checks rectangle validity** for each candidate edge, testing a 3-unit-wide corridor segment against room AABBs and committed corridor footprints.
- **Exempts a throat region** (6 steps from each gateway) from AABB collision checks, so the corridor can exit through the room's wall without false collision with the room's own bounding box.

Search bounds are controlled by `ASTAR_SEARCH_MARGIN_GRID = 80` (40 world units) and `ASTAR_MAX_ITERATIONS = 50000`, providing a generous but bounded search space.

### 5.3 Stair Injection

When a connection spans a height gap, the system attempts to insert a stair room between the two gateways. It tests a range of candidate positions (sampled from low gateway, high gateway, and midpoint, in four cardinal directions and three distance offsets) and validates each candidate with a tighter A\* search (`ASTAR_CANDIDATE_SEARCH_MARGIN_GRID = 28`). The first geometrically valid, non-overlapping candidate is committed.

This mechanism is why stair room types exist as first-class rooms in the library rather than as procedural geometry: each stair variant (`StairRoomStraight`, `StairRoomCavern`, spiral, L-shape) is its own `_BaseRoom` subclass. The delta_y recorded in the logical node's `custom_data` is passed into `setup_room()`, and each stair type scales its geometry accordingly:

```gdscript
# StairRoomStraight.gd
var delta_y = logic_node.custom_data.get("delta_y", 4.0)
var num_steps = abs(delta_y) / step_height   # steps auto-scale to bridge height gap
```

The procedural cave stair (`StairRoomCavern`) constructs a Bezier path of ten points across the height gap and builds a noisy tube mesh along it, producing organic-looking passages that vary structurally across runs.

### 5.4 Zone-Based Routing Separation

To prevent players (or agents) from bypassing the lock-and-key mechanic by finding a corridor shortcut from the pre-lock area to the boss room, corridors are labelled with a `routing_zone`:

- **`pre_lock`**: reachable from the entrance without any key
- **`post_lock`**: reachable only after collecting the key

The A\* validity check rejects any corridor segment that would overlap a committed corridor from a different zone at the same elevation. Gateway throats are pre-registered as zone-labelled rectangles, so even the approach to a locked gateway cannot be shared with a non-locked corridor.

This is a structural solvability guarantee: the routing layer enforces that no pre-lock corridor geometry connects spatially to post-lock corridor geometry, so there is no walkable shortcut past the lock room.

---

## 6. Lock-and-Key Progression System

### 6.1 Three-Layer Design

The lock-and-key mechanic spans all three generation layers, with each layer responsible for a different aspect:

| Layer | Responsibility |
|---|---|
| **GraphRewriting** (`Rule_LockAndKey`) | Creates the semantic structure: which room holds the key, which room has the door, what ID links them. |
| **DungeonGenerator** | Instantiates components from descriptors and calls `configure_from_descriptor()` to bind the `lock_id`. |
| **Runtime** (`LockComponent` hierarchy) | Handles player interaction and state propagation at runtime. |

This separation means the lock-and-key *gameplay behaviour* is entirely independent of the *structural placement* of the lock and key. A new lock type only needs to implement the `LockComponent` interface; no graph rewriting changes are needed.

### 6.2 Component Architecture (RoomBaseObjects)

The runtime components live in [DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/](DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/) and share a common base class hierarchy:

```
DungeonComponent
└── LockComponent          (manages lock_id, agent metadata, group membership)
    ├── LockActivator      (can emit lock activation events)
    │   ├── KeyPickup      (collect on touch → activate_lock())
    │   └── LockTriggerArea (proximity trigger → activate_lock())
    └── AnimatedMesh       (receives lock events → plays animation)
        ├── LockableHingeDoor (rotates open -95°)
        └── FalseDoorBlocker  (fades out and removes collision)
```

**`DungeonComponent`** ([DungeonComponent.gd](DungeonGenerator/Rooms/RoomBaseObjects/DungeonComponent.gd)) provides `bind_to_logic(node, edge)`, called by `DungeonGenerator` after instantiation. This gives every component a reference to its logical node and edge, exposing the full generation-time metadata at runtime.

**`LockUtil`** ([LockUtil.gd](DungeonGenerator/Rooms/RoomBaseObjects/LockAndKey/LockUtil.gd)) is a global event dispatcher:

```gdscript
static func emit_lock_activation(tree, lock_id, source, actor=null):
    tree.call_group("lock_targets", "receive_lock_activation", lock_id, source, actor)
```

Components that should respond to lock events join the `"lock_targets"` group. This tree-wide broadcast with a `lock_id` filter means any number of doors can be wired to the same key, or a single key can open multiple locks, without any explicit wiring between scene nodes.

### 6.3 Agent Metadata

Every `LockComponent` exposes `get_agent_metadata()`:

```gdscript
func get_agent_metadata() -> Dictionary:
    return {
        "component_id": component_id,
        "lock_id": String(lock_id),
        "agent_tag": agent_tag,          # e.g., "key", "door", "trigger"
        "logical_node_id": logical_node.id if logical_node else ""
    }
```

This allows the agent controller to query all interactive objects in the scene and reason about their semantic roles (key, door, trigger) and their structural position in the dungeon graph. This is a direct response to the business requirement that the training environment exposes queryable, machine-readable state.

---

## 7. Diversity, Solvability, and Complexity

### 7.1 Diversity

The system produces diverse dungeons through independent variation at multiple levels:

**Structural diversity** (from graph rewriting):
- Configurable `num_challenges` controls dungeon length and the number of intermediate rooms.
- The `create_loop` flag toggles the boss-return path, changing global topology from a DAG to a graph with a cycle.
- Challenge node insertion picks random edges, so no two runs produce the same room ordering.

**Spatial diversity** (from physical placement):
- Room dimensions are sampled from `RoomParameter` distributions on each run. A room with `width_param` set to a curved distribution over [3, 5] will vary between narrow corridors and wider chambers across runs.
- Elevation changes are applied stochastically (30% probability per non-key-branch edge, delta ±4–8 units), producing multi-floor dungeons with varying floor plans.
- Eight-directional placement with six distance steps means the physical layout depends on random direction selection and the specific AABBs of previously placed rooms.

**Geometric diversity** (from room types):
- `StairRoomCavern` builds a different noisy tube mesh on each run using a seeded Bezier path.
- `DefaultRoom` randomises which of its four walls holds each door, and offsets doors within each wall.
- The cave stair's procedural path is generated by adding random lateral offsets at each of 10 control points along the path.

**Parameter diversity** (from editor configuration):
- Because room libraries are `Array[RoomBlueprint]` on the `DungeonGenerator` node, entire room pools can be swapped between experiments by editing the inspector, producing qualitatively different dungeon styles from the same code.

### 7.2 Solvability

Solvability is guaranteed at the logical graph level by construction:

1. **Connectivity**: The graph starts connected (Entrance → Boss), and every rule insertion splices nodes into existing edges rather than adding disconnected nodes. The `insert_node_between()` method removes the old edge and creates two new edges, so the graph remains connected after every rule application.

2. **Key precedes lock**: `Rule_LockAndKey` enforces that the key-branch stems from the same part of the graph as the lock room, always before the boss on the main path. The key room is a dead-end branch off this pre-boss segment, so the key is structurally reachable before the locked door.

3. **Locked edge requirements**: The `locked` edge stores `requirements["key_id"]` and `requirements["lock_id"]`. The generator uses these to place the hinge door at exactly the locked edge's gateway and the key pickup at the key node. The data-driven link between pickup and door is established at graph construction time and cannot become inconsistent during physical instantiation.

4. **Zone separation**: As described in Section 5.4, the corridor routing layer enforces that no walkable path bypasses the lock. Solvability is not only structurally guaranteed in the graph; it is physically enforced in the geometry.

5. **Logical graph validation**: Before physical instantiation begins, `_validate_logical_graph()` in `DungeonGenerator` checks that every node has a blueprint, every edge has valid endpoints, and every locked edge has a `key_id`. Errors are pushed as engine errors and generation halts.

### 7.3 Navigability

Navigability is a physical-layer guarantee enforced by the corridor routing system:

- Every logical edge in the graph receives a `PhysicalConnection` with two assigned gateways. If gateway assignment fails, a warning is pushed.
- The A\* search for each connection has a large maximum iteration budget (`ASTAR_MAX_ITERATIONS = 50000`) and a fallback retry with relaxed directional constraints for tight placements.
- The 7-unit AABB margin around placed rooms ensures that corridor lanes exist between adjacent rooms; rooms are never placed so close together that routing between them is geometrically impossible.
- Stair injection for height-changing connections ensures that vertical transitions are always physically traversable by an agent.

### 7.4 Complexity

Structural complexity is guaranteed by the minimum content of every generated dungeon:

- At least `num_challenges` intermediate rooms on the main path (default: 3)
- Exactly one locked door requiring the key
- Exactly one key room as a dead-end branch
- Optionally, one boss-return loop that is initially blocked by a false door

This minimum ensures that the dungeon always contains branching, gating, and backtracking challenges. The configurable `num_challenges` parameter makes the upper bound on complexity also controllable, which is important for curriculum learning scenarios where training environments should scale from simple to complex.

---

## 8. Technical Robustness

### 8.1 Structural Correctness by Construction

The most fragility-prone pattern in procedural generation is creating structural invariants in code and then relying on runtime validation to catch violations. This system avoids that pattern by **encoding structural invariants into the data model itself**:

- `LogicalEdge.requirements` and `LogicalEdge.effects` are populated by the rule that creates the edge. There is no separate "wiring pass" where these could fall out of sync.
- `PhysicalConnection` stores both gateways, the logical edge they correspond to, and both `PhysicalAnchor` objects. Calling `validate_physical_assignments()` on it checks all four fields are non-null before routing begins.
- `RoomParameter.sample()` is the only code path that reads parameter values. There is no way to accidentally bypass the distribution curve.

### 8.2 Shared Resource Protection

A subtle but important source of bugs in Godot is that resources loaded from disk are shared by default. If two room instances modify the same `CollisionShape3D` resource, they both change. `DefaultRoom.setup_room()` explicitly duplicates the shape before modifying it:

```gdscript
col_shape.shape = col_shape.shape.duplicate()   # break shared resource reference
col_shape.shape.size = room_size
```

This pattern is applied wherever per-instance data would otherwise write back to a shared resource.

### 8.3 Gateway Role Enforcement

The `claim_gateway_for_edge()` method in `_BaseRoom` performs role-aware gateway allocation. If a room has a gateway with `role = "locked_exit"` and `allows_lock = true`, locked edges will prefer it. This prevents hinge doors from being placed at the wrong opening, which would produce a dungeon where the door blocks an unconstrained path rather than the locked one.

If no role-matched gateway is available, the method falls back to any available gateway rather than failing. This graceful degradation means generation does not break for room types that have not been annotated with roles, while role-annotated rooms benefit from semantic placement.

### 8.4 Corridor Zone Integrity

The routing zone system (Section 5.4) is implemented as a passive constraint in the A\* validity check, not as a post-generation audit. This means zone violations are structurally impossible, not merely unlikely. The `_is_edge_valid()` method rejects a corridor cell the moment it would cross a zone boundary, so the A\* search will route around the violation rather than accepting it and requiring a fixup pass.

### 8.5 AABB Collision Duplication Safety

All room AABB queries call `get_world_aabbs()`, which reads from the room's `Area3D` children at runtime. Because `setup_room()` resizes the collision shape before the AABB is read, the placement layer always works with the room's actual post-configuration footprint, not a stale pre-configuration footprint. This prevents the placement layer from placing rooms that appear non-overlapping but whose real geometry intersects.

### 8.6 Async Setup and Frame Synchronisation

CSG geometry in Godot 4 requires at least one process frame to compute its final mesh and collision bounds. `setup_room()` is therefore `async` and contains `await get_tree().process_frame` before gateway position computations. The `DungeonGenerator` awaits each room's setup before reading its AABB or gateway positions. This prevents race conditions where placement or routing decisions are made against stale geometry.

### 8.7 Debug Visualisation

[DungeonGenerator/DungeonDebugDraw.gd](DungeonGenerator/DungeonDebugDraw.gd) provides a runtime overlay that draws AABB wireframes, gateway markers and direction arrows, committed corridor footprints, and routing zone labels. This is significant for technical robustness: generation errors that would otherwise be silent (wrong gateway direction, misaligned corridor, unexpected room overlap) become visually obvious, shortening the debugging loop during development.

---

## 9. Room Library

The current room library is located at [DungeonGenerator/Rooms/RoomLibrary/](DungeonGenerator/Rooms/RoomLibrary/) and includes the following types:

| Room Type | Description | Key PCG Technique |
|---|---|---|
| **DefaultRoom** | Rectangular chamber with CSG boolean hollowing | Parametric width/length sampling, randomised door wall placement |
| **StairRoomStraight** | Diagonal ramp with stepped geometry | Delta-Y-adaptive step count |
| **StairRoomCavern** | Organic cave passage | Bezier path with random lateral offsets, tube mesh along path with noise |
| **StairRoomSpiral** | Helical staircase | Fixed geometry, height-adapted |
| **StairRoomL** | L-shaped stair landing | Fixed geometry |
| **StairRoomGreatRoom** | Large multi-level chamber | Fixed geometry |
| **StaticEntranceRoom** | Handcrafted starting area | Static scene |

Each room type is self-contained: its scene, its blueprint resource, and its parameter resources all live in the same subfolder. The generation pipeline interacts with all of them identically through the `_BaseRoom` interface.

Seven role-specific blueprints exist for the `DefaultRoom` type in [DungeonGenerator/Rooms/RoomLibrary/BaseRoom/Blueprints/](DungeonGenerator/Rooms/RoomLibrary/BaseRoom/Blueprints/), each with a different `possible_tags` assignment (e.g., one for `"Boss"` rooms, one for `"Key"` rooms, one for general `"Alive"` rooms). This allows the same room geometry to appear across roles while optionally having different size distributions per role.

---

## 10. Configuration and Extensibility Summary

### 10.1 External Configuration Points

All generation parameters are exposed without code changes:

| Parameter | Location | Effect |
|---|---|---|
| `num_challenges` | `DungeonGenerator` inspector | Number of intermediate rooms on main path |
| `create_loop` | `DungeonGenerator` inspector | Enable/disable boss-return path |
| `room_library` | `DungeonGenerator` inspector | Full pool of eligible room blueprints |
| `width_param`, `length_param` | `RoomBlueprint.tres` files | Per-room size distributions |
| `probability_curve` | `RoomParameter.tres` files | Shape of size distribution |
| `min_value`, `max_value` | `RoomParameter.tres` files | Hard bounds on room dimensions |
| `possible_tags` | `RoomBlueprint.tres` files | Which graph roles a room can fill |
| `gateway role`, `allows_*` | Room `.tscn` Gateway nodes | Which edge types a gateway accepts |

### 10.2 Extension Points

| Extension | What to do |
|---|---|
| **New room type** | Extend `_BaseRoom`, implement `setup_room()`, create `RoomBlueprint.tres` |
| **New stair variant** | Extend `_BaseRoom`, handle `delta_y` from `logic_node.custom_data` |
| **New graph rule** | Extend `GraphRule`, implement `can_apply()` and `apply()`, add to `GraphRewriter` |
| **New lock mechanic** | Extend `LockComponent`, join `"lock_targets"` group, implement `receive_lock_activation()` |
| **New component type** | Extend `DungeonComponent`, register descriptor in graph rule, spawn from `DungeonGenerator` |
| **New edge type** | Add string constant to `LogicalEdge`, update `CorridorNetwork` zone logic if needed |

---

## 11. Summary

The dungeon generation system satisfies its functional and application requirements through a design where structural guarantees are encoded at the earliest possible stage and propagated forward, rather than checked retrospectively.

**Diversity** is achieved through independent stochastic variation at the graph, placement, and geometry levels, all controllable through Godot resource parameters without code changes.

**Solvability** is guaranteed by construction in the graph rewriting phase and structurally enforced by the corridor routing zone system, not merely tested after the fact.

**Navigability** is enforced by the AABB margin system, the A\* routing budget, and the stair injection mechanism, which together ensure every logical connection in the dungeon graph has a physical walkable path.

**Complexity** is configurable via the `num_challenges` parameter and the `create_loop` flag, enabling curriculum learning by controlling dungeon depth and the presence of cycles.

The **plug-and-play architecture** centred on `_BaseRoom`, `RoomBlueprint`, and `RoomParameter` means individual rooms are fully decoupled from the generation pipeline. New room types can be introduced, and existing ones can be adjusted, entirely within the Godot editor and the room's own scene file.

The **component socket system** for lock-and-key mechanics, built on `DungeonComponent` and `LockUtil`, exposes machine-readable agent metadata for all interactive objects, directly supporting the requirement that the world serve as a queryable training environment.
