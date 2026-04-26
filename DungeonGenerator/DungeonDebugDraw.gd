# DungeonDebugDraw.gd
# Attach as a child of DungeonGenerator.
#
# USAGE:
#   Call draw_debug(corridor_network, rooms, stair_rooms) after the dungeon is built.
#   Press F1 at runtime to toggle visibility.
#
# COLOR KEY:
#   White   — room AABBs (from _room_aabbs in CorridorNetwork)
#   Magenta — stair room AABBs
#   Green   — gateway_in markers + facing direction
#   Red     — gateway_out markers + facing direction
#   Yellow  — unowned gateways (owner AABB not found — indicates transform/timing bug)

extends Node3D
class_name DungeonDebugDraw

const COLOR_ROOM    := Color(1.0, 1.0, 1.0, 0.6)
const COLOR_STAIRS  := Color(1.0, 0.0, 1.0, 0.9)
const COLOR_GW_IN   := Color(0.2, 1.0, 0.3, 1.0)
const COLOR_GW_OUT  := Color(1.0, 0.2, 0.2, 1.0)
const COLOR_UNOWNED := Color(1.0, 1.0, 0.0, 1.0)
const TOGGLE_KEY    := KEY_F1

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D

func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance  = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override     = _material

	add_child(_mesh_instance)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == TOGGLE_KEY:
		_mesh_instance.visible = not _mesh_instance.visible
		print("DungeonDebugDraw: %s" % ("visible" if _mesh_instance.visible else "hidden"))

# Call this after CorridorNetwork.build() has completed.
#
# network     — the CorridorNetwork node
# rooms       — all BaseRoom instances placed by DungeonGenerator
# stair_rooms — BaseRoom instances spawned by _inject_stairs_and_split
#               (pass an empty array if not yet tracked)
func draw_debug(network: CorridorNetwork, rooms: Array[BaseRoom], stair_rooms: Array[BaseRoom] = []) -> void:
	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	var all_aabbs := network.get_room_aabbs()

	# Build a set of stair AABB positions for O(1) color lookup
	var stair_positions: Array[Vector3] = []
	for stair in stair_rooms:
		for aabb in stair.get_world_aabbs():
			stair_positions.append(aabb.position)

	# Draw all AABBs — magenta for stairs, white for rooms
	for aabb in all_aabbs:
		var is_stair := false
		for sp in stair_positions:
			if aabb.position.distance_to(sp) < 0.05:
				is_stair = true
				break
		_draw_aabb_wireframe(aabb, COLOR_STAIRS if is_stair else COLOR_ROOM)

	# Draw regular room gateways
	for room in rooms:
		_draw_gateway(room.gateway_in,  COLOR_GW_IN,  all_aabbs)
		_draw_gateway(room.gateway_out, COLOR_GW_OUT, all_aabbs)

	# Draw stair gateways (always owned, skip ownership check)
	for stair in stair_rooms:
		_draw_gateway(stair.gateway_in,  COLOR_GW_IN,  all_aabbs)
		_draw_gateway(stair.gateway_out, COLOR_GW_OUT, all_aabbs)

	_immediate_mesh.surface_end()

# ── Geometry helpers ──────────────────────────────────────────────────────────

func _draw_gateway(gateway: Marker3D, base_color: Color, all_aabbs: Array[AABB]) -> void:
	if not gateway:
		return
	var pos   := gateway.global_position
	var color := base_color if _is_point_owned(pos, all_aabbs) else COLOR_UNOWNED
	_draw_cross(pos, 0.4, color)
	# Arrow showing facing direction (-Z is "out of room" by convention)
	_draw_line(pos, pos + (-gateway.global_transform.basis.z) * 1.2, color)

func _draw_aabb_wireframe(aabb: AABB, color: Color) -> void:
	var p := aabb.position
	var s := aabb.size

	var c000 := p
	var c100 := p + Vector3(s.x, 0,   0  )
	var c010 := p + Vector3(0,   s.y, 0  )
	var c110 := p + Vector3(s.x, s.y, 0  )
	var c001 := p + Vector3(0,   0,   s.z)
	var c101 := p + Vector3(s.x, 0,   s.z)
	var c011 := p + Vector3(0,   s.y, s.z)
	var c111 := p + Vector3(s.x, s.y, s.z)

	for edge in [
		[c000,c100],[c100,c110],[c110,c010],[c010,c000],  # bottom face
		[c001,c101],[c101,c111],[c111,c011],[c011,c001],  # top face
		[c000,c001],[c100,c101],[c110,c111],[c010,c011],  # verticals
	]:
		_draw_line(edge[0], edge[1], color)

func _draw_cross(pos: Vector3, half: float, color: Color) -> void:
	for axis in [Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1)]:
		_draw_line(pos - axis * half, pos + axis * half, color)

func _draw_line(a: Vector3, b: Vector3, color: Color) -> void:
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(a)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(b)

func _is_point_owned(world_pos: Vector3, aabbs: Array[AABB]) -> bool:
	for aabb in aabbs:
		if aabb.grow(0.1).has_point(world_pos):
			return true
	return false
