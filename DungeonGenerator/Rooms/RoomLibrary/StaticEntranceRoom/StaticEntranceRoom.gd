extends BaseRoom
class_name StaticEntranceRoom

@onready var scene_transition: SceneTransitionSocket = $SceneTransition

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Berätta för bas-klassen vilka noder som är våra gateways
	gateway_in = $CSGCombiner3D/CSGBox3D3/Target
	gateway_out = $CSGCombiner3D/CSGBox3D7/Target2

	$CSGCombiner3D.material_override = load("res://Assets/Textures/Floors/Stone_floors/cobblestone3/cobblestone3.tres")

func setup_room(_rng: RandomNumberGenerator, _logic_node: LogicalNode) -> void:
	gateway_in = $CSGCombiner3D/CSGBox3D3/Target
	gateway_out = $CSGCombiner3D/CSGBox3D7/Target2

	# Godot convention:
	# Marker3D.forward is local -Z.
	#
	# Target:
	# -Z should point toward world -Z.
	# This means the gateway faces out along +Z.
	gateway_in.global_rotation = Vector3(0.0, 0.0, 0.0)

	# Target2:
	# -Z should point toward world -X.
	# This means the gateway faces out along +X.
	gateway_out.global_rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)

	await get_tree().process_frame


func _orient_gateway_outward(gateway: Node3D, outward_dir: Vector3) -> void:
	if gateway == null:
		push_warning("StaticEntranceRoom: Tried to orient a null gateway.")
		return

	outward_dir = outward_dir.normalized()

	# Godot basis convention:
	# local -Z = forward.
	# Make local -Z point toward outward_dir.
	gateway.global_basis = Basis.looking_at(outward_dir, Vector3.UP)
