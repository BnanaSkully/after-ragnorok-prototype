class_name Diplomacy
extends RefCounted

# The diplomatic relationship between the player and ONE AI faction ("other"):
# war and peace, sworn agreements (an oath, pact, bond... each faction has its
# own word), demands, Trust, and a memory of whether promises were kept.
#
# War and peace (standard 4X): every pair of factions starts at PEACE. At peace
# their units can't attack each other or take each other's outposts. Attacking
# declares WAR, which costs Trust. Peace is made by agreement and brings a short
# truce. A sworn agreement (oath) is a DEFENSIVE ALLIANCE: if anyone declares
# war on one ally, the other joins the war against the aggressor. GameState keeps
# one of these per AI faction. The player gets one diplomatic action per turn
# in total, across all factions (GameState.diplomacy_action_used).
#
# "game" is the GameState (game_state.gd): used to see the factions, the turn
# and the Sun's Daughter, and to post messages.

const PACT_LENGTH := 10 # turns a defensive alliance (oath) lasts
const TRUST_MIN := -10
const TRUST_MAX := 10
const TRUST_KEPT := 2 # trust gained when an oath runs its full length
const TRUST_BROKEN := -5 # trust lost when the player breaks an oath
const OATHBREAKER_TURNS := 8 # after breaking an oath, that faction refuses new ones for this long
const BROKEN_OATH_FAVOUR := -2 # the Sun's Daughter sees it too
const DEMAND_AMOUNT := 5 # Food or Industry asked for in a demand
const TRUST_DEMAND_PAID := -1 # they resent being squeezed even when they pay
const TRUST_DEMAND_REFUSED := -2 # and resent it more when they refuse
# War and peace
const TRUST_DECLARED_WAR := -3 # you declared war on them
const TRUST_WARMONGER := -1 # everyone else, when you declare war (not when you're defending an ally)
const TRUST_DEFENDED_WAR := -2 # them, when you join a war on them to defend your ally
const TRUST_JOINED_ALLY := 2 # your ally, when you join its war as you swore to
const TRUCE_TURNS := 5 # after peace is made, they won't declare war again for this long
const TRUST_PEACE_MADE := 1
const RIVAL_WAR_GAP := 4 # it may declare war when its army is this much stronger (and it doesn't trust you)...
const RIVAL_WAR_HATE := -5 # ...or when its Trust is this low, or it's starving
const RIVAL_WAR_CHANCE := 0.1 # chance each turn when one of those is true
const RIVAL_PEACE_TURNS := 5 # at war this long (or weaker, or afraid of Sköll), it may offer peace
const RIVAL_PEACE_CHANCE := 0.25
const ALLY_ABANDON_GAP := -4 # an AI ally breaks its word rather than join a war on someone this much stronger
# Trading (standard 4X deals). Each uses the player's diplomatic action.
const TRADE_AMOUNT := 5 # you give this much Food or Industry...
const TRADE_BASE := 4 # ...and they give back this much of the other, adjusted:
# +1 if they need what you give, -1 if they need what they'd give up,
# +1 at Trust 3+, -1 at Trust -3 or less (never below 1, never more than they have)
const GIFT_AMOUNT := 5
const GIFT_TRUST := 1 # a gift raises their Trust...
const GIFT_TRUST_CAP := 5 # ...but only up to this (you can't buy friendship forever)
const PEACE_TRIBUTE := 6 # Industry you can offer to sweeten a peace offer...
const PEACE_TRIBUTE_BONUS := 0.3 # ...for this much more chance (kept if they refuse)
# Borders (closed by default; GameState.may_enter). An open-borders agreement
# lets both sides' units cross each other's territory at peace. Allies (an
# oath) always have open borders.
const BORDERS_LENGTH := 10 # turns an open-borders agreement lasts
const RIVAL_BORDERS_TRUST := 1 # an AI offers open borders itself at this Trust or more

