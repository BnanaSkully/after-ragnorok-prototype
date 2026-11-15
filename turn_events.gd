# Small events every few turns after the Landing. Each asks the player to
# choose, and every option costs something.
#
# PLACEHOLDER TEXT - rewrite freely, or add events to the list. Each event has
# a "title", "text" and "options". Each option has a "label" (button text),
# "effects" and a "result" (the message afterwards). Effects:
#   "food", "industry"  added to your stores. A cost (negative) must be
#                       affordable or the button is greyed out.
#   "population"        added to your city (never below 1)
#   "favour"            the Sun's Daughter's Favour toward you
#   "reveal": true      uncovers the land around an AI city you haven't found
#   "guard_turns": N    one of your army units stands watch: it can't move for N turns
#                       (greyed out if you have no army unit)
#   "trust_all": N      added to every AI faction's Trust toward you
#   "spoil": N          you lose up to N Food (a loss, not a payment: always possible)
#   "gamble": {"chance": 0.5, "good": {...}, "good_text": "...",
#              "bad": {...}, "bad_text": "..."}  a coin flip after the costs;
#              losses can't take anything below 0
# Every option must cost something (tests/choices_test.gd checks), and every
# event needs at least one option that's always possible.
# Each event happens at most once a game.

# Sunna's requests to whoever shelters her (the player only; see
# sun_daughter.gd REQUEST_*). The game adds the two options itself: grant
# ("grant" effects, her Favour +1) or refuse (her Favour -2). Placeholder text.
const SUNNA_REQUESTS := [
	{"title": "SUNNA ASKS: LIGHT", "text": "\"Your people huddle in the dark. Light the hearths in every house.\"", "grant": "Light them (Industry -5)", "effects": {"industry": -5}},
	{"title": "SUNNA ASKS: BREAD", "text": "\"There are hungry children at the gate who are not yours. Feed them.\"", "grant": "Feed them (Food -5)", "effects": {"food": -5}},
	{"title": "SUNNA ASKS: A GUARD", "text": "\"I hear him at night. Let soldiers stand at my door.\"", "grant": "Post a guard (an army unit can't move for 3 turns)", "effects": {"guard_turns": 3}},
	{"title": "SUNNA ASKS: A SHRINE", "text": "\"Raise a shrine to my mother, so your people remember what was lost.\"", "grant": "Build it (Industry -6)", "effects": {"industry": -6}},
	{"title": "SUNNA ASKS: KINDNESS", "text": "\"Send grain to your neighbours. The night is long for all of us.\"", "grant": "Send it (Food -4, every AI's Trust +1)", "effects": {"food": -4, "trust_all": 1}},
]

const MIN_GAP := 2 # turns between events (random, inclusive)
const MAX_GAP := 3

