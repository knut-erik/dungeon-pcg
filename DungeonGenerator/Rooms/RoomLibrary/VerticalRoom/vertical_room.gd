extends BaseRoom
class_name VerticalRoom

@export var platform_scene:PackedScene

@onready var bounding_box = $BoundingBox 
@onready var outer_csg = $CSGCombiner3D/OuterCSG
@onready var inner_csg = $CSGCombiner3D/InnerCSG


func _ready() -> void:
	# Berätta för bas-klassen vilka noder som är våra gateways
	gateway_in = $CSGCombiner3D/Door1/Target
	gateway_out = $CSGCombiner3D/Door2/Target2

func setup_room(rng: RandomNumberGenerator, logic_node: LogicalNode):
	# 1. Hämta datan
	var width = 4
	var length = 4
	var height = floor(logic_node.blueprint.height_param.sample(rng))
	
	room_size = Vector3(width, height, length)
	var inner_room_size = Vector3(width-0.1, height-0.1, length-0.1)
	var door_out = $CSGCombiner3D/Door2
	outer_csg.size = room_size
	outer_csg.position.y = height / 2
	inner_csg.size = inner_room_size
	inner_csg.position.y = height / 2
	door_out.position.y = height - 2
	
	var col_shape = bounding_box.get_node_or_null("CollisionShape3D")
	if col_shape and col_shape.shape is BoxShape3D:
		col_shape.shape = col_shape.shape.duplicate()  # break shared resource link
		col_shape.shape.size = room_size
	bounding_box.position.y = height / 2.0
	
	if bounding_box.has_method("set_size"):
		bounding_box.set_size(room_size)
		
	bounding_box.position.y = height / 2.0
	
	
	for i in range(1, height-2):
		var platform : Node3D = platform_scene.instantiate()
		platform.position.y = i
		var x_position = (rng.randf() - 0.5) * (width - 1)
		var z_position = (rng.randf() - 0.5) * (length - 1)
		platform.position.x = x_position
		platform.position.z = z_position
		add_child(platform)
