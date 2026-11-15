class_name Diplomacy
extends RefCounted

# Diplomacy between the player and the rival: sworn agreements (oaths), and a
# memory of whether promises were kept. The player gets one diplomatic action
# per turn.
#
# "game" is the GameState (game_state.gd): diplomacy uses it to see the factions, the turn and the
# Sun's Daughter, and to post messages.

const PACT_LENGTH := 5 # turns an oath lasts
const TRUST_MIN := -10
const TRUST_MAX := 10
const TRUST_KEPT := 2 # trust gained when an oath runs its full length
const TRUST_BROKEN := -5 # trust lost when the player breaks an oath
const OATHBREAKER_TURNS := 8 # after breaking an oath, the rival refuses new ones for this long
const BROKEN_OATH_FAVOUR := -2 # the Sun's Daughter sees it too
const HISTORY_SIZE := 6 # how many past events are shown
const DEMAND_AMOUNT := 5 # Food or Industry asked for in a demand
const TRUST_DEMAND_PAID := -1 # they resent being squeezed even when they pay
const TRUST_DEMAND_REFUSED := -2 # and resent it more when they refuse

# The rival's own diplomacy
const RIVAL_OFFER_CHANCE := 0.35 # chance each turn that it proposes or demands something
const RIVAL_DEMAND_GAP := 3 # it makes demands when its army is this much stronger
const RIVAL_BREAK_GAP := 4 # it may break an oath when its army is this much stronger...
const RIVAL_BREAK_CHANCE := 0.25 # ...or when starving, with this chance each turn
const TRUST_ACCEPTED_THEIR_OATH := 1
const TRUST_REFUSED_THEIR_OATH := -1
const TRUST_PAID_THEIR_DEMAND := 1
const TRUST_REFUSED_THEIR_DEMAND := -1
const RIVAL_BROKEN_OATH_FAVOUR := -2 # the Sun's Daughter sees the rival's betrayal too

# What the rival says when you demand something it doesn't have. Costs nothing.
# %s is the resource (e.g. "Industry"). Rewrite or add lines freely.
const CANT_PAY_REPLIES := [
	"\"We have no %s. Piss off.\"",
	"\"%s? Look around you. Go dig your own.\"",
	"\"Come back when our stores aren't empty. Or don't. Preferably don't.\"",
	"\"You want %s? Sköll can have you first.\"",
	"\"Our cupboards are bare and your manners are worse. Leave.\"",
]

# The GameState (game_state.gd). A "weak" link: the game keeps this object alive,
# but this object doesn't keep the game alive, so Godot can free both later.
var game: GameState:
	get:
		return _game.get_ref()
var _game: WeakRef
var trust := 0 # how much the rival trusts the player (-10 to 10)
var pact_turns_left := 0 # 0 = no oath in force
var oathbreaker_until := 0 # the player counts as an oathbreaker before this turn
var action_used := false # the player's one diplomatic action this turn
var history: Array[String] = [] # newest last
var pending: Dictionary = {} # the rival's offer waiting for the player's answer, e.g. {"type": "demand", "resource": "food"}
var rival_broken_oaths := 0 # how many oaths the rival has broken

func _init(p_game: GameState) -> void:
	_game = weakref(p_game)

func pact_active() -> bool:
	return pact_turns_left > 0

func is_oathbreaker() -> bool:
	return game.turn < oathbreaker_until

# The word this faction uses for a sworn agreement (e.g. "oath").
func pact_word() -> String:
	return game.rival.pact_word

# "an oath", "a pact"
func a_pact() -> String:
	var word := pact_word()
	return ("an " if word[0] in "aeiou" else "a ") + word

# The chance (0 to 1) that the rival accepts an oath right now.
func accept_chance() -> float:
	if is_oathbreaker():
		return 0.0
	var chance := 0.5 + trust * 0.1
	if game.turn >= Skoll.WARNING_TURN:
		chance += 0.2 # the howling makes allies
	if game.player.units.size() > game.rival.units.size():
		chance += 0.1 # it respects strength
	return clampf(chance, 0.05, 0.95)

# Army strength: the total Strength of a faction's units.
func army_power(f: Faction) -> int:
	var power := 0
	for u in f.units:
		power += u.strength
	return power

