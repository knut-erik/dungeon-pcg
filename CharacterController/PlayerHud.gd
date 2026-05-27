class_name PlayerHud
extends CanvasLayer

@export var player_path: NodePath = ^".."
@export var heart_texture: Texture2D
@export var coin_texture: Texture2D
@export var icon_size := Vector2(28.0, 28.0)
@export var max_coin_icons := 64

var _player: Node
var _heart_row: HBoxContainer
var _coin_row: HBoxContainer
var _last_health := -1
var _last_max_health := -1
var _last_money := -1


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_build_layout()
	_refresh(true)


func _process(_delta: float) -> void:
	_refresh(false)


func _build_layout() -> void:
	var root := MarginContainer.new()
	root.name = "Root"
	root.anchor_left = 0.0
	root.anchor_top = 1.0
	root.anchor_right = 0.0
	root.anchor_bottom = 1.0
	root.offset_left = 16.0
	root.offset_top = -88.0
	root.offset_right = 520.0
	root.offset_bottom = -16.0
	add_child(root)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 6)
	root.add_child(stack)

	_coin_row = HBoxContainer.new()
	_coin_row.name = "Coins"
	_coin_row.add_theme_constant_override("separation", 2)
	stack.add_child(_coin_row)

	_heart_row = HBoxContainer.new()
	_heart_row.name = "Hearts"
	_heart_row.add_theme_constant_override("separation", 2)
	stack.add_child(_heart_row)


func _refresh(force: bool) -> void:
	if _player == null:
		return

	var health := int(_player.get("health"))
	var max_health := int(_player.get("max_health"))
	var money := int(_player.get("money"))

	if force or health != _last_health or max_health != _last_max_health:
		_rebuild_hearts(health, max_health)
		_last_health = health
		_last_max_health = max_health

	if force or money != _last_money:
		_rebuild_coins(money)
		_last_money = money


func _rebuild_hearts(health: int, max_health: int) -> void:
	_clear_children(_heart_row)

	for index in range(maxi(0, max_health)):
		var heart := _make_icon(heart_texture)
		heart.modulate = Color.WHITE if index < health else Color(1.0, 1.0, 1.0, 0.22)
		_heart_row.add_child(heart)


func _rebuild_coins(money: int) -> void:
	_clear_children(_coin_row)

	for _index in range(mini(maxi(0, money), max_coin_icons)):
		_coin_row.add_child(_make_icon(coin_texture))


func _make_icon(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
