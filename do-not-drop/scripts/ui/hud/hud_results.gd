extends "res://scripts/ui/hud/hud_notices.gd"
## Results overlay: score hero, checkable breakdown, delivery summary,
## complaints and the end-of-run photo strip.


func _set_hero(visible_: bool, score: int = 0, new_best: bool = false) -> void:
	var hero: Control = score_label.get_parent().get_parent() as Control
	hero.visible = visible_
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
	_set_buttons(retry, false, false, true)


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
	return "\n".join(lines) if not lines.is_empty() else "Llegaste, y eso ya es algo."


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
