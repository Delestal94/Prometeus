extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_supply_vote.gd
##
## S-104 supply-vote contract: ShopVoteManager selects without charging,
## majority wins, ties prefer the cheaper offer, and no votes buy nothing.

var _failures: int = 0


func _initialize() -> void:
	var crew: Node = load("res://scripts/core/crew_progression.gd").new()
	var shop: Node = load("res://scripts/core/shop_vote_manager.gd").new()
	shop.crew_progression = crew

	_test_majority_and_single_charge(crew, shop)
	_test_cheapest_tie(crew, shop)
	_test_no_votes(shop)

	crew.free()
	shop.free()
	if _failures == 0:
		print("PASS: supply voting selects by majority, breaks ties by price and charges only at the depot")
	quit(_failures)


func _test_majority_and_single_charge(crew: Node, shop: Node) -> void:
	crew.reset_campaign()
	shop.open_shop(crew.SUPPLIES)
	shop.vote(1, &"padding")
	shop.vote(2, &"padding")
	shop.vote(3, &"insurance")
	var winner: StringName = shop.finish_vote([1, 2, 3])
	_expect(winner == &"padding", "The two-vote majority selects padding (got %s)" % winner)
	_expect(int(crew.team_money) == crew.STARTING_MONEY,
		"Resolving a winner does not charge the wallet (got $%d)" % int(crew.team_money))
	_expect(crew.buy_supply(winner), "The depot can purchase the selected supply")
	_expect(int(crew.team_money) == 60, "The depot charges the $40 supply exactly once (got $%d)" % int(crew.team_money))
	_expect(not crew.buy_supply(winner), "The same pending supply cannot be purchased twice")
	_expect(int(crew.team_money) == 60, "A rejected duplicate purchase does not charge again (got $%d)" % int(crew.team_money))


func _test_cheapest_tie(crew: Node, shop: Node) -> void:
	crew.reset_campaign()
	shop.open_shop(crew.SUPPLIES)
	shop.vote(1, &"padding")
	shop.vote(2, &"insurance")
	var winner: StringName = shop.resolve_winner([1, 2])
	_expect(winner == &"insurance", "A 1-1 tie selects the cheaper $35 insurance offer (got %s)" % winner)
	_expect(int(crew.team_money) == crew.STARTING_MONEY,
		"Reading a tied winner never changes team money (got $%d)" % int(crew.team_money))


func _test_no_votes(shop: Node) -> void:
	shop.open_shop({&"padding": {"cost": 40}, &"insurance": {"cost": 35}})
	var winner: StringName = shop.finish_vote([1, 2])
	_expect(winner.is_empty(), "No votes resolve to no purchase (got %s)" % winner)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
