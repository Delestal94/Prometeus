class_name HudNotices
extends Node
## Everything that pops up during a run: pings, route events, toasts, money,
## merit and cards -- queued by zone so only the most important shows.

## Set by Hud before this is added as its child.
var hud: Hud
const PING_DISPLAY_SECONDS: float = 2.5
const EVENT_DISPLAY_SECONDS: float = 6.0
const EVENT_STINGER_DELAY: float = 0.3
const PingCatalogData = preload("res://scripts/ui/ping_catalog.gd")
const WorldMix = preload("res://scripts/presentation/world_mix.gd")
## One label per fixed HUD zone. Each source keeps its queued entry here;
## hud_notices.gd renders only the highest-priority one in that zone.
var _notice_sources: Dictionary = {&"critical": {}, &"information": {}}
var _notice_serial: int = 0
## Seconds of the low-visibility event left as this HUD knows it (0 = none),
## and whether the driver's notice for it is up.
var _low_visibility_left: float = 0.0
var _low_visibility_shown: bool = false


func _ready() -> void:
	EventBus.ping_sent.connect(_on_ping)
	EventBus.quick_fade_requested.connect(_on_quick_fade_requested)
	EventBus.team_money_changed.connect(_on_team_money_changed)
	EventBus.merit_changed.connect(_on_merit_changed)
	EventBus.card_changed.connect(_on_card_changed)
	EventBus.route_event_started.connect(_on_route_event_started)
	EventBus.route_event_updated.connect(_on_route_event_updated)
	EventBus.route_event_resolved.connect(_on_route_event_resolved)
	EventBus.unlock_earned.connect(_on_unlock_earned)
	EventBus.low_visibility_changed.connect(_on_low_visibility_changed)
	EventBus.depot_notice.connect(toast)


func _on_ping(peer_id: int, world_position: Vector3, label: String) -> void:
	var who: String = tr("HUD_YOU") if peer_id == NetworkManager.local_id() else tr("UI_PLAYER_N") % peer_id
	var text: String = PingCatalogData.display_text(label)
	toast("%s  %s:  %s" % [_ping_arrow(world_position), who, text], 40)
	hud.ping_label.text = ""
	hud.ping_indicator.text = ""
	# The driver's minimal HUD (jugabilidad-paquetes-rescate.md, "pedidos de
	# freno"): their eyes are on the road, so a crewmate's callout also goes
	# big in the middle of the screen, in the phrase's colour.
	if peer_id != NetworkManager.local_id() and local_is_driving():
		var option: Dictionary = PingCatalogData.option(label)
		hud.ping_indicator.text = "%s %s" % [option["icon"], text]
		hud.ping_indicator.add_theme_color_override(&"font_color", option["color"])
	hud.ping_seconds_left = PING_DISPLAY_SECONDS
	if peer_id != NetworkManager.local_id():
		_mark_pinger(peer_id, label)
	_speak(peer_id, label)


## Whether this client's player is the one at the wheel right now.
func local_is_driving() -> bool:
	for vehicle: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var driver: Variant = vehicle.get(&"driver_peer_id")
		if driver is int and driver == NetworkManager.local_id():
			return true
	return false


func _mark_pinger(peer_id: int, label: String) -> void:
	var option: Dictionary = PingCatalogData.option(label)
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.get_multiplayer_authority() != peer_id or not player is Node3D:
			continue
		var old: Node = player.get_node_or_null(^"PingMarker")
		if old != null:
			old.free()
		var marker := Label3D.new()
		marker.name = "PingMarker"
		marker.text = String(option["icon"])
		marker.font = load(UiTheme.DISPLAY_FONT_PATH)
		marker.font_size = 110
		marker.outline_size = 18
		marker.modulate = option["color"]
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


