# Discoveries hidden in the fog of war: ruins left by whoever lived here
# before the World Tree fell. (Rifts are Sköll's: see skoll.gd. They're found
# the same way, by seeing them; game_state.gd update_sight.)
#
# PLACEHOLDER TEXT - rewrite freely. A ruin is searched once, by the first unit
# to step on it. The player chooses the reward; an AI takes what it needs most.

const RUIN_COUNT := 8
const RUIN_MIN_CITY_DISTANCE := 4 # out of sight of every city at the start
const RUIN_SPACING := 3 # ruins at least this far apart
const RUIN_FOOD := 6
const RUIN_INDUSTRY := 4
const RUIN_FAVOUR := 1

const FLAVOUR := [
	"Your people pick through a stone hall half sunk in the earth. Whoever built it fled long ago.",
	"A ring of fallen standing stones, and beneath them a sealed cellar.",
	"The bones of a great ship, blown here when the sky broke. Its hold is still full.",
	"A burned village. Something was buried under the hearth before the fire.",
]

# Scatters the ruins after the Landing, away from every city.
static func place_ruins(game: GameState) -> Array[Dictionary]:
	var options: Array[Vector2i] = []
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var ok := game.unit_at(c) == null
			for f in game.factions:
				if f.is_alive() and HexMap.hex_distance(c, f.city_pos) < RUIN_MIN_CITY_DISTANCE:
					ok = false
			if ok:
				options.append(c)
	options.shuffle()
	var ruins: Array[Dictionary] = []
	for c in options:
		if ruins.size() >= RUIN_COUNT:
			break
		var spaced := true
		for r in ruins:
			if HexMap.hex_distance(c, r["cell"]) < RUIN_SPACING:
				spaced = false
		if spaced:
			ruins.append({"cell": c, "taken": false})
	return ruins

# The pop-up when one of the player's units searches ruins.
static func ruin_choice() -> Dictionary:
	return {
		"title": "RUINS",
		"text": FLAVOUR.pick_random() + "\nYour people can carry away one thing.",
		"options": [
			{"label": "Take the grain stores (Food +%d)" % RUIN_FOOD, "effects": {"food": RUIN_FOOD}, "result": "Your people haul the grain home."},
			{"label": "Take the tools and iron (Industry +%d)" % RUIN_INDUSTRY, "effects": {"industry": RUIN_INDUSTRY}, "result": "Your people haul the tools home."},
			{"label": "Leave it as a shrine to the dead (her Favour +%d)" % RUIN_FAVOUR, "effects": {"favour": RUIN_FAVOUR}, "result": "You leave the dead in peace. The Sun's Daughter hears of it."},
		],
	}

# An AI searches ruins: Food if it's short of Food, otherwise Industry.
static func ai_take_ruin(game: GameState, f: Faction) -> void:
	if game.food_change(f) <= 0:
		f.food += RUIN_FOOD
	else:
		f.industry += RUIN_INDUSTRY
