extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/coop_vote/tests/test_coop_vote.gd
##
## The coop_vote module on its own (docs/modulos.md), with a game-like
## subclass defined here: opening announces the offers; a vote for an
## unknown offer is refused; the winner is the most voted offer, the
## cheapest on a tie; finish_vote() announces without paying, resolve()
## pays through the game's hook and refuses when it can't; the first vote
## starts the clock and running it out resolves; restart_votes() clears
## them; reset() empties everything.

var _failures: int = 0


class GameVote extends CoopVote:
	var money: int = 100
	var charged: Array = []

	func _default_offers() -> Dictionary:
		return {&"tape": {"cost": 30, "label": "Tape"}, &"padding": {"cost": 60, "label": "Padding"}}

	func _spend(cost: int) -> bool:
		if cost > money:
			return false
		money -= cost
		charged.append(cost)
		return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vote := GameVote.new()
	root.add_child(vote)
	var opened: Array = []
	var changes: Array = []
	var resolutions: Array = []
	vote.opened.connect(func(offers: Dictionary) -> void: opened.append(offers.keys()))
	vote.vote_changed.connect(func(peer_id: int, offer_id: StringName) -> void: changes.append([peer_id, offer_id]))
	vote.resolved.connect(func(offer_id: StringName, offer: Dictionary) -> void: resolutions.append([offer_id, offer]))
	await process_frame
	_expect(vote.connected_peers() == [1], "Offline the only voter is the host")
	vote.request_open()
	_expect(vote.active and opened.size() == 1 and opened[0].has(&"tape"), "Asking opens the game's offers")
	_expect(not vote.vote(1, &"gold"), "A vote for an unknown offer is refused")
	_expect(vote.vote(1, &"padding") and changes == [[1, &"padding"]], "A vote is recorded and announced")
	_expect(vote.resolve_winner([1]) == &"padding" and vote.active, "Asking for the winner changes nothing")
	# A tie between two voters: the cheaper offer wins.
	vote.vote(2, &"tape")
	_expect(vote.resolve_winner([1, 2]) == &"tape", "On a tie the cheapest offer wins")
	_expect(vote.finish_vote([1, 2]) == &"tape" and not vote.active and vote.charged.is_empty(),
		"finish_vote() announces the winner without paying")
	_expect(resolutions.size() == 1 and resolutions[0][0] == &"tape",
		"The resolution is announced (got %s)" % [resolutions])

	vote.open(vote._default_offers())
	vote.vote(1, &"padding")
	_expect(vote.resolve([1]) == &"padding" and vote.money == 40 and vote.charged == [60],
		"resolve() pays through the game's hook")
	vote.open(vote._default_offers())
	vote.vote(1, &"padding")
	_expect(vote.resolve([1]) == &"" and vote.active and vote.money == 40,
		"When the purse can't pay the vote stays open")
	vote.reset()
	_expect(not vote.active and vote.offers.is_empty() and vote.votes.is_empty(), "reset() empties everything")

	# The clock, with a second voter on the roster (a lone host's vote is
	# everyone's, and resolves at once): the first vote starts it, and it runs out.
	var roster := NetSession.new()
	roster.peer_ids = [1, 2]
	vote.session = roster
	vote.vote_duration = 0.05
	vote.request_open()
	_expect(not vote.timer_started, "Opening doesn't start the clock")
	vote.request_vote(&"tape")
	_expect(vote.timer_started and vote.active, "The first vote starts the clock while others still have to vote")
	vote.restart_votes(1)
	_expect(vote.votes.is_empty() and not vote.timer_started, "Restarting clears the votes and the clock")
	vote.request_vote(&"tape")
	for _frame: int in range(12):
		await process_frame
	_expect(not vote.active and resolutions[-1][0] == &"tape",
		"Running out of time resolves on the leader (got %s)" % [resolutions[-1]])
	vote.free()
	roster.free()
	if _failures == 0:
		print("PASS: the vote opens, counts, ties, pays and times out on the module alone")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
