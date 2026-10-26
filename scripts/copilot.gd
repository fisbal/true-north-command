extends Control
## Ask Claude: a help and correction panel inside the game. The player asks a question; Claude answers
## with what is happening in the mission (objective, recent radio log, scores) so it can explain an order,
## correct radio procedure, or say what the Captain's intent means. Uses the player's own Claude key,
## kept on this device only (user://claude.cfg). GDScript has no Anthropic SDK, so this calls the
## Messages API over HTTPS.

const API := "https://api.anthropic.com/v1/messages"
const MODEL := "claude-opus-5-5"
const KEY_FILE := "user://claude.cfg"

var main
var panel: PanelContainer
var title: Label
var answer: RichTextLabel
var scroll: ScrollContainer
var question: LineEdit
var ask_button: Button
var key_row: HBoxContainer
var key_edit: LineEdit
var forget_button: Button
var close_button: Button
var http: HTTPRequest
var history: Array = []
var was_paused := false


func T(en: String, fr: String) -> String:
	return main.T(en, fr)


func _init(m) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.08, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	panel = PanelContainer.new()
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	v.add_child(title)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	answer = RichTextLabel.new()
	answer.bbcode_enabled = true
	answer.fit_content = true
	answer.selection_enabled = true
	answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(answer)
	key_row = HBoxContainer.new()
	v.add_child(key_row)
	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit.custom_minimum_size = Vector2(0, 46)
	key_row.add_child(key_edit)
	var save := Button.new()
	save.name = "Save"
	save.custom_minimum_size = Vector2(0, 46)
	save.pressed.connect(_save_key)
	key_row.add_child(save)
	question = LineEdit.new()
	question.custom_minimum_size = Vector2(0, 46)
	question.text_submitted.connect(func(_t): _ask())
	v.add_child(question)
	var row := HBoxContainer.new()
	v.add_child(row)
	ask_button = Button.new()
	ask_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask_button.custom_minimum_size = Vector2(0, 46)
	ask_button.pressed.connect(_ask)
	row.add_child(ask_button)
	forget_button = Button.new()
	forget_button.custom_minimum_size = Vector2(0, 46)
	forget_button.pressed.connect(_forget_key)
	row.add_child(forget_button)
	close_button = Button.new()
	close_button.custom_minimum_size = Vector2(0, 46)
	close_button.pressed.connect(close_panel)
	row.add_child(close_button)
	http = HTTPRequest.new()
	http.timeout = 90.0
	http.request_completed.connect(_on_reply)
	add_child(http)
	hide()


func open_panel() -> void:
	was_paused = main.paused
	main.paused = true
	relabel()
	layout(main._canvas())
	show()
	(key_edit if _key() == "" else question).grab_focus()


func close_panel() -> void:
	hide()
	main.paused = was_paused


func relabel() -> void:
	title.text = T("✦ Ask Claude", "✦ Demander à Claude")
	key_edit.placeholder_text = T("Paste your Claude key (sk-ant-...)", "Collez votre clé Claude (sk-ant-...)")
	key_row.get_node("Save").text = T("Turn on", "Activer")
	question.placeholder_text = T("Ask about an order, the radio, the intent...", "Une question sur un ordre, la radio, l'intention...")
	ask_button.text = T("Ask", "Demander")
	forget_button.text = T("Forget my key", "Oublier ma clé")
	close_button.text = T("Close", "Fermer")
	var has_key := _key() != ""
	key_row.visible = not has_key
	question.visible = has_key
	ask_button.visible = has_key
	forget_button.visible = has_key
	if answer.text == "" or not has_key:
		answer.text = _intro(has_key)


func _intro(has_key: bool) -> String:
	if has_key:
		return T("Ask anything about the mission: what an order means, how to make a radio report, what the Captain would want. Claude sees your objective and the radio log.",
			"Posez n'importe quelle question sur la mission : le sens d'un ordre, comment faire un compte rendu radio, ce que voudrait le commandant. Claude voit votre objectif et le journal radio.")
	return T("Claude can explain orders and correct your radio procedure. It uses your own Claude key from console.anthropic.com, which stays on this device only.",
		"Claude peut expliquer les ordres et corriger votre procédure radio. Il utilise votre propre clé Claude (console.anthropic.com), qui reste sur cet appareil seulement.")


