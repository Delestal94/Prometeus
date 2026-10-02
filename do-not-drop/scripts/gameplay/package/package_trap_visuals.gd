class_name PackageTrapVisuals
extends RefCounted
## What each trap shows and plays on its box: Hostil's eyes and hiss, Frágil's cushion ring, Explosivo's
## countdown and tick, Líquido's puddle and slosh, Peso Creciente's swell and creak, Ruidoso's groan, the
## shelf straps and the event disguise. Split out of package_feedback.gd (N-225.5) like package_rescue.gd is of
## package.gd: the state (nodes, players, counters) stays on the PackageFeedback, which decides in _ready and
## _process which trap's pieces exist and run. Presentation only: the host's behavior decides, this reads it.

const PackageShippingLabel = preload("res://scripts/gameplay/package/package_shipping_label.gd")

const GROWING_WEIGHT_MAX_SCALE: float = 1.35
const GROWING_WEIGHT_SINK: float = 0.09


static func build_shelf_straps(f: PackageFeedback, shape_size: Vector3) -> void:
	var strap_material := StandardMaterial3D.new()
	strap_material.albedo_color = Color("25343b")
	strap_material.roughness = 0.55
	for x: float in [-shape_size.x * 0.32, shape_size.x * 0.32]:
		var strap := MeshInstance3D.new()
		strap.name = "ShelfStrap"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.045, shape_size.y + 0.06, 0.035)
		strap.mesh = mesh
		strap.material_override = strap_material
		strap.position = Vector3(x, 0.0, -shape_size.z * 0.51)
		strap.visible = false
		f._box.add_child(strap)
		f._shelf_straps.append(strap)


static func apply_shelf_straps(f: PackageFeedback) -> void:
	if f._package == null:
		return
	var mounted: bool = f._package.is_loaded and f._package.current_mount != null
	var tension: float = clampf(f._package.linear_velocity.length() * 0.025
			+ f._package.angular_velocity.length() * 0.012, 0.0, 0.12)
	for strap: MeshInstance3D in f._shelf_straps:
		strap.visible = mounted
		strap.scale.y = 1.0 + tension


## The two labels of the event disguise (a mimetic box shows another trap's name and icon until revealed).
static func build_disguise(f: PackageFeedback, shape_size: Vector3) -> void:
	f._disguise_text = Label3D.new()
	f._disguise_text.position = Vector3(0.0, shape_size.y * 0.22, -shape_size.z * 0.52)
	f._disguise_text.pixel_size = 0.0015
	f._disguise_text.font_size = 32
	f._disguise_text.modulate = PackageFeedback.INK
	f._disguise_text.visible = false
	f._box.add_child(f._disguise_text)
	f._disguise_icon = Sprite3D.new()
	f._disguise_icon.position = Vector3(0.0, shape_size.y * 0.04, -shape_size.z * 0.53)
	f._disguise_icon.pixel_size = 0.001
	f._disguise_icon.visible = false
	f._box.add_child(f._disguise_icon)


static func refresh_event_disguise(f: PackageFeedback) -> void:
	if f._package == null or f._shipping_text == null:
		return
	var shown: String = f._shipping_data
	var shown_parties: String = f._shipping_parties_data
	if not f._package.label_swapped_with.is_empty():
		for other: Node in f.get_tree().get_nodes_in_group(&"cargo"):
			var other_package := other as DeliveryPackage
			if other_package != null and other_package.package_id == f._package.label_swapped_with:
				var content: PackageContent = other_package.content_definition() as PackageContent
				if content != null:
					shown = content.shipping_contents()
					shown_parties = content.shipping_parties()
				break
	if f._shipping_text.text != shown:
		f._shipping_text.text = shown
	if f._shipping_parties != null and f._shipping_parties.text != shown_parties:
		PackageShippingLabel.write_parties(f._shipping_parties, shown_parties)
	var disguised: bool = not f._package.disguise_trap_id.is_empty() and not f._package.disguise_revealed
	if f._disguise_text != null:
		f._disguise_text.visible = disguised
	if f._disguise_icon != null:
		f._disguise_icon.visible = false
	if disguised:
		var definition := load("res://data/traps/%s.tres" % f._package.disguise_trap_id) as TrapDefinition
		if definition != null:
			f._disguise_text.text = definition.localized_name()
			f._disguise_icon.texture = UiTheme.trap_icon(definition.localized_name())
			f._disguise_icon.visible = f._disguise_icon.texture != null
	if f._package.disguise_revealed and not f._was_disguise_revealed:
		PackageBoxMotion.burst_confetti(f)
		var reveal_sound: AudioStreamPlayer3D = f._make_player(
			SynthAudio.glass_chime(), PackageFeedback.TRAP_SOUND_LEVELS_DB[&"glass_chime"])
		reveal_sound.play()
	f._was_disguise_revealed = f._package.disguise_revealed


