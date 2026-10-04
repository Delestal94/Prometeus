class_name SteamVoice
extends Node
## Voice over Steam: capture and send. Portable module (docs/modulos.md).
##
## Voice travels outside the authoritative simulation. Nothing here goes
## through the host's game state: each peer records its own microphone with
## Steam's voice API (already compressed, Opus under the hood) and hands the
## packets to everybody else on an unreliable, ordered channel of its own, so
## a dropped packet is a dropped syllable and never a stall of the game's
## reliable traffic. Received packets are decompressed, within a budget per
## peer, and handed out through `voice_received`; playback is the owner's
## business (VoicePlayback).
##
## "Everybody else" is not peer to peer: a client is connected to the host
## only, so its packets reach the other clients through the host
## (server_relay), which forwards a copy to each one. With N peers all
## talking, every client downloads N - 1 streams and the host uploads
## (N - 1)^2 of them: its own to N - 1 clients, plus each of the N - 1
## clients' to the N - 2 others. That square is why every peer's sending is
## capped (VOICE_SEND_PACKETS_PER_SECOND, VOICE_SEND_BYTES_PER_SECOND) and
## why a game should count voice in the host's uplink: at the caps a stream
## is about 14 KB/s with its framing, so voice alone takes ~1.8 Mbit/s of the
## host's upload with 5 talking and ~5.6 Mbit/s with 8.
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
## Steam packs a few tens of ms of speech per getVoice(); a packet past this
## is a long hitch's backlog (stale by then) or not voice at all, and is
## dropped before it is sent or decoded. Was 8192 (N-212): one packet that
## size is a whole second of VOICE_SEND_BYTES_PER_SECOND.
const MAX_PACKET_BYTES: int = 2048
const FALLBACK_SAMPLE_RATE: int = 24000
## What this peer sends at most, whatever its frame rate (N-212): every
## frame's getVoice() would otherwise be an RPC, and the host relays each
## one (see the top). ASSUMED, not yet measured with real Steam: that Steam
## hands out a packet per ~20 ms of speech (about 50 a second) and that its
## compressed speech is a few KB a second, so a voice stays under both.
## The budget is looked at before getVoice() (send_budget_ready()): Steam
## keeps what it recorded until it is asked, so a frame without budget
## leaves it there and it goes out later in one bigger packet. What is lost
## is a packet taken from Steam that is over MAX_PACKET_BYTES or over the
## bytes left, counted in `dropped_sends`. These are what a bandwidth budget
## should count.
const VOICE_SEND_PACKETS_PER_SECOND: float = 60.0
const VOICE_SEND_BYTES_PER_SECOND: float = 8192.0
## The send budget's burst: a tenth of a second of packets, and room for one
## packet of MAX_PACKET_BYTES (or one that size could never leave).
const VOICE_SEND_PACKET_BURST: float = 6.0
const VOICE_SEND_BYTE_BURST: float = 2048.0
## The bytes send_budget_ready() wants left before Steam is asked: about one
## ~20 ms packet of compressed speech (ASSUMED, not measured with real
## Steam). Asking with less would most likely take out a packet the bytes
## can't cover, and lose it; waiting loses nothing.
const VOICE_SEND_MIN_PACKET_BYTES: int = 64
## Steam keeps handing out recorded voice for a moment after
## stopVoiceRecording(); drain it this many frames so the end of a phrase is
## sent instead of arriving stale at the start of the next one.
const DRAIN_FRAMES: int = 12
## Packets decoded per peer: each costs a decoder call before anything can
## judge it, so a peer flooding the voice channel is cut here. A capped
## sender sends at most VOICE_SEND_PACKETS_PER_SECOND, however fast its
## frames are (and Steam is ASSUMED, not measured, to hand out about 50 a
## second, one per ~20 ms of speech), so this is twice what a voice needs.
## Its own budget, not RpcGuard's: voice must never spend the one that lets
## go of a box.
const VOICE_PACKETS_PER_SECOND: float = 120.0
const VOICE_PACKET_BURST: float = 30.0
## Bytes decoded per peer, the same way: the decoder's work grows with the
## packet, and 30 packets of MAX_PACKET_BYTES would still be a lot of it.
## Twice what a capped sender sends, with a second of that as burst for
## packets that arrive bunched after a stall.
const VOICE_BYTES_PER_SECOND: float = 2.0 * VOICE_SEND_BYTES_PER_SECOND
const VOICE_BYTE_BURST: float = VOICE_SEND_BYTES_PER_SECOND

## The Steam singleton, or a stand-in object in tests. null means no voice.
var backend: Object = null
## The session this voice belongs to (a NetSession), or null.
var session: NetSession = null
## Tests: 1 forces "over Steam", 0 forces "not over Steam", -1 asks the session.
var override_steam_session: int = -1
## Tests: >= 0 is the clock (msec) the send and decode budgets read; -1 is
## Time.get_ticks_msec().
var override_clock_msec: int = -1
## The input action held to talk (push-to-talk).
var talk_action: StringName = &"voice_talk"
var talking: bool = false
## Packets taken from Steam that never left: larger than MAX_PACKET_BYTES, or
## over the send bytes left (a frame without budget doesn't ask Steam, and
## loses nothing). If it climbs while someone simply talks, the caps are too
## tight for Steam's real voice. clear_peers() puts it back to 0.
var dropped_sends: int = 0

