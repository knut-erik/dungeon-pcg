extends BaseRoom
class_name LeverRoom

@onready var lever = $Lever
@onready var bounding_box = $BoundingBox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func setup_room(rng: RandomNumberGenerator, logic_node: LogicalNode):
	# 1. Hämta datan
	var width = 6
	var length = 6
	var height = 4.0 
	
	room_size = Vector3(width, height, length)
	
	var lever_pos_x = logic_node.blueprint.width_param.sample(rng)
	var lever_pos_z = logic_node.blueprint.length_param.sample(rng)
	lever.position = Vector3(lever_pos_x, 0.1, lever_pos_z)
	
	var col_shape = bounding_box.get_node_or_null("CollisionShape3D")
	if col_shape and col_shape.shape is BoxShape3D:
		col_shape.shape = col_shape.shape.duplicate()  # break shared resource link
		col_shape.shape.size = room_size
	bounding_box.position.y = 2