static func build_hostile_eyes(f: PackageFeedback) -> void:
	f._hostile_eyes = Node3D.new()
	f._hostile_eyes.name = "HostileEyes"
	f._hostile_eyes.position = Vector3(0.0, 0.04, -0.34)
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color("ff5e5b")
	eye_material.emission_enabled = true
	eye_material.emission = Color("ff2020")
	eye_material.emission_energy_multiplier = 1.8
	for x: float in [-0.10, 0.10]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.035
		sphere.height = 0.07
		eye.mesh = sphere
		eye.material_override = eye_material
		eye.position = Vector3(x, 0.06, 0.0)
		f._hostile_eyes.add_child(eye)
	for x: float in [-0.18, 0.0, 0.18]:
		var tentacle := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(0.025, 0.16, 0.025)
		tentacle.mesh = bar
		tentacle.material_override = eye_material
		tentacle.position = Vector3(x, -0.06, 0.0)
		f._hostile_eyes.add_child(tentacle)
	f._box.add_child(f._hostile_eyes)


static func apply_hostile(f: PackageFeedback) -> void:
	if f._hostile_eyes == null:
		return
	var package := f.get_parent() as DeliveryPackage
	var behavior: HostileTrapBehavior = (package.trap_behavior as HostileTrapBehavior) if package != null else null
	if behavior == null:
		return
	var aggression: float = behavior.aggression / maxf(package.integrity_max, 1.0)
	f._hostile_eyes.visible = aggression > 0.04
	f._hostile_eyes.scale = Vector3.ONE * lerpf(0.35, 1.25, aggression)
	var attacks: int = behavior.attack_count
	if attacks > f._hostile_last_attack_count:
		f._hostile_last_attack_count = attacks
		f._hostile_hiss_player.play()


## A flat ring around the box: it shows only while the road announces a bump
## (see apply_cushion()).
static func build_cushion_ring(f: PackageFeedback, box_size: Vector3) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.93
	torus.outer_radius = 1.0
	torus.rings = 56
	torus.ring_segments = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	f._cushion_ring = MeshInstance3D.new()
	f._cushion_ring.name = "CushionRing"
	f._cushion_ring.mesh = torus
	f._cushion_ring.material_override = material
	f._cushion_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f._cushion_ring.set_meta(&"box_radius", maxf(box_size.x, box_size.z) * 0.75)
	f._cushion_ring.visible = false
	f._box.add_child(f._cushion_ring)