var _muted: Dictionary = {}  # peer_id -> true
var _peer_volume: Dictionary = {}  # peer_id -> 0..1
var _voice_tokens: Dictionary = {}  # peer_id -> packets left (float)
var _voice_bytes: Dictionary = {}  # peer_id -> bytes left (float)
var _voice_token_msec: Dictionary = {}  # peer_id -> when they were counted
var _send_packets: float = VOICE_SEND_PACKET_BURST
var _send_bytes: float = VOICE_SEND_BYTE_BURST
var _send_msec: int = -1  # When the send budget was counted; -1: never.
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


## Forget everything per-peer when a session ends; peer ids are reused. The
## send budget and `dropped_sends` start over too: the next session counts
## its own.
func clear_peers() -> void:
	_muted.clear()
	_peer_volume.clear()
	_voice_tokens.clear()
	_voice_bytes.clear()
	_voice_token_msec.clear()
	dropped_sends = 0
	_send_packets = VOICE_SEND_PACKET_BURST
	_send_bytes = VOICE_SEND_BYTE_BURST
	_send_msec = -1


## Takes one packet of `bytes` from `peer_id`'s decode budget at `now_msec`
## (Time.get_ticks_msec()): false, spending nothing, while its packets
## (VOICE_PACKET_BURST, refilled at VOICE_PACKETS_PER_SECOND) or its bytes
## (VOICE_BYTE_BURST, at VOICE_BYTES_PER_SECOND) can't cover it. Without
## `bytes` only the packets count.
func take_voice_packet(peer_id: int, now_msec: int, bytes: int = 0) -> bool:
	var since: int = now_msec - int(_voice_token_msec.get(peer_id, now_msec))
	var packets: float = _refilled(float(_voice_tokens.get(peer_id, VOICE_PACKET_BURST)), since,
		VOICE_PACKETS_PER_SECOND, VOICE_PACKET_BURST)
	var budget: float = _refilled(float(_voice_bytes.get(peer_id, VOICE_BYTE_BURST)), since,
		VOICE_BYTES_PER_SECOND, VOICE_BYTE_BURST)
	_voice_token_msec[peer_id] = now_msec
	var allowed: bool = packets >= 1.0 and budget >= bytes
	_voice_tokens[peer_id] = packets - 1.0 if allowed else packets
	_voice_bytes[peer_id] = budget - bytes if allowed else budget
	return allowed


## Takes one packet of `bytes` from this peer's own send budget at `now_msec`
## (Time.get_ticks_msec()): false, spending nothing, while its packets
## (VOICE_SEND_PACKET_BURST, refilled at VOICE_SEND_PACKETS_PER_SECOND) or its
## bytes (VOICE_SEND_BYTE_BURST, at VOICE_SEND_BYTES_PER_SECOND) can't cover
## it, so a big packet held back never costs the smaller ones after it.
func take_send_budget(now_msec: int, bytes: int) -> bool:
	_refill_send_budget(now_msec)
	if _send_packets < 1.0 or _send_bytes < bytes:
		return false
	_send_packets -= 1.0
	_send_bytes -= bytes
	return true


## Whether this peer's send budget, refilled to `now_msec` and spending
## nothing, has a packet left and at least VOICE_SEND_MIN_PACKET_BYTES.
## Looked at before getVoice(): while it says no, the voice stays in Steam
## (see VOICE_SEND_PACKETS_PER_SECOND) instead of being taken and lost.
func send_budget_ready(now_msec: int) -> bool:
	_refill_send_budget(now_msec)
	return _send_packets >= 1.0 and _send_bytes >= VOICE_SEND_MIN_PACKET_BYTES


func _refill_send_budget(now_msec: int) -> void:
	var since: int = now_msec - _send_msec if _send_msec >= 0 else 0
	_send_msec = now_msec
	_send_packets = _refilled(_send_packets, since, VOICE_SEND_PACKETS_PER_SECOND, VOICE_SEND_PACKET_BURST)
	_send_bytes = _refilled(_send_bytes, since, VOICE_SEND_BYTES_PER_SECOND, VOICE_SEND_BYTE_BURST)


## A token bucket's `level` after `since_msec` more: refilled at `rate` a
## second, never past `burst` (a clock that went back refills nothing).
static func _refilled(level: float, since_msec: int, rate: float, burst: float) -> float:
	return minf(burst, level + maxi(0, since_msec) * rate / 1000.0)


func _forget_peer(peer_id: int) -> void:
	_muted.erase(peer_id)
	_peer_volume.erase(peer_id)
	_voice_tokens.erase(peer_id)
	_voice_bytes.erase(peer_id)
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
	# The budget before getVoice(): taking the voice out of Steam without
	# budget to send it would lose it, leaving it there loses nothing.
	var now: int = _now_msec()
	if not send_budget_ready(now):
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
	if written <= 0 or buffer.is_empty():
		return
	if written > MAX_PACKET_BYTES:
		dropped_sends += 1
		return
	if written < buffer.size():
		buffer = buffer.slice(0, written)
	# All or nothing: a packet over the bytes left is lost (Steam no longer
	# has it); one within them spends a packet and its bytes.
	if not take_send_budget(now, buffer.size()):
		dropped_sends += 1
		return
	_send_packet(buffer)


## Where a recorded packet within the budget leaves: to every other peer,
## through the host (see the top). Tests override it to count what would go
## on the wire.
func _send_packet(buffer: PackedByteArray) -> void:
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
	if not take_voice_packet(peer_id, _now_msec(), packet.size()):
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


func _now_msec() -> int:
	return override_clock_msec if override_clock_msec >= 0 else Time.get_ticks_msec()


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
