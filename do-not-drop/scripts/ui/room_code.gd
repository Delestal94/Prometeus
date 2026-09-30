class_name RoomCode
extends RefCounted
## Short room codes for joining a LAN game (S-207): "K7QM-4TXA" instead of
## "192.168.1.37". Static and stateless; the menu and the HUD both use it.
##
## The alphabet has 32 symbols (5 bits each) and leaves out the look-alikes
## O/0 and I/1, so a code read aloud or off a screen is hard to mistype.
##
## The problem: IPv4 (32 bits) + port (16 bits) = 48 bits, and 8 characters
## are only 40. Decision: the port is implicit. Every room the menu creates
## uses NetworkManager.DEFAULT_PORT, so the everyday code carries just the
## address and stays short; a room on another port gets a longer code that
## also carries it. The length tells them apart, so there is no flag to lose:
##
##   8 characters  = 7 data characters (35 bits: 3 zero + the 32-bit address)
##                   + 1 check character; default port.       "K7QM-4TXA"
##   12 characters = 11 data characters (55 bits: 7 zero + address + port)
##                   + 1 check character; explicit port.      "K7QM-4TXA-7WBN"
##
## The check character is a weighted sum of the data symbols mod 32 with odd
## weights (1, 3, 5...), which are invertible mod 32: any single mistyped
## symbol is always caught, and so are almost all swapped neighbours. The
## leading zero bits must really be zero, which rejects a few more random
## strings. Input is forgiving about case, spaces and hyphens; it is never
## forgiving about symbols outside the alphabet (an "O" is not silently a
## "0": the message says the symbol does not exist).
##
## Steam rooms do not use this: they follow the Steam invitation.

const ALPHABET: String = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const BITS_PER_SYMBOL: int = 5
const SHORT_LENGTH: int = 8   # address only, default port
const LONG_LENGTH: int = 12   # address + port
const GROUP: int = 4
const CHECK_SEED: int = 7

## Error values are strings_ui.csv keys, so the caller only has to tr() them.
const ERROR_EMPTY: String = "UI_MENU_STATUS_NEED_IP"
const ERROR_LENGTH: String = "UI_MENU_STATUS_CODE_LENGTH"
const ERROR_CHARS: String = "UI_MENU_STATUS_CODE_CHARS"
const ERROR_CHECK: String = "UI_MENU_STATUS_CODE_CHECK"
const ERROR_PORT: String = "UI_MENU_STATUS_BAD_PORT"


static func default_port() -> int:
	return NetworkManager.DEFAULT_PORT


## "192.168.1.37" (+ port) -> "K7QM-4TXA". Empty when the address is not a
## dotted IPv4 or the port is outside 1..65535. A negative port means the
## default one and yields the short code.
static func encode(address: String, port: int = -1) -> String:
	var ip: int = _parse_ipv4(address)
	if ip < 0:
		return ""
	if port == default_port():
		port = -1
	var data_length: int = SHORT_LENGTH - 1
	var value: int = ip
	if port != -1:
		if port < 1 or port > 65535:
			return ""
		data_length = LONG_LENGTH - 1
		value = (ip << 16) | port
	var symbols: PackedInt32Array = PackedInt32Array()
	symbols.resize(data_length)
	for index: int in range(data_length - 1, -1, -1):
		symbols[index] = value & 31
		value >>= BITS_PER_SYMBOL
	var text: String = ""
	for symbol: int in symbols:
		text += ALPHABET[symbol]
	text += ALPHABET[_check(symbols)]
	return _grouped(text)


## Room code -> {"ok": true, "address": "192.168.1.37", "port": 7777}, or
## {"ok": false, "error": "<strings_ui key>"} when it is empty, the wrong
## length, has symbols that do not exist or fails the check character.
static func decode(text: String) -> Dictionary:
	var code: String = normalize(text)
	if code.is_empty():
		return _failure(ERROR_EMPTY)
	if code.length() != SHORT_LENGTH and code.length() != LONG_LENGTH:
		return _failure(ERROR_LENGTH)
	var symbols: PackedInt32Array = PackedInt32Array()
	for character: String in code:
		var symbol: int = ALPHABET.find(character)
		if symbol < 0:
			return _failure(ERROR_CHARS)
		symbols.append(symbol)
	var check: int = symbols[symbols.size() - 1]
	symbols.resize(symbols.size() - 1)
	if _check(symbols) != check:
		return _failure(ERROR_CHECK)
	var value: int = 0
	for symbol: int in symbols:
		value = (value << BITS_PER_SYMBOL) | symbol
	var port: int = default_port()
	if code.length() == LONG_LENGTH:
		port = value & 0xFFFF
		value >>= 16
		if port < 1:
			return _failure(ERROR_CHECK)
	if value > 0xFFFFFFFF:
		return _failure(ERROR_CHECK)
	return {
		"ok": true,
		"address": "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255],
		"port": port,
	}


## What the "Unirse" field accepts: a room code, or an address. Anything with
## a dot or colon (or "localhost") is an address and is passed through as it
## is, with an optional ":port"; everything else must be a valid code.
## Returns the same shape as decode(), plus "is_code".
static func resolve(text: String) -> Dictionary:
	var typed: String = text.strip_edges()
	if typed.is_empty():
		return _failure(ERROR_EMPTY)
	if not (typed.contains(".") or typed.contains(":") or typed.to_lower() == "localhost"):
		var result: Dictionary = decode(typed)
		result["is_code"] = true
		return result
	var address: String = typed
	var port: int = default_port()
	if typed.count(":") == 1:
		address = typed.get_slice(":", 0).strip_edges()
		var port_text: String = typed.get_slice(":", 1).strip_edges()
		if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
			return {"ok": false, "error": ERROR_PORT, "is_code": false}
		port = int(port_text)
	return {"ok": true, "address": address, "port": port, "is_code": false}


## Upper case, without spaces, hyphens or underscores.
static func normalize(text: String) -> String:
	var clean: String = ""
	for character: String in text.to_upper():
		if character in [" ", "-", "_", "\t", "\n"]:
			continue
		clean += character
	return clean


static func _grouped(code: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for start: int in range(0, code.length(), GROUP):
		parts.append(code.substr(start, GROUP))
	return "-".join(parts)


static func _check(symbols: PackedInt32Array) -> int:
	var sum: int = CHECK_SEED
	for index: int in symbols.size():
		sum += symbols[index] * (2 * index + 1)
	return sum & 31


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


## The address as a 32-bit number, or -1 when it is not a dotted IPv4.
static func _parse_ipv4(address: String) -> int:
	var parts: PackedStringArray = address.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var value: int = 0
	for part: String in parts:
		if not part.is_valid_int() or part.length() > 3:
			return -1
		var octet: int = int(part)
		if octet < 0 or octet > 255:
			return -1
		value = (value << 8) | octet
	return value
