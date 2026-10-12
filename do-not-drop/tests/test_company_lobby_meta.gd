extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_lobby_meta.gd
##
## What Steam shows of the company in play (expansion D-2009, company_lobby_meta.gd,
## CompanyLobbyMeta), the part that needs no Steam:
## - with an active company the lobby data is {company_name, company_day}, both as text (Steam takes
##   text only), and the rich presence {"status": tr("UI_COMPANY_PRESENCE") % [name, day]} in the
##   current language (Spanish and English checked against the table: each translated, different,
##   with the name and the day in it);
## - without an active company (switched off, or none at all) every key is still there with "" as
##   its value, so a lobby or presence that showed a company stops showing it (NetSteamPresence
##   removes a key given "");
## - an active company with no name has no company_name ("") but its day, and the presence reads
##   tr("UI_COMPANY_PRESENCE_UNNAMED") % day;
## - a long name is cut to MAX_NAME_CHARS and the presence line stays within Steam's 256 bytes even
##   with 4-byte characters; control characters and surrounding spaces go;
## - publish() hands it to a NetSession's steam_presence (NetSteamPresence, kept without Steam): the
##   host's lobby data and presence, a client's presence only, and null clears both.
## The wiring in CompanyRoot (when it publishes and that it clears on leaving) is in test_company_root.

