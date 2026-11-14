# The Crossing: events the player faces on the way across Yggdrasil.
#
# PLACEHOLDER TEXT - rewrite these freely, or add more events to the list.
# Each event has some "text" and a list of "choices". Each choice has a
# "label" (the button text) and "effects": numbers added to what the
# player's people arrive with. Use "food", "industry" and "strength".

const START_FOOD := 4
const START_INDUSTRY := 2

const EVENTS := [
	{
		"text": "A branch of the World Tree cracks beneath your people. There is time to save only one thing.",
		"choices": [
			{"label": "Save the food stores", "effects": {"food": 3, "strength": -1}},
			{"label": "Save the warriors", "effects": {"strength": 1, "food": -3}},
		],
	},
	{
		"text": "Among the branches you find an abandoned forge, still warm.",
		"choices": [
			{"label": "Strip it for tools", "effects": {"industry": 3, "food": -1}},
			{"label": "Forage nearby and push on", "effects": {"food": 2}},
		],
	},
	{
		"text": "Something in the void is following you. It is getting closer.",
		"choices": [
			{"label": "Stand and fight", "effects": {"strength": 1, "food": -2}},
			{"label": "Drop the heavy gear and run", "effects": {"industry": -2}},
		],
	},
]
