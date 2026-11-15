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

enum State { SHELTERED, SWALLOWED }

var state := State.SHELTERED
var holder: Faction = null # who shelters her (she chooses at the Landing)

# Start of a new game: nobody holds her yet, and Favour is set.
func reset(player: Faction, rival: Faction) -> void:
	state = State.SHELTERED
	holder = null
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