## The CompanyState autoload's script: each check gets a company of its own, not the autoload.
const COMPANY_STATE := preload("res://scripts/core/company/company_state.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var locale: String = TranslationServer.get_locale()
	var company: COMPANY_STATE = COMPANY_STATE.new()
	root.add_child(company)
	_check_without_company(company)
	_check_named(company)
	_check_unnamed(company)
	_check_long_name(company)
	_check_publish(company)
	TranslationServer.set_locale(locale)
	company.free()
	if _failures == 0:
		print("PASS: company lobby data and rich presence are built with and without a company")
	quit(_failures)


func _check_without_company(company: COMPANY_STATE) -> void:
	company.reset()
	var cleared: Dictionary = {CompanyLobbyMeta.NAME_KEY: "", CompanyLobbyMeta.DAY_KEY: ""}
	_expect(CompanyLobbyMeta.lobby_meta(company) == cleared,
		"An inactive company gives both lobby keys empty (got %s)" % [CompanyLobbyMeta.lobby_meta(company)])
	_expect(CompanyLobbyMeta.lobby_meta(null) == cleared, "No company at all gives the same")
	_expect(CompanyLobbyMeta.rich_presence(company) == {"status": ""}
		and CompanyLobbyMeta.rich_presence(null) == {"status": ""},
		"Without a company the presence's status is empty (got %s)" % [CompanyLobbyMeta.rich_presence(company)])


func _check_named(company: COMPANY_STATE) -> void:
	company.new_company("Acme SRL")
	company.day = 3
	var meta: Dictionary = CompanyLobbyMeta.lobby_meta(company)
	_expect(meta == {"company_name": "Acme SRL", "company_day": "3"},
		"An active company gives its name and day (got %s)" % [meta])
	_expect(typeof(meta["company_day"]) == TYPE_STRING, "The day goes as text, as Steam takes it")
	var key: String = CompanyLobbyMeta.PRESENCE_TEXT
	TranslationServer.set_locale("es")
	var spanish: String = CompanyLobbyMeta.presence_text(company)
	_expect(spanish == tr(key) % ["Acme SRL", 3],
		"In Spanish the presence is %s with the company and its day (got '%s')" % [key, spanish])
	_expect(CompanyLobbyMeta.rich_presence(company) == {"status": spanish}, "The presence goes under 'status'")
	TranslationServer.set_locale("en")
	var english: String = CompanyLobbyMeta.presence_text(company)
	_expect(english == tr(key) % ["Acme SRL", 3], "In English too (got '%s')" % english)
	_expect_translated(key, spanish, english, ["Acme SRL", "3"])


func _check_unnamed(company: COMPANY_STATE) -> void:
	company.new_company()
	company.day = 7
	_expect(CompanyLobbyMeta.lobby_meta(company) == {"company_name": "", "company_day": "7"},
		"A company with no name has no name key but its day (got %s)" % [CompanyLobbyMeta.lobby_meta(company)])
	var key: String = CompanyLobbyMeta.PRESENCE_TEXT_UNNAMED
	TranslationServer.set_locale("es")
	var spanish: String = CompanyLobbyMeta.presence_text(company)
	_expect(spanish == tr(key) % 7,
		"With no name the presence is %s with the day alone, in Spanish (got '%s')" % [key, spanish])
	TranslationServer.set_locale("en")
	var english: String = CompanyLobbyMeta.presence_text(company)
	_expect(english == tr(key) % 7, "...and in English (got '%s')" % english)
	_expect_translated(key, spanish, english, ["7"])
	company.company_name = "  \t \n "
	_expect(CompanyLobbyMeta.lobby_meta(company)["company_name"] == ""
		and CompanyLobbyMeta.presence_text(company) == english,
		"A name of blanks and control characters counts as no name")


func _check_long_name(company: COMPANY_STATE) -> void:
	TranslationServer.set_locale("es")
	company.new_company("  " + "Logística ".repeat(20))
	company.day = 99999
	var shown: String = String(CompanyLobbyMeta.lobby_meta(company)["company_name"])
	_expect(shown.length() <= CompanyLobbyMeta.MAX_NAME_CHARS and shown.begins_with("Logística")
		and shown == shown.strip_edges(),
		"A long name is cut to %d characters, trimmed (got %d: '%s')"
		% [CompanyLobbyMeta.MAX_NAME_CHARS, shown.length(), shown])
	company.company_name = String.chr(0x1F4E6).repeat(100)
	var bytes: int = CompanyLobbyMeta.presence_text(company).to_utf8_buffer().size()
	_expect(bytes <= 255, "With 4-byte characters the presence fits Steam's 256 bytes (got %d)" % bytes)


func _check_publish(company: COMPANY_STATE) -> void:
	TranslationServer.set_locale("es")
	company.new_company("Acme SRL")
	company.day = 4
	var line: String = tr(CompanyLobbyMeta.PRESENCE_TEXT) % ["Acme SRL", 4]
	var host := NetSession.new()
	CompanyLobbyMeta.publish(host.steam_presence, company, true)
	_expect(host.steam_presence.lobby_meta() == {"company_name": "Acme SRL", "company_day": "4"},
		"The host's lobby data is handed over (got %s)" % [host.steam_presence.lobby_meta()])
	_expect(host.steam_presence.rich_presence() == {"status": line},
		"...and its presence (got %s)" % [host.steam_presence.rich_presence()])
	CompanyLobbyMeta.publish(host.steam_presence, null, true)
	_expect(host.steam_presence.lobby_meta().is_empty() and host.steam_presence.rich_presence().is_empty(),
		"Publishing no company clears both (got %s, %s)"
		% [host.steam_presence.lobby_meta(), host.steam_presence.rich_presence()])
	var client := NetSession.new()
	CompanyLobbyMeta.publish(client.steam_presence, company, false)
	_expect(client.steam_presence.lobby_meta().is_empty()
		and client.steam_presence.rich_presence() == {"status": line},
		"A client hands over its presence only (got %s, %s)"
		% [client.steam_presence.lobby_meta(), client.steam_presence.rich_presence()])
	host.free()
	client.free()


## `key` is in the table (the text isn't the key itself), its Spanish and English differ, and both
## carry every value inserted.
func _expect_translated(key: String, spanish: String, english: String, values: Array) -> void:
	var translated: bool = TranslationServer.translate(key) != key and spanish != english
	for value: String in values:
		translated = translated and spanish.contains(value) and english.contains(value)
	_expect(translated, "%s is translated in both languages with %s in it (got '%s', '%s')"
		% [key, values, spanish, english])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
