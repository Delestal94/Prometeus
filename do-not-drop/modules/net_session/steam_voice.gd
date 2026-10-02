class_name SteamVoice
extends Node
## Voice over Steam: capture and send. Portable module (docs/modulos.md).
##
## Voice travels outside the authoritative simulation. Nothing here goes
## through the host's game state: each peer records its own microphone with
## Steam's voice API (already compressed, Opus under the hood) and hands the
## packets to everybody else on an unreliable, ordered channel of its own, so
## a dropped packet is a dropped syllable and never a stall of the game's
## reliable traffic. Received packets are decompressed and handed out through
## `voice_received`; playback is the owner's business.
##
## Steam is reached through Engine.get_singleton, never by name: this script
## has to compile where GodotSteam is absent (CI, headless tests). Tests swap
## `backend` for a fake and force `override_steam_session`.
##
## What the game decides, through the hooks at the end: whether voice is on
## at all, push-to-talk or open mic, and whether this session runs over
## Steam (by default: `session.active_transport` is STEAM and the peer is
## connected).

## Emitted on every peer that receives someone else's voice, already
## decompressed to 16-bit mono PCM at `sample_rate`.
signal voice_received(peer_id: int, pcm: PackedByteArray, sample_rate: int)
## The local microphone opened or closed (for a "talking" icon).
signal talking_changed(talking: bool)

## Its own channel so voice never queues behind the game's unreliable sync.
const VOICE_CHANNEL: int = 3
## Steam's k_EVoiceResultOK.
const VOICE_RESULT_OK: int = 0
## Steam packs a few tens of ms per getVoice(); anything this large is not a
## voice packet and is dropped before it reaches the decoder.
const MAX_PACKET_BYTES: int = 8192
const FALLBACK_SAMPLE_RATE: int = 24000
## Steam keeps handing out recorded voice for a moment after
## stopVoiceRecording(); drain it this many frames so the end of a phrase is
## sent instead of arriving stale at the start of the next one.
const DRAIN_FRAMES: int = 12
## Packets decoded per peer: each costs a decoder call before anything can
## judge it, so a peer flooding the voice channel is cut here. Steam hands out
## a packet per ~20 ms of speech at most (about 50 a second, however fast the
## sender's frames are), so this is more than twice what a real voice needs.
## Its own budget, not RpcGuard's: voice must never spend the one that lets
## go of a box.
const VOICE_PACKETS_PER_SECOND: float = 120.0
const VOICE_PACKET_BURST: float = 30.0

## The Steam singleton, or a stand-in object in tests. null means no voice.
var backend: Object = null
## The session this voice belongs to (a NetSession), or null.
var session: NetSession = null
## Tests: 1 forces "over Steam", 0 forces "not over Steam", -1 asks the session.
var override_steam_session: int = -1
## The input action held to talk (push-to-talk).
var talk_action: StringName = &"voice_talk"
var talking: bool = false

var _muted: Dictionary = {}  # peer_id -> true
var _peer_volume: Dictionary = {}  # peer_id -> 0..1
var _voice_tokens: Dictionary = {}  # peer_id -> packets left (float)
var _voice_token_msec: Dictionary = {}  # peer_id -> when they were counted
var _drain_frames: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton(&"Steam"):
		backend = Engine.get_singleton(&"Steam")
	multiplayer.peer_disconnected.connect(_forget_peer)


func _process(_delta: float) -> void:
	var held: bool = InputMap.has_action(talk_action) and Input.is_action_pressed(talk_action)
	tick(held)


## One frame of capture: open or close the microphone, then send whatever
## Steam has recorded since the last frame. Separate from _process so tests
## can drive it without real key presses.
func tick(talk_held: bool) -> void:
	_set_talking(should_capture(talk_held))
	if talking:
		_send_pending_voice()
	elif _drain_frames > 0:
		_drain_frames -= 1
		_send_pending_voice()


## The whole rule for opening the microphone, in one place: the general
## switch first (off never records), then a Steam session with a voice API,
## then push-to-talk or open mic.
func should_capture(talk_held: bool) -> bool:
	if not _voice_enabled():
		return false
	if not _steam_session() or backend == null or not backend.has_method(&"startVoiceRecording"):
		return false
	return talk_held or not _push_to_talk()


func set_peer_muted(peer_id: int, muted: bool) -> void:
	if muted:
		_muted[peer_id] = true
	else:
		_muted.erase(peer_id)


func is_peer_muted(peer_id: int) -> bool:
	return _muted.has(peer_id)


func set_peer_volume(peer_id: int, volume: float) -> void:
	_peer_volume[peer_id] = clampf(volume, 0.0, 1.0)


