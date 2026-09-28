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

-- Which counter states accept a threat, and which of them carry the bonus.
local acc, aft = Shops.threatAccepted({ state = 'idle' }, 1000)
check('idle accepts a threat', acc == true and aft == false)
acc, aft = Shops.threatAccepted({ state = 'reacting' }, 1000)
check('a reaction already running refuses', acc == false and aft == false)
acc, aft = Shops.threatAccepted({ state = 'dead', until_ = 2000 }, 1000)
check('a dead counter refuses', acc == false and aft == false)
acc, aft = Shops.threatAccepted({ state = 'aftermath', until_ = 2000 }, 1000)
check('a jumpy counter accepts with the bonus', acc == true and aft == true)
acc, aft = Shops.threatAccepted({ state = 'aftermath', until_ = 900 }, 1000)
check('an expired aftermath accepts without the bonus', acc == true and aft == false)
acc, aft = Shops.threatAccepted(nil, 1000)
check('no record refuses', acc == false and aft == false)

-- Per-source rate limit on the threat callback.
eq('a first call is never throttled', Shops.throttled(nil, 1000, 5), false)
eq('a call inside the window is throttled', Shops.throttled(998, 1000, 5), true)
eq('a call on the window edge passes', Shops.throttled(995, 1000, 5), false)
eq('a call past the window passes', Shops.throttled(900, 1000, 5), false)
