class_name PackageImpacts
extends RefCounted
## What hits do to the box (host side): the velocity change each physics step, other boxes and players it
## runs into, and reporting the damage to the run. Split out of package.gd (N-225.4) like package_rescue.gd:
## the state stays on the DeliveryPackage, which keeps thin wrappers (and _integrate_forces).
##
## By name on purpose (N-224.4, test_dynamic_dispatch_budget): RouteEventManager's on_package_impact (see
## package_autoloads.gd: typing the autoload makes a compile cycle).

const PACKAGE_COLLISION_MIN_SPEED: float = 2.2
const PACKAGE_COLLISION_DAMAGE_SCALE: float = 0.62
const PACKAGE_COLLISION_COOLDOWN: float = 0.16
const PLAYER_HIT_MIN_SPEED: float = 4.0
const PLAYER_HIT_PUSH_SCALE: float = 0.38


static func integrate_forces(p: DeliveryPackage, state: PhysicsDirectBodyState3D) -> void:
	var current_velocity: Vector3 = state.linear_velocity
	p._age += state.step
	p._impact_cooldown_remaining = maxf(0.0, p._impact_cooldown_remaining - state.step)
	for other_id: int in p._package_hit_cooldowns.keys():
		var seconds: float = float(p._package_hit_cooldowns[other_id]) - state.step
		if seconds <= 0.0:
			p._package_hit_cooldowns.erase(other_id)
		else:
			p._package_hit_cooldowns[other_id] = seconds
	if p._has_previous_velocity and p._age >= p.spawn_grace_time and p._is_run_active():
		# Gravity during free fall is not an impact. Collision resolution changes
		# velocity suddenly, while this subtraction removes the expected gravity step.
		var collision_delta: Vector3 = current_velocity - p._previous_velocity - state.total_gravity * state.step
		if p._impact_cooldown_remaining <= 0.0:
			var previous_integrity: float = p.integrity
			apply_impact(p, collision_delta.length())
			if p.integrity < previous_integrity:
				p._impact_cooldown_remaining = p.impact_cooldown
	if p.is_open and not p.contents_spilled and not p.is_held:
		var hit: float = 0.0
		if p._has_previous_velocity and p._age >= p.spawn_grace_time:
			hit = (current_velocity - p._previous_velocity - state.total_gravity * state.step).length()
		if state.transform.basis.y.normalized().dot(Vector3.UP) < p.spill_tilt_cos or hit > p.spill_impact:
			p.spill_contents(current_velocity)
	p._previous_velocity = current_velocity
	p._has_previous_velocity = true


static func apply_impact(p: DeliveryPackage, delta_velocity: float) -> void:
	if p.trap_behavior == null or not p._is_run_active():
		return
	# Mid-rescue the contents are already out: nothing left for a hit to break.
	# Echoes of one collision are already folded by PACKAGE_COLLISION_COOLDOWN.
	if p.care.needs_restore or p.care.phase == &"lost":
		return
	var routes: Node = PackageAutoloads.routes(p)
	if routes != null:
		routes.call(&"on_package_impact", p, delta_velocity)
	var before_integrity: float = p.integrity
	var before_state: int = p.trap_state
	var strength: float = clampf(delta_velocity, 0.0, 9.0) * p.impact_absorption * p.care.impact_scale()
	p.trap_behavior.on_impact(strength)
	if delta_velocity >= DeliveryPackage.HARD_HIT_SPEED:
		# Shaken hard: tool work pauses a moment (package_care.gd advance_work).
		p.care.recent_hit = 0.65
	p.care.on_hard_hit(delta_velocity)
	p._check_recovery()
	report_change(p, before_integrity, before_state, p.tr("HUD_PACKAGE_RUINED_IMPACTS"))


static func on_body_entered(p: DeliveryPackage, body: Node) -> void:
	if body is Player:
		_hit_player(p, body as Player)
		return
	var other := body as DeliveryPackage
	if other == null or other == p or p.is_held or other.is_held or p.freeze or other.freeze:
		return
	if not p._is_run_active() or not other._is_run_active():
		return
	var other_id: int = other.get_instance_id()
	if p._package_hit_cooldowns.has(other_id):
		return
	var relative_velocity: Vector3 = p.linear_velocity - other.linear_velocity
	var strength: float = relative_velocity.length()
	if strength < PACKAGE_COLLISION_MIN_SPEED:
		return
	p._package_hit_cooldowns[other_id] = PACKAGE_COLLISION_COOLDOWN
	other._package_hit_cooldowns[p.get_instance_id()] = PACKAGE_COLLISION_COOLDOWN
	# The normal physics bounce remains authoritative.  Adding a little spin
	# lets a hard hit visibly cascade through a stack of loose cargo.
	var spin: Vector3 = relative_velocity.normalized().cross(Vector3.UP)
	p.apply_torque_impulse(spin * strength * 0.12)
	other.apply_torque_impulse(-spin * strength * 0.12)
	var damage_speed: float = strength * PACKAGE_COLLISION_DAMAGE_SCALE
	apply_impact(p, damage_speed)
	apply_impact(other, damage_speed)
	p._emit_event(&"package_collision", [p.package_id, other.package_id, strength])
	p._emit_event(&"package_collision", [other.package_id, p.package_id, strength])


static func _hit_player(p: DeliveryPackage, player: Player) -> void:
	if p.is_held or p.freeze or not p._is_run_active():
		return
	var speed: float = p.linear_velocity.length()
	if speed < PLAYER_HIT_MIN_SPEED:
		return
	var push: Vector3 = p.linear_velocity.normalized() * minf(speed * PLAYER_HIT_PUSH_SCALE, 5.0)
	player.rpc(&"receive_package_hit", push)
	apply_impact(p, speed * 0.35)


static func report_change(p: DeliveryPackage, before_integrity: float, before_state: int, ruin_cause: String) -> void:
	var lost: float = before_integrity - p.integrity
	if lost > 0.0:
		p._emit_event(&"package_damaged", [p.package_id, lost])
		if not p._sharing_parasite_damage and not p.parasite_partner_id.is_empty() and p.is_inside_tree():
			for candidate: Node in p.get_tree().get_nodes_in_group(&"cargo"):
				if candidate is DeliveryPackage and candidate.package_id == p.parasite_partner_id:
					candidate.apply_parasite_damage(lost * 0.5)
					break
	if not is_equal_approx(before_integrity, p.integrity):
		p._emit_event(&"package_integrity_changed", [p.package_id, p.integrity, p.integrity_max])
	if p.trap_state != before_state:
		p._emit_event(&"package_state_changed", [p.package_id, p.trap_state])
		if p.trap_state == ITrapBehavior.TrapState.RUINED:
			p._emit_event(&"package_ruined", [p.package_id, ruin_cause])