# The chance (0 to 1) that the rival gives in to a demand for "food" or "industry".
func demand_chance(resource: String) -> float:
	var rival: Faction = game.rival
	if rival.get(resource) < DEMAND_AMOUNT:
		return 0.0 # it doesn't have that much
	var gap := army_power(game.player) - army_power(rival)
	return clampf(0.5 + gap * 0.1, 0.05, 0.95)

func can_demand() -> bool:
	return not action_used and game.rival.is_alive()

# The player's diplomatic action: demand Food or Industry. Returns true if paid.
func demand(resource: String) -> bool:
	if not can_demand():
		return false
	var rival: Faction = game.rival
	var player: Faction = game.player
	if rival.get(resource) < DEMAND_AMOUNT:
		# They can't pay: a rude answer, but no action used and no Trust change.
		var line: String = CANT_PAY_REPLIES.pick_random()
		if "%s" in line:
			line = line % resource.capitalize()
		game.add_message("%s: %s  (No action used.)" % [rival.name, line])
		return false
	action_used = true
	var chance := demand_chance(resource)
	if randf() < chance:
		rival.set(resource, rival.get(resource) - DEMAND_AMOUNT)
		player.set(resource, player.get(resource) + DEMAND_AMOUNT)
		change_trust(TRUST_DEMAND_PAID)
		remember("Turn %d: %s paid your demand of %d %s (%d%% chance). Trust %+d." % [game.turn, rival.name, DEMAND_AMOUNT, resource.capitalize(), roundi(chance * 100), TRUST_DEMAND_PAID])
		return true
	change_trust(TRUST_DEMAND_REFUSED)
	remember("Turn %d: %s refused your demand of %d %s (%d%% chance). Trust %+d." % [game.turn, rival.name, DEMAND_AMOUNT, resource.capitalize(), roundi(chance * 100), TRUST_DEMAND_REFUSED])
	return false

func can_propose() -> bool:
	return not action_used and not pact_active() and game.rival.is_alive()

# The player's diplomatic action: propose an oath. Returns true if accepted.
func propose_pact() -> bool:
	if not can_propose():
		return false
	action_used = true
	var word := pact_word()
	if is_oathbreaker():
		remember("Turn %d: %s refused your %s. You broke your word before." % [game.turn, game.rival.name, word])
		return false
	var chance := accept_chance()
	if randf() < chance:
		pact_turns_left = PACT_LENGTH
		remember("Turn %d: you and %s swore %s for %d turns." % [game.turn, game.rival.name, a_pact(), PACT_LENGTH])
		return true
	remember("Turn %d: %s refused your %s (%d%% chance)." % [game.turn, game.rival.name, word, roundi(chance * 100)])
	return false

# The player attacks the rival while an oath is in force.
func break_pact() -> void:
	pact_turns_left = 0
	change_trust(TRUST_BROKEN)
	oathbreaker_until = game.turn + OATHBREAKER_TURNS
	var p: Faction = game.player
	p.favour = clampi(p.favour + BROKEN_OATH_FAVOUR, 0, SunDaughter.MAX_FAVOUR)
	remember("Turn %d: YOU BROKE YOUR %s with %s. Trust %+d. %s Favour %+d." % [game.turn, pact_word().to_upper(), game.rival.name, TRUST_BROKEN, SunDaughter.NAME.capitalize(), BROKEN_OATH_FAVOUR])

# Called at the end of every turn.
func new_turn() -> void:
	action_used = false
	if pact_active():
		pact_turns_left -= 1
		if pact_turns_left == 0:
			change_trust(TRUST_KEPT)
			remember("Turn %d: the %s with %s ran its course. Both kept their word. Trust %+d." % [game.turn, pact_word(), game.rival.name, TRUST_KEPT])

# --- The rival's own diplomacy ------------------------------------------------
# Called at the start of the rival's turn, before its units move: it may break
# an oath if it's much stronger or starving. Its units can then attack at once.
func rival_consider_breaking() -> void:
	if not pact_active():
		return
	var rival: Faction = game.rival
	var gap := army_power(rival) - army_power(game.player)
	var starving: bool = rival.food <= 0 and game.food_change(rival) < 0
	if (gap >= RIVAL_BREAK_GAP or starving) and randf() < RIVAL_BREAK_CHANCE:
		pact_turns_left = 0
		rival_broken_oaths += 1
		rival.favour = clampi(rival.favour + RIVAL_BROKEN_OATH_FAVOUR, 0, SunDaughter.MAX_FAVOUR)
		var why := "they were starving" if starving else "their army outgrew yours"
		remember("Turn %d: %s BROKE THEIR %s with you (%s)." % [game.turn, rival.name, pact_word().to_upper(), why])

