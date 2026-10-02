class_name PackageFeedback
extends Node
## A presentation-only child: changing color never changes simulation state.
##
## The confetti burst on ruin is deliberately loud (docs/requerimientos-tecnicos.md
## 3.4, "momentos clipeables") -- package_ruined is already relayed to every peer
## (see package.gd's _emit_event), so each client's own local burst fires in lockstep
## with everyone else's without this script needing to know or care about the network.

const PackageVerb = preload("res://scripts/gameplay/package/package_verb.gd")
const SynthAudioTraps = preload("res://modules/synth_audio/synth_audio_traps.gd")
const PackageRuinEffects = preload("res://scripts/gameplay/package/package_ruin_effects.gd")
const PackageScribble = preload("res://scripts/gameplay/package/package_scribble.gd")
## The settings autoload's script, as a type (impact_effects, colorblind_palette,
## colorblind_palette_changed): it names no other autoload, so preloading it here
## compiles before they exist. test_dynamic_dispatch_budget checks it is the script
## GameSettings runs.
const GAME_SETTINGS := preload("res://scripts/core/game_settings.gd")
const CONFETTI_COLORS: Array[Color] = [Color("f47e6d"), Color("f4c562"), Color("83e2ba"), Color("6db3d6")]
const CONFETTI_COUNT: int = 28
const CONFETTI_LIFETIME: float = 1.1
const RUIN_HOLD_SECONDS: float = 0.35
const RUIN_PARTICLE_SPEED: float = 0.15
## Reference-distance levels for every trap cue owned by this component.
## `tests/audio_loudness_report.gd` keeps their resulting RMS near -18 dBFS.
const TRAP_SOUND_LEVELS_DB: Dictionary = {
	&"glass_chime": -0.7,
	&"creature_groan": -12.7,
	&"wood_creak": -3.2,
	&"liquid_slosh": 4.6,
	&"explosive_tick": -2.7,
	&"cushion_pad": -0.9,
	&"hostile_hiss": 2.5,
	&"comic_ruin_stinger": -5.3,
	&"comic_boom": 0.0,
}

## Nodes wobbled for the Ruidoso trap and on impacts: Box holds the whole
## cardboard model and what's inside it, so everything shudders together.
const WOBBLE_NODE_NAMES: Array[StringName] = [&"Box"]
## Creaks retrigger more often the closer the box is to failing -- at full
## distress roughly one every 0.8s, calm but not fresh roughly one every 4s.
const CREAK_INTERVAL_MAX: float = 4.0
const CREAK_INTERVAL_MIN: float = 0.8
## A one-shot decaying jitter on any hit (item #23), on top of Ruidoso's own
## continuous agitation wobble (PackageBoxMotion.apply_jitter()).
const IMPACT_SHAKE_PER_DAMAGE: float = 0.05
const INK: Color = Color("1e2235")
const GRIP_COLOR: Color = Color(1.0, 0.84, 0.48)
const GRIP_ENERGY: float = 0.45
## Glow gained per second holding (about a tenth of a second to full).
const GRIP_EASE: float = 10.0
const LABEL_DROP_DAMAGE: float = 18.0
## Fallback when a package has no PackageContent: the fragile box.
const DEFAULT_BOX_MODEL: String = "res://assets/models/cargo/sm_cargo_box_cube.glb"
## Printed cardboard is tinted, not repainted, by trap state: the print stays
## readable while the box still reads as "worried" or "wrecked" at a glance.
const STATE_TINT: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.88, 0.76), Color(0.8, 0.64, 0.6)]

@export var box_node_path: NodePath = ^"../Box"

