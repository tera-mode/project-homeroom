## StudentDB.gd
## 転校生データの読み込み・検索。AutoLoadとして登録される。
## data/students.json を読み込み、抽選・検索機能を提供する。
extends Node

# 全転校生データ
var _all_students: Array = []

# 現在の周回数（unlock_cycle フィルタに使用）
var current_cycle: int = 1

# カテゴリ別出現重み
const CATEGORY_WEIGHTS: Dictionary = {
	"honor": 3.0,
	"idol": 2.0,
	"yankee": 2.0,
	"entertainer": 1.0,
	"wildcard": 0.3
}

func _ready() -> void:
	_load_students()

# students.json を読み込む
func _load_students() -> void:
	var path = "res://data/students.json"
	if not FileAccess.file_exists(path):
		push_error("students.json not found")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("Failed to parse students.json: " + json.get_error_message())
		return

	_all_students = json.get_data().get("students", [])

# IDで転校生データを取得する
func get_student_by_id(student_id: String) -> Dictionary:
	for student in _all_students:
		if student["id"] == student_id:
			return student.duplicate(true)
	return {}

# 現在の周回数で解放されているキャラ一覧を返す
func get_available_students() -> Array:
	var available = []
	for student in _all_students:
		if student.get("unlock_cycle", 1) <= current_cycle:
			available.append(student)
	return available

# カテゴリと出現重みを考慮してランダムに1体抽選する
func draw_random_student(already_placed: Array = []) -> Dictionary:
	var pool = get_available_students()

	# 既に配置済みのキャラは除外
	pool = pool.filter(func(s): return not (s["id"] in already_placed))

	if pool.is_empty():
		# 全員配置済みなら制限なしで抽選
		pool = get_available_students()

	if pool.is_empty():
		return {}

	# 重み付きランダム抽選
	var total_weight = 0.0
	var weights = []
	for student in pool:
		var category = student.get("category", "honor")
		var rarity = student.get("rarity", 1)
		var w = CATEGORY_WEIGHTS.get(category, 1.0) / rarity
		weights.append(w)
		total_weight += w

	var roll = randf() * total_weight
	var cumulative = 0.0
	for i in range(pool.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			return pool[i].duplicate(true)

	return pool[pool.size() - 1].duplicate(true)

# タグで転校生を検索する
func get_students_by_tag(tag: String) -> Array:
	var result = []
	for student in _all_students:
		if tag in student.get("tags", []):
			result.append(student.duplicate(true))
	return result

# カテゴリで転校生を検索する
func get_students_by_category(category: String) -> Array:
	var result = []
	for student in _all_students:
		if student.get("category", "") == category:
			result.append(student.duplicate(true))
	return result

# 全転校生IDリストを返す
func get_all_student_ids() -> Array:
	return _all_students.map(func(s): return s["id"])

# 周回数を設定する
func set_cycle(cycle: int) -> void:
	current_cycle = cycle
