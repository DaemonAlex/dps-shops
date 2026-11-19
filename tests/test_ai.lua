-- tests/test_ai.lua: AI clerk helpers (shared/ai.lua).
local c = Config.Counters[1]

eq('npc id', ShopAI.npcId('sandy_247'), 'shopclerk_sandy_247')
eq('counter id back', ShopAI.counterIdOf('shopclerk_sandy_247'), 'sandy_247')
eq('other ids ignored', ShopAI.counterIdOf('informant_yellowjack'), nil)

local n1, n2 = ShopAI.clerkName(c), ShopAI.clerkName(c)
eq('same counter, same name', n1, n2)
check('name comes from the pool', type(n1) == 'string' and #n1 > 0)

local d = ShopAI.definition(c)
eq('definition id', d.id, 'shopclerk_' .. c.id)
check('prompt names the shop', d.systemPrompt:find(c.label, 1, true) ~= nil)
check('has a voice key', type(d.voice) == 'string')
check('has voice samples', #d.voiceSamples > 0)

local t = ShopAI.contextText(c, { state = 'aftermath', night = true,
    store = { owned = true, name = "Raj's", items = { { label = 'Water', price = 4, amount = 10 } } },
    player = { masked = true, armed = true, weapon = 'pistol' } })
check('robbery is mentioned', t:find('robbed', 1, true) ~= nil)
check('stock is listed with price', t:find('Water $4 (10 left)', 1, true) ~= nil)
check('mask is mentioned', t:find('mask', 1, true) ~= nil)
check('gun is mentioned', t:find('pistol', 1, true) ~= nil)
local calm = ShopAI.contextText(c, { state = 'idle', store = { owned = false, items = {} } })
check('calm store is not jumpy', calm:find('robbed', 1, true) == nil)
check('unowned store mentions it is for sale', calm:find('for sale', 1, true) ~= nil)

eq('armed is watched first', ShopAI.watchReason({ armed = true, masked = true }), 'armed')
eq('masked is watched', ShopAI.watchReason({ masked = true }), 'masked')
eq('long browse is watched', ShopAI.watchReason({ secondsHere = 999 }), 'loitering')
eq('a buyer is not watched for browsing', ShopAI.watchReason({ secondsHere = 999, bought = true }), nil)
eq('a quick visit is fine', ShopAI.watchReason({ secondsHere = 10 }), nil)
