## ParamStore.gd
## パラメータ集計・管理。AutoLoadとして登録される。
## 5種のパラメータ（study / romance / friendship / popularity / happening）を一元管理する。
extends Node

# パラメータ定義（params_definition.json から読み込み）
var param_defs: Array = []

# 現在のパラメータ値
var params: Dictionary = {}

# 一時的な差分（プレビュー用）
var _preview_deltas: Dictionary = {}

# シグナル
signal params_changed(new_params: Dictionary)
signal param_preview_updated(deltas: Dictionary)

func _ready() -> void:
	_load_param_definitions()
	_initialize_params()

# パラメータ定義JSONを読み込む
func _load_param_definitions() -> void:
	var path = "res://data/params_definition.json"
	if not FileAccess.file_exists(path):
		push_error("params_definition.json not found")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse params_definition.json")
		return

	param_defs = json.get_data().get("params", [])

# 初期値でパラメータを設定
func _initialize_params() -> void:
	for def in param_defs:
		params[def["id"]] = def.get("initial", 0)

# パラメータに差分を適用する
func apply_deltas(deltas: Dictionary) -> void:
	for param_id in deltas:
		if param_id in params:
			var def = _get_def(param_id)
			var min_val = def.get("min", 0) if def else 0
			var max_val = def.get("max", 100) if def else 100
			params[param_id] = clamp(params[param_id] + deltas[param_id], min_val, max_val)

	_update_happening()
	params_changed.emit(params.duplicate())

# happeningを他4パラメータの加重平均＋ランダム補正で更新
func _update_happening() -> void:
	var happening_def = _get_def("happening")
	if not happening_def or not happening_def.get("derived", false):
		return

	var weights = happening_def.get("weights", {
		"study": 0.25, "romance": 0.25, "friendship": 0.25, "popularity": 0.25
	})

	var weighted_sum = 0.0
	var total_weight = 0.0
	for param_id in weights:
		if param_id in params:
			weighted_sum += params[param_id] * weights[param_id]
			total_weight += weights[param_id]

	if total_weight > 0:
		var base = weighted_sum / total_weight
		# 既存のhappeningを一定割合で維持しながらブレンド
		params["happening"] = clamp(int(base * 0.7 + params["happening"] * 0.3), 0, 100)

# 指定パラメータの現在値を返す
func get_param(param_id: String) -> int:
	return params.get(param_id, 0)

# 全パラメータの現在値を返す
func get_all_params() -> Dictionary:
	return params.duplicate()

# プレビュー用の仮差分を設定（実際には反映しない）
func set_preview(deltas: Dictionary) -> void:
	_preview_deltas = deltas
	param_preview_updated.emit(deltas)

# プレビューをクリア
func clear_preview() -> void:
	_preview_deltas = {}
	param_preview_updated.emit({})

# プレビュー込みのパラメータを返す（表示用）
func get_preview_params() -> Dictionary:
	var preview = params.duplicate()
	for param_id in _preview_deltas:
		if param_id in preview:
			var def = _get_def(param_id)
			var min_val = def.get("min", 0) if def else 0
			var max_val = def.get("max", 100) if def else 100
			preview[param_id] = clamp(preview[param_id] + _preview_deltas[param_id], min_val, max_val)
	return preview

# セーブデータ用に現在値を辞書として返す
func get_save_data() -> Dictionary:
	return params.duplicate()

# セーブデータから復元する
func load_save_data(data: Dictionary) -> void:
	for param_id in data:
		if param_id in params:
			params[param_id] = data[param_id]
	params_changed.emit(params.duplicate())

# リセット（新規ゲーム）
func reset() -> void:
	_initialize_params()
	params_changed.emit(params.duplicate())

# --- Private ---

func _get_def(param_id: String) -> Dictionary:
	for def in param_defs:
		if def["id"] == param_id:
			return def
	return {}
