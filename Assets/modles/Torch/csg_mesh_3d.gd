extends Node3D

@onready var csg_root: CSGCombiner3D = $CSGCombiner3D

func _ready():
	var baked_mesh: ArrayMesh = csg_root.bake_static_mesh()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = baked_mesh
	mesh_instance.transform = csg_root.transform

	add_child(mesh_instance)

	# Optional: remove/hide original CSG
	csg_root.visible = false
	# csg_root.queue_free()