## One per package, shared by every surface of its box model: highlight
## (emission) and the state tint change it per instance.
var _material: StandardMaterial3D
## Soft rim shown while a player is aiming at this box (see highlight()).
## Built with the box model, which only exists a frame after spawning; a
## highlight asked for before that is remembered and applied then.
var _outline: Node3D
var _outline_wanted: bool = false
var _package_id: StringName
var _box: Node3D
var _state: int = 0
## Distress reported per-frame via package_integrity_changed (already
## relayed to every client for the HUD) -- 0 fresh, 1 about to fail. Reused
## here as a generic "how bad is it" scalar instead of adding new signals:
## every trap already funnels its own specific mechanic into this same
## shared integrity axis (docs/parametros-diseno.md), so it's free.
var _distress: float = 0.0
var _trap_id: StringName = &""
var _wobble_nodes: Dictionary = {}  ## name -> {"node": Node3D, "base_position": Vector3}
var _wobble_seed: float = 0.0
var _chime_player: AudioStreamPlayer3D
var _groan_player: AudioStreamPlayer3D
var _creak_player: AudioStreamPlayer3D
var _creak_countdown: float = 0.0
var _impact_shake_strength: float = 0.0
var _growth_scale: float = 1.0
var _bounce_time: float = -1.0  ## negative: no bounce in progress
var _shipping_label: RigidBody3D
var _shipping_text: Label3D
var _shipping_data: String = ""
var _shipping_parties: Label3D
## What this box's own label says; a swapped label shows another box's (see
## PackageTrapVisuals.refresh_event_disguise()).
var _shipping_parties_data: String = ""
var _state_badge: Label3D
## The verb over the box (N-117): what to do about it, in the world, only while
## it is asking (see _verb_text()).
var _verb_label: Label3D
var _disguise_text: Label3D
var _disguise_icon: Sprite3D
var _was_disguise_revealed: bool = false
var _label_detached: bool = false
var _dent_pieces: Array[MeshInstance3D] = []
var _impact_damage_visual: float = 0.0
var _liquid_puddle: MeshInstance3D
var _liquid_slosh_player: AudioStreamPlayer3D
var _liquid_last_slosh_level: float = 0.0
var _explosive_display: Label3D
## Fragile's "Amortiguá": the ring that closes on the box as a bump nears, the
## thump when a tap softened one, and the last cushion state it read (from
## the host's care state) with the moment it did, so the ring keeps closing
## between the host's updates.
var _cushion_ring: MeshInstance3D
var _cushion_player: AudioStreamPlayer3D
var _cushion_snapshot: Dictionary = {}
var _cushion_at: float = 0.0
var _cushion_saved: int = 0
var _explosive_tick_player: AudioStreamPlayer3D
var _explosive_tick_timer: float = 0.0
var _hostile_eyes: Node3D
var _hostile_hiss_player: AudioStreamPlayer3D
var _hostile_last_attack_count: int = 0
var _shelf_straps: Array[MeshInstance3D] = []
var _package: DeliveryPackage
## The local player's own hold on this box (PlayerHoldFeedback, S-205): a warm
## glow that eases in the frame they press, ahead of anything the host says.
var _grip_wanted: bool = false
var _grip_glow: float = 0.0
## Every trap's own "it broke" stinger (item #23-adjacent, playtest polish
## 2026-09-27): comic_ruin_stinger() for most traps, comic_boom() for
## Explosivo -- picked once in _ready(), see there.
var _ruin_player: AudioStreamPlayer3D


