# The Crossing: events the player faces on the way across Yggdrasil.
#
# PLACEHOLDER TEXT - rewrite these freely, or add more events to the list.
# Each event has some "text" and a list of "choices". Each choice has a
# "label" (the button text) and "effects": numbers added to what the
# player's people arrive with. Use "food", "industry", "strength" and "favour".
#
# "favour" is how much the Sun's Daughter trusts you. She travels with the
# survivors and watches how each people behaves; at the Landing she shelters
# with whoever she trusts most. Protecting people raises it, abandoning them
# lowers it.

const START_FOOD := 4
const START_INDUSTRY := 2

const EVENTS := [
	{
		"text": "A branch of the World Tree cracks beneath your people. There is time to save only one thing.",
		"choices": [
			{"label": "Save the food stores", "effects": {"food": 3, "strength": -1, "favour": -1}},
			{"label": "Save the warriors", "effects": {"strength": 1, "food": -3, "favour": 1}},
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
			{"label": "Stand and fight so the others can escape", "effects": {"strength": 1, "food": -2, "favour": 1}},
			{"label": "Drop the heavy gear and run", "effects": {"industry": -2, "favour": -1}},
		],
	},
	{
		"text": "A girl made of light walks among the survivors: Sunna, the Sun's Daughter, born just before the wolf swallowed her mother. She is weighing which people to trust. Whatever hunts her will hunt whoever she shelters with.",
		"choices": [
			{"label": "Share your food with her", "effects": {"food": -2, "favour": 2}},
			{"label": "Leave her be", "effects": {}},
		],
	},
]
