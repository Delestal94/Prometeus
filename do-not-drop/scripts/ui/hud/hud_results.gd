class_name HudResults
extends Node
## The end-of-run screen: score, breakdown, complaints and delivery photos.

## Set by Hud before this is added as its child.
var hud: Hud


func _ready() -> void:
	EventBus.run_ended.connect(_on_ended)


func set_hero(visible_: bool, score: int = 0, new_best: bool = false) -> void:
	var hero: Control = hud.score_label.get_parent().get_parent() as Control
	hero.visible = visible_
	hud.score_label.text = tr("HUD_POINTS") % score
	hud.record_label.get_parent().get_parent().visible = new_best


func set_buttons(primary: String, restart: bool, options: bool, menu: bool) -> void:
	hud.action_button.visible = not primary.is_empty()
	hud.action_button.text = primary
	hud.second_button.visible = restart and hud.prompts.can_restart()
	hud.options_button.visible = options
	hud.menu_button.visible = menu
	var first: Button = hud.action_button if hud.action_button.visible else hud.menu_button
	first.grab_focus()


func _on_ended(score: int, results: Dictionary) -> void:
	hud.soft_pause = false
	hud.notices.clear_all_notices()
	hud.overlay_mode = "results"
	hud.overlay.show()
	hud.set_economy_visible(false)
	hud.overlay_kicker.text = "RESULTADO"
	var new_best: bool = bool(results.get("is_new_best", false))
	set_hero(true, score, new_best)
	var best_line: String = "" if new_best else tr("HUD_RESULT_RECORD") % int(results.get("best_score", 0))
	var retry: String = tr("HUD_RETRY") if hud.prompts.can_restart() else ""
	var client_line: String = "" if hud.prompts.can_restart() else tr("HUD_RESULT_GUEST_NOTE")
	if results.has("distance_traveled"):
		hud.overlay_title.text = tr("HUD_RESULT_ENDLESS_TITLE")
		hud.overlay_body.text = String(results["reason"])
		hud.overlay_stats.text = tr("HUD_RESULT_ENDLESS_STATS") % [float(results["distance_traveled"]), results["elapsed_seconds"], CrewProgression.team_money, best_line, client_line]
		hud.complaints_label.visible = false
		hud.photo_strip.visible = false
		set_buttons(retry, false, false, true)
		return
	var success: bool = results["delivered"]
	var total: int = int(results.get("cargo_total", 0))
	var intact: int = int(results.get("cargo_intact", 0))
	var ruined: int = int(results.get("cargo_ruined", 0))
	var delivered_doors: int = int(results.get("houses_delivered", 0))
	var missed_doors: int = int(results.get("houses_missed", 0))
	if not success:
		hud.overlay_title.text = tr("HUD_RESULT_FAILED_TITLE")
	elif delivered_doors == 0 and missed_doors > 0:
		hud.overlay_title.text = tr("HUD_RESULT_FINISHED_TITLE")
	else:
		hud.overlay_title.text = tr("HUD_RESULT_DELIVERED_TITLE")
	hud.overlay_body.text = _delivery_summary(delivered_doors, missed_doors, total, ruined,
			intact) if success else String(results["reason"])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	var chaos_line: String = tr("HUD_RESULT_CHAOS_BONUS") % chaos if chaos > 1.0 else ""
	var door_line: String = tr("HUD_RESULT_DOORS") % int(results.get("delivery_points",
			0)) if results.has("delivery_points") else ""
	if results.has("breakdown"):
		hud.overlay_stats.text = format_score_breakdown(results,
				score) + tr("HUD_RESULT_TEAM") % CrewProgression.team_money + best_line + client_line
	else:
		hud.overlay_stats.text = tr("HUD_RESULT_STATS") % [results["elapsed_seconds"], results["cargo_points"], results["time_bonus"], door_line, chaos_line, CrewProgression.team_money, best_line, client_line]
	_show_complaints(results.get("complaints", []))
	_show_photos()
	set_buttons(retry, false, false, true)


static func format_score_breakdown(results: Dictionary, score: int) -> String:
	var lines: PackedStringArray = [TranslationServer.translate("HUD_RESULT_ON_ROAD") % float(results.get("elapsed_seconds", 0.0))]
	for line: Dictionary in results.get("breakdown", []):
		var points: int = int(line["points"])
		lines.append("%s   %s%d" % [String(line["label"]), "+" if points >= 0 else "−", absi(points)])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	if chaos > 1.0:
		lines.append(TranslationServer.translate("HUD_RESULT_CHAOS_LINE") % chaos)
	lines.append(TranslationServer.translate("HUD_RESULT_TOTAL") % score)
	return "\n".join(lines)


func _delivery_summary(delivered_doors: int, missed_doors: int, aboard: int, ruined: int, intact: int) -> String:
	var lines: PackedStringArray = []
	if delivered_doors > 0:
		lines.append((tr("HUD_RESULT_DOORS_ONE") if delivered_doors == 1 else tr("HUD_RESULT_DOORS_MANY")) % delivered_doors)
	if missed_doors > 0:
		lines.append(tr("HUD_RESULT_MISSED_ONE") if missed_doors == 1 else tr("HUD_RESULT_MISSED_MANY") % missed_doors)
	if aboard > 0:
		var back: int = aboard - ruined
		if back == 1:
			lines.append(tr("HUD_RESULT_BACK_ONE") % (tr("HUD_RESULT_INTACT_SUFFIX") if intact >= 1 else ""))
		elif back > 1:
			lines.append(tr("HUD_RESULT_BACK_MANY") % [back, intact])
	return "\n".join(lines) if not lines.is_empty() else tr("HUD_RESULT_ARRIVED")


func _show_complaints(complaints: Array) -> void:
	if complaints.is_empty():
		hud.complaints_label.visible = false
		return
	var lines: PackedStringArray = []
	for complaint: Dictionary in complaints:
		var house: int = int(complaint["house"]) + 1
		if bool(complaint["dismissed"]):
			lines.append(tr("HUD_COMPLAINT_SETTLED") % house)
		else:
			lines.append(tr("HUD_COMPLAINT_PAID") % house)
	hud.complaints_label.text = "\n".join(lines)
	hud.complaints_label.visible = true


func _show_photos() -> void:
	for child: Node in hud.photo_strip.get_children():
		child.queue_free()
	var photos: Dictionary = RunManager.delivery_photos
	if photos.is_empty():
		hud.photo_strip.visible = false
		return
	var houses: Array = photos.keys()
	houses.sort()
	for index: int in range(houses.size()):
		var house: int = houses[index]
		var frame := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = UiTheme.WHITE
		style.border_color = Hud.INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.set_content_margin_all(6)
		style.content_margin_bottom = 22
		style.shadow_color = Hud.INK
		style.shadow_size = 1
		style.shadow_offset = Vector2(0, 4)
		frame.add_theme_stylebox_override("panel", style)
		frame.rotation_degrees = [-3.0, 2.0, -1.5, 3.0][index % 4]
		var thumbnail := TextureRect.new()
		thumbnail.texture = photos[house]
		thumbnail.custom_minimum_size = Vector2(160, 90)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(thumbnail)
		hud.photo_strip.add_child(frame)
	hud.photo_strip.visible = true
