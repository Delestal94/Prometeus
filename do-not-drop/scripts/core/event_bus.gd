extends NetEventBus
## Facts shared by simulation and presentation. UI requests are separate from facts.
##
## In multiplayer these facts are decided on the host (the van and every
## package are host-authoritative). relay() (net_session module, NetEventBus,
## docs/modulos.md) is how a host-side fact reaches every client's own local
## EventBus, so their HUD and RunManager react the same way theirs would
## offline. Emit UI requests (start_requested and friends) with plain emit()
## as before -- those are per-peer, not facts. This file is the game's
## signals and its two player-initiated requests (ping, horn).

## name_key: TrapDefinition.name_key(), translated by each listener (N-805).
signal cargo_registered(package_id: StringName, name_key: String)
## Low-rate (a few times a second, not every physics tick): a trap's hint
## text can change every frame (a countdown, say), and relaying that at full
## physics rate would spam the network for a label nobody reads that closely.
## hint is a LocText line ([key, args...]); each peer translates it (N-805).
signal package_hint_changed(package_id: StringName, hint: Array)
signal package_state_changed(package_id: StringName, new_state: int)
signal package_integrity_changed(package_id: StringName, integrity: float, maximum: float)
signal package_ruined(package_id: StringName, cause: String)
signal package_damaged(package_id: StringName, damage: float)
signal package_collision(package_id: StringName, other_package_id: StringName, strength: float)
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
signal package_contents_recovered(package_id: StringName)
signal vehicle_telemetry(speed_kmh: float)
signal vehicle_impact(strength: float, impact_position: Vector3)
signal run_started(route_id: StringName, players: Array)
signal run_ended(score: int, results: Dictionary)
## Host-side and local (a plain emit, not a relay): the run's results are
## decided and about to be shared. RunChronicle writes the next-day newspaper
## from them and relays newspaper_ready before anyone hears run_ended, so the
## page is in every peer's hands when their results come up (N-606).
signal run_results_decided(results: Dictionary)
## The next-day newspaper, written by the host (RunChronicle + NewsDesk) and
## relayed: story ids, variants and slots, never text -- each peer reads it in
## its own language (NewsDesk.read). Arrives before run_ended. See NewsDesk.compose().
signal newspaper_ready(paper: Dictionary)
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
## Local-only onboarding card shown once per trap for this profile.
signal tutorial_tip_requested(text: String)
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
## Local-only (a plain emit, never relayed): a peer that joined mid-run read in
## the host's session state that this door was already resolved
## (RunManager._receive_session_state, N-975). What shows a waiting house (its
## marker and doorbell, the dashboard GPS, the depot's board) catches up as on
## house_delivery_recorded; nothing replays the moment (voices, faces, the
## neighbour's scene) and nothing records it again (register_delivery).
signal delivery_restored(house_index: int, outcome: StringName)
## What the door saw of a rescued box (repaired / unconvincing / substituted),
## relayed right before its house_delivery_recorded. Relayed.
signal delivery_care_noted(house_index: int, category: StringName)
## This run's delivery deadlines, [{house, seconds, reason}], as it starts, and again whenever one is shortened mid-run
## (RunManager.shorten_next_deadline). Relayed.
signal delivery_deadlines_set(deadlines: Array)
## The delivery photo was filed against a door (or wasn't -- accepted says
## which), so the HUD can confirm the shot landed.
signal delivery_photo_taken(house_index: int, accepted: bool)
signal route_event_started(event_id: StringName, event: Dictionary)
signal route_event_updated(event_id: StringName, event: Dictionary)
signal route_event_resolved(event_id: StringName, success: bool, peer_id: int)
## Local-only, never relayed: something happened on the roadside that the
## next-day newspaper may tell (N-606.4b). `kind` is &"dog_chase" (a village
## dog ran after the truck: sent when it starts, and again with the tag
## &"honked" if the horn sends it home) or &"train_stop" (the truck waited out
## a train at a level crossing; host only). Each peer's RunChronicle hears its
## own copy; only the host's writes the paper.
signal roadside_moment(kind: StringName, tags: Array)
signal unlock_earned(unlock_id: StringName, title: String)
## Which box each house waits for, decided by the host when the run starts:
## [[package_id, trap_key, code, content_id], ...] in house order (route.assign_packages()).
signal houses_assigned(assignments: Array)
## Somebody rang with a box the house didn't order; it was handed back.
signal house_refused_package(house_index: int, expected_label: String)
## The depot (depot.gd) posted today's orders on its board, one entry per
## house in order: {"house", "package_id", "code", "trap", "trap_key", "content"}.
## Every peer works the same list out from the session seed, so this is a
## plain local emit, not a relay.
signal depot_orders_posted(orders: Array)
## Local-only, like interaction_prompt_changed: this player used a depot
## station (lockers, workshop, supplies counter, board) and its screen should
## open on this client. station is DepotStation.station_id.
signal depot_station_opened(station: StringName)
## Local-only: this player used the counter of a service station on the road
## (N-110, service_counter.gd) and its supplies screen should open on this
## client. `shop` is the station's ServiceStopShop, which the panel treats as
## its "depot".
signal service_counter_opened(shop: Node)
## Local-only: the shared repair kit's counts changed on this peer
## (RunManager.care_supplies), so a screen that shows them can refresh.
signal care_supplies_changed
## The supplies waiting for the next run, and the team's money after the
## purchase. The host decides; depot.gd hands it to every peer.
signal depot_supplies_changed(supplies: Array, team_money: int)
## Something the whole crew should read in the depot or from it (a purchase,
## the door closing behind them, an order left on the shelf). Relayed.
signal depot_notice(text: String)
## A box left the van and lies on the road (N-213.1): the crew has
## `seconds` to pick it up and put it back before it's written off. Relayed.
signal cargo_overboard(package_id: StringName, position: Vector3, seconds: float)
## That box's rescue window closed: back aboard (`rescued`) or lost. Relayed.
signal cargo_overboard_ended(package_id: StringName, rescued: bool)
## An animal is going for a box (N-109, route/cargo_animals.gd): `kind` is
## &"gull", &"dog" or &"bees". It reaches the box in `warn_seconds` (the
## warning: cry, bark or buzz plus the icon over the box) and then has
## `act_seconds` to be stopped before it does its harm. Host decides,
## relayed; sent again to a peer that joins in the middle of one.
signal cargo_animal_alert(kind: StringName, package_id: StringName, warn_seconds: float, act_seconds: float)
## That animal is gone. `outcome` says why: &"scared" (the horn), &"held" (the
## crew held the box), &"distracted" (the dog took the stick), &"sealed" (the
## lid was closed), &"left" (it gave up or had nothing left to go for) or
## &"snatched" (the gull took the box). `peer_id` is who did it, 0 if nobody.
## Relayed.
signal cargo_animal_ended(kind: StringName, package_id: StringName, outcome: StringName, peer_id: int)
## A hard hit broke something on the truck (N-214, vehicle_faults.gd):
## &"rear_door" or &"mirror" for now. Host decides, relayed.
signal vehicle_fault_started(fault_id: StringName, impact_position: Vector3)
## That fault got fixed; method says how (&"part" from the shop, &"kit"...).
## Relayed.
signal vehicle_fault_repaired(fault_id: StringName, method: StringName)
## The driver's view is (or stops being) blocked for a spell (N-113,
## low_visibility_event.gd): `kind` is &"mud" for now; `duration` is how long
## it lasts and `elapsed` how far in it already is (0 unless a late joiner is
## catching up). `active` false = it ended. Host decides, relayed.
signal low_visibility_changed(active: bool, kind: StringName, duration: float, elapsed: float)

