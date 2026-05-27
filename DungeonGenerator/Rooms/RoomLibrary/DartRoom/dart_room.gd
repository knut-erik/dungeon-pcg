extends BaseRoom

@onready var bounding_box = $BoundingBox
@onready var dart_trap_1 = $DartTrap
@onready var dart_trap_2 = $DartTrap2
@onready var respawn_point = Vector3.ZERO

func setup_room(rng: RandomNumberGenerator, logic_node: LogicalNode):
	# 1. Hämta datan
	var width = 6.0
	var length = 3.0
	var height = 4.0 
		
	room_size = Vector3(width, height, length)
	var inner_room_size = Vector3(width-0.1, height-0.1, length-0.1)
	
	var col_shape = bounding_box.get_node_or_null("CollisionShape3D")
	if col_shape and col_shape.shape is BoxShape3D:
		col_shape.shape = col_shape.shape.duplicate()  # break shared resource link
		col_shape.shape.size = room_size
	bounding_box.position.y = 2
	
	dart_trap_1.dart_respawn_point = respawn_point
	dart_trap_2.dart_respawn_point = respawn_point