## The callout's voice (N-505.2): babble pitched by the caller's colour slot,
## from their head when their player is in the scene, flat otherwise (your own
## call, or a lobby without bodies).
func _speak(peer_id: int, label: String) -> void:
	var slot: int = posmod(peer_id, Player.PLAYER_COLORS.size())
	var stream: AudioStreamWAV = SynthAudio.callout_voice(slot, PingCatalogData.syllables(label))
	var parent: Node = self
	if peer_id != NetworkManager.local_id():
		for player: Node in get_tree().get_nodes_in_group(&"player"):
			if player is Node3D and player.get_multiplayer_authority() == peer_id:
				parent = player
	# The Voice bus, so the "Voces" slider owns it (S-402).
	var bus_name: StringName = &"Voice" if AudioServer.get_bus_index(&"Voice") >= 0 else &"Master"
	var old: Node = parent.get_node_or_null(^"CalloutVoice")
	if old != null:
		old.free()
	var voice: Node
	if parent is Node3D:
		var voice_3d := AudioStreamPlayer3D.new()
		voice_3d.unit_size = 6.0
		voice_3d.max_distance = 40.0
		voice_3d.position = Vector3(0.0, 1.7, 0.0)
		voice_3d.volume_db = WorldMix.CALLOUT_VOICE_DB
		voice_3d.stream = stream
		voice_3d.bus = bus_name
		voice_3d.finished.connect(voice_3d.queue_free)
		voice = voice_3d
	else:
		var voice_flat := AudioStreamPlayer.new()
		voice_flat.volume_db = WorldMix.CALLOUT_VOICE_DB
		voice_flat.stream = stream
		voice_flat.bus = bus_name
		voice_flat.finished.connect(voice_flat.queue_free)
		voice = voice_flat
	voice.name = "CalloutVoice"
	parent.add_child(voice)
	voice.call(&"play")


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
	tween.tween_property(hud.fade_rect, ^"color:a", 1.0, half)
	tween.tween_property(hud.fade_rect, ^"color:a", 0.0, half)


func _on_team_money_changed(amount: int) -> void:
	hud.economy_label.text = "$%d" % amount


func _on_merit_changed(peer_id: int, total: int) -> void:
	if peer_id == NetworkManager.local_id():
		var gained: int = maxi(total - hud.local_merit_total, 0)
		hud.local_merit_total = total
		toast(tr("HUD_MERIT") % [gained, total])


func _on_card_changed(peer_id: int, card_id: int) -> void:
	if peer_id != NetworkManager.local_id():
		return
	refresh_card()
	if card_id >= 0:
		toast(tr("HUD_CARD_EARNED") % CrewProgression.card_name(card_id))


func refresh_card() -> void:
	if hud.card_label == null:
		return
	var card_id: int = int(CrewProgression.cards.get(NetworkManager.local_id(), -1))
	hud.card_label.visible = card_id >= 0
	if card_id < 0:
		hud.card_label.text = ""
		return
	var action: String = GameSettings.prompt(tr("HUD_CARD_USE_KEY") % GameSettings.binding_label(&"use_card"),
			tr("HUD_CARD_USE_PAD"))
	hud.card_label.text = UiTheme.keycaps(tr("HUD_CARD") % [CrewProgression.card_name(card_id), action])


func _on_unlock_earned(_unlock_id: StringName, title: String) -> void:
	toast(tr("HUD_UNLOCKED") % title, 20, UiTheme.UI_SOUNDS.UNLOCK)
	# Queued, not played: it fires right before the results screen (UnlockManager
	# hears run_ended first), so the unlock phrase waits for the result one.
	UiTheme.UI_SOUNDS.queue_stinger(self, UiTheme.UI_SOUNDS.STINGER_UNLOCK)


## The run's end closes any open event as failed (RouteEventManager
## close_for_run_end); that one stays silent so the result stinger is not
## preceded by a "failed" jingle. A client gets the relayed close a moment
## before its own run_ended, so the stinger waits EVENT_STINGER_DELAY and only
## plays if the run is still going by then.
func _play_event_stinger(id: StringName) -> void:
	if not RunManager.is_running:
		return
	get_tree().create_timer(EVENT_STINGER_DELAY).timeout.connect(func() -> void:
		if is_inside_tree() and RunManager.is_running:
			UiTheme.UI_SOUNDS.play_stinger(self, id))


