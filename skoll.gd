class_name Skoll
extends RefCounted

# Sköll, the wolf who swallowed the sun at Ragnarök. He followed the survivors
# through the void. He warns from WARNING_TURN, arrives on ARRIVAL_TURN through
# one of the rifts (chosen at random), hunts the city that rift belongs to,
# walks one hex a turn toward it and attacks it. Once he has found Sunna's
# city he hunts whoever shelters her.
# Cycles: driven back, he vanishes into the void and returns RETURN_TURNS
# later through a rift (they are permanent), STRENGTH_PER_RETURN stronger; each time he comes
# through, ash spreads (GameState.spread_ash).
# While Sunna is hidden (sheltered or rogue) he can't be killed: a unit that
# attacks him dies but WOUNDS him (his Strength is lowered by his wounds,
# which heal WOUND_HEAL a turn); wounds of half his Strength drive him back.
# Once she has risen, or he has swallowed her, he is MORTAL: an attack that
# beats him kills him (GameState.wolf_slain).
#
# "game" is the GameState (game_state.gd): Sköll uses it to see the factions, post messages and end
# the game.

const WARNING_TURN := 10 # howling warnings start on this turn
const ARRIVAL_TURN := 14 # he arrives on this turn
const STRENGTH := 10 # his starting Strength
const SWALLOW_BONUS := 8 # Strength he gains by swallowing Sunna (much stronger, but mortal)
const RETURN_TURNS := 3 # turns in the void after being driven back
const STRENGTH_PER_RETURN := 2 # he comes back stronger each time
const WOUND_HEAL := 2 # wounds heal this much a turn
const CITY_DAMAGE := 2.0 # he tears at a city's HP this many times as hard as an army would (a siege beast)

# The rifts he comes through are in rifts.gd (GameState.rifts).
const SCENT_WEIGHT := 2 # he scents Sunna: her protector's rift is this many times as likely as any other (pick_rift)
const HELD_RANGE := 3 # driving him back within this many hexes of your city counts as your city holding against him (Nathan's pick, 22 Nov)
const SIGHT_RANGE := 2 # fog of war: he only sees this far; a rogue Daughter further away is hidden from him
const SPEED := 2 # hexes a turn he walks toward the city he hunts (was 1; Nathan's playtest: "he isn't scary anymore")
const RAGE_SPEED := 3 # once Sunna has risen he is mortal but enraged: he runs this fast at her city
const SPRINT := 3 # hexes a turn he runs when hunting her in the open (she runs 1; was 2, kept faster than SPEED)

# The GameState (game_state.gd). A "weak" link: the game keeps this object alive,
# but this object doesn't keep the game alive, so Godot can free both later.
var game: GameState:
	get:
		return _game.get_ref()
var _game: WeakRef
var active := false # false until he arrives
var pos := HexMap.NO_CELL
var strength := STRENGTH
var target: Faction = null # the city he is hunting right now
var knows_her := false # he has found Sunna's city: from now on he hunts whoever shelters her
var wounds := 0 # lowers his Strength until healed (see effective_strength)
var away_until := 0 # driven back: he returns on this turn
var returns := 0 # how many times he has come back
var slain := false

func _init(p_game: GameState) -> void:
	_game = weakref(p_game)

# Fog of war: what Sköll can see from where he stands.
func can_see(cell: Vector2i) -> bool:
	return active and HexMap.hex_distance(pos, cell) <= SIGHT_RANGE

func is_at(cell: Vector2i) -> bool:
	return active and cell == pos

# His Strength right now: lowered by his wounds (never below 1).
func effective_strength() -> int:
	return maxi(1, strength - wounds)

# Can he die? Only once Sunna has risen, or he has swallowed her.
func is_mortal() -> bool:
	return game.daughter.is_risen() or game.daughter.is_swallowed()

