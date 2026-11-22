class_name Faction
extends RefCounted

# Everything one side owns. Each faction gets its own copy of these,
# so the player and the rival keep separate cities, units and resources.
# "class_name Faction" above lets any other script use Faction by name.

var name: String
var city_pos: Vector2i
var units: Array[Unit] = [] # this faction's units on the map (armies and scouts)
var outposts: Array[Vector2i] = [] # hexes of its outposts (each claims the hexes around it)
var strength := 3 # Strength of new army units (higher = better odds in combat)
var food := 0
var industry := 0
var favour := 0 # how much the Sun's Daughter trusts this faction (0 to 10)
var walls := 0 # city wall level (each level adds defence)
var city_hp := 20 # GameState.CITY_MAX_HP: attacks wear it down; at 0 the city falls
var buildings := {} # city buildings it has (key from buildings.gd -> true)
var population := 1 # city size: grows from surplus Food, each extra point makes +1 Food and +1 Industry
var pact_word := "oath" # what this faction calls a sworn agreement (Norse factions swear oaths)
var is_player := false
# Fog of war: every hex this faction has ever seen (hex -> true). Seen hexes
# stay explored; what's on them now is only known while they're in sight.
var explored := {}
var known_rifts := {} # rifts it has found (hex -> true); forgotten when the rifts shift
# Tributary (standard 4X vassal): the name of the faction that took its city in
# a war ("" = free). A tributary pays half its Industry income to its overlord
# and can't be at war with it until it rises up. (A name, not a link, so two
# factions never hold each other.)
var overlord := ""
var skoll_held := 0 # how many times its city held against Sköll, or its armies drove him back near it (Skoll.HELD_RANGE; Sunna rises only where a city has held: GameState.rise_missing)

# (How a faction looks on screen, its colours, is up to the view: see main.gd.)
func _init(p_name: String, p_city: Vector2i, p_pact_word := "oath") -> void:
	name = p_name
	city_pos = p_city
	pact_word = p_pact_word

func add_unit(cell: Vector2i, kind := Unit.Kind.ARMY) -> Unit:
	var u := Unit.new(self, cell, kind)
	units.append(u)
	return u

func remove_unit(u: Unit) -> void:
	units.erase(u)

func scout_count() -> int:
	return units.filter(func(u): return u.is_scout()).size()

# The faction is out of the game once its city has fallen.
func is_alive() -> bool:
	return city_pos != HexMap.NO_CELL