# The AI faction's own diplomacy
const RIVAL_OFFER_CHANCE := 0.15 # chance each turn that it proposes or demands something (per faction; with 3 AIs about 1 turn in 3 has an offer)
const RIVAL_DEMAND_GAP := 3 # it makes demands when its army is this much stronger
const RIVAL_BREAK_GAP := 4 # it may break an oath when its army is this much stronger...
const RIVAL_BREAK_CHANCE := 0.25 # ...or when starving, with this chance each turn
const TRUST_ACCEPTED_THEIR_OATH := 1
const TRUST_REFUSED_THEIR_OATH := -1
const TRUST_PAID_THEIR_DEMAND := 1
const TRUST_REFUSED_THEIR_DEMAND := -1
const RIVAL_BROKEN_OATH_FAVOUR := -2 # the Sun's Daughter sees the rival's betrayal too
const SCARED_OFFER_CHANCE := 0.5 # each turn, a faction sheltering her that fears Sköll tries to give her to you
const TRUST_TOOK_THE_DAUGHTER := 1 # you took her off their hands
const TRUST_REFUSED_THE_DAUGHTER := -1
const TRUST_GAVE_HER := 1 # you gave Sunna to the people that claimed her
const TRUST_REFUSED_CLAIM := -1 # you refused their claim on her

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
var other: Faction # the AI faction this relationship is with
var trust := 0 # how much that faction trusts the player (-10 to 10)
var pact_turns_left := 0 # 0 = no alliance in force
var at_war := false
var war_since := 0 # the turn the current war started
var truce_until := 0 # after peace, they won't declare war before this turn
var borders_until := 0 # open-borders agreement in force before this turn
var oathbreaker_until := 0 # the player counts as an oathbreaker with them before this turn
var pending: Dictionary = {} # their offer waiting for the player's answer, e.g. {"type": "demand", "resource": "food"}
var rival_broken_oaths := 0 # how many agreements they have broken
var claim_trust_lost := 0 # Trust lost because you hold Sunna, their lost sun (at most SunDaughter.CLAIM_TRUST_MAX)

func _init(p_game: GameState, p_other: Faction) -> void:
	_game = weakref(p_game)
	other = p_other

# The player's one diplomatic action per turn is shared across all factions.
var action_used: bool:
	get:
		return game.diplomacy_action_used
	set(value):
		game.diplomacy_action_used = value

func pact_active() -> bool:
	return pact_turns_left > 0

# May the two sides' units cross each other's territory at peace?
func borders_open() -> bool:
	return pact_active() or game.turn < borders_until

func borders_turns_left() -> int:
	return maxi(0, borders_until - game.turn)

func can_ask_borders() -> bool:
	return can_deal() and not at_war and not borders_open()

# The chance (0 to 1) that they agree to open borders: 40% + 10% per Trust.
func borders_chance() -> float:
	return clampf(0.4 + trust * 0.1, 0.05, 0.95)

# The player's diplomatic action: ask for open borders. Returns true if agreed.
func ask_open_borders() -> bool:
	if not can_ask_borders():
		return false
	action_used = true
	var chance := borders_chance()
	if randf() < chance:
		borders_until = game.turn + BORDERS_LENGTH
		remember("Turn %d: %s opened their borders to you for %d turns (%d%% chance). Yours are open to them too." % [game.turn, other.name, BORDERS_LENGTH, roundi(chance * 100)])
		return true
	remember("Turn %d: %s refused to open their borders (%d%% chance)." % [game.turn, other.name, roundi(chance * 100)])
	return false

func in_truce() -> bool:
	return game.turn < truce_until

func is_oathbreaker() -> bool:
	return game.turn < oathbreaker_until

# The word this faction uses for a sworn agreement (e.g. "oath").
func pact_word() -> String:
	return other.pact_word

# "an oath", "a pact"
func a_pact() -> String:
	var word := pact_word()
	return ("an " if word[0] in "aeiou" else "a ") + word

# The chance (0 to 1) that the rival accepts an oath (a defensive alliance) right now.
func accept_chance() -> float:
	if is_oathbreaker() or at_war:
		return 0.0
	var chance := 0.5 + trust * 0.1
	if game.turn >= Skoll.WARNING_TURN:
		chance += 0.2 # the howling makes allies
	if game.player.units.size() > other.units.size():
		chance += 0.1 # it respects strength
	return clampf(chance, 0.05, 0.95)