func _ready() -> void:
	var parent: Node = get_parent()
	_package = parent as DeliveryPackage
	_package_id = _package.package_id
	var definition: TrapDefinition = _package.trap_definition
	_trap_id = definition.id if definition != null else &""
	# Distinct phase per package so several Ruidoso boxes riding together
	# don't all shudder in perfect unison.
	_wobble_seed = randf() * TAU
	_box = get_node(box_node_path) as Node3D
	_material = StandardMaterial3D.new()
	_material.roughness = 0.9
	# Always on, at zero: switching emission on and off changes the shader
	# variant, a hitch in GL Compatibility. The grip glow only moves the energy.
	_material.emission_enabled = true
	_material.emission = GRIP_COLOR
	_material.emission_energy_multiplier = 0.0
	_apply_identity.call_deferred()
	# Populated for every trap type, not just Ruidoso -- item #23's impact
	# shake rides the same nodes regardless of what the package's trap is.
	for wobble_name: StringName in WOBBLE_NODE_NAMES:
		var node: Node3D = get_node_or_null(NodePath("../" + String(wobble_name))) as Node3D
		if node != null:
			_wobble_nodes[wobble_name] = {"node": node, "base_position": node.position}
	match _trap_id:
		&"noisy":
			_groan_player = _make_player(SynthAudio.creature_groan(), -60.0)
		&"fragile", &"balance":
			_chime_player = _make_player(SynthAudio.glass_chime(), TRAP_SOUND_LEVELS_DB[&"glass_chime"])
		&"growing_weight":
			_creak_player = _make_player(SynthAudio.wood_creak(), TRAP_SOUND_LEVELS_DB[&"wood_creak"])
			_creak_countdown = CREAK_INTERVAL_MAX
		&"liquid":
			PackageTrapVisuals.build_liquid_puddle(self, _package)
			_liquid_slosh_player = _make_player(SynthAudio.liquid_slosh(), TRAP_SOUND_LEVELS_DB[&"liquid_slosh"])
		&"explosive":
			PackageTrapVisuals.build_explosive_display(self)
			_explosive_tick_player = _make_player(SynthAudio.explosive_tick(), TRAP_SOUND_LEVELS_DB[&"explosive_tick"])
		&"hostile":
			PackageTrapVisuals.build_hostile_eyes(self)
			_hostile_hiss_player = _make_player(SynthAudio.hostile_hiss(), TRAP_SOUND_LEVELS_DB[&"hostile_hiss"])
	# Every trap gets a stinger for the moment it actually fails, on top of
	# the confetti burst and whatever cue it already has of its own (Frágil's
	# chime pitches down for this same moment) -- picked once, since which
	# trap this package has never changes after _ready(). Explosivo gets its
	# own "BOOM." (explosive_trap_behavior.gd's get_hint() literally says
	# that once seconds_left hits 0) instead of the generic cartoon fail.
	if _trap_id == &"fragile":
		_cushion_player = _make_player(SynthAudioTraps.cushion_pad(), TRAP_SOUND_LEVELS_DB[&"cushion_pad"])
	var explosive: bool = _trap_id == &"explosive"
	_ruin_player = _make_player(SynthAudio.comic_boom() if explosive else SynthAudio.comic_ruin_stinger(),
		TRAP_SOUND_LEVELS_DB[&"comic_boom"] if explosive else TRAP_SOUND_LEVELS_DB[&"comic_ruin_stinger"])
	_set_state(0)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("package_state_changed", _on_package_state_changed)
		bus.connect("package_ruined", _on_package_ruined)
		bus.connect("package_integrity_changed", _on_integrity_changed)
		bus.connect("package_damaged", _on_package_damaged)
		bus.connect("package_collision", _on_package_collision)
		bus.connect("package_placed", _on_package_placed)
	var settings: GAME_SETTINGS = _settings()
	if settings != null:
		settings.colorblind_palette_changed.connect(_refresh_accessibility_palette)


func _apply_identity() -> void:
	var package: DeliveryPackage = _package
	var content: PackageContent = package.content_definition() as PackageContent
	var shape_size := Vector3(0.65, 0.65, 0.65)
	var box_scene: PackedScene = null
	var shipping_data: String = tr("HUD_SHIPPING_UNDECLARED")
	var shipping_parties: String = ""
	if content != null:
		shape_size = content.box_size
		box_scene = content.box_model
		shipping_data = content.shipping_contents()
		shipping_parties = content.shipping_parties()
	if box_scene == null:
		box_scene = load(DEFAULT_BOX_MODEL)
	var model: Node3D = box_scene.instantiate()
	model.name = "Model"
	# Box GLBs sit on their base; the package's origin is its centre.
	model.position.y = -shape_size.y * 0.5
	_box.add_child(model)
	PackageBoxDressing.add_cardboard_details(self, shape_size)
	PackageTrapVisuals.build_shelf_straps(self, shape_size)
	PackageBoxDressing.adopt_box_material(self, model)
	var collider: CollisionShape3D = package.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collider != null:
		var shape := BoxShape3D.new()
		shape.size = shape_size
		collider.shape = shape
	PackageBoxDressing.add_shipping_label(self, shipping_data, shipping_parties, shape_size)
	# Somebody's marker scribble on the front face (S-602); the label is on the back.
	var scribble: Label3D = PackageScribble.build(content, _package_id, shape_size)
	if scribble != null:
		_box.add_child(scribble)
	_build_state_badge(shape_size)
	_build_verb_label(shape_size)
	if _trap_id == &"fragile":
		PackageTrapVisuals.build_cushion_ring(self, shape_size)
	if _explosive_display != null:
		# Above the at-risk badge, clear of the lid: a sign sunk into the
		# cardboard is unreadable, even more so held right under the eyes.
		_explosive_display.position = Vector3(0.0, shape_size.y * 0.62 + 0.30, 0.0)
	PackageTrapVisuals.build_disguise(self, shape_size)
	PackageBoxDressing.add_dent_pieces(self, shape_size * 0.5)
	PackageBoxDressing.build_outline(self, shape_size)