func take_turn() -> void:
	if game.turn < WARNING_TURN or slain:
		return
	if game.turn < ARRIVAL_TURN:
		var left: int = ARRIVAL_TURN - game.turn
		game.add_message("Howling in the void... Sköll arrives %s." % ("next turn" if left == 1 else "in %d turns" % left))
		return
	if not active:
		if game.turn < away_until:
			return # prowling the void
		arrive()
		return
	wounds = maxi(0, wounds - WOUND_HEAL)
	var hunted := her_city()
	if hunted != null:
		target = hunted
	# The Daughter out in the open: if he can smell her, he goes for her.
	var daughter: SunDaughter = game.daughter
	if daughter.is_rogue() and can_see(daughter.pos):
		hunt_daughter(daughter)
		return
	if target == null or not target.is_alive():
		pick_target()
	if target == null:
		return
	# He lopes SPEED hexes a turn toward the city he hunts. Reaching it, he
	# attacks at once; a unit standing in his way stops him and he fights it.
	for step in (RAGE_SPEED if game.daughter.is_risen() else SPEED):
		if HexMap.is_neighbour(pos, target.city_pos):
			attack_city(target)
			return
		var best := HexMap.NO_CELL
		var best_d := 999
		var best_free := false
		for c in HexMap.neighbours(pos):
			if game.is_city(c) or game.rifts.walker_at(c) != null:
				continue # (Rift Walkers are creatures of the roots, like him: he lopes round them)
			var d := HexMap.hex_distance(c, target.city_pos)
			var free: bool = game.unit_at(c) == null
			# closest to the city first; at the same distance he goes round a unit rather than through it
			if d < best_d or (d == best_d and free and not best_free):
				best_d = d
				best = c
				best_free = free
		if best == HexMap.NO_CELL:
			return
		var in_the_way: Unit = game.unit_at(best)
		if in_the_way:
			attack_unit(in_the_way)
			return
		pos = best

# Sköll doesn't know who shelters the Daughter. He only finds out after
# the battle, if she turns out to be in the city he attacked.
func attack_city(f: Faction) -> void:
	var defence: int = game.city_defence(f)
	var dealt: int = roundi(game.combat_damage(effective_strength(), defence) * CITY_DAMAGE)
	var taken: int = game.combat_damage(defence, effective_strength())
	var she_is_here: bool = game.daughter.shelters_with(f) or game.daughter.risen_with(f)
	f.city_hp -= dealt
	if she_is_here and not knows_her:
		knows_her = true
		var where := "your city" if f == game.player else "the %s city" % f.name
		game.add_message("Sköll has found %s: she hides in %s. From now on he hunts whoever shelters her." % [SunDaughter.NAME, where])
	if f.city_hp <= 0:
		game.add_message("Sköll attacked %s's city (defence %d) and tore it down." % [f.name, defence])
		pos = f.city_pos
		var inside: Unit = game.unit_at(f.city_pos) # whoever is in the city dies, even an enemy
		if inside:
			inside.faction.remove_unit(inside)
		f.city_pos = HexMap.NO_CELL
		f.units.clear() # with its city gone, the faction's army scatters
		f.outposts.clear() # and its outposts are abandoned
		f.overlord = ""
		for g in game.factions:
			if g.overlord == f.name:
				g.overlord = "" # its tributaries are free
		if she_is_here:
			swallow_daughter()
		game.devour(f) # (your city: you lose; enough factions: Sköll wins)
		if not game.game_over:
			# Sated, he goes back into the void to feed, and returns stronger.
			game.add_message("Gorged, Sköll sinks back into the void to feed.")
			drive_back()
	else:
		game.add_message("%s's city (defence %d) held: it lost %d HP (%d left) and wounded Sköll by %d." % [f.name, defence, dealt, f.city_hp, taken])
		f.skoll_held += 1
		wound(taken, f)

# She's out in the open: he sprints toward her (SPRINT hexes a turn), and if
# he reaches her he swallows her with no battle.
func hunt_daughter(d: SunDaughter) -> void:
	for step in SPRINT:
		if HexMap.is_neighbour(pos, d.pos):
			pos = d.pos
			game.add_message("Sköll caught %s out in the open." % SunDaughter.NAME)
			swallow_daughter()
			return
		var best := HexMap.NO_CELL
		var best_d := HexMap.hex_distance(pos, d.pos)
		for c in HexMap.neighbours(pos):
			if game.is_city(c) or game.is_blocked(c):
				continue
			var dist := HexMap.hex_distance(c, d.pos)
			if dist < best_d:
				best_d = dist
				best = c
		if best == HexMap.NO_CELL:
			break
		pos = best
	game.add_message("Sköll has spotted %s in the open and sprints after her!" % SunDaughter.NAME)

