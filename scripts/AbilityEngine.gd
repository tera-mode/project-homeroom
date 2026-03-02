## AbilityEngine.gd
## AutoLoad: 全キャラの特殊能力を1日1回適用する（EffectEngine置換）
extends Node

var _ability_map: Dictionary = {}

func _ready() -> void:
	_load_abilities()

func _load_abilities() -> void:
	var file = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if file == null:
		push_error("AbilityEngine: abilities.json not found")
		return
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("AbilityEngine: JSON parse error")
		return
	for ab in json.get_data().get("abilities", []):
		_ability_map[ab["ability_id"]] = ab

# 全キャラの特殊能力を適用し、処理ログを返す
func apply_all_abilities(board: Node) -> Array:
	var log_entries = []

	for entry in board.get_all_placed():
		var seat_index = entry["seat_index"]
		var student_data = entry["student_data"]
		var char_id = student_data.get("id", "")
		if char_id == "":
			continue

		var state = CharacterState.get_state(char_id)
		var abilities: Array = state.get("abilities", student_data.get("abilities", []))

		for ability_id in abilities:
			var ab = _ability_map.get(ability_id, {})
			if ab.is_empty():
				continue

			var effect_details = []

			for effect in ab.get("effects", []):
				var scope       = effect.get("scope", "self")
				var effect_type = effect.get("effect_type", "param")
				var delta       = effect.get("delta", 0)
				var targets     = _resolve_targets(board, seat_index, scope)

				for target_idx in targets:
					var target_data = board.get_student_at(target_idx)
					if target_data == null:
						continue
					var target_id = target_data.get("id", "")
					if target_id == "":
						continue

					match effect_type:
						"param":
							CharacterState.apply_param_delta(target_id, effect.get("target_param", "study"), delta)
						"friendship":
							FriendshipManager.apply_friendship_delta(target_id, char_id, delta)
						"fulfillment":
							CharacterState.apply_fulfillment_delta(target_id, delta)

					# 詳細ログに追記
					var target_name: String
					if target_id == "player":
						target_name = "あなた"
					else:
						var td = StudentDB.get_student_by_id(target_id)
						target_name = td.get("name", target_id)

					var actor_name: String
					if char_id == "player":
						actor_name = "あなた"
					else:
						var ad = StudentDB.get_student_by_id(char_id)
						actor_name = ad.get("name", char_id)

					var effect_str = ""
					var sign = "+" if delta >= 0 else ""
					match effect_type:
						"param":
							var param_names = {"study": "勉強", "sports": "運動", "art": "芸術"}
							effect_str = target_name + " の" + param_names.get(effect.get("target_param","study"), "?") + " " + sign + str(delta)
						"friendship":
							# apply_friendship_delta(target_id, char_id, delta) = target の char への仲良し度
							effect_str = target_name + " の " + actor_name + " への仲良し度 " + sign + str(delta)
						"fulfillment":
							effect_str = target_name + " の充実度 " + sign + str(delta)
					effect_details.append(effect_str)

			log_entries.append({
				"actor":        char_id,
				"ability_name": ab.get("name", ability_id),
				"effect_desc":  ab.get("description", ""),
				"details":      effect_details
			})

	return log_entries

func _resolve_targets(board: Node, seat_index: int, scope: String) -> Array:
	if scope == "self":
		return [seat_index]
	return board.get_neighbors(seat_index, scope)
