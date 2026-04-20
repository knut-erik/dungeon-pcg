# GraphRule.gd (Bas-klass)
extends RefCounted
class_name GraphRule

var room_library: Array[RoomBlueprint]

func _init(lib: Array[RoomBlueprint]):
	room_library = lib

# Ska överskridas av specifika regler
func can_apply(_graph: LogicalGraph, _target_node: LogicalNode) -> bool:
	return false
	
func apply(_graph: LogicalGraph, _target_node: LogicalNode) -> void:
	pass

# Hjälpfunktion för att hämta rum
func get_blueprint(tag: String) -> RoomBlueprint:
	var valid = []
	for bp in room_library:
		if bp.possible_tags.has(tag):
			valid.append(bp)
	return valid.pick_random() if valid.size() > 0 else null
