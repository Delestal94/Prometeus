extends "res://scripts/ui/hud/hud_notices.gd"
## Results overlay: score hero, checkable breakdown, delivery summary,
## complaints and the end-of-run photo strip.

const RESULT_PLAYER_COLORS: Array[Color] = [
	Color("83e2ba"), Color("f4c562"), Color("f47e6d"), Color("6db3d6"), Color("c9a0e0"),
]


func _set_hero(visible_: bool, score: int = 0, new_best: bool = false) -> void:
	var hero: Control = score_label.get_parent().get_parent() as Control
	hero.visible = visible_
	card.add_theme_constant_override("separation", 8 if visible_ else 14)
	overlay_title.add_theme_font_size_override("font_size", 52 if visible_ else 62)
	score_label.text = "%d PTS" % score
	record_label.get_parent().get_parent().visible = new_best


func _set_buttons(primary: String, restart: bool, options: bool, menu: bool) -> void:
	action_button.visible = not primary.is_empty()
	action_button.text = primary
	second_button.visible = restart and _can_restart()
	options_button.visible = options
	menu_button.visible = menu
	var first: Button = action_button if action_button.visible else menu_button
	first.grab_focus()


func _on_ended(score: int, results: Dictionary) -> void:
	_soft_pause = false
	_clear_all_notices()
	overlay_mode = "results"
	overlay.show()
	economy_label.hide()
	overlay_kicker.text = "RESULTADO"
	var new_best: bool = bool(results.get("is_new_best", false))
	_set_hero(true, score, new_best)
	var best_line: String = "" if new_best else "\nRécord: %d pts" % int(results.get("best_score", 0))
	var retry: String = "Volver a intentar" if _can_restart() else ""
	var client_line: String = "" if _can_restart() else "\n\nSolo el anfitrión puede reiniciar. Para otra vuelta, volvé al menú y unite de nuevo a la sala."
	if results.has("distance_traveled"):
		overlay_title.text = "FIN DEL RECORRIDO"
		overlay_body.text = String(results["reason"])
		overlay_stats.text = "%.0f m recorridos   ·   %.1f s\nEquipo: $%d%s%s" % [float(results["distance_traveled"]), results["elapsed_seconds"], CrewProgression.team_money, best_line, client_line]
		complaints_label.visible = false
		photo_strip.visible = false
		result_details.visible = false
		_set_buttons(retry, false, false, true)
		return
	var success: bool = results["delivered"]
	var total: int = int(results.get("cargo_total", 0))
	var intact: int = int(results.get("cargo_intact", 0))
	var ruined: int = int(results.get("cargo_ruined", 0))
	var delivered_doors: int = int(results.get("houses_delivered", 0))
	var missed_doors: int = int(results.get("houses_missed", 0))
	if not success:
		overlay_title.text = "OTRA VUELTA"
	elif delivered_doors == 0 and missed_doors > 0:
		overlay_title.text = "RUTA TERMINADA"
	else:
		overlay_title.text = "¡ENTREGADO!"
	overlay_body.text = _delivery_summary(delivered_doors, missed_doors, total, ruined, intact) if success else String(results["reason"])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	var chaos_line: String = "\nBonus por caos compartido: x%.1f" % chaos if chaos > 1.0 else ""
	var door_line: String = "\nPuertas: %d pts" % int(results.get("delivery_points", 0)) if results.has("delivery_points") else ""
	if results.has("breakdown"):
		overlay_stats.text = format_score_breakdown(results, score) + "\nEquipo: $%d" % CrewProgression.team_money + best_line + client_line
	else:
		overlay_stats.text = "En ruta: %.1f s\nCarga: %d pts   +   Rapidez: %d pts%s%s\nEquipo: $%d%s%s" % [results["elapsed_seconds"], results["cargo_points"], results["time_bonus"], door_line, chaos_line, CrewProgression.team_money, best_line, client_line]
	_show_complaints(results.get("complaints", []))
	_show_photos()
	_show_result_details(results)
	_set_buttons(retry, false, false, true)


func _show_result_details(results: Dictionary) -> void:
	for child: Node in result_rows_box.get_children():
		child.queue_free()
	for entry: Dictionary in results.get("deliveries", []):
		_add_delivery_row(entry)
	_show_awards(results.get("awards", []))
	_show_route_event(results.get("route_event", {}))
	_show_unlock_progress()
	result_details.visible = not result_rows_box.get_children().is_empty() \
			or not result_awards_label.text.is_empty() \
			or result_event_label.visible \
			or result_progress_label.visible


