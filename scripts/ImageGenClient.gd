## ImageGenClient.gd
## 画像生成MCP（Gemini Imagen API）連携クライアント。
## GDScriptからHTTPリクエストでキャラクタースプライトを生成し、assets/sprites/ に保存する。
extends Node

# Gemini Imagen API エンドポイント
const API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
const MODEL = "imagen-3.0-generate-001"

# 環境変数から APIキーを取得
var _api_key: String = ""

# HTTPリクエストノード
var _http_request: HTTPRequest

# キュー（複数リクエストの順次処理）
var _request_queue: Array = []
var _is_processing: bool = false

# シグナル
signal sprite_generated(student_id: String, file_path: String)
signal sprite_generation_failed(student_id: String, error: String)

func _ready() -> void:
	_api_key = OS.get_environment("GEMINI_API_KEY")
	if _api_key.is_empty():
		push_warning("GEMINI_API_KEY not set. Image generation will be disabled.")

	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

# 転校生スプライトを生成してキューに追加する
func request_student_sprite(student_id: String, student_data: Dictionary) -> void:
	if _api_key.is_empty():
		push_warning("API key not set, skipping sprite generation for: " + student_id)
		return

	var prompt = _build_character_prompt(student_data)
	_request_queue.append({
		"student_id": student_id,
		"prompt": prompt,
		"output_path": "user://assets/sprites/" + student_id + "_48x48.png"
	})

	if not _is_processing:
		_process_next_request()

# スプライトファイルが存在するか確認する
func has_sprite(student_id: String) -> bool:
	var path = "user://assets/sprites/" + student_id + "_48x48.png"
	return FileAccess.file_exists(path)

# --- Private ---

# キャラクタープロンプトを構築する（DESIGN_POLICY.md §8 に準拠）
func _build_character_prompt(student_data: Dictionary) -> String:
	var name = student_data.get("name", "")
	var category = student_data.get("category", "honor")
	var tags = student_data.get("tags", [])

	# カテゴリ別の character_description と personality_adjective
	var desc_map = {
		"idol": "pink twin-tails, sparkly eyes, ribbon accessories",
		"honor": "short dark hair, glasses, tidy uniform",
		"yankee": "spiky dyed-brown hair, partially open collar, wristband",
		"entertainer": "wavy orange hair, wide grin, colorful bag",
		"wildcard": "black hair covering one eye, expressionless, simple uniform"
	}

	var adj_map = {
		"idol": "cheerful sparkling",
		"honor": "serious studious",
		"yankee": "confident cool",
		"entertainer": "energetic funny",
		"wildcard": "mysterious silent"
	}

	var character_description = desc_map.get(category, "short hair, school uniform")
	var personality_adjective = adj_map.get(category, "neutral")

	return (
		"Cute chibi anime character, 2-head proportion, %s, " % character_description +
		"Japanese school uniform (white shirt, navy skirt/pants), " +
		"thick black outline, flat colors, no gradient, pastel color palette, " +
		"white background, large expressive eyes, simple kawaii expression, " +
		"%s pose, no shading, clean vector-like style, " % personality_adjective +
		"192x192 pixels, game sprite style"
	)

# 次のリクエストを処理する
func _process_next_request() -> void:
	if _request_queue.is_empty():
		_is_processing = false
		return

	_is_processing = true
	var req = _request_queue[0]

	var url = "%s/%s:predict?key=%s" % [API_BASE, MODEL, _api_key]
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({
		"instances": [{"prompt": req["prompt"]}],
		"parameters": {
			"sampleCount": 1,
			"aspectRatio": "1:1"
		}
	})

	var err = _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("HTTP request failed for: " + req["student_id"])
		_request_queue.pop_front()
		sprite_generation_failed.emit(req["student_id"], "Request error: %d" % err)
		_process_next_request()

# HTTPリクエスト完了コールバック
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _request_queue.is_empty():
		return

	var req = _request_queue.pop_front()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("API request failed. Code: %d" % response_code)
		sprite_generation_failed.emit(req["student_id"], "HTTP error: %d" % response_code)
		_process_next_request()
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		sprite_generation_failed.emit(req["student_id"], "JSON parse error")
		_process_next_request()
		return

	var data = json.get_data()
	var predictions = data.get("predictions", [])
	if predictions.is_empty():
		sprite_generation_failed.emit(req["student_id"], "No predictions returned")
		_process_next_request()
		return

	# base64 画像データをデコードして保存
	var b64 = predictions[0].get("bytesBase64Encoded", "")
	if b64.is_empty():
		sprite_generation_failed.emit(req["student_id"], "No image data")
		_process_next_request()
		return

	var img_bytes = Marshalls.base64_to_raw(b64)
	var img = Image.new()
	if img.load_png_from_buffer(img_bytes) != OK:
		sprite_generation_failed.emit(req["student_id"], "Image decode error")
		_process_next_request()
		return

	# 192→48px にリサイズ
	img.resize(48, 48, Image.INTERPOLATE_LANCZOS)

	# 保存先ディレクトリを確保
	DirAccess.make_dir_recursive_absolute("user://assets/sprites/")

	var file_path = req["output_path"]
	img.save_png(file_path)

	sprite_generated.emit(req["student_id"], file_path)
	_process_next_request()