func army_power(f: Faction) -> int:
	return game.army_power(f)

# The chance (0 to 1) that the rival gives in to a demand for "food" or "industry".
func demand_chance(resource: String) -> float:
	var rival: Faction = other
	if rival.get(resource) < DEMAND_AMOUNT:
		return 0.0 # it doesn't have that much
	var gap := army_power(game.player) - army_power(rival)
	return clampf(0.5 + gap * 0.1, 0.05, 0.95)

func can_demand() -> bool:
	return not action_used and other.is_alive()

# The player's diplomatic action: demand Food or Industry. Returns true if paid.
func demand(resource: String) -> bool:
	if not can_demand():
		return false
	var rival: Faction = other
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
	return not action_used and not pact_active() and not at_war and other.is_alive() and not game.tribute_bound(other, game.player)

# --- Trading -------------------------------------------------------------------
func other_resource(res: String) -> String:
	return "industry" if res == "food" else "food"

# Is this faction short of Food or Industry? (Short of Food: stores under 5
# or not growing; short of Industry: can't afford an army unit.)
func needs(f: Faction, res: String) -> bool:
	if res == "food":
		return f.food < 5 or game.food_change(f) <= 0
	return f.industry < GameState.UNIT_COST

# How much of the other resource they'd give for TRADE_AMOUNT of "give" from
# the player (0 = no deal: at war, or they have nothing to give).
func trade_quote(give: String) -> int:
	if at_war or not other.is_alive():
		return 0
	var back := other_resource(give)
	var amount := TRADE_BASE
	if needs(other, give):
		amount += 1
	if needs(other, back):
		amount -= 1
	if trust >= 3:
		amount += 1
	elif trust <= -3:
		amount -= 1
	return clampi(amount, 1, other.get(back)) if other.get(back) > 0 else 0

func can_deal() -> bool:
	return not action_used and other.is_alive()

# The player trades TRADE_AMOUNT of "give" for the quoted amount of the other.
func trade(give: String) -> bool:
	var amount := trade_quote(give)
	var player: Faction = game.player
	if not can_deal() or amount <= 0 or player.get(give) < TRADE_AMOUNT:
		return false
	action_used = true
	var back := other_resource(give)
	player.set(give, player.get(give) - TRADE_AMOUNT)
	other.set(give, other.get(give) + TRADE_AMOUNT)
	other.set(back, other.get(back) - amount)
	player.set(back, player.get(back) + amount)
	remember("Turn %d: you traded %d %s to %s for %d %s." % [game.turn, TRADE_AMOUNT, give.capitalize(), other.name, amount, back.capitalize()])
	return true

func gift_trust_gain() -> int:
	return GIFT_TRUST if trust < GIFT_TRUST_CAP else 0

func can_gift(res: String) -> bool:
	return can_deal() and not at_war and game.player.get(res) >= GIFT_AMOUNT

# A gift of GIFT_AMOUNT: Trust +1 (until Trust reaches GIFT_TRUST_CAP).
func gift(res: String) -> bool:
	if not can_gift(res):
		return false
	action_used = true
	var player: Faction = game.player
	player.set(res, player.get(res) - GIFT_AMOUNT)
	other.set(res, other.get(res) + GIFT_AMOUNT)
	var gain := gift_trust_gain()
	change_trust(gain)
	remember("Turn %d: you gave %s %d %s. Trust %+d." % [game.turn, other.name, GIFT_AMOUNT, res.capitalize(), gain])
	return true

func tribute_peace_chance() -> float:
	return clampf(peace_chance() + PEACE_TRIBUTE_BONUS, 0.05, 0.95)

func can_offer_tribute() -> bool:
	return can_propose_peace() and game.player.industry >= PEACE_TRIBUTE

