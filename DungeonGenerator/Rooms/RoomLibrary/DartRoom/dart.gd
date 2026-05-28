extends CSGBox3D

var respawn_point : Vector3
var speed : float = 10
# Called when the node enters the scene tree for the first time.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position += transform.basis.x * speed * delta

func _on_hit_box_body_entered(body: Node3D) -> void:
	if body.is_in_group("character"):
		body.velocity = Vector3.ZERO
		body.damage(1)
	queue_free()
