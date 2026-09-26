extends "res://scripts/ui/hud/hud_prompts.gd"
## Short-lived HUD notices: pings, toasts, route events, cards/merit and
## the cosmetic fade used around abrupt camera changes.

const PING_DISPLAY_SECONDS: float = 2.5
const EVENT_DISPLAY_SECONDS: float = 6.0


func _on_ping(peer_id: int, world_position: Vector3, label: String) -> void:
	var who: String = "Vos" if peer_id == NetworkManager.local_id() else "Jugador %d" % peer_id
	_toast("%s  %s:  %s" % [_ping_arrow(world_position), who, label], 40)
	ping_label.text = ""
	ping_indicator.text = ""
	ping_seconds_left = PING_DISPLAY_SECONDS
	if peer_id != NetworkManager.local_id():
		_mark_pinger(peer_id)


func _mark_pinger(peer_id: int) -> void:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() != peer_id or not player is Node3D:
			continue
		var old: Node = player.get_node_or_null(^"PingMarker")
		if old != null:
			old.free()
		var marker := Label3D.new()
		marker.name = "PingMarker"
		marker.text = "!"
		marker.font = load(UiTheme.DISPLAY_FONT_PATH)
		marker.font_size = 110
		marker.outline_size = 18
		marker.modulate = UiTheme.YELLOW
		marker.outline_modulate = UiTheme.INK
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.fixed_size = true
		marker.pixel_size = 0.0009
		marker.position = Vector3(0.0, 2.25, 0.0)
		player.add_child(marker)
		var tween := marker.create_tween()
		tween.tween_interval(PING_DISPLAY_SECONDS - 0.6)
		tween.tween_property(marker, ^"modulate:a", 0.0, 0.6)
		tween.tween_callback(marker.queue_free)


func _ping_arrow(world_position: Vector3) -> String:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return "PING"
	var local: Vector3 = camera.global_transform.basis.inverse() * (world_position - camera.global_position)
	if absf(local.x) > absf(local.y):
		return "→" if local.x > 0.0 else "←"
	return "↓" if local.y > 0.0 else "↑"


func _on_quick_fade_requested(seconds: float) -> void:
	var half: float = maxf(seconds * 0.5, 0.01)
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, ^"color:a", 1.0, half)
	tween.tween_property(fade_rect, ^"color:a", 0.0, half)


func _on_team_money_changed(amount: int) -> void:
	economy_label.text = "$%d" % amount


func _on_merit_changed(peer_id: int, total: int) -> void:
	if peer_id == NetworkManager.local_id():
		var gained: int = maxi(total - _local_merit_total, 0)
		_local_merit_total = total
		_toast("Mérito +%d  ·  total %d" % [gained, total])


func _on_card_changed(peer_id: int, card_id: int) -> void:
	if peer_id != NetworkManager.local_id():
		return
	_refresh_card()
	if card_id >= 0:
		_toast("Carta obtenida: %s" % CrewProgression.card_name(card_id))


func _refresh_card() -> void:
	if card_label == null:
		return
	var card_id: int = int(CrewProgression.cards.get(NetworkManager.local_id(), -1))
	card_label.visible = card_id >= 0
	if card_id < 0:
		card_label.text = ""
		return
	var action: String = GameSettings.prompt("%s  usar" % GameSettings.binding_label(&"use_card"), "D-pad izquierda  usar")
	card_label.text = UiTheme.keycaps("CARTA: %s   ·   %s" % [CrewProgression.card_name(card_id), action])


func _on_unlock_earned(_unlock_id: StringName, title: String) -> void:
	_toast("¡Desbloqueaste %s!" % title)


func _toast(text: String, priority: int = 20) -> void:
	_notice_serial += 1
	_set_notice(&"information", StringName("toast_%d" % _notice_serial), text, priority, MINT, PING_DISPLAY_SECONDS)
	toast_seconds_left = PING_DISPLAY_SECONDS


func _on_route_event_started(event_id: StringName, event: Dictionary) -> void:
	if bool(event.get("incident", false)):
		_toast("%s — %s" % [event.get("title", "Incidente"), event.get("prompt", "")])
		return
	_route_event_active_id = event_id
	_on_route_event_updated(event_id, event)
	event_seconds_left = 0.0


