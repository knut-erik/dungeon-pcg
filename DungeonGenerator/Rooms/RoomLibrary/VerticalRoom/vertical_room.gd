extends BaseRoom
class_name VerticalRoom

@export var platform_scene:PackedScene

@onready var bounding_box = $BoundingBox 

func _ready() -> void:
	# Berätta för bas-klassen vilka noder som är våra gateways
	gateway_in = $CSGCombiner3D/Door1/Target
	gateway_out = $CSGCombiner3D/Door2/Target

func setup_room(rng: RandomNumberGenerator, logic_node: LogicalNode):
	# 1. Hämta datan
	var width = 4
	var length = 4
	var height = floor(logic_node.blueprint.height_param.sample(rng))
	
	room_size = Vector3(width, height, length)
	var inner_room_size = Vector3(width-0.1, height-0.1, length-0.1)
	
	if bounding_box.has_method("set_size"):
		bounding_box.set_size(room_size)
		
	bounding_box.position.y = height / 2.0
	
	for i in range(height):
		var platform : Node3D = platform_scene.instantiate()
		platform.position.y = i
		var x_position = (rng.randf() - 0.5) * (width - 0.5)
		var z_position = (rng.randf() - 0.5) * (length - 0.5)
		platform.position.x = x_position
		platform.position.z = z_position
		add_child(platform)
