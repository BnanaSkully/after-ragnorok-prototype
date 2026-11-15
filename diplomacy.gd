class_name Diplomacy
extends RefCounted

# Diplomacy between the player and the rival: sworn agreements (oaths), and a
# memory of whether promises were kept. The player gets one diplomatic action
# per turn.
#
# "game" is main.gd: diplomacy uses it to see the factions, the turn and the
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

var game # main.gd
var trust := 0 # how much the rival trusts the player (-10 to 10)
var pact_turns_left := 0 # 0 = no oath in force
var oathbreaker_until := 0 # the player counts as an oathbreaker before this turn
var action_used := false # the player's one diplomatic action this turn
var history: Array[String] = [] # newest last

func _init(p_game) -> void:
	game = p_game

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
	action_used = true
	var rival: Faction = game.rival
	var player: Faction = game.player
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

func change_trust(amount: int) -> void:
	trust = clampi(trust + amount, TRUST_MIN, TRUST_MAX)

func remember(event: String) -> void:
	history.append(event)
	if history.size() > HISTORY_SIZE:
		history.pop_front()
	game.add_message(event)
