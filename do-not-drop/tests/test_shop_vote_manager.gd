extends SceneTree

var failures := 0

func _initialize() -> void:
	var crew: Node = load("res://scripts/core/crew_progression.gd").new()
	crew.name = "CrewProgression"
	get_root().add_child(crew)
	var shop: Node = load("res://scripts/core/shop_vote_manager.gd").new()
	shop.name = "ShopVoteManager"
	shop.crew_progression = crew
	get_root().add_child(shop)
	crew.reset_campaign()
	shop.open_shop({&"pliers": {"cost": 40, "label": "Pinzas"}, &"mop": {"cost": 30, "label": "Mopa"}})
	_expect(shop.vote(1, &"pliers") and shop.vote(2, &"pliers") and shop.vote(3, &"mop"), "Players can vote for valid offers")
	_expect(shop.resolve([1, 2, 3]) == &"pliers", "Majority selects the cooperative purchase")
	_expect(int(crew.team_money) == 60, "The shared wallet pays once")
	shop.open_shop({&"mop": {"cost": 30, "label": "Mopa"}})
	crew.cards[2] = crew.Card.PRIORITY
	_expect(shop.use_priority(2, &"mop") == &"mop", "Priority card can override a vote")
	_expect(not crew.cards.has(2), "Priority card is consumed")
	shop.open_shop({&"mask": {"cost": 40, "label": "Máscara"}})
	crew.cards[3] = crew.Card.DISCOUNT
	_expect(shop.use_discount(3, &"mask") == &"mask", "Discount card applies before shared purchase")
	_expect(int(crew.team_money) == 10, "Discount halves the cooperative price")
	if failures == 0:
		print("PASS: shop voting and priority cards use shared money correctly")
	quit(failures)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
