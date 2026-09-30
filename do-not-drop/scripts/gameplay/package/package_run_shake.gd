extends RefCounted
## What running with a box in the arms does to it (N-115, player_sprint.gd).
## Static helpers over a DeliveryPackage, like package_rescue.gd: package.gd is
## at its line limit, and the damage itself still goes down the usual road
## (the trap's reaction, the EventBus events, the ruin).

## Impact strength (m/s of velocity change) of a fall from a trip: a hard hit,
## like a box dropped from the chest onto the road (DeliveryPackage.HARD_HIT_SPEED).
const STUMBLE_IMPACT: float = 6.0
## The bounce feedback reads as a collision of this strength (its shake is
## strength x 0.025 of the mesh jitter).
const SHAKE_AS_COLLISION: float = 18.0
const CREAK_DB: float = -16.0


## Host: the carrier ran one step with the box. Small, once per step; padding
## and tape soften it like a bump (strength is scaled by both).
static func jolt(p: DeliveryPackage, strength: float = 1.0) -> void:
	if p.trap_behavior == null or not p._is_run_active() or p.care.needs_restore or p.care.phase == &"lost":
		return
	var before_integrity: float = p.integrity
	var before_state: int = p.trap_state
	p.trap_behavior.call("on_carried_step", strength * p.impact_absorption * p.care.impact_scale())
	p._check_recovery()
	p._report_change(before_integrity, before_state, p.tr("HUD_PACKAGE_RUINED_RUNNING"))


## Host: the carrier tripped. The box leaves their hands where it is, with a
## shove ahead, and lands as a drop with impact.
static func stumble(p: DeliveryPackage, push: Vector3) -> void:
	if not p.is_multiplayer_authority() or not p.is_held:
		return
	p._release_carrier()
	p.reset_physics_interpolation()
	p.set_held(false)
	p._ride_along_if_aboard()
	p.linear_velocity += push
	p.apply_impact(STUMBLE_IMPACT)


## Every peer, once per footfall of the carrier: the box bounces in their arms
## and, every other step, creaks. Presentation only -- it moves the Box mesh
## through the feedback component (like the impact shake) and never the body.
static func bounce(p: DeliveryPackage, step: int) -> void:
	var feedback: Node = p.get_node_or_null(^"PackageFeedbackComponent")
	if feedback != null:
		feedback.call(&"_on_package_placed", p.package_id)
		feedback.call(&"_on_package_collision", p.package_id, &"", SHAKE_AS_COLLISION)
	if step % 2 != 0:
		return
	var creak := p.get_node_or_null(^"RunCreak") as AudioStreamPlayer3D
	if creak == null:
		creak = AudioStreamPlayer3D.new()
		creak.name = "RunCreak"
		creak.bus = &"SFX"
		creak.stream = SynthAudio.wood_creak()
		creak.volume_db = CREAK_DB
		creak.unit_size = 6.0
		creak.max_distance = 20.0
		p.add_child(creak)
	creak.pitch_scale = randf_range(0.9, 1.15)
	creak.play()