func _add_delivery_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	result_rows_box.add_child(row)
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
		var fallback: Label = UiTheme.label(row, "◆", 17, YELLOW, true)
		fallback.custom_minimum_size.x = 25
	var outcome: StringName = StringName(entry.get("outcome", &"missed"))
	var result_text: String = {
		&"delivered_ok": "INTACTO ✓",
		&"delivered_at_risk": "CON REPAROS !",
		&"delivered_ruined": "ARRUINADO ✕",
		&"missed": "SIN ENTREGA",
	}.get(outcome, "SIN ENTREGA")
	var label: Label = UiTheme.label(row, "Casa %d  ·  %s  ·  %s" % [int(entry.get("house", 0)) + 1, trap_name, result_text], 15, INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(entry.get("photo", false)):
		UiTheme.tag(row, "FOTO ✓", UiTheme.SKY, -1.0, 13)


func _show_awards(awards: Array) -> void:
	var lines: PackedStringArray = []
	for award: Dictionary in awards:
		var peer: int = int(award.get("peer", 0))
		var color: Color = RESULT_PLAYER_COLORS[posmod(peer, RESULT_PLAYER_COLORS.size())]
		var player_name: String = "Vos" if peer == NetworkManager.local_id() else "Jugador %d" % peer
		lines.append("[color=#%s]●[/color] [b]%s[/b]  %s" % [color.to_html(false), String(award.get("title", "Premio")), player_name])
	result_awards_label.text = "\n".join(lines)
	result_awards_label.visible = not lines.is_empty()


func _show_route_event(route_event: Dictionary) -> void:
	result_event_label.visible = not route_event.is_empty()
	if route_event.is_empty():
		return
	result_event_label.text = "Evento: %s\n%s" % [
		String(route_event.get("title", "Evento de ruta")),
		"RESUELTO ✓" if bool(route_event.get("success", false)) else "FALLIDO ✕",
	]


func _show_unlock_progress() -> void:
	var progress: Dictionary = UnlockManager.next_unlock_progress()
	result_progress_label.visible = not progress.is_empty()
	result_progress_bar.visible = not progress.is_empty()
	if progress.is_empty():
		return
	var missing_deliveries: int = maxi(int(progress["target_deliveries"]) - int(progress["current_deliveries"]), 0)
	var missing_score: int = maxi(int(progress["target_score"]) - int(progress["current_score"]), 0)
	var needs: PackedStringArray = []
	if missing_deliveries > 0:
		needs.append("%d entrega%s" % [missing_deliveries, "" if missing_deliveries == 1 else "s"])
	if missing_score > 0:
		needs.append("%d pts" % missing_score)
	result_progress_label.text = "Te faltan %s para %s" % [" y ".join(needs), String(progress["title"])]
	result_progress_bar.value = float(progress["progress"]) * 100.0


static func format_score_breakdown(results: Dictionary, score: int) -> String:
	var lines: PackedStringArray = ["En ruta: %.1f s" % float(results.get("elapsed_seconds", 0.0))]
	for line: Dictionary in results.get("breakdown", []):
		var points: int = int(line["points"])
		lines.append("%s   %s%d" % [String(line["label"]), "+" if points >= 0 else "−", absi(points)])
	var chaos: float = float(results.get("chaos_multiplier", 1.0))
	if chaos > 1.0:
		lines.append("Caos compartido   ×%.1f" % chaos)
	lines.append("Total   %d pts" % score)
	return "\n".join(lines)


func _delivery_summary(delivered_doors: int, missed_doors: int, aboard: int, ruined: int, intact: int) -> String:
	var lines: PackedStringArray = []
	if delivered_doors > 0:
		lines.append("Entregaste en %d puerta%s." % [delivered_doors, "" if delivered_doors == 1 else "s"])
	if missed_doors > 0:
		lines.append("1 vecino se quedó esperando." if missed_doors == 1 else "%d vecinos se quedaron esperando." % missed_doors)
	if aboard > 0:
		var back: int = aboard - ruined
		if back == 1:
			lines.append("Volvió 1 paquete en la furgoneta%s." % (", intacto" if intact >= 1 else ""))
		elif back > 1:
			lines.append("Volvieron %d paquetes en la furgoneta, %d intactos." % [back, intact])
	return " ".join(lines) if not lines.is_empty() else "Llegaste, y eso ya es algo."


func _show_complaints(complaints: Array) -> void:
	if complaints.is_empty():
		complaints_label.visible = false
		return
	var lines: PackedStringArray = []
	for complaint: Dictionary in complaints:
		var house: int = int(complaint["house"]) + 1
		if bool(complaint["dismissed"]):
			lines.append("Casa %d reclamó que llegó roto — les mostraste la foto. Caso cerrado." % house)
		else:
			lines.append("Casa %d reclamó que llegó roto y no tenías foto. Te lo descuentan." % house)
	complaints_label.text = "\n".join(lines)
	complaints_label.visible = true


func _show_photos() -> void:
	for child: Node in photo_strip.get_children():
		child.queue_free()
	var photos: Dictionary = RunManager.delivery_photos
	if photos.is_empty():
		photo_strip.visible = false
		return
	var houses: Array = photos.keys()
	houses.sort()
	for index: int in range(houses.size()):
		var house: int = houses[index]
		var frame := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = UiTheme.WHITE
		style.border_color = INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.set_content_margin_all(6)
		style.content_margin_bottom = 22
		style.shadow_color = INK
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
		photo_strip.add_child(frame)
	photo_strip.visible = true
