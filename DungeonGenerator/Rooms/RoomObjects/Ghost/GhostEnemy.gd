class_name GhostEnemy
extends Node3D

@export var max_health: int = 3
@export var hit_damage: int = 1
@export var hurt_flash_time: float = 0.08

@onready var visual_root: Node3D = $Visual
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D

var _health: int = 0
var _is_dead: bool = false


func _ready() -> void:
	_health = max_health
	add_to_group("enemy")
	add_to_group("interactable")
	_sync_agent_metadata()
	_play_looping_animation()


func interact(actor: Node) -> void:
	if _is_dead:
		return

	if actor != null and actor.has_method("swing_sword"):
		actor.swing_sword()

	take_damage(hit_damage)
	print("GhostEnemy: hit hp=", _health, "/", max_health)


func take_damage(amount: int) -> void:
	if _is_dead:
		return

	_health = max(_health - amount, 0)
	_flash_hurt()

	if _health <= 0:
		_die()


func get_rl_tags() -> Array[String]:
	return ["enemy", "ghost"]


func _sync_agent_metadata() -> void:
	_apply_agent_metadata(self)

	for child: Node in find_children("*", "", true, false):
		if child is Node:
			_apply_agent_metadata(child)


func _apply_agent_metadata(node: Node) -> void:
	node.set_meta("agent_tags", get_rl_tags())
	node.set_meta("semantic_tag", "enemy")
	node.set_meta("component_type", "enemy")

	for tag: String in get_rl_tags():
		var group_name: String = "tag_%s" % tag
		if not node.is_in_group(group_name):
			node.add_to_group(group_name)


func _play_looping_animation() -> void:
	var animation_player: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		return

	var animations: PackedStringArray = animation_player.get_animation_list()
	if animations.is_empty():
		return

	var animation_name: StringName = StringName(animations[0])
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR

	animation_player.play(animation_name)


func _flash_hurt() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(visual_root, "scale", Vector3(1.12, 1.12, 1.12), hurt_flash_time)
	tween.tween_property(visual_root, "scale", Vector3.ONE, hurt_flash_time)


func _die() -> void:
	_is_dead = true

	if collision_shape != null:
		collision_shape.disabled = true

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.18)
	tween.tween_callback(Callable(self, "queue_free"))