## The verb sign above the state badge: big, billboarded, drawn over the box.
## The bomb has its own sign (ExplosiveCountdown) and does not get this one.
func _build_verb_label(box_size: Vector3) -> void:
	if _trap_id == &"explosive":
		return
	_verb_label = Label3D.new()
	_verb_label.name = "VerbIcon"
	_verb_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_verb_label.font_size = 54
	_verb_label.pixel_size = 0.0022
	_verb_label.outline_size = 14
	_verb_label.outline_modulate = INK
	_verb_label.no_depth_test = true
	_verb_label.render_priority = 2
	_verb_label.outline_render_priority = 1
	_verb_label.position = Vector3(0.0, box_size.y * 0.62 + 0.38, 0.0)
	_verb_label.visible = false
	_box.add_child(_verb_label)


func _apply_verb() -> void:
	if _verb_label == null:
		return
	var ask: Dictionary = PackageVerb.ask(_trap_id, _state, _package.care_state if _package != null else {},
			_package != null and _package._is_run_active())
	_verb_label.visible = not ask.is_empty()
	if ask.is_empty():
		return
	_verb_label.text = String(ask["text"])
	_verb_label.modulate = ask["color"]
	_verb_label.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.06)


func _build_state_badge(box_size: Vector3) -> void:
	_state_badge = Label3D.new()
	_state_badge.name = "AccessibleState"
	_state_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_state_badge.font_size = 46
	_state_badge.pixel_size = 0.0022
	_state_badge.outline_size = 10
	_state_badge.position = Vector3(0.0, box_size.y * 0.62 + 0.10, 0.0)
	_box.add_child(_state_badge)
	_refresh_state_badge()


func _apply_outline() -> void:
	if _outline != null:
		_outline.visible = _outline_wanted


func _make_player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 6.0
	player.max_distance = 20.0
	add_child(player)
	return player


func _on_package_state_changed(id: StringName, new_state: int) -> void:
	if id != _package_id:
		return
	_set_state(new_state)
	# Frágil and Equilibrio use a bright warning chime on the way into
	# AT_RISK, pitched down a fourth for RUINED so severity reads by ear.
	if _trap_id in [&"fragile", &"balance"] and new_state != 0:
		_chime_player.pitch_scale = 1.0 if new_state == 1 else 0.75
		_chime_player.play()


func _on_package_ruined(id: StringName, _cause: String) -> void:
	if id == _package_id:
		# The comic stinger is the ruin cue itself (it replaced the old impact
		# thud), so it plays even with impact effects turned off.
		if PackageRuinEffects.spawn(_trap_id, get_parent() as Node3D, _impact_effects_enabled()) == null:
			PackageBoxMotion.burst_confetti(self, _impact_effects_enabled())
		if _trap_id == &"growing_weight": _bounce_time = 0.0  # S-310: per-trap ruin effect; the thud squashes the box
		if _ruin_player != null:
			_ruin_player.play()


func _on_integrity_changed(id: StringName, integrity: float, maximum: float) -> void:
	if id != _package_id:
		return
	_distress = clampf(1.0 - integrity / maxf(maximum, 0.01), 0.0, 1.0)
	if _trap_id == &"growing_weight":
		PackageTrapVisuals.apply_growth(self)


## Item #23: any hit visibly rattles the box a little, on its own mesh, not
## only in the camera shake -- a fragile package taking a hit and a noisy
## one getting bumped both react, not just whichever trap already had a
## continuous effect running.
func _on_package_damaged(id: StringName, damage: float) -> void:
	if id != _package_id:
		return
	_impact_shake_strength = clampf(_impact_shake_strength + damage * IMPACT_SHAKE_PER_DAMAGE, 0.0, 1.0)
	_impact_damage_visual = clampf(_impact_damage_visual + damage * 0.035, 0.0, 1.0)
	PackageBoxMotion.apply_damage_deformation(self)
	if damage >= LABEL_DROP_DAMAGE:
		PackageBoxMotion.detach_shipping_label(self)