func _on_route_event_updated(event_id: StringName, event: Dictionary) -> void:
	if bool(event.get("incident", false)):
		return
	var objective: String = String(event.get("prompt", ""))
	if event_id == &"inspection" and int(event.get("loose", 0)) > 0:
		objective = "Faltan asegurar %d cajas" % int(event["loose"])
	elif event_id == &"mixed_labels" and event.get("phase") == &"swapped":
		objective = "%s  ?" % objective
	var seconds: int = ceili(float(event.get("remaining", 0.0)))
	_set_notice(&"critical", &"route_event", "%s\n%s\n%02d:%02d" % [event.get("title", "Evento"), objective, seconds / 60, seconds % 60], 80, YELLOW)
	if event_id in [&"mixed_labels", &"mimetic_package"]:
		for id: StringName in cargo_rows:
			_refresh_row(id)


func _on_route_event_resolved(event_id: StringName, success: bool, _peer_id: int) -> void:
	if event_id not in RouteEventManager.EVENTS:
		return
	if _route_event_active_id == event_id:
		_route_event_active_id = &""
	_clear_notice(&"critical", &"route_event")
	for id: StringName in cargo_rows:
		_refresh_row(id)
	_set_notice(&"critical", &"route_result", "Evento resuelto" if success else "Evento fallido", 70, MINT if success else RED, PING_DISPLAY_SECONDS)
	event_seconds_left = PING_DISPLAY_SECONDS


func _set_notice(zone: StringName, key: StringName, text: String, priority: int,
		color: Color, duration: float = -1.0) -> void:
	if not _notice_sources.has(zone):
		return
	if text.is_empty():
		_clear_notice(zone, key)
		return
	var sources: Dictionary = _notice_sources[zone]
	var previous: Dictionary = sources.get(key, {})
	_notice_serial += 1 if previous.is_empty() else 0
	sources[key] = {
		"text": text,
		"priority": priority,
		"color": color,
		"duration": duration,
		"remaining": duration,
		"serial": int(previous.get("serial", _notice_serial)),
	}
	_notice_sources[zone] = sources
	_render_notice_zone(zone)


func _clear_notice(zone: StringName, key: StringName) -> void:
	if not _notice_sources.has(zone):
		return
	var sources: Dictionary = _notice_sources[zone]
	sources.erase(key)
	_notice_sources[zone] = sources
	_render_notice_zone(zone)


func _clear_all_notices() -> void:
	_notice_sources = {&"critical": {}, &"information": {}}
	_render_notice_zone(&"critical")
	_render_notice_zone(&"information")


func _process_notices(delta: float) -> void:
	for zone: StringName in _notice_sources:
		var sources: Dictionary = _notice_sources[zone]
		var active_key := _top_notice_key(sources)
		if active_key != &"":
			var active: Dictionary = sources[active_key]
			if float(active.get("remaining", -1.0)) >= 0.0:
				active.remaining = float(active.remaining) - delta
				if float(active.remaining) <= 0.0:
					sources.erase(active_key)
				else:
					sources[active_key] = active
		_notice_sources[zone] = sources
		_render_notice_zone(zone)


func _render_notice_zone(zone: StringName) -> void:
	var label: Label = event_label if zone == &"critical" else toast_label
	if label == null:
		return
	var sources: Dictionary = _notice_sources[zone]
	var best_key := _top_notice_key(sources)
	if best_key == &"":
		label.text = ""
		return
	var best: Dictionary = sources[best_key]
	label.text = String(best.text)
	label.add_theme_color_override("font_color", best.color)


func _top_notice_key(sources: Dictionary) -> StringName:
	var best_key: StringName = &""
	for key: StringName in sources:
		var entry: Dictionary = sources[key]
		if best_key == &"":
			best_key = key
			continue
		var best: Dictionary = sources[best_key]
		if int(entry.priority) > int(best.priority) \
				or (int(entry.priority) == int(best.priority) and int(entry.serial) < int(best.serial)):
			best_key = key
	return best_key
