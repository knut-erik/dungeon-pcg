extends Path3D
class_name Corridor

@onready var outer_polygon = $CSGCombiner3D/Outer_Polygon
@onready var inner_polygon = $CSGCombiner3D/Inner_Polygon

func generate_from_path(path_points: PackedVector3Array):
	curve = Curve3D.new()
	global_position = Vector3.ZERO
	
	for p in path_points:
		curve.add_point(p)
		
	if outer_polygon and inner_polygon:
		# 1. Rensa gamla länkar för att tvinga fram en uppdatering
		outer_polygon.path_node = NodePath("")
		inner_polygon.path_node = NodePath("")
		
		# 2. Ge Godot en frame att registrera rensningen
		await get_tree().process_frame
		
		# 3. Länka tillbaka kurvan
		outer_polygon.path_node = NodePath("../..")
		inner_polygon.path_node = NodePath("../..")

'''JUST L SHAPED AND U SHAPED CORRIDORS 
extends Node3D
class_name Corridor

const WIDTH  := 3.0
const HEIGHT := 3.4

# Generates an L-shaped (or straight, or 3-segment) corridor from a list of
# ordered waypoints. Each consecutive pair becomes one CSGBox3D segment.
# Interior joints get a half-width extension on each side so segments meet
# cleanly. Gateway ends get NO extension so the corridor never enters a room.
func generate(waypoints: PackedVector3Array) -> void:
	if waypoints.size() < 2:
		return
	var combiner = CSGCombiner3D.new()
	combiner.use_collision = true
	add_child(combiner)
	for i in range(waypoints.size() - 1):
		_add_segment(
			combiner,
			waypoints[i],
			waypoints[i + 1],
			i == 0,                          # is gateway start
			i == waypoints.size() - 2        # is gateway end
		)

func _add_segment(parent: CSGCombiner3D, a: Vector3, b: Vector3,
				  is_gateway_start: bool, is_gateway_end: bool) -> void:
	if a.distance_to(b) < 0.05:
		return

	# Interior joints overlap by WIDTH/2 on each side so there is no gap.
	# Gateway ends do NOT extend — extending into a room creates visual artefacts.
	var ext_a: float = 0.0 if is_gateway_start else WIDTH * 0.5
	var ext_b: float = 0.0 if is_gateway_end   else WIDTH * 0.5

	var dx: float = abs(b.x - a.x)
	var dz: float = abs(b.z - a.z)
	var box := CSGBox3D.new()

	if dx >= dz:  # segment runs along X
		var dir: float = sign(b.x - a.x) if dx > 0.001 else 1.0
		var length: float = dx + ext_a + ext_b
		box.size     = Vector3(length, HEIGHT, WIDTH)
		# Shift center: start at (a.x - dir*ext_a), end at (a.x - dir*ext_a + dir*length)
		box.position = Vector3(
			a.x - dir * ext_a + dir * length * 0.5,
			a.y + HEIGHT * 0.5,
			(a.z + b.z) * 0.5
		)
	else:          # segment runs along Z
		var dir: float = sign(b.z - a.z) if dz > 0.001 else 1.0
		var length: float = dz + ext_a + ext_b
		box.size     = Vector3(WIDTH, HEIGHT, length)
		box.position = Vector3(
			(a.x + b.x) * 0.5,
			a.y + HEIGHT * 0.5,
			a.z - dir * ext_a + dir * length * 0.5
		)

	parent.add_child(box)'''


''' extends Path3D
class_name Corridor

@onready var outer_polygon = $CSGCombiner3D/Outer_Polygon
@onready var inner_polygon = $CSGCombiner3D/Inner_Polygon

func generate_from_path(path_points: PackedVector3Array):
	curve = Curve3D.new()
	global_position = Vector3.ZERO
	
	# Skapa en mjuk kurva genom alla punkter
	for p in path_points:
		# Genom att inte ange in/out-vektorer låter vi Godot räkna ut mjukheten automatiskt!
		curve.add_point(p)
		
	# Tvinga kurvan att räkna ut sina längder (kritiskt för CSG)
	curve.bake_interval = 0.5
	
	if outer_polygon and inner_polygon:
		# Säkerställ att Path Interval är tillräckligt lågt på polygonerna
		outer_polygon.path_interval = 0.5
		inner_polygon.path_interval = 0.5
		
		outer_polygon.path_node = NodePath("../..")
		inner_polygon.path_node = NodePath("../..")'''

'''extends Path3D
class_name Corridor

@export var curve_tension: float = 8.0 

# Hämta referenser till båda polygonerna
@onready var outer_polygon = $CSGCombiner3D/Outer_Polygon
@onready var inner_polygon = $CSGCombiner3D/Inner_Polygon

func generate_spline(gateway_a: Marker3D, gateway_b: Marker3D):
	# Tvinga fram en helt ny, unik kurva varje gång
	curve = Curve3D.new()
	
	var pos_a = gateway_a.global_position
	var pos_b = gateway_b.global_position
	
	var dir_out_a = -gateway_a.global_transform.basis.z.normalized()
	var dir_out_b = -gateway_b.global_transform.basis.z.normalized()
	
	global_position = Vector3.ZERO
	
	curve.add_point(pos_a, Vector3.ZERO, dir_out_a * curve_tension)
	curve.add_point(pos_b, dir_out_b * curve_tension, Vector3.ZERO)
	
	if outer_polygon and inner_polygon:
		outer_polygon.path_node = NodePath("../..") 
		inner_polygon.path_node = NodePath("../..")'''