func toast(text: String, priority: int = 20, cue: StringName = UiTheme.UI_SOUNDS.TOAST) -> void:
	_notice_serial += 1
	set_notice(&"information", StringName("toast_%d" % _notice_serial), text, priority, Hud.MINT, PING_DISPLAY_SECONDS)
	hud.toast_seconds_left = PING_DISPLAY_SECONDS
	UiTheme.UI_SOUNDS.play(self, cue)


func _on_route_event_started(event_id: StringName, event: Dictionary) -> void:
	if bool(event.get("incident", false)):
		toast("%s — %s" % [_event_text(event, "title", "HUD_INCIDENT"), _event_text(event, "prompt")])
		return
	hud.route_event_active_id = event_id
	_on_route_event_updated(event_id, event)
	hud.event_seconds_left = 0.0


func _on_route_event_updated(event_id: StringName, event: Dictionary) -> void:
	if bool(event.get("incident", false)):
		return
	var objective: String = _event_text(event, "prompt")
	if event_id == &"inspection" and int(event.get("loose", 0)) > 0:
		objective = tr("HUD_BOXES_TO_SECURE") % int(event["loose"])
	elif event_id == &"mixed_labels" and event.get("phase") == &"swapped":
		objective = "%s  ?" % objective
	var seconds: int = ceili(float(event.get("remaining", 0.0)))
	var title: String = _event_text(event, "title", "HUD_EVENT")
	set_notice(&"critical", &"route_event",
			"%s\n%s\n%02d:%02d" % [title, objective, seconds / 60, seconds % 60], 80, Hud.YELLOW)
	if event_id in [&"mixed_labels", &"mimetic_package"]:
		for id: StringName in hud.cargo_rows:
			hud.cargo.refresh_row(id)


## The driver's view is blocked for a spell (N-113, low_visibility_event.gd):
## the one at the wheel is told to get guided, everybody else to guide them
## with the phrase wheel (N-505). Ends with the event.
func _on_low_visibility_changed(is_starting: bool, _kind: StringName, duration: float, seconds_in: float) -> void:
	_low_visibility_left = maxf(duration - seconds_in, 1.0) if is_starting else 0.0
	refresh_low_visibility(0.0)
	if is_starting and not local_is_driving():
		toast(GameSettings.prompt(tr("HUD_LOW_VISIBILITY_GUIDE_KEY") % GameSettings.binding_label(&"ui_ping"),
				tr("HUD_LOW_VISIBILITY_GUIDE_PAD")), 45)


## Every frame while the event lasts: the driver's notice follows whoever is at
## the wheel now (a swap mid-event moves it), and goes with the event.
func refresh_low_visibility(delta: float) -> void:
	_low_visibility_left = maxf(_low_visibility_left - delta, 0.0)
	var wanted: bool = _low_visibility_left > 0.0 and local_is_driving()
	if wanted == _low_visibility_shown:
		return
	_low_visibility_shown = wanted
	if wanted:
		set_notice(&"critical", &"low_visibility", tr("HUD_LOW_VISIBILITY_DRIVER"), 85, Hud.YELLOW)
	else:
		clear_notice(&"critical", &"low_visibility")


func _event_text(event: Dictionary, field: String, fallback: String = "") -> String:
	var key: String = String(event.get(field, fallback))
	var text: String = tr(key)
	var args: Array = event.get(field + "_args", [])
	return text % args if not args.is_empty() else text


