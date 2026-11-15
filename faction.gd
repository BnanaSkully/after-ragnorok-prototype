class_name Faction
extends RefCounted

# Everything one side owns. Each faction gets its own copy of these,
# so the player and the rival keep separate cities, units and resources.
# "class_name Faction" above lets any other script use Faction by name.

var name: String
var city_pos: Vector2i
var units: Array[Unit] = [] # this faction's army units on the map
var strength := 3 # Strength of new units (higher = better odds in combat)
var food := 0
var industry := 0
var favour := 0 # how much the Sun's Daughter trusts this faction (0 to 10)
var walls := 0 # city wall level (each level adds defence)
var population := 1 # city size: grows from surplus Food, each extra point makes +1 Food and +1 Industry
var pact_word := "oath" # what this faction calls a sworn agreement (Norse factions swear oaths)

# (How a faction looks on screen, its colours, is up to the view: see main.gd.)
func _init(p_name: String, p_city: Vector2i) -> void:
	name = p_name
	city_pos = p_city

func add_unit(cell: Vector2i) -> Unit:
	var u := Unit.new(self, cell)
	units.append(u)
	return u

func remove_unit(u: Unit) -> void:
	units.erase(u)

# The faction is out of the game once its city has fallen.
func is_alive() -> bool:
	return city_pos != HexMap.NO_CELL
