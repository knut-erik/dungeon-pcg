# BaseRoom.gd
extends Node3D
class_name BaseRoom

var room_size: Vector3 = Vector3.ZERO

# Dessa tilldelas i barn-klassernas _ready() funktioner
var gateway_in: Marker3D
var gateway_out: Marker3D

# Hämtar alla bounding boxes för detta rum
func get_local_aabbs() -> Array[AABB]:
	var aabbs: Array[AABB] = []
	for child in get_children():
		if child is Area3D: 
			var col_shape = child.get_node_or_null("CollisionShape3D")
			if col_shape and col_shape.shape is BoxShape3D:
				var size = col_shape.shape.size
				var pos = child.position 
				aabbs.append(AABB(pos - (size / 2.0), size))
	return aabbs

# Rummen måste kunna svara på vilka gateways de har lediga
func get_available_gateway_in() -> Marker3D:
	if gateway_in and not gateway_in.get_meta("is_connected", false): 
		return gateway_in
	return null

func get_available_gateway_out() -> Marker3D:
	if gateway_out and not gateway_out.get_meta("is_connected", false): 
		return gateway_out
	return null

# Denna MÅSTE skrivas över av barn-klasserna
func setup_room(_rng: RandomNumberGenerator, _logic_node: LogicalNode):
	push_warning("setup_room() anropades på BaseRoom. Detta bör göras i barn-klassen!")
