extends Node3D
class_name TerrainDungeonDirector

enum TerrainPreset {
	CANYON_LINEAR,
	CANYON_BRANCHING,
	OPEN_VALLEY_WITH_CLIFFS,
	RAVINE_LOOP
}

@export var preset: TerrainPreset = TerrainPreset.CANYON_BRANCHING
@export var seed: int = 1
@export var path_length := 280.0
@export_range(4.0, 48.0, 0.25) var route_width := 18.0
@export_range(32.0, 256.0, 0.25) var wall_height := 128.0
@export_range(0, 12, 1) var branch_count := 5
@export_range(0.0, 1.0, 0.01) var openness := 0.35
@export_range(0.0, 1.0, 0.01) var noise_strength := 0.45
@export var debug_print := true

@export var terrain_path: NodePath = ^"JarVoxelTerrain"


func _enter_tree() -> void:
	apply_configuration()


func apply_configuration() -> void:
	var terrain: Node = get_node_or_null(terrain_path)
	if terrain == null:
		push_warning("TerrainDungeonDirector: No terrain found at %s." % terrain_path)
		return

	var sdf: Resource = terrain.get("sdf") as Resource
	if sdf == null:
		push_warning("TerrainDungeonDirector: Terrain has no SDF resource.")
		return

	var biome: Resource = sdf.get("biome") as Resource
	if biome == null:
		push_warning("TerrainDungeonDirector: SDF has no biome resource.")
		return

	var settings: Dictionary = _build_settings()
	_apply_noise_seeds(sdf, biome)
	_apply_biome_settings(biome, settings)
	_apply_sdf_settings(sdf, settings)

	if sdf.has_method("invalidate_layout_cache"):
		sdf.call("invalidate_layout_cache")

	if debug_print:
		print(
			"TerrainDungeonDirector: preset=",
			TerrainPreset.keys()[preset],
			" seed=",
			seed,
			" route_width=",
			settings["route_width"],
			" branches=",
			settings["branch_count"],
			" openness=",
			settings["openness"]
		)


func _build_settings() -> Dictionary:
	var settings: Dictionary = {
		"path_length": path_length,
		"route_width": route_width,
		"wall_height": wall_height,
		"branch_count": branch_count,
		"openness": openness,
		"noise_strength": noise_strength,
		"main_meander": 18.0,
		"secondary_meander": 5.0,
		"branch_min_length": 16.0,
		"branch_max_length": 58.0,
		"branch_width_scale": 0.75,
		"town_radius": 34.0,
		"cave_radius": 10.0,
		"wall_falloff": 18.0,
		"edge_noise": 0.5,
		"pocket_strength": 0.8,
		"pocket_threshold": 0.94
	}

	match preset:
		TerrainPreset.CANYON_LINEAR:
			settings["branch_count"] = 0
			settings["openness"] = minf(openness, 0.20)
			settings["main_meander"] = 12.0
			settings["secondary_meander"] = 3.0
			settings["wall_falloff"] = 12.0
			settings["pocket_strength"] = 0.2
		TerrainPreset.CANYON_BRANCHING:
			settings["branch_count"] = maxi(2, branch_count)
			settings["openness"] = openness
			settings["main_meander"] = 22.0
			settings["secondary_meander"] = 7.0
			settings["branch_max_length"] = 68.0
			settings["wall_falloff"] = 20.0
		TerrainPreset.OPEN_VALLEY_WITH_CLIFFS:
			settings["route_width"] = route_width + 6.0
			settings["branch_count"] = maxi(3, branch_count)
			settings["openness"] = maxf(openness, 0.55)
			settings["main_meander"] = 28.0
			settings["secondary_meander"] = 8.0
			settings["branch_width_scale"] = 0.95
			settings["town_radius"] = 52.0
			settings["wall_falloff"] = 34.0
			settings["pocket_strength"] = 1.4
		TerrainPreset.RAVINE_LOOP:
			settings["branch_count"] = maxi(4, branch_count)
			settings["openness"] = maxf(openness, 0.40)
			settings["main_meander"] = 30.0
			settings["secondary_meander"] = 10.0
			settings["branch_min_length"] = 26.0
			settings["branch_max_length"] = 82.0
			settings["branch_width_scale"] = 0.70
			settings["wall_falloff"] = 16.0
			settings["pocket_strength"] = 1.2

	return settings


