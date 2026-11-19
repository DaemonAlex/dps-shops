-- tests/test_owned.lua: owned-shop rules (shared/owned.lua) against the shipped config.
local O = Config.Owned

check('owned config has stores', #O.Stores >= 18, #O.Stores)
local warns = Owned.configWarnings(Config)
for _, w in ipairs(warns) do print('    warn: ' .. w) end

local s1 = Owned.storeById('market_1')
check('market_1 exists', s1 ~= nil)
eq('unknown store is nil', Owned.storeById('nope'), nil)

-- blank state carries the default product lines
local st = Owned.blankState(s1)
check('blank state has default lines', next(st.categories) ~= nil)
eq('blank state has no owner', st.owner, nil)

-- unowned stores sell defaults without a count
local inv = Owned.customerInventory(s1, st)
check('unowned store sells something', #inv > 0, #inv)
eq('unowned items have no count', inv[1].count, nil)

-- owned store sells only what is in stock, at the owner's price
st.owner = 'CID1'
local def, cat = Owned.itemDef('water_bottle', st.categories)
check('water is a product of the default lines', def ~= nil)
st.stock = { water_bottle = { amount = 5, price = def.max }, cola = { amount = 0, price = 3 } }
inv = Owned.customerInventory(s1, st)
local w
for _, i in ipairs(inv) do if i.name == 'water_bottle' then w = i end end
check('owned store lists water', w ~= nil)
eq('owned water count', w and w.count, 5)
eq('owned water price', w and w.price, def.max)
for _, i in ipairs(inv) do check('out-of-stock item hidden', i.name ~= 'cola' or i.count > 0) end

-- roles
eq('owner role', Owned.roleOf(st, 'CID1'), 4)
st.staff = { CID2 = { role = 1, commission = 10 } }
eq('staff role', Owned.roleOf(st, 'CID2'), 1)
eq('stranger role', Owned.roleOf(st, 'CID3'), 0)
check('clerk may put stock on the shelf', Owned.allowed(1, 'storeProductFromInventory'))
check('clerk may not withdraw', not Owned.allowed(1, 'withdrawMoney'))
check('only the owner sells the store', not Owned.allowed(3, 'sellStore') and Owned.allowed(4, 'sellStore'))
check('unknown action is owner-only', not Owned.allowed(3, 'whatever'))

-- prices
eq('price clamps up', Owned.clampPrice(def, -5), def.min)
eq('price clamps down', Owned.clampPrice(def, 99999), def.max)
eq('price rounds', Owned.clampPrice({ min = 1, max = 100 }, 7.6), 8)
eq('nonsense price', Owned.clampPrice(def, 'abc'), nil)

-- capacity grows with the stock upgrade
local base = Owned.capacity(s1, { upgrades = { stock = 0 } })
local up1 = Owned.capacity(s1, { upgrades = { stock = 1 } })
check('stock upgrade adds room', up1 > base, up1 .. ' vs ' .. base)
eq('stock total', Owned.stockTotal({ stock = { a = { amount = 3 }, b = { amount = 4 } } }), 7)

-- money split
local toStore, toStaff = Owned.saleSplit(100, 10)
eq('till share', toStore, 90); eq('clerk share', toStaff, 10)
toStore, toStaff = Owned.saleSplit(100, 90)
eq('commission capped at 50', toStaff, 50)

-- upgrades get dearer per level and stop at 5
local p1 = Owned.upgradePrice(s1, 'stock', { upgrades = { stock = 0 } })
local p2 = Owned.upgradePrice(s1, 'stock', { upgrades = { stock = 1 } })
check('second level costs more', p2 > p1)
local none = Owned.upgradePrice(s1, 'stock', { upgrades = { stock = 5 } })
eq('no level past 5', none, nil)

-- names
eq('good name', Owned.cleanName("  Bob's   Corner-Store "), "Bob's Corner-Store")
eq('too short', Owned.cleanName('ab'), nil)
eq('odd characters refused', Owned.cleanName('<b>shop</b>'), nil)

-- product lines
check('24/7 cannot carry rifles', not Owned.typeAllowsCategory(s1, 'rifle_weapons'))

-- placing
check('nothing placed yet', not Owned.isPlaced(nil))
check('office alone is not enough', not Owned.isPlaced({ office = vec3(1, 2, 3), counters = {} }))
check('office + counter opens', Owned.isPlaced({ office = vec3(1, 2, 3), counters = { vec3(1, 2, 3) } }))
local all = Owned.allStores({ store_x = { type = '247store', buyPrice = 1000, sellPrice = 500 }, market_1 = { type = 'x' } })
eq('admin-added store joins the list', #all, #O.Stores + 1)
eq('config store keeps its definition', Owned.storeById('market_1').type, '247store')