# At war: offer PEACE_TRIBUTE Industry for peace. Paid only if they accept.
func offer_tribute_for_peace() -> bool:
	if not can_offer_tribute():
		return false
	action_used = true
	var chance := tribute_peace_chance()
	if randf() < chance:
		game.player.industry -= PEACE_TRIBUTE
		other.industry += PEACE_TRIBUTE
		make_peace()
		remember("Turn %d: you paid %s %d Industry for peace (%d%% chance). Truce for %d turns." % [game.turn, other.name, PEACE_TRIBUTE, roundi(chance * 100), TRUCE_TURNS])
		return true
	remember("Turn %d: %s refused %d Industry for peace (%d%% chance). You keep it." % [game.turn, other.name, PEACE_TRIBUTE, roundi(chance * 100)])
	return false

func can_propose_peace() -> bool:
	return not action_used and at_war and other.is_alive()

# The chance (0 to 1) that the rival makes peace right now: Trust, who's winning,
# and the fear of Sköll all count.
func peace_chance() -> float:
	var chance := 0.3 + trust * 0.1 + (army_power(game.player) - army_power(other)) * 0.05
	if game.turn >= Skoll.WARNING_TURN:
		chance += 0.2 # the howling makes enemies think again
	return clampf(chance, 0.05, 0.95)

# The player's diplomatic action: propose peace. Returns true if accepted.
func propose_peace() -> bool:
	if not can_propose_peace():
		return false
	action_used = true
	var chance := peace_chance()
	if randf() < chance:
		make_peace()
		remember("Turn %d: you made peace with %s (%d%% chance). Truce for %d turns, Trust %+d." % [game.turn, other.name, roundi(chance * 100), TRUCE_TURNS, TRUST_PEACE_MADE])
		return true
	remember("Turn %d: %s refused peace (%d%% chance). The war goes on." % [game.turn, other.name, roundi(chance * 100)])
	return false

func make_peace() -> void:
	at_war = false
	truce_until = game.turn + TRUCE_TURNS
	change_trust(TRUST_PEACE_MADE)

# The player declares war on this faction (by attacking it). Breaking an
# alliance to do it is also breaking your oath. "defending" = joining a war on
# them because they attacked your ally: no warmonger penalty.
func player_declare_war(defending := false) -> void:
	if at_war:
		return
	if game.player.overlord == other.name:
		# Rising up against your overlord: you're free, and at war with them.
		game.player.overlord = ""
		pact_turns_left = 0
		at_war = true
		war_since = game.turn
		change_trust(TRUST_DECLARED_WAR)
		remember("Turn %d: YOU ROSE UP against the %s. No more tribute, and you are at war. Trust %+d." % [game.turn, other.name, TRUST_DECLARED_WAR])
		return
	if other.overlord == game.player.name:
		other.overlord = "" # attacking your own tributary sets it free
	if pact_active():
		break_pact()
	elif defending:
		change_trust(TRUST_DEFENDED_WAR)
	else:
		change_trust(TRUST_DECLARED_WAR)
	at_war = true
	war_since = game.turn
	borders_until = 0
	if defending:
		remember("Turn %d: you declared war on %s to defend your ally. Trust %+d." % [game.turn, other.name, TRUST_DEFENDED_WAR])
		return
	for r in game.relations:
		if r != self and r.other.is_alive():
			r.change_trust(TRUST_WARMONGER)
	remember("Turn %d: YOU DECLARED WAR on %s. Their Trust %+d, everyone else's %+d (warmonger)." % [game.turn, other.name, TRUST_DECLARED_WAR, TRUST_WARMONGER])

# This AI declares war on the player (an ally doing so breaks its oath).
# Then the player's other allies answer the call (GameState.player_attacked).
func rival_declare_war(why: String) -> void:
	var rival: Faction = other
	at_war = true
	war_since = game.turn
	borders_until = 0
	if pact_active():
		pact_turns_left = 0
		rival_broken_oaths += 1
		rival.favour = clampi(rival.favour + RIVAL_BROKEN_OATH_FAVOUR, 0, SunDaughter.MAX_FAVOUR)
		remember("Turn %d: %s BROKE THEIR %s and DECLARED WAR on you (%s)." % [game.turn, rival.name, pact_word().to_upper(), why])
	else:
		remember("Turn %d: %s DECLARED WAR on you (%s)." % [game.turn, rival.name, why])
	game.player_attacked(rival)