func layout(cv: Vector2) -> void:
	var w := minf(700.0, cv.x - 24.0)
	panel.custom_minimum_size = Vector2(w, 0)
	scroll.custom_minimum_size = Vector2(w - 20.0, clampf(cv.y - 330.0, 110.0, 380.0))


func _key() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(KEY_FILE) != OK:
		return ""
	return str(cfg.get_value("claude", "key", ""))


func _save_key() -> void:
	var k := key_edit.text.strip_edges()
	if k == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("claude", "key", k)
	cfg.save(KEY_FILE)
	key_edit.text = ""
	answer.text = ""
	relabel()
	question.grab_focus()


func _forget_key() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEY_FILE))
	history.clear()
	answer.text = ""
	relabel()


func _context() -> String:
	var lines: PackedStringArray = []
	lines.append("Mission: %d, era: %s, stage: %d, phase: %s" % [main.mission, main.era, main.stage, main.phase])
	lines.append("Objective: " + str(main.objective))
	lines.append("Scores (0-100): " + str(main.scores))
	if main.player:
		lines.append("Ship: %.1f kn, heading %03d" % [absf(main.player.speed), int(round(main.player.heading)) % 360])
	lines.append("Recent radio log:\n" + main.log_box.get_parsed_text().right(1500))
	return "\n".join(lines)


func _ask() -> void:
	var q := question.text.strip_edges()
	var key := _key()
	if q == "" or key == "" or http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	question.text = ""
	history.append({"role": "user", "content": q})
	while history.size() > 12:
		history.pop_front()
	answer.text = "[color=#f2c46d]" + q + "[/color]\n\n" + T("Claude is thinking...", "Claude réfléchit...")
	ask_button.disabled = true
	var system := ("You are the coach inside True North Command, a Canadian Armed Forces training game where the player is an Officer of the Watch "
		+ "in the Royal Canadian Navy. Help the player understand orders, the commander's intent, CAF orders format, radio procedure and ship handling, "
		+ "and correct their mistakes kindly and precisely. Keep answers short (under 150 words), practical, and about the game. "
		+ "All characters and ships are fictional; places, ranks and history are real. Answer in %s.\n\nCurrent game state:\n%s") % [
			"French (Canadian)" if main.lang == "fr" else "English", _context()]
	var body := JSON.stringify({"model": MODEL, "max_tokens": 1024, "system": system, "messages": history})
	var headers := PackedStringArray([
		"content-type: application/json", "x-api-key: " + key, "anthropic-version: 2023-06-01",
		"anthropic-dangerous-direct-browser-access: true"])
	if http.request(API, headers, HTTPClient.METHOD_POST, body) != OK:
		_show_error(0)


func _on_reply(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	ask_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		history.pop_back()
		_show_error(code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var text := ""
	if data is Dictionary:
		for block in data.get("content", []):
			if block.get("type") == "text":
				text += block.get("text", "")
	if text == "":
		history.pop_back()
		_show_error(code)
		return
	history.append({"role": "assistant", "content": text})
	var q: String = history[history.size() - 2]["content"]
	answer.text = "[color=#f2c46d]" + q.replace("[", "[lb]") + "[/color]\n\n" + text.replace("[", "[lb]")
	scroll.scroll_vertical = 0


func _show_error(code: int) -> void:
	var msg := T("Claude could not answer. Check your connection and try again.", "Claude n'a pas pu répondre. Vérifiez votre connexion et réessayez.")
	if code == 401 or code == 403:
		msg = T("This key was not accepted. Tap Forget my key and paste a new one.", "Cette clé n'a pas été acceptée. Touchez Oublier ma clé et collez-en une nouvelle.")
	elif code == 429 or code == 529:
		msg = T("Claude is busy right now. Wait a moment and try again.", "Claude est occupé. Attendez un instant et réessayez.")
	answer.text = "[color=#e07a6a]" + msg + "[/color]"
