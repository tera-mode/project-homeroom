## CharacterState.gd
## AutoLoad: 全キャラクターの実行時状態（能力値・充実度）を管理する
extends Node

# _states[char_id] = {
#   gender, type, like_type, dislike_type, abilities,
#   study, sports, art, fulfillment
# }
var _states: Dictionary = {}

func init_character(char_id: String, master_data: Dictionary) -> void:
	_states[char_id] = {
		"gender":       master_data.get("gender", "male"),
		"type":         master_data.get("type", "futsu"),
		"like_type":    master_data.get("like_type", ""),
		"dislike_type": master_data.get("dislike_type", ""),
		"abilities":    master_data.get("abilities", []).duplicate(),
		"study":        master_data.get("initial_study", 0),
		"sports":       master_data.get("initial_sports", 0),
		"art":          master_data.get("initial_art", 0),
		"fulfillment":  0
	}

func get_state(char_id: String) -> Dictionary:
	return _states.get(char_id, {})

func apply_param_delta(char_id: String, param: String, delta: int) -> void:
	if not _states.has(char_id):
		return
	if _states[char_id].has(param):
		_states[char_id][param] += delta

func apply_fulfillment_delta(char_id: String, delta: int) -> void:
	apply_param_delta(char_id, "fulfillment", delta)

func get_all_active_ids() -> Array:
	return _states.keys()

func remove_character(char_id: String) -> void:
	_states.erase(char_id)

func get_save_data() -> Dictionary:
	return _states.duplicate(true)

func load_save_data(data: Dictionary) -> void:
	_states = data.duplicate(true)

func reset() -> void:
	_states = {}
