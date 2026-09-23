extends Node
## Facts shared by simulation and presentation. UI requests are separate from facts.
##
## In multiplayer these facts are decided on the host (the van and every
## package are host-authoritative). relay() is how a host-side fact reaches
## every client's own local EventBus, so their HUD and RunManager react the
## same way theirs would offline. Emit UI requests (start_requested and
## friends) with plain emit() as before -- those are per-peer, not facts.

signal cargo_registered(package_id: StringName, display_name: String)
## Low-rate (a few times a second, not every physics tick): a trap's hint
## text can change every frame (a countdown, say), and relaying that at full
## physics rate would spam the network for a label nobody reads that closely.
signal package_hint_changed(package_id: StringName, hint: String)
signal package_state_changed(package_id: StringName, new_state: int)
signal package_integrity_changed(package_id: StringName, integrity: float, maximum: float)
signal package_ruined(package_id: StringName, cause: String)
signal package_damaged(package_id: StringName, damage: float)
## Fires once, right as the package lands on its mount -- purely for the
## settle-bounce presentation (docs/especificaciones-visuales.md #22), not a
## fact anything else needs.
signal package_placed(package_id: StringName)
## The lid opened or closed (host decides, relayed): drives the flap
## animation and what the crew can see inside.
signal package_lid_changed(package_id: StringName, open: bool)
## An open box tipped over or took a hard hit and its contents fell out.
## state is the trap state right before, so the pieces thrown out match
## what was in there (a whole vase, or its shards).
signal package_contents_spilled(package_id: StringName, velocity: Vector3, state: int)
signal vehicle_telemetry(speed_kmh: float)
signal vehicle_impact(strength: float, impact_position: Vector3)
signal run_started(route_id: StringName, players: Array)
signal run_ended(score: int, results: Dictionary)
signal route_progress_changed(progress: float, remaining_meters: float, section: String)
signal delivery_status_changed(in_zone: bool, stopped_seconds: float)
signal start_requested
signal restart_requested
signal pause_requested
signal interaction_prompt_changed(prompt: String)
## Local-only, like interaction_prompt_changed: whether this client's own
## player has a box in hand, so the HUD can show how to set it down.
signal carry_changed(carrying: bool)
## Local-only too: the box this player could open or close right now (in
## hand, at their seat, or looked at). action is "Abrir caja"/"Cerrar caja"
## or empty; inside is what they can see in it while it's open.
signal package_lid_hint_changed(action: String, inside: String)
## Non-verbal communication (docs/controles-y-ui.md): any player can ping,
## not just the host, so this needs its own client->host->everyone hop
## instead of relay() (which only ever originates from host-run simulation).
signal ping_sent(peer_id: int, position: Vector3, label: String)
## Same shape as ping_sent, same reason: whoever's driving might not be the
## host, but everyone should hear the horn.
signal horn_honked(peer_id: int)
## A quick black flash to soften a hard camera cut (boarding a seat) or a
## scene reload (restarting) -- purely local presentation, like
## interaction_prompt_changed, so a plain emit() is enough: nobody else's
## screen should flash because of what happens on this one client.
signal quick_fade_requested(seconds: float)
signal team_money_changed(amount: int)
signal merit_changed(peer_id: int, total: int)
signal card_changed(peer_id: int, card: int)
signal shop_opened(offers: Dictionary)
signal shop_vote_changed(peer_id: int, offer_id: StringName)
signal shop_resolved(offer_id: StringName, offer: Dictionary)
## A house resolved (delivered ok/ruined, or driven past). Host-side fact,
## relayed, so every passenger's HUD reacts to a door they weren't standing
## at. photo_available says whether there's still something worth
## photographing there -- the phone camera uses it to offer the shot.
signal house_delivery_recorded(house_index: int, outcome: StringName, package_id: StringName)
## The delivery photo was filed against a door (or wasn't -- accepted says
## which), so the HUD can confirm the shot landed.
signal delivery_photo_taken(house_index: int, accepted: bool)
signal route_event_started(event_id: StringName, event: Dictionary)
signal route_event_updated(event_id: StringName, event: Dictionary)
signal route_event_resolved(event_id: StringName, success: bool, peer_id: int)


## Emits locally and, if this is the host of an online session, rebroadcasts
## to every client so their own EventBus fires the same signal. Call this
## instead of emit_signal() for anything that originates from host-run
## simulation (package/vehicle facts, run state) so clients stay in sync.
func relay(event_name: StringName, args: Array = []) -> void:
	callv(&"emit_signal", [event_name] + args)
	if NetworkManager.is_online() and NetworkManager.is_host():
		_relay.rpc(event_name, args)


@rpc("authority", "call_remote", "reliable")
func _relay(event_name: StringName, args: Array) -> void:
	callv(&"emit_signal", [event_name] + args)


## Any peer calls this (directly if it's already the host, via rpc_id(1, ...)
## otherwise -- see Player._send_ping()). The host is the only one allowed to
## decide a ping actually happened, same authority rule as every other
## player-initiated action in this project, then relay()s it as a fact so
## everyone's HUD (including the sender's) reacts identically.
@rpc("any_peer", "call_remote", "reliable")
func request_ping(position: Vector3, label: String) -> void:
	if NetworkManager.is_online() and not NetworkManager.is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else NetworkManager.local_id()
	relay(&"ping_sent", [peer_id, position, label])


## Same client->host->everyone shape as request_ping(), for the driver's horn.
@rpc("any_peer", "call_remote", "reliable")
func request_horn() -> void:
	if NetworkManager.is_online() and not NetworkManager.is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else NetworkManager.local_id()
	relay(&"horn_honked", [peer_id])
