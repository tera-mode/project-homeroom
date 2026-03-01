## FriendshipManager.gd
## AutoLoad: キャラ間双方向仲良し度と関係性ラベルを管理する
extends Node

# _friendships[from_id][to_id] = int
var _friendships: Dictionary = {}

func init_for_character(char_id: String, all_existing_ids: Array) -> void:
	if not _friendships.has(char_id):
		_friendships[char_id] = {}
	for other_id in all_existing_ids:
		if other_id == char_id:
			continue
		if not _friendships[char_id].has(other_id):
			_friendships[char_id][other_id] = 0
		if not _friendships.has(other_id):
			_friendships[other_id] = {}
		if not _friendships[other_id].has(char_id):
			_friendships[other_id][char_id] = 0

func get_friendship(from_id: String, to_id: String) -> int:
	return _friendships.get(from_id, {}).get(to_id, 0)

func apply_friendship_delta(from_id: String, to_id: String, delta: int) -> void:
	if not _friendships.has(from_id):
		_friendships[from_id] = {}
	if not _friendships[from_id].has(to_id):
		_friendships[from_id][to_id] = 0
	_friendships[from_id][to_id] += delta

# 関係性ラベルを返す（zekko / bimyo / "" / tomodachi / shinyu / koibito）
func get_relationship_label(id_a: String, id_b: String, gender_a: String, gender_b: String) -> String:
	var a_to_b = get_friendship(id_a, id_b)
	var b_to_a = get_friendship(id_b, id_a)
	var min_val = min(a_to_b, b_to_a)
	var max_val = max(a_to_b, b_to_a)

	if min_val <= -10:
		return "zekko"
	if min_val <= -3:
		return "bimyo"
	if min_val >= 10:
		return "shinyu" if gender_a == gender_b else "koibito"
	if max_val >= 10 and min_val >= 3:
		return "tomodachi"
	if min_val >= 3:
		return "tomodachi"
	return ""

func get_all_relationships_for(char_id: String) -> Dictionary:
	return _friendships.get(char_id, {}).duplicate()

func remove_character(char_id: String) -> void:
	_friendships.erase(char_id)
	for from_id in _friendships:
		_friendships[from_id].erase(char_id)

func get_save_data() -> Dictionary:
	return _friendships.duplicate(true)

func load_save_data(data: Dictionary) -> void:
	_friendships = data.duplicate(true)

func reset() -> void:
	_friendships = {}