func _on_package_collision(id: StringName, _other_id: StringName, strength: float) -> void:
	if id != _package_id:
		return
	_impact_shake_strength = clampf(_impact_shake_strength + strength * 0.025, 0.0, 1.0)


## Item #22: a quick settle bounce instead of the box appearing locked in
## place the instant it's set down.
func _on_package_placed(id: StringName) -> void:
	if id == _package_id:
		_bounce_time = 0.0


func _process(delta: float) -> void:
	PackageTrapVisuals.refresh_event_disguise(self)
	PackageBoxMotion.apply_jitter(self, delta)
	PackageBoxMotion.apply_bounce(self, delta)
	PackageTrapVisuals.apply_shelf_straps(self)
	_apply_grip(delta)
	if _state_badge != null:
		var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.009) * 0.08
		_state_badge.scale = Vector3.ONE * (pulse if _state == ITrapBehavior.TrapState.AT_RISK else 1.0)
	match _trap_id:
		&"noisy":
			PackageTrapVisuals.apply_groan(self)
		&"growing_weight":
			PackageTrapVisuals.apply_creak(self, delta)
		&"liquid":
			PackageTrapVisuals.apply_liquid(self)
		&"explosive":
			PackageTrapVisuals.apply_explosive(self, delta)
		&"hostile":
			PackageTrapVisuals.apply_hostile(self)
		&"fragile":
			PackageTrapVisuals.apply_cushion(self)
	_apply_verb()


## Lit by the local player's hold on this box, right away (see
## player_hold_feedback.gd): presentation only, the host's care decides the rest.
func set_local_grip(active: bool) -> void:
	_grip_wanted = active


## 0..1 how lit the grip glow is.
func grip_glow() -> float:
	return _grip_glow


func _apply_grip(delta: float) -> void:
	var target: float = 1.0 if _grip_wanted else 0.0
	if is_equal_approx(_grip_glow, target):
		return
	_grip_glow = move_toward(_grip_glow, target, delta * GRIP_EASE)
	_material.emission_energy_multiplier = _grip_glow * GRIP_ENERGY


func _update_box_scale() -> void:
	PackageBoxMotion.update_box_scale(self)


func _impact_effects_enabled() -> bool:
	var settings: GAME_SETTINGS = _settings()
	return settings.impact_effects if settings != null else true


## Called by package_pickup_point.gd while this package is (or stops being)
## the player's current interaction target -- a highlight instead of only
## the HUD's text prompt saying "Agarrar paquete" (item #98). An emission
## overlay, not a swapped albedo: the box's real color already carries its
## trap state, this just glows on top without fighting _set_state() for it.
func highlight(enabled: bool) -> void:
	_outline_wanted = enabled
	_apply_outline()


func _set_state(new_state: int) -> void:
	_state = new_state
	_material.albedo_color = STATE_TINT[clampi(new_state, 0, STATE_TINT.size() - 1)]
	_refresh_state_badge()


func _refresh_state_badge() -> void:
	if _state_badge == null:
		return
	_state_badge.text = tr(["HUD_STATE_OK", "HUD_STATE_AT_RISK", "HUD_STATE_RUINED"][clampi(_state, 0, 2)])
	_state_badge.modulate = UiTheme.state_color(_state, _colorblind_palette_enabled())
	# Only trouble earns a marker: an "OK" floating over every healthy box
	# on the shelves read as noise, not information.
	_state_badge.visible = _state != ITrapBehavior.TrapState.OK


func _refresh_accessibility_palette(_enabled: bool) -> void:
	_refresh_state_badge()


func _colorblind_palette_enabled() -> bool:
	var settings: GAME_SETTINGS = _settings()
	return settings.colorblind_palette if settings != null else false


## Null-safe: a box outside the tree (or a test without the autoload) gets null.
func _settings() -> GAME_SETTINGS:
	return get_node_or_null(^"/root/GameSettings") as GAME_SETTINGS