# He comes through a rift: the first time on ARRIVAL_TURN, then again
# RETURN_TURNS after each time he's driven back, stronger each time.
func arrive() -> void:
	active = true
	wounds = 0
	if returns > 0:
		strength += STRENGTH_PER_RETURN
	var guard := come_through_rift()
	var hunted := her_city()
	if hunted != null:
		target = hunted
	game.spread_ash(pos)
	if returns == 0:
		game.add_message("Sköll, the wolf who swallowed the sun, tears through a rift! He is hunting %s. Ash spreads where he walks." % target_text())
	else:
		game.add_message("Sköll returns through a rift, stronger (Strength %d). He is hunting %s. More of the land turns to ash." % [strength, target_text()])
	if guard != null:
		game.add_message("He burst out of the rift %s's unit was standing on, and fell on it." % guard.faction.name)
		attack_unit(guard)

# Once he has found her, the city sheltering Sunna (or the one she rose for).
func her_city() -> Faction:
	var d: SunDaughter = game.daughter
	if knows_her and (d.state == SunDaughter.State.SHELTERED or d.is_risen()) and d.holder != null and d.holder.is_alive():
		return d.holder
	return null

# Sköll becomes the sun: much stronger, the whole map goes dark, but he can die.
func swallow_daughter() -> void:
	game.daughter.state = SunDaughter.State.SWALLOWED
	game.daughter.holder = null
	game.daughter.pos = HexMap.NO_CELL
	strength += SWALLOW_BONUS
	game.add_message("Sköll swallowed %s! He is the sun now (Strength %d), and the world goes dark. But the sun inside him makes him MORTAL: a large combined force can kill him." % [SunDaughter.NAME, strength])

# A unit stands in his way: both take damage, like any fight between units
# (GameState.combat_damage). The unit loses HP (and may die: then he steps
# in); the damage it deals back becomes his wounds.
func attack_unit(u: Unit) -> void:
	var defence: int = game.defender_strength(u) # (wounds weaken it; forest and hills help)
	var dealt: int = game.combat_damage(effective_strength(), defence)
	var taken: int = game.combat_damage(defence, effective_strength())
	u.hp -= dealt
	u.acted = true
	if u.hp <= 0:
		game.add_message("Sköll attacked %s's unit and destroyed it (dealt %d, took %d)." % [u.faction.name, dealt, taken])
		var cell := u.pos
		game.unit_died(u)
		pos = cell
	else:
		game.add_message("%s's unit held against Sköll: it lost %d HP and wounded him by %d." % [u.faction.name, dealt, taken])
	wound(taken, u.faction)

# A unit (the player's) attacks him, helped by every other army of its own or
# its allies next to him (GameState.wolf_attack). The damage it deals becomes
# his wounds. Hidden Sunna: he can't die and the attacker dies (Nathan's rule).
# Mortal: a normal two-way fight; he dies when his wounds reach his Strength.
func attacked_by(u: Unit) -> void:
	var attack: int = game.wolf_attack(u)
	var dealt: int = game.combat_damage(attack, effective_strength())
	if is_mortal():
		var taken: int = game.combat_damage(effective_strength(), attack)
		u.hp -= taken
		game.add_message("Your attack (%d against %d) wounded Sköll by %d; your unit lost %d HP." % [attack, effective_strength(), dealt, taken])
		if u.hp <= 0:
			game.add_message("Your unit died.")
			game.unit_died(u)
	else:
		game.add_message("Sköll can't be killed while %s is hidden. Your unit died, but its attack of %d wounded him by %d." % [SunDaughter.NAME, attack, dealt])
		game.unit_died(u)
	wound(dealt, u.faction, true)

# Wounds lower his Strength until they heal (WOUND_HEAL a turn). Wounds of half
# his Strength drive him back into the void. Only an ATTACK on him ("hunted")
# can kill him, once he's mortal: then he stands and fights, and wounds equal
# to his Strength kill him ("by" is whoever struck the last blow). Damage from
# cities and units he attacks only drives him off: slaying the wolf takes a
# deliberate (combined) attack, not his own recklessness.
func wound(amount: int, by: Faction = null, hunted := false) -> void:
	wounds += amount
	if is_mortal() and hunted:
		if wounds >= strength:
			game.add_message("Sköll falls! The wolf is dead.")
			slain = true
			active = false
			pos = HexMap.NO_CELL
			game.wolf_slain(by)
		else:
			game.add_message("Sköll is wounded: %d of his %d Strength left." % [effective_strength(), strength])
		return
	if wounds * 2 >= strength:
		game.add_message("Badly wounded (%d of his %d Strength), Sköll flees into the void." % [mini(wounds, strength), strength])
		# Driving him off near your own city counts as your city holding against him
		# (Sunna rises only where a city has held: GameState.rise_missing).
		if by != null and by.is_alive() and HexMap.hex_distance(pos, by.city_pos) <= HELD_RANGE:
			by.skoll_held += 1
		drive_back()
	else:
		game.add_message("Sköll is wounded: Strength %d for now (heals %d a turn)." % [effective_strength(), WOUND_HEAL])