# The player's diplomatic action: propose an oath. Returns true if accepted.
func propose_pact() -> bool:
	if not can_propose():
		return false
	action_used = true
	var word := pact_word()
	if is_oathbreaker():
		remember("Turn %d: %s refused your %s. You broke your word before." % [game.turn, other.name, word])
		return false
	var chance := accept_chance()
	if randf() < chance:
		pact_turns_left = PACT_LENGTH
		remember("Turn %d: you and %s swore %s for %d turns." % [game.turn, other.name, a_pact(), PACT_LENGTH])
		return true
	remember("Turn %d: %s refused your %s (%d%% chance)." % [game.turn, other.name, word, roundi(chance * 100)])
	return false

# The player breaks an alliance: by attacking the ally, or by refusing to join
# its war when it was attacked.
func break_pact() -> void:
	pact_turns_left = 0
	change_trust(TRUST_BROKEN)
	oathbreaker_until = game.turn + OATHBREAKER_TURNS
	var p: Faction = game.player
	p.favour = clampi(p.favour + BROKEN_OATH_FAVOUR, 0, SunDaughter.MAX_FAVOUR)
	remember("Turn %d: YOU BROKE YOUR %s with %s. Trust %+d. %s Favour %+d." % [game.turn, pact_word().to_upper(), other.name, TRUST_BROKEN, SunDaughter.NAME.capitalize(), BROKEN_OATH_FAVOUR])

# Called at the end of every turn.
func new_turn() -> void:
	action_used = false
	if pact_active():
		pact_turns_left -= 1
		if pact_turns_left == 0:
			change_trust(TRUST_KEPT)
			remember("Turn %d: the %s with %s ran its course. Both kept their word. Trust %+d." % [game.turn, pact_word(), other.name, TRUST_KEPT])

# --- The rival's own diplomacy ------------------------------------------------
# Called at the start of the rival's turn, before its units move: it may
# declare war on the player. An ally only betrays you when it's much stronger
# or starving; anyone else also when it hates you (Trust -5 or less). Never
# during a truce. Its units can attack at once.
func rival_consider_war() -> void:
	if at_war or in_truce() or not other.is_alive() or not game.player.is_alive():
		return
	if game.tribute_bound(other, game.player):
		return # overlord and tributary: only an uprising (GameState.ai_rebellions)
	var rival: Faction = other
	var gap := army_power(rival) - army_power(game.player)
	var starving: bool = rival.food <= 0 and game.food_change(rival) < 0
	var why := ""
	if pact_active():
		if gap >= RIVAL_BREAK_GAP:
			why = "their army outgrew yours"
		elif starving:
			why = "they were starving"
		if why != "" and randf() < RIVAL_BREAK_CHANCE:
			rival_declare_war(why)
		return
	if trust <= RIVAL_WAR_HATE:
		why = "they despise you"
	elif gap >= RIVAL_WAR_GAP and trust < 2:
		why = "their army is far stronger"
	elif game.daughter.shelters_with(game.player) and trust < 2 and gap >= 0:
		why = "they want %s back, their lost sun" % SunDaughter.claim_name(rival)
	elif starving:
		why = "they are starving and want your stores"
	if why != "" and randf() < RIVAL_WAR_CHANCE:
		rival_declare_war(why)

