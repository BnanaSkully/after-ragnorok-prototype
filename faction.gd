class_name Faction
extends RefCounted

# Everything one side owns. Each faction gets its own copy of these,
# so the player and the rival keep separate cities, units and resources.
# "class_name Faction" above lets any other script use Faction by name.

var name: String
var territory_color: Color
var unit_color: Color
var city_pos: Vector2i
var units: Array[Unit] = [] # this faction's army units on the map
var strength := 3 # Strength of new units (higher = better odds in combat)
var food := 0
var industry := 0
var favour := 0 # how much the Sun's Daughter trusts this faction (0 to 10)
var walls := 0 # city wall level (each level adds defence)
var pact_word := "oath" # what this faction calls a sworn agreement (Norse factions swear oaths)

func _init(p_name: String, p_territory: Color, p_unit: Color, p_city: Vector2i) -> void:
	name = p_name
	territory_color = p_territory
	unit_color = p_unit
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
