extends Node
## Proximity voice, Steam only (N-212). The first slice: capture and send.
##
## Voice travels outside the authoritative simulation. Nothing here goes
## through the host's game state: each peer records its own microphone with
## Steam's voice API (already compressed, Opus under the hood) and hands the
## packets to everybody else on an unreliable, ordered channel of its own, so
## a dropped packet is a dropped syllable and never a stall of the game's
## reliable traffic.
##
## LAN/ENet has no voice (N-212.4, decided with critico-diseno in N-704.3):
## an AudioEffectCapture + encoder path would double the bugs in the feature
## that was the number one complaint in both reference games. Over LAN the
## crew is in the same room anyway.
##
## Steam is reached through Engine.get_singleton, never by name, for the same
## reason as network_manager.gd: this script has to compile on CI and in the
## headless tests, where GodotSteam is absent. Tests swap `backend` for a fake.
##
## Playback (AudioStreamPlayer3D at each player's head, N-212.2) is the next
## slice: until then received packets are decompressed and handed out through
## `voice_received`.

## Emitted on every peer that receives someone else's voice, already
## decompressed to 16-bit mono PCM at `sample_rate`.
signal voice_received(peer_id: int, pcm: PackedByteArray, sample_rate: int)
## The local microphone opened or closed (for a "talking" icon later).
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

## The Steam singleton, or a stand-in object in tests. null means no voice.
var backend: Object = null
## Whether this session runs over Steam. Resolved from NetworkManager unless
## a test sets `override_steam_session`.
var override_steam_session: int = -1
var talking: bool = false

var _muted: Dictionary = {}  # peer_id -> true
var _peer_volume: Dictionary = {}  # peer_id -> 0..1
var _drain_frames: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton(&"Steam"):
		backend = Engine.get_singleton(&"Steam")
	multiplayer.peer_disconnected.connect(_forget_peer)


func _process(_delta: float) -> void:
	var held: bool = InputMap.has_action(&"voice_talk") and Input.is_action_pressed(&"voice_talk")
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
## switch first (off never records, N-212.3), then a Steam session with a
## voice API, then push-to-talk or open mic.
func should_capture(talk_held: bool) -> bool:
	if not _settings_bool(&"voice_chat_enabled", false):
		return false
	if not _steam_session() or backend == null or not backend.has_method(&"startVoiceRecording"):
		return false
	return talk_held or not _settings_bool(&"voice_push_to_talk", true)


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


func _forget_peer(peer_id: int) -> void:
	_muted.erase(peer_id)
	_peer_volume.erase(peer_id)


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
	receive_packet(multiplayer.get_remote_sender_id(), packet)


## Where a remote packet lands. Public so tests can feed it without a session.
func receive_packet(peer_id: int, packet: PackedByteArray) -> void:
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return
	if is_peer_muted(peer_id) or peer_volume(peer_id) <= 0.0:
		return
	if not _settings_bool(&"voice_chat_enabled", false):
		return
	if backend == null or not backend.has_method(&"decompressVoice"):
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
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network == null or not _connected():
		return false
	return int(network.get(&"active_transport")) == 1  # NetworkManager.Transport.STEAM


## A peer that is still joining counts as online for NetworkManager, but an
## RPC through it fails every frame: no microphone until it is connected.
func _connected() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer is not OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _settings_bool(property: StringName, fallback: bool) -> bool:
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	if settings == null:
		return fallback
	return bool(settings.get(property))


func _exit_tree() -> void:
	# Never leave Steam recording the microphone behind a closed game.
	_set_talking(false)