## The ring closes on the box as the bump nears and turns green once a tap
## would count; grey while the last tap still makes the next one wait. A tap
## that softened a hit lands with a thump.
static func apply_cushion(f: PackageFeedback) -> void:
	if f._cushion_ring == null or f._package == null:
		return
	var snapshot: Dictionary = f._package.care_state.get("cushion", {})
	var now: float = Time.get_ticks_msec() / 1000.0
	if snapshot != f._cushion_snapshot:
		f._cushion_snapshot = snapshot.duplicate()
		f._cushion_at = now
	var eta: float = float(snapshot.get("eta", -1.0)) - (now - f._cushion_at)
	var saved: int = int(snapshot.get("saved", 0))
	if saved > f._cushion_saved and f._cushion_player != null:
		f._cushion_player.play()
		f._bounce_time = 0.0
	f._cushion_saved = saved
	var shown: bool = float(snapshot.get("eta", -1.0)) >= 0.0 and eta > -0.1
	f._cushion_ring.visible = shown
	if not shown:
		return
	var lead: float = maxf(float(snapshot.get("lead", 0.7)), 0.05)
	var closing: float = clampf(eta / lead, 0.0, 1.0)
	var radius: float = float(f._cushion_ring.get_meta(&"box_radius", 0.5)) * (1.0 + 0.9 * closing)
	f._cushion_ring.scale = Vector3(radius, radius, radius)
	var color: Color = Color(1.0, 0.8, 0.25, 0.9)
	if not bool(snapshot.get("ready", true)):
		color = Color(0.5, 0.5, 0.5, 0.65)
	elif eta <= float(snapshot.get("window", 0.35)):
		color = Color(0.35, 1.0, 0.6, 1.0)
	(f._cushion_ring.material_override as StandardMaterial3D).albedo_color = color


static func build_explosive_display(f: PackageFeedback) -> void:
	f._explosive_display = Label3D.new()
	f._explosive_display.name = "ExplosiveCountdown"
	f._explosive_display.font_size = 64
	f._explosive_display.pixel_size = 0.0022
	f._explosive_display.outline_size = 12
	f._explosive_display.modulate = Color("ff5e5b")
	f._explosive_display.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Drawn over the box it floats on, never swallowed by it.
	f._explosive_display.no_depth_test = true
	f._explosive_display.render_priority = 2
	f._explosive_display.outline_render_priority = 1
	f._explosive_display.position = Vector3(0.0, 0.62, 0.0)
	f._box.add_child(f._explosive_display)


static func apply_explosive(f: PackageFeedback, delta: float) -> void:
	if f._explosive_display == null:
		return
	var package := f.get_parent() as DeliveryPackage
	var behavior: ExplosiveTrapBehavior = (package.trap_behavior as ExplosiveTrapBehavior) if package != null else null
	if behavior == null:
		return
	var seconds: float = behavior.seconds_left
	var direction: StringName = behavior.next_direction()
	# The bomb only ticks on the host: every other peer reads the sequence
	# the host publishes with the care state (PackageRescue.publish_care()).
	var sequence: Dictionary = package.care_state.get("sequence", {})
	var done: int = behavior.sequence_index
	var total: int = behavior.sequence.size()
	if not sequence.is_empty():
		var steps: Array = sequence.get("steps", [])
		done = int(sequence.get("index", 0))
		total = steps.size()
		seconds = float(sequence.get("seconds", seconds))
		direction = StringName(steps[done]) if done < steps.size() else &""
	var state: int = behavior.get_state()
	# The code is the driver's to read (dashboard_gps.gd): the box only counts
	# how far along the owner is, unless the owner is the one who reads it.
	var owner_reads: bool = not sequence.is_empty() and StringName(sequence.get("reader", &"owner")) == &"owner"
	if not owner_reads:
		f._explosive_display.text = f.tr("HUD_EXPLOSIVE_CODE_SIGN") % [ceili(seconds), done, total]
	else:
		f._explosive_display.text = f.tr("HUD_EXPLOSIVE_DEFUSE") % [ceili(seconds), explosive_arrow(direction)]
	f._explosive_display.modulate = UiTheme.state_color(state, f._colorblind_palette_enabled())
	# The countdown only means something once the bomb is on the road: on
	# the depot's shelf it would just be a floating, ticking sign (depot.gd).
	f._explosive_display.visible = package._is_run_active()
	if not f._explosive_display.visible or seconds <= 0.0 or direction == &"":
		return
	f._explosive_tick_timer -= delta
	var interval: float = lerpf(0.16, 0.46, clampf(seconds / 14.0, 0.0, 1.0))
	if f._explosive_tick_timer <= 0.0:
		f._explosive_tick_timer = interval
		f._explosive_tick_player.play()


