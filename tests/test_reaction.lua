-- tests/test_reaction.lua
local p = { aggressive = 0.10, aggressiveMax = 0.35, weapon = 'WEAPON_PISTOL' }
eq('day, alone, base chance', Shops.aggressiveChance(p, { hour = 12, robbers = 1 }, Config), 0.10)
eq('night adds the night bonus', Shops.aggressiveChance(p, { hour = 23, robbers = 1 }, Config), 0.25)
eq('crowd bonus caps at two extra', Shops.aggressiveChance(p, { hour = 12, robbers = 5 }, Config), 0.30)
eq('never above aggressiveMax', Shops.aggressiveChance(p, { hour = 23, robbers = 5, aftermath = true }, Config), 0.35)
eq('unarmed persona never aggressive', Shops.aggressiveChance({ aggressive = 0.9, aggressiveMax = 0.9 }, { hour = 23, robbers = 3 }, Config), 0)
eq('roll below chance is aggressive', Shops.rollReaction(p, { hour = 12, robbers = 1 }, function() return 0.05 end, Config), 'aggressive')
eq('roll above chance is submissive', Shops.rollReaction(p, { hour = 12, robbers = 1 }, function() return 0.50 end, Config), 'submissive')
check('night wraps midnight', Shops.isNight(2, Config) and Shops.isNight(23, Config) and not Shops.isNight(12, Config))

-- A client's robber count is advisory and is clamped before it reaches the roll.
eq('robbers default to one', Shops.clampRobbers(nil), 1)
eq('robbers below one clamp up', Shops.clampRobbers(0), 1)
eq('robbers in range pass through', Shops.clampRobbers(3), 3)
eq('robbers above four clamp down', Shops.clampRobbers(99), 4)
eq('robber strings are numbers', Shops.clampRobbers('2'), 2)
eq('robber junk defaults to one', Shops.clampRobbers('lots'), 1)
eq('robber fractions floor', Shops.clampRobbers(2.9), 2)

-- An aftermath window that has run out reads as idle everywhere.
eq('a live aftermath stays aftermath', Shops.stateOf('aftermath', 2000, 1000), 'aftermath')
eq('an expired aftermath reads idle', Shops.stateOf('aftermath', 900, 1000), 'idle')
eq('an aftermath with no deadline reads idle', Shops.stateOf('aftermath', nil, 1000), 'idle')
eq('dead is never collapsed by time', Shops.stateOf('dead', 900, 1000), 'dead')
eq('reacting passes through', Shops.stateOf('reacting', nil, 1000), 'reacting')
eq('no state reads idle', Shops.stateOf(nil, nil, 1000), 'idle')

-- The melee set decides the gun flag on both sides (the server has no
-- GetWeapontypeGroup native). tests/run.lua stubs joaat as the identity.
check('a bat is melee', Shops.isMeleeHash('WEAPON_BAT'))
check('a wrench is melee', Shops.isMeleeHash('WEAPON_WRENCH'))
check('unarmed is in the melee set', Shops.isMeleeHash('WEAPON_UNARMED'))
check('a pistol is not melee', not Shops.isMeleeHash('WEAPON_PISTOL'))
check('an unknown weapon is not melee', not Shops.isMeleeHash('WEAPON_MADE_UP'))

-- The whole accept/refuse decision, table driven. No natives in any of it.
local cases = {
    { 'idle aim from an armed player is accepted',
      { reason = 'aim', armed = true, state = 'idle', now = 1000 }, true, false, 'ok' },
    { 'unarmed aim is refused',
      { reason = 'aim', armed = false, state = 'idle', now = 1000 }, false, false, 'unarmed' },
    { 'an unknown reason is refused',
      { reason = 'poke', armed = true, state = 'idle', now = 1000 }, false, false, 'reason' },
    { 'a missing reason is refused',
      { armed = true, state = 'idle', now = 1000 }, false, false, 'reason' },
    { 'a reaction already running refuses',
      { reason = 'aim', armed = true, state = 'reacting', now = 1000 }, false, false, 'reacting' },
    { 'a dead counter refuses',
      { reason = 'aim', armed = true, state = 'dead', until_ = 2000, now = 1000 }, false, false, 'dead' },
    { 'a jumpy counter accepts with the bonus',
      { reason = 'aim', armed = true, state = 'aftermath', until_ = 2000, now = 1000 }, true, true, 'ok' },
    { 'an expired aftermath accepts without the bonus',
      { reason = 'aim', armed = true, state = 'aftermath', until_ = 900, now = 1000 }, true, false, 'ok' },
    { 'a robbery needs no weapon',
      { reason = 'robbery', armed = false, state = 'idle', now = 1000 }, true, false, 'ok' },
    { 'a first robbery is accepted',
      { reason = 'robbery', armed = false, state = 'idle', lastRobberyAt = nil, now = 1000 }, true, false, 'ok' },
    { 'a second robbery inside ten minutes is refused',
      { reason = 'robbery', armed = false, state = 'idle', lastRobberyAt = 1000, now = 1500 }, false, false, 'cooldown' },
    { 'a robbery on the cooldown edge is refused',
      { reason = 'robbery', armed = false, state = 'idle', lastRobberyAt = 1000, now = 1599 }, false, false, 'cooldown' },
    { 'a robbery after ten minutes is accepted',
      { reason = 'robbery', armed = false, state = 'idle', lastRobberyAt = 1000, now = 1600 }, true, false, 'ok' },
    { 'the robbery cooldown does not gate an aim',
      { reason = 'aim', armed = true, state = 'idle', lastRobberyAt = 1000, now = 1001 }, true, false, 'ok' },
    { 'a robbery on a dead counter still refuses',
      { reason = 'robbery', armed = false, state = 'dead', until_ = 2000, now = 1000 }, false, false, 'dead' },
    { 'no context at all refuses',
      nil, false, false, 'reason' },
}
for _, c in ipairs(cases) do
    local acc, aft, why = Shops.threatDecision(c[2])
    check(c[1], acc == c[3] and aft == c[4] and why == c[5],
        ('got %s/%s/%s want %s/%s/%s'):format(tostring(acc), tostring(aft), tostring(why),
            tostring(c[3]), tostring(c[4]), tostring(c[5])))
end

-- Per-source rate limit on the threat callback.
eq('a first call is never throttled', Shops.throttled(nil, 1000, 5), false)
eq('a call inside the window is throttled', Shops.throttled(998, 1000, 5), true)
eq('a call on the window edge passes', Shops.throttled(995, 1000, 5), false)
eq('a call past the window passes', Shops.throttled(900, 1000, 5), false)
