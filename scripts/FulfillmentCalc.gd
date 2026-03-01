## FulfillmentCalc.gd
## AutoLoad: 充実度の毎日計算・テスト結果反映・転校判定
extends Node

# 関係性ラベルごとの充実度変動
const LABEL_DELTA: Dictionary = {
	"shinyu":    3,
	"koibito":   3,
	"tomodachi": 1,
	"bimyo":    -1,
	"zekko":    -3,
	"":          0
}

# 当日の充実度変動量を計算する（関係性の合算）
func calc_daily_fulfillment_delta(char_id: String) -> int:
	var state = CharacterState.get_state(char_id)
	if state.is_empty():
		return 0

	var total = 0
	var gender_a = state.get("gender", "male")

	for other_id in CharacterState.get_all_active_ids():
		if other_id == char_id:
			continue
		var other_state = CharacterState.get_state(other_id)
		var gender_b = other_state.get("gender", "male")
		var label = FriendshipManager.get_relationship_label(char_id, other_id, gender_a, gender_b)
		total += LABEL_DELTA.get(label, 0)

	return total

# テスト結果を充実度に反映する（合格+5 / 不合格-5）
func apply_test_result(char_id: String, passed: bool) -> void:
	CharacterState.apply_fulfillment_delta(char_id, 5 if passed else -5)

# 充実度 ≤ -10 のプレイヤー以外のキャラIDを返す
func get_transfer_candidates(player_id: String) -> Array:
	var candidates = []
	for char_id in CharacterState.get_all_active_ids():
		if char_id == player_id:
			continue
		if CharacterState.get_state(char_id).get("fulfillment", 0) <= -10:
			candidates.append(char_id)
	return candidates
