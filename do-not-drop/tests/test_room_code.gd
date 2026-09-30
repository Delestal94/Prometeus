extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_room_code.gd
##
## Short LAN room codes (S-207, room_code.gd):
## - address + port -> code -> address + port round-trips for 1000 random
##   addresses (default port and explicit ports);
## - the alphabet never uses O/0/I/1, has 32 unique symbols, and codes come
##   grouped "XXXX-XXXX" (8 characters, or 12 when the port is not the default);
## - input is forgiving about case, spaces and hyphens;
## - a mistyped code is rejected with a translated message: every single
##   wrong symbol is caught, wrong length and symbols outside the alphabet
##   say so;
## - "Unirse" accepts a code or an address (main_menu.gd), and shows the
##   message instead of connecting when the code is wrong;
## - the host's HUD shows the code instead of the IP (hud.gd).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var default_port: int = int(network.get(&"DEFAULT_PORT"))

	# --- alphabet ---
	var alphabet: String = RoomCode.ALPHABET
	_expect(alphabet.length() == 32, "The alphabet has 32 symbols (got %d)" % alphabet.length())
	var seen: Dictionary = {}
	for character: String in alphabet:
		seen[character] = true
	_expect(seen.size() == 32, "The alphabet has no repeated symbol")
	for banned: String in ["O", "0", "I", "1"]:
		_expect(not alphabet.contains(banned), "The alphabet leaves out '%s'" % banned)

	# --- a known shape ---
	var code: String = RoomCode.encode("192.168.1.37")
	_expect(code.length() == 9 and code[4] == "-", "A default-port code is 'XXXX-XXXX' (got '%s')" % code)
	var long_code: String = RoomCode.encode("192.168.1.37", 9000)
	_expect(long_code.length() == 14 and long_code[4] == "-" and long_code[9] == "-",
		"A code with another port is 'XXXX-XXXX-XXXX' (got '%s')" % long_code)
	_expect(RoomCode.encode("192.168.1.37", default_port) == code,
		"Passing the default port explicitly gives the short code")
	_expect(RoomCode.encode("not an ip").is_empty(), "A non-IPv4 address has no code")
	_expect(RoomCode.encode("").is_empty(), "No address, no code")
	_expect(RoomCode.encode("256.1.1.1").is_empty(), "An octet over 255 has no code")
	_expect(RoomCode.encode("1.2.3").is_empty(), "A short address has no code")
	_expect(RoomCode.encode("10.0.0.1", 70000).is_empty(), "A port over 65535 has no code")
	_expect(RoomCode.encode("10.0.0.1", 0).is_empty(), "Port 0 has no code")

	# --- round trip: 1000 addresses ---
	var random := RandomNumberGenerator.new()
	random.seed = 207
	var round_trip_failures: int = 0
	var codes: Array[String] = []
	for index: int in 1000:
		var address: String = "%d.%d.%d.%d" % [random.randi_range(0, 255), random.randi_range(0, 255),
				random.randi_range(0, 255), random.randi_range(0, 255)]
		var port: int = default_port if index % 2 == 0 else random.randi_range(1, 65535)
		var text: String = RoomCode.encode(address, port)
		var result: Dictionary = RoomCode.decode(text)
		if text.is_empty() or not bool(result["ok"]) or String(result["address"]) != address \
				or int(result["port"]) != port:
			round_trip_failures += 1
			if round_trip_failures <= 3:
				print("  round trip failed: %s:%d -> '%s' -> %s" % [address, port, text, result])
		if index % 2 == 0:
			codes.append(text)
	_expect(round_trip_failures == 0, "1000 addresses survive the round trip (%d failed)" % round_trip_failures)
	for known: String in ["0.0.0.0", "255.255.255.255", "10.0.0.1", "192.168.0.1", "172.16.254.3"]:
		for port: int in [default_port, 1, 65535]:
			var decoded: Dictionary = RoomCode.decode(RoomCode.encode(known, port))
			_expect(bool(decoded["ok"]) and decoded["address"] == known and int(decoded["port"]) == port,
				"%s:%d round-trips" % [known, port])

	# --- forgiving input ---
	var lowered: String = code.to_lower().replace("-", " ")
	_expect(bool(RoomCode.decode(lowered)["ok"]) and RoomCode.decode(lowered)["address"] == "192.168.1.37",
		"Lower case with a space instead of the hyphen is accepted ('%s')" % lowered)
	var messy: String = "  " + code.replace("-", "") + "\t"
	_expect(bool(RoomCode.decode(messy)["ok"]), "No hyphen and stray whitespace are accepted")
	_expect(bool(RoomCode.decode(long_code.to_lower())["ok"]), "The long form is case-insensitive too")

	# --- mistyped codes ---
	var wrong_symbols: int = 0
	var undetected: int = 0
	var attempts: int = 0
	for sample: int in 40:
		var original: String = codes[sample]
		for position: int in original.length():
			if original[position] == "-":
				continue
			for replacement: String in alphabet:
				if replacement == original[position]:
					continue
				var typo: String = original.substr(0, position) + replacement + original.substr(position + 1)
				attempts += 1
				if bool(RoomCode.decode(typo)["ok"]):
					undetected += 1
	_expect(attempts > 9000 and undetected == 0,
		"Every single wrong symbol is rejected (%d of %d slipped through)" % [undetected, attempts])
	var swapped_missed: int = 0
	var swapped_tries: int = 0
	for sample: int in 200:
		var plain: String = RoomCode.normalize(codes[sample])
		for position: int in range(plain.length() - 1):
			if plain[position] == plain[position + 1]:
				continue
			swapped_tries += 1
			var swapped: String = plain.substr(0, position) + plain[position + 1] + plain[position] \
					+ plain.substr(position + 2)
			if bool(RoomCode.decode(swapped)["ok"]):
				swapped_missed += 1
	_expect(swapped_missed * 20 < swapped_tries,
		"Swapped neighbours are almost always rejected (%d of %d slipped through)" % [swapped_missed, swapped_tries])

	var length_result: Dictionary = RoomCode.decode("K7QM-4TX")
	_expect(not bool(length_result["ok"]) and length_result["error"] == RoomCode.ERROR_LENGTH,
		"A missing character is a length error")
	length_result = RoomCode.decode(code + "A")
	_expect(not bool(length_result["ok"]) and length_result["error"] == RoomCode.ERROR_LENGTH,
		"An extra character is a length error")
	var chars_result: Dictionary = RoomCode.decode("K7QM-4TX0")
	_expect(not bool(chars_result["ok"]) and chars_result["error"] == RoomCode.ERROR_CHARS,
		"A zero is a symbol that doesn't exist")
	chars_result = RoomCode.decode("K7QM-4TXO")
	_expect(not bool(chars_result["ok"]) and chars_result["error"] == RoomCode.ERROR_CHARS,
		"A letter O is a symbol that doesn't exist")
	var check_result: Dictionary = RoomCode.decode(code.substr(0, 8) + _next_symbol(code[8]))
	_expect(not bool(check_result["ok"]) and check_result["error"] == RoomCode.ERROR_CHECK,
		"A wrong last character fails the check")
	_expect(RoomCode.decode("")["error"] == RoomCode.ERROR_EMPTY, "Empty text asks for a code")

	# Every error is a real, translated message in both languages.
	for error_key: String in [RoomCode.ERROR_EMPTY, RoomCode.ERROR_LENGTH, RoomCode.ERROR_CHARS,
			RoomCode.ERROR_CHECK, RoomCode.ERROR_PORT]:
		for locale: String in ["es", "en"]:
			TranslationServer.set_locale(locale)
			var message: String = TranslationServer.translate(error_key)
			_expect(message != error_key and not message.is_empty(), "%s has a %s message" % [error_key, locale])
	TranslationServer.set_locale("es")

	# --- resolve(): code or address ---
	var by_code: Dictionary = RoomCode.resolve(code)
	_expect(bool(by_code["ok"]) and bool(by_code["is_code"]) and by_code["address"] == "192.168.1.37"
			and int(by_code["port"]) == default_port, "resolve() turns a code into address and port")
	var by_ip: Dictionary = RoomCode.resolve("  203.0.113.1 ")
	_expect(bool(by_ip["ok"]) and not bool(by_ip["is_code"]) and by_ip["address"] == "203.0.113.1"
			and int(by_ip["port"]) == default_port, "resolve() passes a plain IP through")
	var with_port: Dictionary = RoomCode.resolve("203.0.113.1:9000")
	_expect(bool(with_port["ok"]) and with_port["address"] == "203.0.113.1" and int(with_port["port"]) == 9000,
		"resolve() understands 'ip:port'")
	_expect(not bool(RoomCode.resolve("203.0.113.1:abc")["ok"])
			and RoomCode.resolve("203.0.113.1:99999")["error"] == RoomCode.ERROR_PORT, "A bad port is rejected")
	_expect(bool(RoomCode.resolve("localhost")["ok"]) and RoomCode.resolve("localhost")["address"] == "localhost",
		"'localhost' is still an address")
	_expect(RoomCode.resolve("   ")["error"] == RoomCode.ERROR_EMPTY, "Blank text asks for a code or IP")
	_expect(not bool(RoomCode.resolve("hola")["ok"]), "Something that is neither an address nor a code is rejected")

	# --- the menu: a mistyped code shows its message and does not connect ---
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	network.disconnect(&"session_ready", Callable(menu, "_on_session_ready"))
	var field: LineEdit = menu.get(&"_address_field")
	var status: Label = menu.get(&"_status_label")
	var typo_code: String = code.substr(0, 3) + _next_symbol(code[3]) + code.substr(4)
	field.text = typo_code
	menu.call(&"_join_by_address")
	_expect(status.text == TranslationServer.translate(RoomCode.ERROR_CHECK) and status.visible,
		"The menu shows the message for a mistyped code (got '%s')" % status.text)
	_expect(not bool(menu.get(&"_busy")) and not bool(network.call(&"is_online")),
		"A mistyped code never starts a connection")
	field.text = "K7QM-4TX"
	menu.call(&"_join_by_address")
	_expect(status.text == TranslationServer.translate(RoomCode.ERROR_LENGTH),
		"The menu explains a code of the wrong length")
	field.text = ""
	menu.call(&"_join_by_address")
	_expect(status.text == TranslationServer.translate("UI_MENU_STATUS_NEED_IP"),
		"An empty field asks for a code or IP")
	field.text = code
	menu.call(&"_join_by_address")
	_expect(bool(menu.get(&"_busy")) and status.text.contains("192.168.1.37"),
		"A valid code starts connecting to its address (status '%s')" % status.text)
	_expect(network.get(&"transport") == network.Transport.ENET, "Joining by code forces ENet")
	menu.call(&"_cancel_connection")
	network.call(&"leave_session")
	network.set(&"transport", network.Transport.AUTO)
	menu.free()

	# --- the host's HUD: code instead of IP ---
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	network.set(&"transport", network.Transport.ENET)
	var hosted: Error = network.call(&"host_session")
	if hosted == OK:
		await process_frame
		var label_text: String = hud.session_label.text
		var lan_address: String = network.call(&"lan_address")
		if lan_address.is_empty():
			_expect(label_text.contains(TranslationServer.translate("HUD_SESSION_NO_LAN")),
				"Without a LAN the host's corner says so ('%s')" % label_text)
		else:
			_expect(label_text.contains(RoomCode.encode(lan_address, default_port)),
				"The host's corner shows the room code ('%s')" % label_text)
			_expect(not label_text.contains(lan_address), "The host's corner no longer shows the raw IP")
	else:
		print("  (could not host on this machine, HUD check skipped: %s)" % hosted)
	network.call(&"leave_session")
	network.set(&"transport", network.Transport.AUTO)
	hud.free()

	if _failures == 0:
		print("PASS: room codes round-trip, reject typos with a message, and join/HUD use them")
	quit(_failures)


## The symbol after this one in the alphabet: a guaranteed typo.
func _next_symbol(symbol: String) -> String:
	return RoomCode.ALPHABET[(RoomCode.ALPHABET.find(symbol) + 1) % 32]


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