# Called at the start of the player's turn: the rival may propose an oath or
# make a demand. Sets "pending"; main.gd shows the Accept/Refuse pop-up.
func rival_make_offer() -> void:
	pending = {}
	var rival: Faction = other
	var player: Faction = game.player
	if not rival.is_alive():
		return
	# Sheltering the Daughter but scared of Sköll: try to give her to the player
	# (checked first, with its own chance). If she's still worth something to
	# them they hand her over for nothing; if not, they pay the player to take her.
	if game.ai_wants_rid_of_daughter(rival) and randf() < SCARED_OFFER_CHANCE:
		pending = {"type": "daughter", "pay": mini(maxi(0, -game.daughter_value(rival)), rival.industry)}
		return
	var gap := army_power(rival) - army_power(player)
	var afraid: bool = game.turn >= Skoll.WARNING_TURN
	if at_war:
		# Losing, tired of the war, or afraid of Sköll: it may ask for peace.
		if (gap < 0 or afraid or game.turn - war_since >= RIVAL_PEACE_TURNS) and randf() < RIVAL_PEACE_CHANCE:
			pending = {"type": "peace"}
		return
	if randf() >= RIVAL_OFFER_CHANCE:
		return
	# You hold the sun they believe is theirs: they may demand her.
	if game.daughter.shelters_with(player) and game.turn >= SunDaughter.TRADE_TURN and game.daughter_value(rival) >= SunDaughter.CLAIM_VALUE_MIN and gap >= 0 and randf() < SunDaughter.CLAIM_DEMAND_CHANCE:
		pending = {"type": "claim"}
		return
	# Trusting enough, and borders still closed: it may offer to open them.
	if not borders_open() and trust >= RIVAL_BORDERS_TRUST and randf() < 0.4:
		pending = {"type": "borders"}
		return
	if not pact_active() and not is_oathbreaker() and not game.tribute_bound(rival, player) and (afraid or gap < 0 or trust >= 2):
		pending = {"type": "oath"}
		return
	if gap >= RIVAL_DEMAND_GAP:
		var options: Array[String] = []
		for resource in ["food", "industry"]:
			if player.get(resource) >= DEMAND_AMOUNT:
				options.append(resource)
		if not options.is_empty():
			pending = {"type": "demand", "resource": options.pick_random()}
			return
	# Short of one thing and with plenty of the other: it offers a trade.
	for want in ["food", "industry"]:
		var give := other_resource(want)
		var amount := trade_quote(want) # what it would pay for TRADE_AMOUNT of "want"
		if needs(rival, want) and not needs(rival, give) and amount > 0 and player.get(want) >= TRADE_AMOUNT:
			pending = {"type": "trade", "want": want, "give": give, "amount": amount}
			return

func has_pending() -> bool:
	return not pending.is_empty()

# The text of the pop-up for the pending offer.
func pending_text() -> String:
	var rival: Faction = other
	if pending.get("type") == "oath":
		return "%s proposes %s, a defensive alliance for %d turns: if anyone declares war on one of you, the other joins the war.\n\nAccept: the %s begins, Trust %+d.\nRefuse: Trust %+d." % [rival.name, a_pact(), PACT_LENGTH, pact_word(), TRUST_ACCEPTED_THEIR_OATH, TRUST_REFUSED_THEIR_OATH]
	if pending.get("type") == "borders":
		return "%s offers open borders for %d turns: your units may cross their lands at peace, and theirs yours.\n\nAccept: borders open both ways.\nRefuse: they stay closed." % [rival.name, BORDERS_LENGTH]
	if pending.get("type") == "trade":
		return "%s is short of %s and offers a trade: %d %s for %d of your %s.\n\nAccept: the trade is made.\nRefuse: no harm done." % [rival.name, String(pending["want"]).capitalize(), pending["amount"], String(pending["give"]).capitalize(), TRADE_AMOUNT, String(pending["want"]).capitalize()]
	if pending.get("type") == "peace":
		return "%s is tired of the war and offers peace.\n\nAccept: peace, and a truce for %d turns. Trust %+d.\nRefuse: the war goes on." % [rival.name, TRUCE_TURNS, TRUST_PEACE_MADE]
	if pending.get("type") == "demand":
		var res: String = String(pending["resource"]).capitalize()
		return "%s demands %d %s from you. Their army is stronger than yours.\n\nPay: you lose %d %s, Trust %+d.\nRefuse: Trust %+d." % [rival.name, DEMAND_AMOUNT, res, DEMAND_AMOUNT, res, TRUST_PAID_THEIR_DEMAND, TRUST_REFUSED_THEIR_DEMAND]
	if pending.get("type") == "claim":
		return "The %s say %s is %s, their own lost sun, and demand that you give her back.\n\nHand her over: she shelters with them (you lose +%d Food, +%d Industry, +%d defence; Sköll hunts them instead). Her Favour toward you %+d. Trust %+d.\nRefuse: Trust %+d." % [rival.name, SunDaughter.NAME, SunDaughter.claim_name(rival), SunDaughter.FOOD, SunDaughter.INDUSTRY, SunDaughter.DEFENCE, SunDaughter.TRADED_FAVOUR, TRUST_GAVE_HER, TRUST_REFUSED_CLAIM]
	if pending.get("type") == "daughter":
		var deal := "and will pay you %d Industry to take her" % pending["pay"] if pending["pay"] > 0 else "for nothing"
		return "The %s fear Sköll and want %s gone. They offer her to you, %s.\n\nTake her: she shelters in your city (+%d Food, +%d Industry a turn, +%d defence, but Sköll hunts her). Trust %+d.\nRefuse: Trust %+d." % [rival.name, SunDaughter.NAME, deal, SunDaughter.FOOD, SunDaughter.INDUSTRY, SunDaughter.DEFENCE, TRUST_TOOK_THE_DAUGHTER, TRUST_REFUSED_THE_DAUGHTER]
	return ""