static func explosive_arrow(direction: StringName) -> String:
	return {&"up": "↑", &"down": "↓", &"left": "←", &"right": "→"}.get(direction, "✓")


static func build_liquid_puddle(f: PackageFeedback, package: DeliveryPackage) -> void:
	if package == null:
		return
	var puddle_mesh := CylinderMesh.new()
	puddle_mesh.top_radius = 1.0
	puddle_mesh.bottom_radius = 1.0
	puddle_mesh.height = 0.025
	puddle_mesh.radial_segments = 16
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.12, 0.68, 0.88, 0.52)
	material.metallic = 0.18
	material.roughness = 0.18
	f._liquid_puddle = MeshInstance3D.new()
	f._liquid_puddle.name = "LiquidPuddle"
	f._liquid_puddle.mesh = puddle_mesh
	f._liquid_puddle.material_override = material
	f._liquid_puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f._liquid_puddle.position.y = -package.get_half_extents().y + 0.015
	f._liquid_puddle.scale = Vector3.ZERO
	f._box.add_child(f._liquid_puddle)


static func apply_liquid(f: PackageFeedback) -> void:
	if f._liquid_puddle == null:
		return
	var package := f.get_parent() as DeliveryPackage
	var behavior: LiquidTrapBehavior = (package.trap_behavior as LiquidTrapBehavior) if package != null else null
	if behavior == null:
		return
	var amount: float = behavior.spill_amount
	var ratio: float = clampf(amount / maxf(package.integrity_max, 1.0), 0.0, 1.0)
	var radius: float = lerpf(0.02, 0.52, ratio)
	f._liquid_puddle.scale = Vector3(radius, 1.0, radius)
	f._liquid_puddle.visible = ratio > 0.015
	if ratio > f._liquid_last_slosh_level + 0.12:
		f._liquid_last_slosh_level = ratio
		if f._liquid_slosh_player != null:
			f._liquid_slosh_player.play()
	elif ratio < f._liquid_last_slosh_level:
		f._liquid_last_slosh_level = ratio


## Peso Creciente: the crate visibly swells and settles lower as its mass
## multiplier climbs, instead of only the HUD number changing. Straps stay
## their original size on purpose -- them visibly failing to contain a
## growing box reads as more urgent than if they grew to match it. Scale is
## tracked separately from the bounce's own scale pulse (_update_box_scale
## combines them) so placing a Peso Creciente package mid-grow doesn't have
## the two fight over Box.scale.
static func apply_growth(f: PackageFeedback) -> void:
	f._growth_scale = lerpf(1.0, GROWING_WEIGHT_MAX_SCALE, f._distress)
	f._box.position.y = -GROWING_WEIGHT_SINK * f._distress
	f._update_box_scale()


## Ruidoso's audible half of the same distress that drives the wobble:
## louder and higher-pitched the more agitated it is, silent at rest so a
## calm crate isn't moaning in the background the whole ride.
static func apply_groan(f: PackageFeedback) -> void:
	if f._distress <= 0.0:
		f._groan_player.stop()
		return
	if not f._groan_player.playing:
		f._groan_player.play()
	f._groan_player.volume_db = lerpf(-40.0, PackageFeedback.TRAP_SOUND_LEVELS_DB[&"creature_groan"], f._distress)
	f._groan_player.pitch_scale = lerpf(0.85, 1.3, f._distress)


## Peso Creciente's audible half: a creak burst, retriggered on its own
## schedule rather than every frame -- real creaking is intermittent, and
## the interval itself shortens as the box gets closer to unmanageable.
static func apply_creak(f: PackageFeedback, delta: float) -> void:
	if f._distress <= 0.0:
		f._creak_countdown = PackageFeedback.CREAK_INTERVAL_MAX
		return
	f._creak_countdown -= delta
	if f._creak_countdown <= 0.0:
		f._creak_countdown = lerpf(PackageFeedback.CREAK_INTERVAL_MAX, PackageFeedback.CREAK_INTERVAL_MIN, f._distress)
		f._creak_player.pitch_scale = randf_range(0.9, 1.1)
		f._creak_player.play()