const EVENTS := [
	{
		"title": "REFUGEES",
		"text": "Stragglers from the Crossing stumble out of the dark: a dozen families, starving.",
		"options": [
			{"label": "Take them in (Food -4, population +1: +1 Food, +1 Industry, +1 defence a turn)", "effects": {"food": -4, "population": 1}, "result": "The newcomers are fed and set to work."},
			{"label": "Turn them away (her Favour -1)", "effects": {"favour": -1}, "result": "They walk back into the dark. Sunna watches them go."},
		],
	},
	{
		"title": "STORM",
		"text": "A storm from the void tears across your fields in the night.",
		"options": [
			{"label": "Rebuild the granary now (Industry -3)", "effects": {"industry": -3}, "result": "The granary stands again by dawn."},
			{"label": "Let it be and hope (50%: lose 5 Food)", "effects": {"gamble": {"chance": 0.5, "good": {}, "good_text": "Most of the stores survived the storm.", "bad": {"food": -5}, "bad_text": "Rain ruined the stores: Food -5."}}, "result": ""},
		],
	},
	{
		"title": "THE ARK'S IRON",
		"text": "Your smiths want to break up the hull of the ark that carried you across the void.",
		"options": [
			{"label": "Break it up (Industry +4, her Favour -1)", "effects": {"industry": 4, "favour": -1}, "result": "The ark becomes tools. She sailed in it; she says nothing."},
			{"label": "Keep it as a memorial (Food -2 for the ceremony)", "effects": {"food": -2}, "result": "The ark stands on the shore, a reminder of what you survived."},
		],
	},
	{
		"title": "SICK HERDS",
		"text": "A sickness is spreading through the animals you brought across.",
		"options": [
			{"label": "Cull the sick ones (Food -3)", "effects": {"food": -3}, "result": "The sickness is stopped."},
			{"label": "Wait and see (50%: lose 6 Food)", "effects": {"gamble": {"chance": 0.5, "good": {}, "good_text": "The sickness passes on its own.", "bad": {"food": -6}, "bad_text": "Half the herd dies: Food -6."}}, "result": ""},
		],
	},
	{
		"title": "GIANT ELK",
		"text": "Hunters report a herd of giant elk in the hills.",
		"options": [
			{"label": "Arm a hunting party (Industry -3: 60% Food +8)", "effects": {"industry": -3, "gamble": {"chance": 0.6, "good": {"food": 8}, "good_text": "The hunters return heavy with meat: Food +8.", "bad": {}, "bad_text": "The herd scatters. The hunters come back empty-handed."}}, "result": ""},
			{"label": "Leave them be (they trample a field: Food -1)", "effects": {"spoil": 1}, "result": "The elk move on, leaving a flattened field."},
		],
	},
	{
		"title": "A TRAVELLER",
		"text": "A ragged traveller says he has seen where another people landed, and will tell you for a meal.",
		"options": [
			{"label": "Feed him (Food -2, reveals an AI city)", "effects": {"food": -2, "reveal": true}, "result": ""},
			{"label": "Send him away (he'll tell the others about you: every AI's Trust -1)", "effects": {"trust_all": -1}, "result": "He walks off into the dark, muttering. Your neighbours will hear his version."},
		],
	},
	{
		"title": "A FEAST FOR THE DEAD",
		"text": "Your people want a feast to honour those lost at Ragnarök.",
		"options": [
			{"label": "Hold the feast (Food -4, her Favour +1)", "effects": {"food": -4, "favour": 1}, "result": "The songs carry far into the night."},
			{"label": "Refuse: every grain counts (30%: population -1)", "effects": {"gamble": {"chance": 0.7, "good": {}, "good_text": "Your people grumble, but stay.", "bad": {"population": -1}, "bad_text": "Some families leave in anger: population -1."}}, "result": ""},
		],
	},
	{
		"title": "WOLF TRACKS",
		"text": "Huge tracks circle the city at night. Not Sköll, not yet. Something smaller, and hungry.",
		"options": [
			{"label": "Post guards (an army unit stands watch: can't move for 2 turns)", "effects": {"guard_turns": 2}, "result": "The guards keep watch, and the tracks stop."},
			{"label": "Build a palisade (Industry -3)", "effects": {"industry": -3}, "result": "A palisade goes up around the stores."},
			{"label": "Ignore them (50%: lose 4 Food)", "effects": {"gamble": {"chance": 0.5, "good": {}, "good_text": "The tracks vanish.", "bad": {"food": -4}, "bad_text": "Something got into the stores: Food -4."}}, "result": ""},
		],
	},
	{
		"title": "MERCHANTS",
		"text": "A band of survivors with a laden cart offers to trade.",
		"options": [
			{"label": "Trade grain for tools (Food -3, Industry +3)", "effects": {"food": -3, "industry": 3}, "result": "A fair trade."},
			{"label": "Trade tools for grain (Industry -3, Food +4)", "effects": {"industry": -3, "food": 4}, "result": "A fair trade."},
			{"label": "Rob them (Food +3, Industry +3; every AI's Trust -1, her Favour -1)", "effects": {"food": 3, "industry": 3, "trust_all": -1, "favour": -1}, "result": "You take the cart. The story travels fast."},
		],
	},
]
