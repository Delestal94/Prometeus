extends "res://scripts/ui/hud/hud_cargo_panel.gd"
## Context-sensitive teaching: interaction/lid prompts, role hints and the
## short keyboard/gamepad cheat sheet.


func _refresh_shortcuts() -> void:
	if shortcut_label == null:
		return
	var learning: bool = get_tree().paused or not RunManager.is_running or RunManager.elapsed_seconds < SHORTCUT_VISIBLE_SECONDS
	var target: float = 1.0 if learning else 0.25
	var pill: Control = shortcut_label.get_parent() as Control
	pill.modulate.a = move_toward(pill.modulate.a, target, 0.02)


func _refresh_shortcut_text() -> void:
	var items: PackedStringArray = [
		_key("F  celular", "LB  celular"),
		_key("Click rueda  ping", "D-pad arriba  ping"),
		_key("C  centrar vista", "Clic stick der.  centrar vista"),
		_key("%s  mirar atrás" % GameSettings.binding_label(&"look_back"), "Clic stick izq.  mirar atrás"),
		_key("Esc  pausa", "Start  pausa"),
	]
	if _can_restart():
		items.append(_key("Mantener R  reiniciar", "Mantener Y  reiniciar"))
	shortcut_label.text = UiTheme.keycaps("   ·   ".join(items), true)


func _can_restart() -> bool:
	return not NetworkManager.is_online() or NetworkManager.is_host()


func _refresh_role() -> void:
	_role = _local_role()


func _local_role() -> int:
	var level: Node = get_parent()
	if level == null:
		return Role.ON_FOOT
	var player: Variant = level.get(&"local_player")
	if not is_instance_valid(player):
		return Role.ON_FOOT
	var seat: String = String((player as Node).get(&"seat_node_path"))
	if seat.is_empty():
		return Role.ON_FOOT
	return Role.DRIVER if seat.contains("DriverEyePoint") else Role.PASSENGER


func _flash_hint(text: String, seconds: float) -> void:
	_hint_override = text
	_hint_override_seconds = seconds


func _refresh_hint(delta: float) -> void:
	if _hint_override_seconds > 0.0:
		_hint_override_seconds -= delta
		hint_label.text = "[b]%s[/b]" % _hint_override
		hint_label.add_theme_color_override("default_color", STATE_TEXT[1])
		return
	hint_label.text = UiTheme.keycaps(_base_hint())
	hint_label.add_theme_color_override("default_color", MUTED)


func _base_hint() -> String:
	var waiting: bool = not RunManager.is_running and RunManager.results.is_empty()
	match _role:
		Role.DRIVER:
			if waiting:
				return "Todavía no hay carga a bordo  ·  %s bajarte a buscar un paquete" % _key("E", "A")
			return _key(
				"W/S  acelerar y frenar   ·   A/D  girar   ·   Espacio  freno de mano   ·   H  bocina   ·   E  bajarte",
				"RT  acelerar   ·   LT  frenar   ·   Stick izq.  girar   ·   X  freno de mano   ·   B  bocina   ·   A  bajarte")
		Role.PASSENGER:
			return _key(
				"Click izq. (mantener)  cuidar tu paquete   ·   WASD  secuencias   ·   E  bajarte",
				"RT (mantener)  cuidar tu paquete   ·   Stick izq.  secuencias   ·   A  bajarte")
	if waiting:
		return _key(
			"WASD  caminar   ·   Espacio  saltar   ·   E  agarrar / dejar   ·   Q  soltar paquete",
			"Stick izq.  caminar   ·   X  saltar   ·   A  agarrar / dejar")
	return _key(
		"WASD  caminar   ·   E  interactuar   ·   F  sacar una foto de la entrega",
		"Stick izq.  caminar   ·   A  interactuar   ·   LB  sacar una foto de la entrega")


func _on_interaction_prompt(prompt: String) -> void:
	_interaction_prompt = prompt
	_render_interaction_prompt()


func _on_carry_changed(carrying: bool) -> void:
	_carrying = carrying
	_render_interaction_prompt()


func _render_interaction_prompt() -> void:
	var lines: PackedStringArray = []
	if not _interaction_prompt.is_empty():
		lines.append("[ %s ]  %s" % [_key("E", "A"), _interaction_prompt])
	if _carrying:
		lines.append("[ %s ]  Soltar paquete" % _key("Q", "B"))
	if not _lid_action.is_empty():
		lines.append("[ %s ]  %s" % [_key("T", "D-pad abajo"), _lid_action])
	if not _lid_inside.is_empty():
		lines.append("Adentro:  %s" % _lid_inside)
	interaction_label.text = "\n".join(lines)


func _on_lid_hint_changed(action: String, inside: String) -> void:
	_lid_action = action
	_lid_inside = inside
	_render_interaction_prompt()


func _on_damage(_id: StringName, damage: float) -> void:
	_flash_hint("¡Golpe!  −%d de integridad. Bajá la velocidad antes del próximo obstáculo." % roundi(damage), 2.5)


func _on_delivery(in_zone: bool, stopped: float) -> void:
	if in_zone:
		_flash_hint("Mantené la camioneta detenida…" if stopped > 0.0 else "¡Llegaste! Frená dentro de la zona marcada para entregar.", 0.25)
	elif in_delivery:
		_flash_hint("Volvé a la zona de entrega y detené la camioneta.", 3.0)
	in_delivery = in_zone
