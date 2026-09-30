extends Node3D
## A player's wordless voice (S-402): cartoon babble from their head, pitched
## by their colour slot, on the "Voice" bus so the "Voces" slider owns it.
## Presentation only: it observes its player and the EventBus signals that
## already reach every peer, so nothing here is replicated or changes play.
##
## The syllables are SynthAudio.callout_voice() (vowel formants, 120 ms each,
## base pitch per colour slot, the same voice the ping wheel babbles with);
## the mood comes from the syllable count and a pitch glide on the player node:
##   hurt     "ow!"    two syllables, sharp start, drops
##   ragdoll  "aaah"   four syllables, high wail sliding down
##   cheer    "yay"    three syllables, rising: an intact delivery
##   ruined   "aww"    three syllables, sagging: your own box is wrecked
## Pings are voiced by hud_notices.gd (also on the Voice bus).
##
## Triggers, all local to each peer:
##   hurt / ragdoll  the player's _flinch_time / _ragdolled rise (set by
##                   receive_package_hit(), host-authoritative, run on every
##                   peer). A ragdolling hit raises both in one call: it
##                   voices only the ragdoll, never both.
##   ruined          EventBus.package_ruined for a box in this player's hands
##                   or at their seat.
##   cheer           EventBus.house_delivery_recorded with the intact outcome
##                   for the box this player was holding or tending (the
##                   station remembers it a moment: the door takes the box
##                   out of their hands before the record reaches a client).
## One line at a time, with a short cooldown so a pile of hits or a chain of
## ruined boxes never machine-guns.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const LINES: Dictionary = {
	&"hurt": {"syllables": 2, "from": 1.25, "to": 0.95},
	&"ragdoll": {"syllables": 4, "from": 1.4, "to": 0.75},
	&"cheer": {"syllables": 3, "from": 1.0, "to": 1.25},
	&"ruined": {"syllables": 3, "from": 1.0, "to": 0.7},
}
const COOLDOWN_MSEC: int = 600
## How long a box stays "theirs" after it leaves their hands, for the delivery cheer.
const BOX_MEMORY_MSEC: int = 2500
## Random pitch spread (+/-) so repeated lines don't sound copy-pasted.
const PITCH_JITTER: float = 0.04
const HEAD_HEIGHT: float = 1.7

var player: Node
var voice: AudioStreamPlayer3D
## Slot in Player.PLAYER_COLORS (the player's colour slot, PlayerColorSlot); picks the base pitch.
var slot: int = 0
var last_line: StringName = &""
var _last_flinch: float = 0.0
var _last_ragdolled: bool = false
var _cooldown_until: int = 0
var _box_id: StringName = &""
var _box_seen_at: int = -BOX_MEMORY_MSEC
var _tween: Tween
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = &"PlayerVoice"


func _ready() -> void:
	player = get_parent()
	slot = PlayerColorSlot.slot(player.get_multiplayer_authority(), Player.PLAYER_COLORS.size())
	position = Vector3(0.0, HEAD_HEIGHT, 0.0)
	_rng.randomize()
	voice = AudioStreamPlayer3D.new()
	voice.name = "Voice"
	voice.unit_size = 6.0
	voice.max_distance = 40.0
	voice.volume_db = WorldMix.CALLOUT_VOICE_DB
	voice.bus = &"Voice" if AudioServer.get_bus_index(&"Voice") >= 0 else &"Master"
	add_child(voice)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"package_ruined", _on_package_ruined)
		bus.connect(&"house_delivery_recorded", _on_house_delivery_recorded)


func _process(_delta: float) -> void:
	var flinch: float = float(player.get(&"_flinch_time"))
	var ragdolled: bool = bool(player.get(&"_ragdolled"))
	if ragdolled and not _last_ragdolled:
		speak(&"ragdoll")
	elif flinch > _last_flinch + 0.001 and not ragdolled:
		speak(&"hurt")
	_last_flinch = flinch
	_last_ragdolled = ragdolled
	var held: DeliveryPackage = _held_box()
	if held != null:
		_box_id = held.package_id
		_box_seen_at = Time.get_ticks_msec()


## Starts a line ("hurt", "ragdoll", "cheer" or "ruined") unless the previous
## one is still inside the cooldown. Returns whether it played.
func speak(kind: StringName) -> bool:
	var now: int = Time.get_ticks_msec()
	if not LINES.has(kind) or now < _cooldown_until or voice == null:
		return false
	_cooldown_until = now + COOLDOWN_MSEC
	last_line = kind
	var line: Dictionary = LINES[kind]
	var stream: AudioStreamWAV = SynthAudio.callout_voice(slot, int(line["syllables"]))
	var jitter: float = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	voice.stream = stream
	voice.pitch_scale = float(line["from"]) * jitter
	voice.play()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(voice, ^"pitch_scale", float(line["to"]) * jitter,
		stream.get_length() / float(line["from"]))
	return true


func _held_box() -> DeliveryPackage:
	var carried: Variant = player.get(&"carried_package")
	if is_instance_valid(carried) and carried is DeliveryPackage:
		return carried
	var tended: Variant = player.get(&"tended_package")
	if is_instance_valid(tended) and tended is DeliveryPackage:
		return tended
	return null


## Whether this box is this player's own: in their hands or at their seat, or
## (on a peer that hasn't mirrored the hands yet) one that names them as its
## carrier or tender.
func owns_box(package_id: StringName) -> bool:
	var held: DeliveryPackage = _held_box()
	if held != null and held.package_id == package_id:
		return true
	var peer_id: int = player.get_multiplayer_authority()
	for candidate: Node in get_tree().get_nodes_in_group(&"cargo"):
		if candidate is DeliveryPackage and candidate.package_id == package_id:
			return candidate.carrier == player or (peer_id > 0 and candidate.tender_peer_id == peer_id)
	return false


func _on_package_ruined(package_id: StringName, _cause: String) -> void:
	if owns_box(package_id):
		speak(&"ruined")


func _on_house_delivery_recorded(_house_index: int, outcome: StringName, package_id: StringName) -> void:
	if outcome != DeliveryHouse.OUTCOME_OK:
		return
	var remembered: bool = package_id == _box_id and Time.get_ticks_msec() - _box_seen_at <= BOX_MEMORY_MSEC
	if remembered or owns_box(package_id):
		speak(&"cheer")
