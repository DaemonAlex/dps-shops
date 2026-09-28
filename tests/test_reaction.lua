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
