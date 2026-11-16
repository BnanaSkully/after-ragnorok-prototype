# City buildings (standard 4X): each is bought once with Industry and gives a
# permanent bonus. Walls are separate (two levels; WALL_* in game_state.gd).
# The rules for what each does live where they apply in game_state.gd
# (food_change, industry_change, city_defence, can_see, build_building).
#
# Numbers are first guesses; balance later.

const GRANARY_FOOD := 2
const WORKSHOP_INDUSTRY := 2
const WATCHTOWER_SIGHT := 2
const WATCHTOWER_DEFENCE := 1
const FORGE_STRENGTH := 1
const BARRACKS_SUPPLY := 2

# In the order the build panel lists them (and the AI considers them).
const LIST := {
	"granary": {"name": "Granary", "cost": 8, "text": "+%d Food a turn" % GRANARY_FOOD},
	"workshop": {"name": "Workshop", "cost": 12, "text": "+%d Industry a turn" % WORKSHOP_INDUSTRY},
	"watchtower": {"name": "Watchtower", "cost": 6, "text": "your city sees %d hexes further, +%d city defence" % [WATCHTOWER_SIGHT, WATCHTOWER_DEFENCE]},
	"forge": {"name": "Forge", "cost": 10, "text": "every army unit you build from now on has +%d Strength" % FORGE_STRENGTH},
	"barracks": {"name": "Barracks", "cost": 8, "text": "+%d army supply (you can field %d more armies)" % [BARRACKS_SUPPLY, BARRACKS_SUPPLY]},
}

static func cost(key: String) -> int:
	return LIST[key]["cost"]
