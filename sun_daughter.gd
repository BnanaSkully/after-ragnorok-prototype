class_name SunDaughter
extends RefCounted

# The Sun's Daughter: the new sun, born just before Sköll swallowed her mother.
# She travels with the survivors on the Crossing and watches how each people
# behaves. Her Favour toward a faction (0 to 10) is stored on the Faction itself.
# At the Landing she chooses to shelter with whoever she trusts most.

const NAME := "Sunna" # the Sun's Daughter (Nathan named her in the middle-game playtest)
const PLAYER_START_FAVOUR := 3
const RIVAL_FAVOUR_MIN := 4 # each AI faction's Favour is hidden and random in this range
const RIVAL_FAVOUR_MAX := 7 # (was 3-6; contested Sunna design, 22 Nov)
const MAX_FAVOUR := 10

# What sheltering her gives
const FOOD := 1 # extra Food per turn (was 2: she is a prize to fight over, not an economy)
const INDUSTRY := 1 # extra Industry per turn (was 2)
const DEFENCE := 1 # extra city defence (was 3)

# How she judges whoever shelters her: is the kingdom fed, and is it ready
# when Sköll arrives?
const FED_TURNS_PER_FAVOUR := 3 # every 3 turns in a row without starving: Favour +1...
const FED_FAVOUR_CAP := 7 # ...but only up to this: to reach RISE_FAVOUR you must grant her requests
const STARVING_FAVOUR := -2 # a turn in which the kingdom starves (a unit deserts)
const READY_DEFENCE := 10 # what she wants by the time Sköll arrives:
const READY_ARMY := 6 #   city defence and total army Strength
const READY_FAVOUR := 2 # both met
const UNREADY_FAVOUR := -3 # neither met (one met: no change)

# Going rogue
const LEAVE_FAVOUR := 2 # at this Favour or below she leaves her protector
const WARN_FAVOUR := 4 # at this Favour or below the player is warned
const PERSUADE_PER_FAVOUR := 0.1 # chance to persuade her = Favour x 10%

# Trading her (from TRADE_TURN, by whoever shelters her). Her "value" to a
# faction is a price in Industry: positive, they pay the giver; negative, the
# giver must pay them to take her; below TRADE_REFUSE_BELOW they refuse outright.
const TRADE_TURN := 10
const TRADE_BASE_VALUE := 6 # her bonuses are worth having...
const FEAR_HOWLING := 3 # ...less once Sköll's howling starts,
const FEAR_LOOSE := 6 # ...even less once he's loose (this replaces FEAR_HOWLING),
const FEAR_HUNTED := 3 # ...and less again if he's hunting their city.
const DISDAIN_PER := 3 # -1 for every 3 points their army is stronger than the giver's
const TRADE_MAX_PRICE := 10
const TRADE_REFUSE_BELOW := -8
const TRADED_FAVOUR := -2 # being traded costs Favour toward whoever gave her away

# Requests (only the player is asked): every REQUEST_GAP turns from
# REQUEST_FROM, while she shelters with you, she asks for something
# (turn_events.gd SUNNA_REQUESTS). Granting costs it and raises her Favour;
# refusing lowers it.
const REQUEST_FROM := 8
const REQUEST_GAP := 4
const REQUEST_GRANTED := 1
const REQUEST_REFUSED := -2

# Rising: from GameState.RISE_TURN, if she shelters with a faction whose
# Favour is RISE_FAVOUR or more, she rises as the new sun and stands with
# them: they get RISEN_FOOD and RISEN_INDUSTRY a turn (and her defence), Sköll
# becomes mortal at his normal Strength, and the ash stops.
const RISE_FAVOUR := 8
const RISEN_FOOD := 3
const RISEN_INDUSTRY := 3

# Rival claims (contested Sunna, step 3): every people believes she is its
# own lost sun, and resents whoever holds her. Every CLAIM_GAP turns, each AI's
# Trust toward the player -1 while the player shelters her (at most
# CLAIM_TRUST_MAX in a game from this; AIs keep no Trust toward each other).
# Holding her is a reason for war (diplomacy.gd rival_consider_war,
# GameState.ai_wars_turn), an AI may demand her (diplomacy.gd "claim"), and
# taking her holder's city carries her off (GameState.make_tributary).
const CLAIM_NAMES := {"Norse": "Sól", "Japanese": "Amaterasu", "Greek": "Helios", "Celtic": "Belenus"}
const CLAIM_GAP := 4
const CLAIM_TRUST := -1
const CLAIM_TRUST_MAX := 4
const CLAIM_DEMAND_CHANCE := 0.5 # when an AI makes an offer and wants her, chance it demands her
const CLAIM_VALUE_MIN := -3 # it only demands her while she's worth at least this to it (daughter_value): a terrified people doesn't
const CLAIM_SIEGE_PULL := 3 # an AI at war with her holder marches on that city as if it were this much nearer

