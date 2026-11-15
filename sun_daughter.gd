class_name SunDaughter
extends RefCounted

# The Sun's Daughter: the new sun, born just before Sköll swallowed her mother.
# She travels with the survivors on the Crossing and watches how each people
# behaves. Her Favour toward a faction (0 to 10) is stored on the Faction itself.
# At the Landing she chooses to shelter with whoever she trusts most.

const NAME := "the Sun's Daughter" # change her name here
const PLAYER_START_FAVOUR := 3
const RIVAL_FAVOUR_MIN := 3 # the rival's Favour is hidden and random in this range
const RIVAL_FAVOUR_MAX := 6
const MAX_FAVOUR := 10

# What sheltering her gives
const FOOD := 2 # extra Food per turn
const INDUSTRY := 2 # extra Industry per turn
const DEFENCE := 3 # extra city defence

# How she judges whoever shelters her: is the kingdom fed, and is it ready
# when Sköll arrives?
const FED_TURNS_PER_FAVOUR := 3 # every 3 turns in a row without starving: Favour +1
const STARVING_FAVOUR := -2 # a turn in which the kingdom starves (a unit deserts)
const READY_DEFENCE := 10 # what she wants by the time Sköll arrives:
const READY_ARMY := 6 #   city defence and total army Strength
const READY_FAVOUR := 2 # both met
const UNREADY_FAVOUR := -3 # neither met (one met: no change)

enum State { SHELTERED, SWALLOWED }

var state := State.SHELTERED
var holder: Faction = null # who shelters her (she chooses at the Landing)
var fed_turns := 0 # turns in a row her protector has kept its people fed

# Start of a new game: nobody holds her yet, and Favour is set.
func reset(player: Faction, rival: Faction) -> void:
	state = State.SHELTERED
	holder = null
	fed_turns = 0
	player.favour = PLAYER_START_FAVOUR
	rival.favour = randi_range(RIVAL_FAVOUR_MIN, RIVAL_FAVOUR_MAX) # hidden from the player

# She shelters with whoever she trusts most. A tie is decided at random.
func choose_protector(player: Faction, rival: Faction) -> void:
	if player.favour == rival.favour:
		holder = [player, rival].pick_random()
	else:
		holder = player if player.favour > rival.favour else rival

func shelters_with(f: Faction) -> bool:
	return state == State.SHELTERED and holder == f

func is_swallowed() -> bool:
	return state == State.SWALLOWED

func change_favour(f: Faction, amount: int) -> void:
	f.favour = clampi(f.favour + amount, 0, MAX_FAVOUR)

func whose(f: Faction) -> String:
	return "your" if f.name == "Player" else f.name + "'s"

# Once a turn, for her protector. Returns a message, or "" if nothing changed.
func judge_feeding(starved: bool) -> String:
	if holder == null:
		return ""
	if starved:
		fed_turns = 0
		change_favour(holder, STARVING_FAVOUR)
		return "%s saw %s people starve. Her Favour %+d." % [NAME.capitalize(), whose(holder), STARVING_FAVOUR]
	fed_turns += 1
	if fed_turns % FED_TURNS_PER_FAVOUR == 0:
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
