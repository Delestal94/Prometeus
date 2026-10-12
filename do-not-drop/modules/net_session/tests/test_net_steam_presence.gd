extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_session/tests/test_net_steam_presence.gd
##
## What Steam shows of the game (NetSteamPresence, NetSession.steam_presence; D-2009):
## - every NetSession has one; without Steam (this headless run, ENet, CI) set_lobby_meta() and
##   set_rich_presence() only keep what they're given and fail at nothing: values as text, ""
##   removes a key, and lobby_meta() / rich_presence() hand out copies;
## - fit() cuts text to Steam's byte limits on a character boundary (a rich presence value of
##   multibyte characters stays valid UTF-8 within MAX_PRESENCE_VALUE_BYTES);
## - over a fake Steam: the rich presence goes to setRichPresence at once; lobby data waits for a
##   lobby (nothing goes out with none), and when this process's Steam lobby is up
##   (session_ready(true) with lobby_id set, and getLobbyOwner is this getSteamID) everything kept
##   goes on it and every change after that too, a "" as deleteLobbyData; a client
##   (session_ready(false), or an online peer that isn't the server) writes no lobby data; nor does
##   one whose peer already dropped (is_host() true, lobby_id still set) but Steam says another owns
##   the lobby; an ENet session with a stale lobby_id neither; once the session ends (lobby left)
##   nothing is written to the old lobby, and what was kept stays for the next one.

const CLOSED_PORT: int = 24641
## Steam ids of this process and of another member of the lobby.
const MY_STEAM_ID: int = 76561198000000001
const OTHER_STEAM_ID: int = 76561198000000002

var _failures: int = 0


# The fake mirrors GodotSteam's camelCase API, so its names can't be snake_case.
# gdlint: disable=function-name
class FakeSteam extends Object:
	var lobby_writes: Array = []
	var lobby_deletes: Array = []
	var presence_writes: Array = []
	var left: Array = []
	## Who owns every lobby, as getLobbyOwner says (0: nobody).
	var lobby_owner: int = 0

	func setLobbyData(lobby: int, key: String, value: String) -> bool:
		lobby_writes.append([lobby, key, value])
		return true

	func deleteLobbyData(lobby: int, key: String) -> bool:
		lobby_deletes.append([lobby, key])
		return true

	func getLobbyOwner(_lobby: int) -> int:
		return lobby_owner

	func getSteamID() -> int:
		return MY_STEAM_ID

	func setRichPresence(key: String, value: String) -> bool:
		presence_writes.append([key, value])
		return true

	func leaveLobby(lobby: int) -> void:
		left.append(lobby)
# gdlint: enable=function-name


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_without_steam()
	_test_fit()
	await _test_fake_steam()
	if _failures == 0:
		print("PASS: Steam lobby data and rich presence are kept without Steam and written when it can")
	quit(_failures)


func _test_without_steam() -> void:
	var session := NetSession.new()
	root.add_child(session)
	var presence: NetSteamPresence = session.steam_presence
	_expect(presence != null, "Every NetSession has its steam_presence")
	presence.set_lobby_meta({"room": "Acme", "day": 3})
	_expect(presence.lobby_meta() == {"room": "Acme", "day": "3"},
		"Without Steam the lobby data is kept, values as text (got %s)" % [presence.lobby_meta()])
	presence.set_lobby_meta({"room": ""})
	_expect(presence.lobby_meta() == {"day": "3"}, "\"\" removes a key (got %s)" % [presence.lobby_meta()])
	var copy: Dictionary = presence.lobby_meta()
	copy["day"] = "99"
	_expect(presence.lobby_meta() == {"day": "3"}, "lobby_meta() is a copy")
	presence.set_rich_presence("status", "Playing")
	_expect(presence.rich_presence() == {"status": "Playing"},
		"Without Steam the rich presence is kept (got %s)" % [presence.rich_presence()])
	session.session_ready.emit(true)
	_expect(presence.lobby_meta() == {"day": "3"} and presence.rich_presence() == {"status": "Playing"},
		"A session starting without Steam changes nothing kept")
	presence.set_rich_presence("status", "")
	_expect(presence.rich_presence().is_empty(), "\"\" removes a rich presence key")
	session.free()


func _test_fit() -> void:
	var wide: String = "ñ".repeat(200)
	var cut: String = NetSteamPresence.fit(wide, NetSteamPresence.MAX_PRESENCE_VALUE_BYTES)
	var bytes: PackedByteArray = cut.to_utf8_buffer()
	_expect(bytes.size() <= NetSteamPresence.MAX_PRESENCE_VALUE_BYTES and cut.length() == 127
		and bytes.get_string_from_utf8() == cut,
		"fit() cuts 400 bytes of 2-byte characters to 127 whole ones (got %d chars, %d bytes)"
		% [cut.length(), bytes.size()])
	_expect(NetSteamPresence.fit("short", 255) == "short", "fit() leaves short text alone")
	var session := NetSession.new()
	session.steam_presence.set_rich_presence("status", wide)
	_expect(String(session.steam_presence.rich_presence()["status"]).to_utf8_buffer().size() <= 255,
		"A rich presence value is kept within Steam's limit")
	session.free()