# Called at the start of the player's turn: the rival may propose an oath or
# make a demand. Sets "pending"; main.gd shows the Accept/Refuse pop-up.
func rival_make_offer() -> void:
	pending = {}
	var rival: Faction = game.rival
	var player: Faction = game.player
	if not rival.is_alive() or randf() >= RIVAL_OFFER_CHANCE:
		return
	var gap := army_power(rival) - army_power(player)
	var afraid: bool = game.turn >= Skoll.WARNING_TURN
	if not pact_active() and not is_oathbreaker() and (afraid or gap < 0 or trust >= 2):
		pending = {"type": "oath"}
		return
	if gap >= RIVAL_DEMAND_GAP:
		var options: Array[String] = []
		for resource in ["food", "industry"]:
			if player.get(resource) >= DEMAND_AMOUNT:
				options.append(resource)
		if not options.is_empty():
			pending = {"type": "demand", "resource": options.pick_random()}

func has_pending() -> bool:
	return not pending.is_empty()

# The text of the pop-up for the pending offer.
func pending_text() -> String:
	var rival: Faction = game.rival
	if pending.get("type") == "oath":
		return "%s proposes %s: %d turns in which neither side attacks.\n\nAccept: the %s begins, Trust %+d.\nRefuse: Trust %+d." % [rival.name, a_pact(), PACT_LENGTH, pact_word(), TRUST_ACCEPTED_THEIR_OATH, TRUST_REFUSED_THEIR_OATH]
	if pending.get("type") == "demand":
		var res: String = String(pending["resource"]).capitalize()
		return "%s demands %d %s from you. Their army is stronger than yours.\n\nPay: you lose %d %s, Trust %+d.\nRefuse: Trust %+d." % [rival.name, DEMAND_AMOUNT, res, DEMAND_AMOUNT, res, TRUST_PAID_THEIR_DEMAND, TRUST_REFUSED_THEIR_DEMAND]
	return ""

# The player's answer to the pending offer.
func answer(accept: bool) -> void:
	if pending.is_empty():
		return
	var rival: Faction = game.rival
	var player: Faction = game.player
	var offer := pending
	pending = {}
	if offer["type"] == "oath":
		if accept:
			pact_turns_left = PACT_LENGTH
			change_trust(TRUST_ACCEPTED_THEIR_OATH)
			remember("Turn %d: you accepted %s's %s for %d turns. Trust %+d." % [game.turn, rival.name, pact_word(), PACT_LENGTH, TRUST_ACCEPTED_THEIR_OATH])
		else:
			change_trust(TRUST_REFUSED_THEIR_OATH)
			remember("Turn %d: you refused %s's %s. Trust %+d." % [game.turn, rival.name, pact_word(), TRUST_REFUSED_THEIR_OATH])
	elif offer["type"] == "demand":
		var resource: String = offer["resource"]
		if accept and player.get(resource) >= DEMAND_AMOUNT:
			player.set(resource, player.get(resource) - DEMAND_AMOUNT)
			rival.set(resource, rival.get(resource) + DEMAND_AMOUNT)
			change_trust(TRUST_PAID_THEIR_DEMAND)
			remember("Turn %d: you paid %s's demand of %d %s. Trust %+d." % [game.turn, rival.name, DEMAND_AMOUNT, resource.capitalize(), TRUST_PAID_THEIR_DEMAND])
		else:
			change_trust(TRUST_REFUSED_THEIR_DEMAND)
			remember("Turn %d: you refused %s's demand of %d %s. Trust %+d." % [game.turn, rival.name, DEMAND_AMOUNT, resource.capitalize(), TRUST_REFUSED_THEIR_DEMAND])

func change_trust(amount: int) -> void:
	trust = clampi(trust + amount, TRUST_MIN, TRUST_MAX)

func remember(event: String) -> void:
	history.append(event)
	if history.size() > HISTORY_SIZE:
		history.pop_front()
	game.add_message(event)
