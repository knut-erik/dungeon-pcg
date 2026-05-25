extends AIController3D

var input_actions := {
	"move_x": 0.0,
	"move_z": 0.0,
	"jump": false,
	"interact": false,
	"look_yaw": 0.0,
	"look_pitch": 0.0
}

func get_obs() -> Dictionary:
	return {"obs": []}


func get_reward() -> float:
	return 0.0


func get_action_space() -> Dictionary:
	return {
		"move_x": {"size": 2, "action_type": "discrete"},
		"move_z": {"size": 2, "action_type": "discrete"},
		"interact": {"size": 2, "action_type": "discrete"},
		"look_yaw": {"size": 1, "action_type": "continuous"},
		"look_pitch": {"size": 1, "action_type": "continuous"},
	}


func set_action(action) -> void:
	input_actions["move_x"] = [-1.0, 1.0][action["move_x"]]
	input_actions["move_z"] = [-1.0, 1.0][action["move_z"]]
	input_actions["interact"] = action["interact"]
	input_actions["look_yaw"] = action["look_yaw"][0]
	input_actions["look_pitch"] = action["look_pitch"][0]
	
	