func _apply_noise_seeds(sdf: Resource, biome: Resource) -> void:
	var biome_noise: Resource = sdf.get("biome_noise") as Resource
	var shape_noise: Resource = sdf.get("shape_noise") as Resource
	var detail_noise: Resource = biome.get("detail_noise") as Resource

	if biome_noise != null:
		biome_noise.set("seed", seed)

	if shape_noise != null:
		shape_noise.set("seed", seed + 101)

	if detail_noise != null:
		detail_noise.set("seed", seed + 202)


func _apply_biome_settings(biome: Resource, settings: Dictionary) -> void:
	var branch_count_value: int = int(settings["branch_count"])
	var branchiness: float = 1.0 if branch_count_value > 0 else 0.0
	var open_value: float = float(settings["openness"])
	var noise_value: float = float(settings["noise_strength"])

	biome.set("path_width", float(settings["route_width"]))
	biome.set("valley_depth", clampf(0.32 + open_value * 0.28, 0.0, 1.0))
	biome.set("mountain_steepness", clampf(2.3 - open_value * 0.7, 0.4, 4.0))
	biome.set("winding_scale", 0.018 + noise_value * 0.035)
	biome.set("branchiness", branchiness)
	biome.set("town_radius", float(settings["town_radius"]))
	biome.set("cave_inset_strength", 1.0 + open_value * 0.35)


func _apply_sdf_settings(sdf: Resource, settings: Dictionary) -> void:
	var open_value: float = float(settings["openness"])
	var noise_value: float = float(settings["noise_strength"])
	var branch_count_value: int = int(settings["branch_count"])
	var requested_wall: float = float(settings["wall_height"])
	var high_wall: float = clampf(requested_wall, 4.0, 14.0)

	sdf.set("path_length", float(settings["path_length"]))
	sdf.set("path_step", 6.0)
	sdf.set("main_meander_amplitude", float(settings["main_meander"]) * (0.65 + noise_value * 0.7))
	sdf.set("secondary_meander_amplitude", float(settings["secondary_meander"]) * (0.55 + noise_value * 0.9))
	sdf.set("branch_max_count", branch_count_value)
	sdf.set("branch_min_length", float(settings["branch_min_length"]))
	sdf.set("branch_max_length", float(settings["branch_max_length"]))
	sdf.set("branch_bend_amplitude", 3.0 + noise_value * 10.0)
	sdf.set("branch_width_scale", float(settings["branch_width_scale"]))
	sdf.set("cave_radius", float(settings["cave_radius"]) + open_value * 8.0)
	sdf.set("height_scale", 1.0)
	sdf.set("mountain_base_height", 2.0 + high_wall * 0.08)
	sdf.set("mountain_relief", high_wall * (0.72 + open_value * 0.18))
	sdf.set("ridge_relief", high_wall * 0.12)
	sdf.set("valley_floor_height", 0.0)
	sdf.set("valley_floor_relief", 0.25 + noise_value * 1.4)
	sdf.set("carve_depth", high_wall * (0.55 + open_value * 0.22))
	sdf.set("wall_falloff", maxf(float(settings["wall_falloff"]), 18.0 + open_value * 16.0))
	_try_set_sdf_property(sdf, "containment_height", clampf(requested_wall * 0.22, 5.0, 10.0))
	_try_set_sdf_property(sdf, "containment_width", clampf(8.0 + open_value * 8.0, 8.0, 16.0))
	_try_set_sdf_property(sdf, "containment_offset", 1.0 + open_value * 1.5)
	sdf.set("edge_noise_strength", float(settings["edge_noise"]) + noise_value * 1.2)
	sdf.set("pocket_strength", float(settings["pocket_strength"]) * noise_value)
	sdf.set("pocket_threshold", float(settings["pocket_threshold"]))
	sdf.set("mountain_macro_frequency", 0.010 + noise_value * 0.018)
	sdf.set("mountain_ridge_frequency", 0.018 + noise_value * 0.040)
	sdf.set("floor_detail_frequency", 0.012 + noise_value * 0.045)
	sdf.set("edge_noise_frequency", 0.018 + noise_value * 0.040)
	sdf.set("pocket_frequency", 0.006 + noise_value * 0.018)


func _try_set_sdf_property(sdf: Resource, property_name: String, value: Variant) -> void:
	for property in sdf.get_property_list():
		if str(property.get("name", "")) == property_name:
			sdf.set(property_name, value)
			return