func peer_volume(peer_id: int) -> float:
	return float(_peer_volume.get(peer_id, 1.0))


## Forget everything per-peer when a session ends; peer ids are reused.
func clear_peers() -> void:
	_muted.clear()
	_peer_volume.clear()
	_voice_tokens.clear()
	_voice_token_msec.clear()


## Takes one packet from `peer_id`'s budget at `now_msec` (Time.get_ticks_msec());
## false once the burst is spent, until it refills at VOICE_PACKETS_PER_SECOND.
func take_voice_packet(peer_id: int, now_msec: int) -> bool:
	var tokens: float = float(_voice_tokens.get(peer_id, VOICE_PACKET_BURST))
	var since: int = maxi(0, now_msec - int(_voice_token_msec.get(peer_id, now_msec)))
	tokens = minf(VOICE_PACKET_BURST, tokens + since * VOICE_PACKETS_PER_SECOND / 1000.0)
	_voice_token_msec[peer_id] = now_msec
	if tokens < 1.0:
		_voice_tokens[peer_id] = tokens
		return false
	_voice_tokens[peer_id] = tokens - 1.0
	return true


func _forget_peer(peer_id: int) -> void:
	_muted.erase(peer_id)
	_peer_volume.erase(peer_id)
	_voice_tokens.erase(peer_id)
	_voice_token_msec.erase(peer_id)


func _set_talking(value: bool) -> void:
	if value == talking:
		return
	talking = value
	_drain_frames = 0 if value else DRAIN_FRAMES
	if backend != null:
		backend.call(&"startVoiceRecording" if value else &"stopVoiceRecording")
	talking_changed.emit(value)


func _send_pending_voice() -> void:
	if backend == null or not backend.has_method(&"getVoice"):
		return
	var result: Variant = backend.call(&"getVoice")
	if not result is Dictionary:
		return
	var voice: Dictionary = result
	if int(voice.get("result", -1)) != VOICE_RESULT_OK:
		return
	# The key moved between GodotSteam versions ("buffer" / "voice_data").
	var buffer: PackedByteArray = voice.get("buffer", voice.get("voice_data", PackedByteArray()))
	var written: int = int(voice.get("written", buffer.size()))
	if written <= 0 or written > MAX_PACKET_BYTES:
		return
	if written < buffer.size():
		buffer = buffer.slice(0, written)
	if _connected():
		_receive_voice.rpc(buffer)


@rpc("any_peer", "call_remote", "unreliable_ordered", VOICE_CHANNEL)
func _receive_voice(packet: PackedByteArray) -> void:
	if RpcGuard.sender_ok(self):
		receive_packet(multiplayer.get_remote_sender_id(), packet)


## Where a remote packet lands. Public so tests can feed it without a session.
func receive_packet(peer_id: int, packet: PackedByteArray) -> void:
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return
	if is_peer_muted(peer_id) or peer_volume(peer_id) <= 0.0:
		return
	if not _voice_enabled():
		return
	if backend == null or not backend.has_method(&"decompressVoice"):
		return
	if not take_voice_packet(peer_id, Time.get_ticks_msec()):
		return
	var rate: int = FALLBACK_SAMPLE_RATE
	if backend.has_method(&"getVoiceOptimalSampleRate"):
		rate = maxi(int(backend.call(&"getVoiceOptimalSampleRate")), 8000)
	var result: Variant = backend.call(&"decompressVoice", packet, rate)
	if not result is Dictionary or int((result as Dictionary).get("result", -1)) != VOICE_RESULT_OK:
		return
	var pcm: PackedByteArray = (result as Dictionary).get("uncompressed", PackedByteArray())
	var size: int = int((result as Dictionary).get("size", pcm.size()))
	if size <= 0:
		return
	if size < pcm.size():
		pcm = pcm.slice(0, size)
	voice_received.emit(peer_id, pcm, rate)


func _steam_session() -> bool:
	if override_steam_session >= 0:
		return override_steam_session == 1
	if session == null or not _connected():
		return false
	return session.active_transport == NetSession.Transport.STEAM


## A peer that is still joining counts as online for the session, but an
## RPC through it fails every frame: no microphone until it is connected.
func _connected() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer is not OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _exit_tree() -> void:
	# Never leave Steam recording the microphone behind a closed game.
	_set_talking(false)


# --- Hooks the game fills in ---------------------------------------------------

## The general switch: off never records and never plays.
func _voice_enabled() -> bool:
	return true


## Push-to-talk (true) or open mic (false).
func _push_to_talk() -> bool:
	return true