# The player's answer to the pending offer.
func answer(accept: bool) -> void:
	if pending.is_empty():
		return
	var rival: Faction = other
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
	elif offer["type"] == "borders":
		if accept and not at_war:
			borders_until = game.turn + BORDERS_LENGTH
			remember("Turn %d: you and %s opened your borders to each other for %d turns." % [game.turn, rival.name, BORDERS_LENGTH])
		else:
			game.add_message("You kept your borders closed to %s." % rival.name)
	elif offer["type"] == "trade":
		var want: String = offer["want"]
		var give: String = offer["give"]
		var amount: int = mini(offer["amount"], rival.get(give))
		if accept and player.get(want) >= TRADE_AMOUNT and amount > 0:
			player.set(want, player.get(want) - TRADE_AMOUNT)
			rival.set(want, rival.get(want) + TRADE_AMOUNT)
			rival.set(give, rival.get(give) - amount)
			player.set(give, player.get(give) + amount)
			remember("Turn %d: you accepted %s's trade: %d %s for %d %s." % [game.turn, rival.name, TRADE_AMOUNT, want.capitalize(), amount, give.capitalize()])
		else:
			game.add_message("You turned down %s's trade." % rival.name)
	elif offer["type"] == "peace":
		if accept and at_war:
			make_peace()
			remember("Turn %d: you accepted %s's offer of peace. Truce for %d turns, Trust %+d." % [game.turn, rival.name, TRUCE_TURNS, TRUST_PEACE_MADE])
		else:
			remember("Turn %d: you refused %s's offer of peace. The war goes on." % [game.turn, rival.name])
	elif offer["type"] == "daughter":
		if accept and game.daughter.shelters_with(rival):
			var pay: int = mini(offer["pay"], rival.industry)
			rival.industry -= pay
			player.industry += pay
			game.hand_over_daughter(rival, player)
			change_trust(TRUST_TOOK_THE_DAUGHTER)
			var paid := "and they paid you %d Industry" % pay if pay > 0 else "for nothing"
			remember("Turn %d: you took %s from the %s, %s. Trust %+d." % [game.turn, SunDaughter.NAME, rival.name, paid, TRUST_TOOK_THE_DAUGHTER])
		else:
			change_trust(TRUST_REFUSED_THE_DAUGHTER)
			remember("Turn %d: you refused to take %s from the %s. Trust %+d." % [game.turn, SunDaughter.NAME, rival.name, TRUST_REFUSED_THE_DAUGHTER])
	elif offer["type"] == "claim":
		if accept and game.daughter.shelters_with(player):
			game.hand_over_daughter(player, rival)
			change_trust(TRUST_GAVE_HER)
			remember("Turn %d: you gave %s back to the %s, who call her %s. Trust %+d." % [game.turn, SunDaughter.NAME, rival.name, SunDaughter.claim_name(rival), TRUST_GAVE_HER])
		else:
			change_trust(TRUST_REFUSED_CLAIM)
			remember("Turn %d: you refused to give %s to the %s. Trust %+d." % [game.turn, SunDaughter.claim_name(rival), rival.name, TRUST_REFUSED_CLAIM])
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

# Shown at the bottom of the screen and kept in the diplomacy memory.
func remember(event: String) -> void:
	game.remember(event)
