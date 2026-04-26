extends BaseRoom
class_name StairRoomStraight

@onready var bounding_box = $Area3D 
@onready var stair_mesh = $CSGPolygon3D 

func _ready() -> void:
	gateway_in = $Target
	gateway_out = $Target2

func setup_room(_rng: RandomNumberGenerator, logic_node: LogicalNode):
	var delta_y = logic_node.custom_data.get("delta_y", 4.0)
	
	var step_height = 0.25 
	var step_depth = 0.4   
	
	var num_steps = max(1, abs(delta_y) / step_height)
	var total_length = num_steps * step_depth
	var room_width = 3.0 
	
	room_size = Vector3(room_width, abs(delta_y) + 4.0, total_length)
	
	var shape = bounding_box.get_node_or_null("CollisionShape3D")
	if shape and shape.shape is BoxShape3D:
		shape.shape = shape.shape.duplicate()  # break shared resource link
		shape.shape.size = room_size
		bounding_box.position = Vector3(0, delta_y / 2.0, 0)
		
	# Gateways placeras i ändarna av trappan
	gateway_in.position = Vector3(0, 0, total_length / 2.0)
	gateway_in.rotation_degrees.y = 180
	
	gateway_out.position = Vector3(0, delta_y, -total_length / 2.0)
	gateway_out.rotation_degrees.y = 0
	
	if stair_mesh:
		stair_mesh.mode = CSGPolygon3D.MODE_DEPTH
		stair_mesh.depth = room_width
		
		# Rotera +90 grader för alignment
		stair_mesh.rotation_degrees.y = 90
		stair_mesh.position = Vector3(room_width / 2.0, 0, total_length / 2.0)
		
		var points = PackedVector2Array()
		points.append(Vector2(0, 0)) # Start (Botten)
		points.append(Vector2(total_length, delta_y)) # Slut (Toppen)
		points.append(Vector2(total_length, 0)) # Solid bas
		stair_mesh.polygon = points