# Company mode (D-0215, docs/arquitectura.md section 10.3). Facts of the business, never
# relayed: CompanyNet applies every business event on each peer, the host too, and each
# peer emits these locally while applying it. Applying a snapshot (late join, seq gap)
# fires none of them, only CompanyNet.company_state_restored, so a late joiner doesn't
# replay the day's sounds and notices. Presentation listens; the simulation never
# depends on a listener.

## A company day opened (DayCycle, D-0203). `day` counts from 1.
signal company_day_started(day: int)
## The day is closing: 20:00 came or the last trip out ended (DayCycle, D-0203).
signal company_day_closing(day: int)
## The day's closing summary is ready for the closing screen (DayCycle, D-0203):
## earnings, costs, deliveries and failures as plain values.
signal company_day_summary(day: int, summary: Dictionary)
## A customer order came in (D-0801): CompanyRoot emits it on every peer, once per order, from
## CompanyNet's order_added event (D-0813.1); a snapshot's orders don't emit it.
signal order_added(order_id: StringName)
## A box was packed and sealed for that order (OrderBook.mark_packed).
signal order_packed(order_id: StringName)
## That order reached its customer (OrderBook.mark_delivered).
signal order_delivered(order_id: StringName)
## A supplier's truck arrived at the shed with the units bought (shed, D-0602).
signal supply_arrived(supplier_id: StringName)
## A box was taped shut at a packing station (shed, D-0701); `order_id` is &"" when the
## box isn't tied to an order yet.
signal box_sealed(station_id: StringName, order_id: StringName)
## A map gate opened for good (CompanyState.open_gate, D-0306).
signal gate_opened(gate_id: StringName)
## The company reached a milestone (CompanyState, D-0118/D-04xx).
signal milestone_reached(milestone_id: StringName)
## Any wallet movement (CompanyState.earn/spend/charge): `amount` is signed (negative
## when money went out) and `reason` the same tag the ledger keeps.
signal money_changed(amount: int, reason: StringName)


