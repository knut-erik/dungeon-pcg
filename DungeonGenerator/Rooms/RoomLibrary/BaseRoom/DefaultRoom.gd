# DefaultRoom.gd
extends BaseRoom
class_name DefaultRoom

# Hämta referenser baserat på din Scen-struktur
@onready var bounding_box = $Area3D 
@onready var main_room = $CSGCombiner3D/CSGBox3D
@onready var hollowing_room = $CSGCombiner3D/CSGBox3D4
@onready var door_hole_in = $CSGCombiner3D/CSGBox3D3
@onready var door_hole_out = $CSGCombiner3D/CSGBox3D2

func _ready() -> void:
	# Berätta för bas-klassen vilka noder som är våra gateways
	gateway_in = $CSGCombiner3D/CSGBox3D2/Target
	gateway_out = $CSGCombiner3D/CSGBox3D3/Target2

func setup_room(rng: RandomNumberGenerator, logic_node: LogicalNode):
	# 1. Hämta datan
	var width = logic_node.blueprint.width_param.sample(rng)
	var length = logic_node.blueprint.length_param.sample(rng)
	var height = 4.0 
	
	room_size = Vector3(width, height, length)
	var inner_room_size = Vector3(width-0.1, height-0.1, length-0.1)
	
	main_room.size = room_size
	hollowing_room.size = inner_room_size
	
	if bounding_box.has_method("set_size"):
		bounding_box.set_size(room_size)
		
	bounding_box.position.y = height / 2.0
	
	var walls = [0, 1, 2, 3] 
	walls.shuffle()
	
	_place_door_on_wall(door_hole_in, walls[0], room_size, rng)
	_place_door_on_wall(door_hole_out, walls[1], room_size, rng)
	
	await get_tree().process_frame  # Let CSG positions settle
	var center = global_position
	_ensure_gateway_faces_inward(gateway_in, door_hole_in, center)
	_ensure_gateway_faces_inward(gateway_out, door_hole_out, center)

func _ensure_gateway_faces_inward(gateway: Marker3D, _door_csg: CSGBox3D, room_center: Vector3) -> void:
	# The gateway's -Z should point AWAY from room center
	var outward = -(gateway.global_position - room_center).normalized()
	var gateway_forward = -gateway.global_transform.basis.z
	
	# If they're pointing in opposite hemispheres, the gateway is already correct
	# If dot > 0, gateway Z points away from center (inward toward outside) — flip it
	if outward.dot(gateway_forward) > 0:
		gateway.rotate_y(deg_to_rad(180))

func _place_door_on_wall(door_csg: CSGBox3D, wall_index: int, room_size_param: Vector3, rng: RandomNumberGenerator):
	var half_w = room_size_param.x / 2.0
	var half_l = room_size_param.z / 2.0
	var max_x = max(0.0, half_w - 1.5)
	var max_z = max(0.0, half_l - 1.5)
	var y_pos = 1.1 
	
	match wall_index:
		0: 
			door_csg.position = Vector3(rng.randf_range(-max_x, max_x), y_pos, -half_l)
			door_csg.rotation_degrees.y = 0 
		1: 
			door_csg.position = Vector3(rng.randf_range(-max_x, max_x), y_pos, half_l)
			door_csg.rotation_degrees.y = 180
		2: 
			door_csg.position = Vector3(-half_w, y_pos, rng.randf_range(-max_z, max_z))
			door_csg.rotation_degrees.y = 90
		3: 
			door_csg.position = Vector3(half_w, y_pos, rng.randf_range(-max_z, max_z))
			door_csg.rotation_degrees.y = -90
