'''extends AIController3D
class_name DungeonAgentController

@onready var player: PlayerController3D = get_parent()

var reward_value: float = 0.0


func _ready() -> void:
	player.use_agent_control = heuristic != "human"


func get_obs() -> Dictionary:
	var obs_data := player.get_agent_observation()

	var obs := [
		obs_data["health_normalized"],
		float(obs_data["money"]) / 100.0,
		float(obs_data["game_state"]),
		obs_data["position"][0] / 50.0,
		obs_data["position"][1] / 20.0,
		obs_data["position"][2] / 50.0,
		obs_data["velocity"][0] / 10.0,
		obs_data["velocity"][1] / 10.0,
		obs_data["velocity"][2] / 10.0,
		1.0 if obs_data["looked_object_present"] else 0.0,
		float(obs_data["looked_tag_id"]) / 100.0
	]

	return {"obs": obs}


func get_reward() -> float:
	return reward_value


func get_action_space() -> Dictionary:
	return {
		"move": {
			"size": 2,
			"action_type": "continuous"
		},
		"look": {
			"size": 2,
			"action_type": "continuous"
		},
		"jump": {
			"size": 2,
			"action_type": "discrete"
		},
		"interact": {
			"size": 2,
			"action_type": "discrete"
		}
	}


func set_action(action) -> void:
	player.use_agent_control = heuristic != "human"

	player.set_agent_action({
		"move_x": clamp(action["move"][0], -1.0, 1.0),
		"move_z": clamp(action["move"][1], -1.0, 1.0),
		"look_yaw": clamp(action["look"][0], -1.0, 1.0),
		"look_pitch": clamp(action["look"][1], -1.0, 1.0),
		"jump": int(action["jump"]) == 1,
		"interact": int(action["interact"]) == 1
	})'''