## Minimum seconds between two callouts from the same player (N-505.3).
## The host rate-limits each player to one callout per this many seconds,
## so a held-down wheel can't spam the crew (NetEventBus.request_cooldowns).
var ping_cooldown_seconds: float = 1.5:
	set(value):
		ping_cooldown_seconds = value
		request_cooldowns[&"ping_sent"] = value


## The two events a player may request (NetEventBus refuses any other):
## callouts at their pace, the horn as often as it's pressed.
func _init() -> void:
	request_cooldowns[&"ping_sent"] = ping_cooldown_seconds
	request_cooldowns[&"horn_honked"] = 0.0


## Host: the shape of each request as well (N-221), since request() itself is
## an RPC any peer can call: a callout is a place and a short label, the horn
## carries nothing.
func _accept_request(peer_id: int, event_name: StringName, args: Array) -> bool:
	match event_name:
		&"ping_sent":
			if args.size() != 2 or not args[0] is Vector3 or not (args[1] is String or args[1] is StringName):
				return false
		&"horn_honked":
			if not args.is_empty():
				return false
	return super(peer_id, event_name, args)


## Any peer calls this (directly if it's already the host, via rpc_id(1, ...)
## otherwise -- see Player._send_ping()). The host is the only one allowed to
## decide a ping actually happened, same authority rule as every other
## player-initiated action in this project, then relay()s it as a fact so
## everyone's HUD (including the sender's) reacts identically.
@rpc("any_peer", "call_remote", "reliable")
func request_ping(position: Vector3, label: String) -> void:
	if RpcGuard.finite_vec3(position) and RpcGuard.text_ok(label):
		request(&"ping_sent", [position, label])


## Forgets every player's last callout, so the next one goes through.
func reset_ping_cooldowns() -> void:
	reset_request_cooldowns()


## Same client->host->everyone shape as request_ping(), for the driver's horn.
@rpc("any_peer", "call_remote", "reliable")
func request_horn() -> void:
	request(&"horn_honked", [])