func _on_route_event_resolved(event_id: StringName, success: bool, _peer_id: int) -> void:
	if event_id not in RouteEventManager.EVENTS:
		return
	_play_event_stinger(UiTheme.UI_SOUNDS.STINGER_EVENT_WON if success else UiTheme.UI_SOUNDS.STINGER_EVENT_FAILED)
	if hud.route_event_active_id == event_id:
		hud.route_event_active_id = &""
	clear_notice(&"critical", &"route_event")
	for id: StringName in hud.cargo_rows:
		hud.cargo.refresh_row(id)
	set_notice(&"critical", &"route_result", tr("HUD_EVENT_RESOLVED") if success else tr("HUD_EVENT_FAILED"), 70,
			Hud.MINT if success else Hud.RED, PING_DISPLAY_SECONDS)
	hud.event_seconds_left = PING_DISPLAY_SECONDS


## The closest open delivery deadline, counting down; yellow in its last
## 20 seconds so the driver knows it's time to push (or to let it go).
func refresh_deadline() -> void:
	var deadline: Dictionary = RunManager.next_deadline() if RunManager.is_running else {}
	if deadline.is_empty():
		clear_notice(&"information", &"deadline")
		return
	var left: int = maxi(0, ceili(float(deadline["seconds"]) - RunManager.elapsed_seconds))
	var house: int = int(deadline["house"]) + 1
	var reason: String = tr(String(deadline["reason"]))
	var text: String = tr("HUD_DEADLINE_NOTICE") % [house, reason, left / 60, left % 60]
	set_notice(&"information", &"deadline", text,
		40 if left > 20 else 75, Hud.MINT if left > 20 else Hud.YELLOW)


## The bomb's code, for the one at the wheel (N-117, "Pedí el código"): the
## arrows still to say aloud, the seconds and a "+N" for other bombs, on the
## HUD where a driver's eyes are, red in the last six seconds. Nobody else
## gets it: the owner of the box has to ask (DashboardGps.bomb_codes() lists
## only the codes whose reader is the driver).
func refresh_bomb_code() -> void:
	var label: Label = hud.code_label
	if label == null:
		return
	var codes: Array[Dictionary] = []
	if RunManager.is_running and local_is_driving():
		codes = DashboardGps.bomb_codes(get_tree().get_nodes_in_group(&"cargo"))
	if codes.is_empty():
		label.text = ""
		return
	var code_text: String = ", ".join(DashboardGps.code_lines(codes, 1, tr("HUD_BOMB_CODE"), tr("HUD_BOMB_CODE_MORE")))
	if label.text != code_text:
		label.text = code_text
	var code_color: Color = Hud.RED if float(codes[0]["seconds"]) <= 6.0 else Hud.YELLOW
	if not label.has_theme_color_override("font_color") or label.get_theme_color("font_color") != code_color:
		label.add_theme_color_override("font_color", code_color)


func set_notice(zone: StringName, key: StringName, text: String, priority: int,
		color: Color, duration: float = -1.0) -> void:
	if not _notice_sources.has(zone):
		return
	if text.is_empty():
		clear_notice(zone, key)
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


func clear_notice(zone: StringName, key: StringName) -> void:
	if not _notice_sources.has(zone):
		return
	var sources: Dictionary = _notice_sources[zone]
	sources.erase(key)
	_notice_sources[zone] = sources
	_render_notice_zone(zone)


func clear_all_notices() -> void:
	_notice_sources = {&"critical": {}, &"information": {}}
	_render_notice_zone(&"critical")
	_render_notice_zone(&"information")


func process_notices(delta: float) -> void:
	refresh_low_visibility(delta)
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
	var label: Label = hud.event_label if zone == &"critical" else hud.toast_label
	if label == null:
		return
	var sources: Dictionary = _notice_sources[zone]
	var best_key := _top_notice_key(sources)
	if best_key == &"":
		label.text = ""
		return
	var best: Dictionary = sources[best_key]
	if label.text != String(best.text):
		label.text = String(best.text)
	# Overriding a theme colour notifies the label's whole subtree, even with
	# the same value, and this runs every frame while a notice is up.
	if not label.has_theme_color_override("font_color") or label.get_theme_color("font_color") != best.color:
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