func _test_fake_steam() -> void:
	var session := NetSession.new()
	root.add_child(session)
	var fake := FakeSteam.new()
	session._steam = fake
	session._steam_ready = true
	var presence: NetSteamPresence = session.steam_presence
	presence.set_rich_presence("status", "Day 3")
	_expect(fake.presence_writes == [["status", "Day 3"]],
		"With Steam up the rich presence is set at once (got %s)" % [fake.presence_writes])
	presence.set_lobby_meta({"room": "Acme", "day": 3})
	_expect(fake.lobby_writes.is_empty(), "No lobby yet: lobby data is only kept (got %s)" % [fake.lobby_writes])

	# The Steam lobby comes up (NetSession._on_lobby_created sets lobby_id, then session_ready).
	session.lobby_id = 42
	fake.lobby_owner = MY_STEAM_ID
	session.active_transport = NetSession.Transport.STEAM
	fake.presence_writes.clear()
	session.session_ready.emit(true)
	_expect(fake.lobby_writes.has([42, "room", "Acme"]) and fake.lobby_writes.has([42, "day", "3"])
		and fake.lobby_writes.size() == 2,
		"The hosted lobby gets everything kept (got %s)" % [fake.lobby_writes])
	_expect(fake.presence_writes == [["status", "Day 3"]],
		"A session starting with Steam up sets the rich presence again (got %s)" % [fake.presence_writes])
	fake.lobby_writes.clear()
	presence.set_lobby_meta({"day": 4, "room": ""})
	_expect(fake.lobby_writes == [[42, "day", "4"]] and fake.lobby_deletes == [[42, "room"]]
		and presence.lobby_meta() == {"day": "4"},
		"While hosting, a change goes on the lobby and \"\" deletes the key (got %s, deleted %s)"
		% [fake.lobby_writes, fake.lobby_deletes])
	fake.lobby_deletes.clear()

	fake.lobby_writes.clear()
	session.session_ready.emit(false)
	_expect(fake.lobby_writes.is_empty(), "session_ready(false), a joiner, writes no lobby data")
	await _check_client_writes_nothing(session, fake)
	_check_not_owner_writes_nothing(session, fake)

	session.active_transport = NetSession.Transport.ENET
	presence.set_lobby_meta({"day": 5})
	_expect(fake.lobby_writes.is_empty(), "On ENet a stale lobby_id gets nothing (got %s)" % [fake.lobby_writes])
	session.active_transport = NetSession.Transport.STEAM

	session.leave_session()
	_expect(fake.left == [42] and session.lobby_id == 0, "Leaving the session leaves the lobby")
	presence.set_lobby_meta({"day": 6})
	_expect(fake.lobby_writes.is_empty() and fake.lobby_deletes.is_empty(),
		"After the session nothing is written to the old lobby")
	_expect(presence.lobby_meta() == {"day": "6"}, "...and what is kept stays for the next lobby")

	session._steam = null
	session._steam_ready = false
	session.free()
	fake.free()


## An online peer that isn't the server (a client still connecting) owns no lobby, even with a
## lobby_id: Steam would refuse its writes anyway.
func _check_client_writes_nothing(session: NetSession, fake: FakeSteam) -> void:
	var peer := ENetMultiplayerPeer.new()
	_expect(peer.create_client("127.0.0.1", CLOSED_PORT) == OK, "A client peer starts connecting")
	session.multiplayer.multiplayer_peer = peer
	await process_frame
	_expect(session.is_online() and not session.is_host(), "The session is a client now")
	session.steam_presence.set_lobby_meta({"day": 9})
	_expect(fake.lobby_writes.is_empty(), "A client writes no lobby data (got %s)" % [fake.lobby_writes])
	peer.close()
	session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## A client whose peer already dropped counts as a host (offline) while its lobby_id is still set:
## Steam says another member owns that lobby, so nothing is written to it, "" included.
func _check_not_owner_writes_nothing(session: NetSession, fake: FakeSteam) -> void:
	fake.lobby_owner = OTHER_STEAM_ID
	_expect(session.is_host() and session.lobby_id == 42, "A dropped client looks like a host with a lobby")
	session.steam_presence.set_lobby_meta({"day": 7, "room": ""})
	session.session_ready.emit(true)
	_expect(fake.lobby_writes.is_empty() and fake.lobby_deletes.is_empty(),
		"A peer that doesn't own the lobby writes nothing to it (got %s, deleted %s)"
		% [fake.lobby_writes, fake.lobby_deletes])
	fake.lobby_owner = MY_STEAM_ID


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
