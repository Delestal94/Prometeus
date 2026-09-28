class_name HudResults
extends Node
## The end-of-run screen: score, breakdown, complaints and delivery photos.

## Set by Hud before this is added as its child.
var hud: Hud

const RESULT_PLAYER_COLORS: Array[Color] = [
	Color("83e2ba"), Color("f4c562"), Color("f47e6d"), Color("6db3d6"), Color("c9a0e0"),
]


func _ready() -> void:
	EventBus.run_ended.connect(_on_ended)


func set_hero(visible_: bool, score: int = 0, new_best: bool = false) -> void:
	var hero: Control = hud.score_label.get_parent().get_parent() as Control
	hero.visible = visible_
	hud.card.add_theme_constant_override("separation", 8 if visible_ else 14)
	hud.overlay_title.add_theme_font_size_override("font_size", 52 if visible_ else 62)
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
	# The results card stands alone: the run's HUD peeking around its edges
	# read as leftovers (HUD redesign 2026-09-28).
	hud.hud_layer.hide()
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
		hud.result_details.visible = false
		set_buttons(retry, false, false, true)
		return
	var success: bool = bool(results.get("delivered", false))
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
			intact) if success else String(results.get("reason", ""))
	# The rescues are the run's story: "Jarrón: 1 arreglo(s) en el camino".
	var stories: Array = results.get("stories", [])
	if not stories.is_empty():
		hud.overlay_body.text += "\n" + "\n".join(PackedStringArray(stories))
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	var chaos_line: String = tr("HUD_RESULT_CHAOS_BONUS") % chaos if chaos > 1.0 else ""
	var door_line: String = tr("HUD_RESULT_DOORS") % int(results.get("delivery_points",
			0)) if results.has("delivery_points") else ""
	if results.has("breakdown"):
		hud.overlay_stats.text = format_score_breakdown(results,
				score) + tr("HUD_RESULT_TEAM") % CrewProgression.team_money + best_line + client_line
	else:
		hud.overlay_stats.text = tr("HUD_RESULT_STATS") % [float(results.get("elapsed_seconds", 0.0)),
				int(results.get("cargo_points", 0)), int(results.get("time_bonus",
				0)), door_line, chaos_line, CrewProgression.team_money, best_line, client_line]
	_show_complaints(results.get("complaints", []))
	_show_photos()
	_show_result_details(results)
	set_buttons(retry, false, false, true)


func _show_result_details(results: Dictionary) -> void:
	for child: Node in hud.result_rows_box.get_children():
		child.queue_free()
	for entry: Dictionary in results.get("deliveries", []):
		_add_delivery_row(entry)
	_show_awards(results.get("awards", []))
	_show_route_event(results.get("route_event", {}))
	_show_unlock_progress()
	hud.result_details.visible = not hud.result_rows_box.get_children().is_empty() \
			or not hud.result_awards_label.text.is_empty() \
			or hud.result_event_label.visible \
			or hud.result_progress_label.visible


func _add_delivery_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	hud.result_rows_box.add_child(row)
	var trap_name: String = String(entry.get("trap", "PAQUETE"))
	var texture: Texture2D = UiTheme.trap_icon(trap_name)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(25, 25)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	else:
		var fallback: Label = UiTheme.label(row, "◆", 17, Hud.YELLOW, true)
		fallback.custom_minimum_size.x = 25
	var outcome: StringName = StringName(entry.get("outcome", &"missed"))
	var result_text: String = {
		&"delivered_ok": "INTACTO ✓",
		&"delivered_at_risk": "CON REPAROS !",
		&"delivered_ruined": "ARRUINADO ✕",
		&"missed": "SIN ENTREGA",
		&"lost": "PERDIDO ✕",
	}.get(outcome, "SIN ENTREGA")
	var label: Label = UiTheme.label(row, "Casa %d  ·  %s  ·  %s" % [int(entry.get("house", 0)) + 1, trap_name,
			result_text], 15, Hud.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(entry.get("photo", false)):
		UiTheme.tag(row, "FOTO ✓", UiTheme.SKY, -1.0, 13)


func _show_awards(awards: Array) -> void:
	var lines: PackedStringArray = []
	for award: Dictionary in awards:
		var peer: int = int(award.get("peer", 0))
		var color: Color = RESULT_PLAYER_COLORS[posmod(peer, RESULT_PLAYER_COLORS.size())]
		var player_name: String = "Vos" if peer == NetworkManager.local_id() else "Jugador %d" % peer
		lines.append("[color=#%s]●[/color] [b]%s[/b]  %s" % [color.to_html(false), String(award.get("title", "Premio")),
				player_name])
	hud.result_awards_label.text = "\n".join(lines)
	hud.result_awards_label.visible = not lines.is_empty()


func _show_route_event(route_event: Dictionary) -> void:
	hud.result_event_label.visible = not route_event.is_empty()
	if route_event.is_empty():
		return
	hud.result_event_label.text = "Evento: %s\n%s" % [
		String(route_event.get("title", "Evento de ruta")),
		"RESUELTO ✓" if bool(route_event.get("success", false)) else "FALLIDO ✕",
	]


func _show_unlock_progress() -> void:
	var progress: Dictionary = UnlockManager.next_unlock_progress()
	hud.result_progress_label.visible = not progress.is_empty()
	hud.result_progress_bar.visible = not progress.is_empty()
	if progress.is_empty():
		return
	var missing_deliveries: int = maxi(int(progress["target_deliveries"]) - int(progress["current_deliveries"]), 0)
	var missing_score: int = maxi(int(progress["target_score"]) - int(progress["current_score"]), 0)
	var needs: PackedStringArray = []
	if missing_deliveries > 0:
		needs.append("%d entrega%s" % [missing_deliveries, "" if missing_deliveries == 1 else "s"])
	if missing_score > 0:
		needs.append("%d pts" % missing_score)
	# "Te falta 1 entrega", but "Te faltan 2 entregas" or "... 1 entrega y 30 pts".
	var singular: bool = needs.size() == 1 and missing_deliveries == 1
	hud.result_progress_label.text = "Te %s %s para %s" % ["falta" if singular else "faltan", " y ".join(needs),
		String(progress["title"])]
	hud.result_progress_bar.value = float(progress["progress"]) * 100.0


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