# Driven back: he vanishes into the void and returns RETURN_TURNS later
# through a rift, stronger. The rifts stay where they are (Nathan, 22 Nov:
# rifts are permanent), so a rift you found stays on your map.
func drive_back() -> void:
	active = false
	pos = HexMap.NO_CELL
	wounds = 0
	returns += 1
	away_until = game.turn + RETURN_TURNS
	game.add_message("Sköll slinks back into the void. He will return in %d turns, stronger." % RETURN_TURNS)

# Come out of a random rift and hunt the city it opened toward. The rifts are
# permanent, so a faction may park a unit on one: he still comes through it,
# bursts out onto a free hex next to it and falls on that unit (arrive attacks
# it). Returns that unit, or null. A rift he can't use (a city or rogue Sunna
# on it, or no free hex beside a guarded one) is skipped.
func come_through_rift() -> Unit:
	var choices: Array[Vector2i] = []
	for r in game.rifts.cells:
		if game.is_city(r):
			continue
		var u: Unit = game.unit_at(r)
		if u == null and not game.is_blocked(r):
			choices.append(r)
		elif u != null and exit_beside(r) != HexMap.NO_CELL:
			choices.append(r)
	var guard: Unit = null
	if choices.is_empty():
		pos = game.rifts.random_edge_cell()
		game.rifts.revealed = pos
	else:
		var rift := pick_rift(choices)
		game.rifts.revealed = rift
		guard = game.unit_at(rift)
		pos = exit_beside(rift) if guard != null else rift
	var owner: Faction = game.rifts.owner_of(game.rifts.revealed)
	if owner != null and owner.is_alive():
		target = owner # he hunts the city this rift opened toward
	else:
		pick_target()
	return guard

# A free hex next to a rift a unit stands on, where he comes out (the first
# free one in a fixed order, so seeded games repeat), or NO_CELL.
func exit_beside(rift: Vector2i) -> Vector2i:
	for c in HexMap.neighbours(rift):
		if HexMap.in_bounds(c) and not game.is_blocked(c) and not game.is_city(c):
			return c
	return HexMap.NO_CELL

# He scents Sunna: the rift of the city sheltering her counts SCENT_WEIGHT
# times (about 40% with 4 cities instead of 25%). Not while she's rogue (her
# trail leads nowhere) or once she has risen or been swallowed.
func pick_rift(free: Array[Vector2i]) -> Vector2i:
	var d: SunDaughter = game.daughter
	var her_rift := HexMap.NO_CELL
	if d.state == SunDaughter.State.SHELTERED and d.holder != null:
		for r in free:
			if game.rifts.city.get(r, "") == d.holder.name:
				her_rift = r
	if her_rift == HexMap.NO_CELL:
		return free.pick_random()
	var roll := randi_range(1, free.size() - 1 + SCENT_WEIGHT)
	if roll <= SCENT_WEIGHT:
		return her_rift
	var others := free.filter(func(r): return r != her_rift)
	return others.pick_random()

# (Used when his rift belongs to no standing city, or his target fell.) He
# doesn't know which city hides the Daughter: he hunts the nearest city (ties
# at random).
func pick_target() -> void:
	var best: Array[Faction] = []
	var best_d := 999
	for f in game.factions:
		if not f.is_alive():
			continue
		var d := HexMap.hex_distance(pos, f.city_pos)
		if d < best_d:
			best_d = d
			best = [f]
		elif d == best_d:
			best.append(f)
	target = best.pick_random() if not best.is_empty() else null

func target_text() -> String:
	if target == null:
		return "nobody"
	return "your city" if target == game.player else "%s's city" % target.name