enum State { SHELTERED, ROGUE, SWALLOWED, RISEN }

var state := State.SHELTERED
var holder: Faction = null # who shelters her (she chooses at the Landing)
var fed_turns := 0 # turns in a row her protector has kept its people fed
var pos := HexMap.NO_CELL # where she stands while ROGUE

# Start of a new game: nobody holds her yet, and Favour is set.
func reset(player: Faction, ai_factions: Array[Faction]) -> void:
	state = State.SHELTERED
	holder = null
	fed_turns = 0
	pos = HexMap.NO_CELL
	player.favour = PLAYER_START_FAVOUR
	for f in ai_factions:
		f.favour = randi_range(RIVAL_FAVOUR_MIN, RIVAL_FAVOUR_MAX) # hidden from the player

# She shelters with whoever she trusts most. A tie is decided at random.
func choose_protector(candidates: Array[Faction]) -> void:
	var best: Array[Faction] = []
	var best_favour := -1
	for f in candidates:
		if f.favour > best_favour:
			best_favour = f.favour
			best = [f]
		elif f.favour == best_favour:
			best.append(f)
	holder = best.pick_random()

func shelters_with(f: Faction) -> bool:
	return state == State.SHELTERED and holder == f

func is_swallowed() -> bool:
	return state == State.SWALLOWED

# She has risen as the new sun, standing with the faction she chose ("holder").
func is_risen() -> bool:
	return state == State.RISEN

func risen_with(f: Faction) -> bool:
	return state == State.RISEN and holder == f

func is_rogue() -> bool:
	return state == State.ROGUE

func persuade_chance(f: Faction) -> float:
	return clampf(f.favour * PERSUADE_PER_FAVOUR, 0.0, 1.0)

# She walks out of her protector's city onto the given hex.
func go_rogue(cell: Vector2i) -> void:
	state = State.ROGUE
	holder = null
	fed_turns = 0
	pos = cell

# She agrees to shelter in this faction's city.
func join(f: Faction) -> void:
	state = State.SHELTERED
	holder = f
	fed_turns = 0
	pos = HexMap.NO_CELL

func change_favour(f: Faction, amount: int) -> void:
	f.favour = clampi(f.favour + amount, 0, MAX_FAVOUR)

# What faction f calls her: its own lost sun (Sól, Amaterasu, Helios, Belenus).
static func claim_name(f: Faction) -> String:
	return CLAIM_NAMES.get(f.name, NAME)

func whose(f: Faction) -> String:
	return "your" if f.is_player else f.name + "'s"

# Once a turn, for her protector. Returns a message, or "" if nothing changed.
func judge_feeding(starved: bool) -> String:
	if holder == null:
		return ""
	if starved:
		fed_turns = 0
		change_favour(holder, STARVING_FAVOUR)
		return "%s saw %s people starve. Her Favour %+d." % [NAME.capitalize(), whose(holder), STARVING_FAVOUR]
	fed_turns += 1
	if fed_turns % FED_TURNS_PER_FAVOUR == 0 and holder.favour < FED_FAVOUR_CAP:
		change_favour(holder, 1)
		return "%s is content: %s people have been fed for %d turns. Her Favour +1." % [NAME.capitalize(), whose(holder), fed_turns]
	return ""

# When Sköll arrives: is her protector ready? Returns a message.
func judge_readiness(defence: int, army: int) -> String:
	if holder == null:
		return ""
	var met := int(defence >= READY_DEFENCE) + int(army >= READY_ARMY)
	var amount := 0
	var verdict := "is uneasy, only half ready"
	if met == 2:
		amount = READY_FAVOUR
		verdict = "is reassured"
	elif met == 0:
		amount = UNREADY_FAVOUR
		verdict = "is afraid, nothing is ready"
	change_favour(holder, amount)
	return "%s %s (defence %d/%d, army %d/%d). Her Favour %+d." % [NAME.capitalize(), verdict, defence, READY_DEFENCE, army, READY_ARMY, amount]
