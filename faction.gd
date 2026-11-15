class_name Faction
extends RefCounted

# Everything one side owns. Each faction gets its own copy of these,
# so the player and the rival keep separate cities, units and resources.
# "class_name Faction" above lets any other script use Faction by name.

var name: String
var territory_color: Color
var unit_color: Color
var city_pos: Vector2i
var unit_pos: Vector2i
var unit_moves := 1
var unit_alive := true
var strength := 3 # higher strength = better odds in combat
var food := 0
var industry := 0
var favour := 0 # how much the Sun's Daughter trusts this faction (0 to 10)

func _init(p_name: String, p_territory: Color, p_unit: Color, p_city: Vector2i, p_unit_pos: Vector2i) -> void:
	name = p_name
	territory_color = p_territory
	unit_color = p_unit
	city_pos = p_city
	unit_pos = p_unit_pos
