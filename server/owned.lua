-- Owned shops, server side: saved state, the ox_inventory counter shops, and every owner/staff action.
-- All money and stock rules live in shared/owned.lua; this file only checks who is asking and where they stand.
if not (Config.Owned and Config.Owned.Enabled) then return end

local O = Config.Owned
local SHOP_PREFIX = 'dps_owned_'
local OFFICE_REACH = 4.0      -- metres from the office spot an action may come from
local stores = {}             -- id -> state (see shared/owned.lua)
local spots = {}              -- id -> { office = vector3, counters = { vector3 } } placed in game by an admin
local extra = {}              -- id -> { type, buyPrice, sellPrice }: stores an admin added in game
local list = {}               -- every store definition (config + extra), rebuilt by refreshList()

local function refreshList() list = Owned.allStores(extra) end

-- A store definition with its placed spots folded in (office/counters are nil until placed).
local function storeOf(id)
    for _, s in ipairs(list) do
        if s.id == id then
            local sp = spots[id] or {}
            return setmetatable({ office = sp.office, counters = sp.counters, garage = sp.garage }, { __index = s })
        end
    end
    return nil
end
local dirty = {}              -- id -> true when the state needs saving

local function log(...) if Config.Debug then print('[dps-shops:owned]', ...) end end

-- ---------- saving ----------
local function encode(state)
    return json.encode({ upgrades = state.upgrades, categories = state.categories, stock = state.stock, staff = state.staff, jobs = state.jobs })
end

local function save(id)
    local st = stores[id]
    MySQL.prepare.await('INSERT INTO dps_shop_stores (id, owner, name, balance, data) VALUES (?, ?, ?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE owner = VALUES(owner), name = VALUES(name), balance = VALUES(balance), data = VALUES(data)',
        { id, st.owner, st.name, st.balance, encode(st) })
    dirty[id] = nil
end

local function ledger(id, kind, amount, who, note)
    MySQL.insert('INSERT INTO dps_shop_ledger (store_id, kind, amount, citizenid, note) VALUES (?, ?, ?, ?, ?)',
        { id, kind, amount or 0, who, note })
end

-- Sales come in fast; the till is written at most every 30 seconds and on stop.
CreateThread(function()
    while true do
        Wait(30000)
        for id in pairs(dirty) do save(id) end
    end
end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(dirty) do save(id) end
end)

-- ---------- the counter shops customers see ----------
local function label(store, st)
    local t = Owned.typeOf(store)
    return st.name or (t and t.blip.label) or 'Store'
end

local function registerShop(store)
    local st = stores[store.id]
    if not Owned.isPlaced(store) then return end   -- not on the map yet: no counter to buy at
    local t = Owned.typeOf(store)
    local groups
    if t and #t.requiredJob > 0 then
        groups = {}
        for _, j in ipairs(t.requiredJob) do groups[j] = 0 end
    end
    exports.ox_inventory:RegisterShop(SHOP_PREFIX .. store.id, {
        name = label(store, st),
        inventory = Owned.customerInventory(store, st),
        locations = store.counters,
        groups = groups,
    })
end

-- ---------- players ----------
local function player(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData
end

local function fullName(pd)
    local c = pd and pd.charinfo
    return c and ((c.firstname or '') .. ' ' .. (c.lastname or '')) or 'Unknown'
end

local function ownedCount(cid)
    local n = 0
    for _, st in pairs(stores) do if st.owner == cid then n = n + 1 end end
    return n
end

local function employedCount(cid)
    local n = 0
    for _, st in pairs(stores) do if st.staff[cid] then n = n + 1 end end
    return n
end

local function nearOffice(src, store)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not store.office then return false end
    return #(GetEntityCoords(ped) - store.office) <= OFFICE_REACH
end

-- One gate for every action: the store exists, the player stands at its office, and their role allows it.
local function gate(src, id, action)
    local store = storeOf(id)
    if not store or not Owned.isPlaced(store) then return nil, 'No such store.' end
    if not nearOffice(src, store) then return nil, 'You need to be at the store office.' end
    local pd = player(src)
    if not pd then return nil, 'No character.' end
    local st = stores[id]
    local role = Owned.roleOf(st, pd.citizenid)
    if action and not Owned.allowed(role, action) then return nil, 'Your role cannot do that.' end
    return store, st, pd, role
end

-- ---------- sales: ox_inventory asks before every purchase ----------
exports.ox_inventory:registerHook('buyItem', function(p)
    local id = type(p.shopType) == 'string' and p.shopType:match('^' .. SHOP_PREFIX .. '(.+)$')
    if not id then return true end
    if ShopCustomerBought then ShopCustomerBought(p.source) end   -- a paying customer is not a loiterer (server/ai.lua)
    local st = stores[id]
    if not st or not st.owner then return true end      -- unowned: the city's stock, the money leaves the game
    local s = st.stock[p.itemName]
    if not s or s.amount < p.count then return false end
    s.amount = s.amount - p.count
    if s.amount <= 0 then st.stock[p.itemName] = nil end
    st.balance = st.balance + (p.totalPrice or 0)
    dirty[id] = true
    ledger(id, 'sale', p.totalPrice, nil, ('%dx %s'):format(p.count, p.itemName))
    if not st.stock[p.itemName] then registerShop(storeOf(id)) end   -- sold out: off the shelf
    return true
end, { print = false })

-- ---------- what the office shows ----------
local function view(store, st, pd, role)
    local t = Owned.typeOf(store)
    local v = {
        id = store.id, name = label(store, st), owned = st.owner ~= nil, role = role, roleName = O.RoleNames[role],
        buyPrice = store.buyPrice, sellPrice = store.sellPrice,
        capacity = Owned.capacity(store, st), stocked = Owned.stockTotal(st),
        upgrades = {}, products = {}, staff = {}, lines = {},
        maxStaff = t.maxStaff, slotsLeft = Owned.categorySlotsLeft(store, st),
    }
    if Owned.allowed(role, 'showBalance') then v.balance = st.balance end
    v.instant = O.InstantRestock
    v.hasGarage = store.garage ~= nil
    v.jobs = {}
    for _, j in ipairs(st.jobs or {}) do
        local def = Owned.itemDef(j.item, st.categories)
        v.jobs[#v.jobs + 1] = { id = j.id, label = def and def.label or j.item, amount = j.amount, reward = j.reward, taken = j.takenBy ~= nil }
    end
    for cat in pairs(st.categories) do
        local c = O.Categories[cat]
        for item, def in pairs(c.items) do
            local s = st.stock[item]
            v.products[#v.products + 1] = { item = item, label = def.label, line = c.label,
                amount = s and s.amount or 0, price = s and s.price or def.price,
                min = def.min, max = def.max, cost = def.cost, batch = def.batch,
                run = Owned.runCapacity(store, st, def), runCost = Owned.importCost(store, st, def, Owned.runCapacity(store, st, def)),
                export = def.export }
        end
    end
    table.sort(v.products, function(a, b) return a.label < b.label end)
    for key, up in pairs(t.upgrades) do
        local price, next = Owned.upgradePrice(store, key, st)
        v.upgrades[#v.upgrades + 1] = { key = key, level = st.upgrades[key] or 0, price = price, next = next }
    end
    table.sort(v.upgrades, function(a, b) return a.key < b.key end)
    for cid, s in pairs(st.staff) do
        v.staff[#v.staff + 1] = { cid = cid, name = s.name, role = s.role, roleName = O.RoleNames[s.role], commission = s.commission }
    end
    for _, cat in ipairs(t.categories) do
        local c = O.Categories[cat]
        v.lines[#v.lines + 1] = { key = cat, label = c.label, carried = st.categories[cat] == true,
            buyPrice = c.buyPrice, sellPrice = c.sellPrice }
    end
    return v
end

lib.callback.register('dps-shops:owned:spots', function()
    local out = {}
    for _, def in ipairs(list) do
        local store = storeOf(def.id)
        if Owned.isPlaced(store) then
            out[#out + 1] = { id = def.id, office = store.office, counters = store.counters, name = label(store, stores[def.id]) }
        end
    end
    return out
end)

lib.callback.register('dps-shops:owned:view', function(src, id)
    local store, st, pd, role = gate(src, id)
    if not store then return nil, st end
    return view(store, st, pd, role)
end)

-- ---------- actions ----------
local actions = {}

function actions.buyStore(src, store, st, pd)
    if st.owner then return false, 'This store already has an owner.' end
    if ownedCount(pd.citizenid) >= O.MaxStoresPerPlayer then return false, 'You already own as many stores as you can.' end
    if not exports.qbx_core:RemoveMoney(src, O.StoreAccount, store.buyPrice, 'dps-shops buy ' .. store.id) then
        return false, 'Not enough money in the bank.'
    end
    stores[store.id] = Owned.blankState(store)
    stores[store.id].owner = pd.citizenid
    save(store.id); ledger(store.id, 'bought', store.buyPrice, pd.citizenid)
    registerShop(store)
    return true, 'The store is yours.'
end

function actions.sellStore(src, store, st, pd)
    local payout = store.sellPrice + st.balance
    exports.qbx_core:AddMoney(src, O.StoreAccount, payout, 'dps-shops sell ' .. store.id)
    ledger(store.id, 'sold', payout, pd.citizenid)
    stores[store.id] = Owned.blankState(store)
    save(store.id); registerShop(store)
    return true, ('Sold. $%d went to your bank.'):format(payout)
end

function actions.renameStore(src, store, st, pd, args)
    local name = Owned.cleanName(args.name)
    if not name then return false, 'Use 3 to 30 letters or numbers.' end
    st.name = name; save(store.id); registerShop(store)
    return true, 'Renamed.'
end

function actions.setPrice(src, store, st, pd, args)
    local def = Owned.itemDef(args.item, st.categories)
    if not def then return false, 'Not a product this store carries.' end
    local price = Owned.clampPrice(def, args.price)
    if not price then return false, 'Not a price.' end
    st.stock[args.item] = st.stock[args.item] or { amount = 0 }
    st.stock[args.item].price = price
    save(store.id); registerShop(store)
    return true, ('Price set to $%d.'):format(price)
end

local function addStock(store, st, item, def, amount)
    local s = st.stock[item] or { amount = 0, price = def.price }
    s.amount = s.amount + amount
    st.stock[item] = s
end

function actions.storeProductFromInventory(src, store, st, pd, args)
    local def = Owned.itemDef(args.item, st.categories)
    local amount = math.floor(tonumber(args.amount) or 0)
    if not def or amount < 1 then return false, 'Not a product this store carries.' end
    if Owned.stockTotal(st) + amount > Owned.capacity(store, st) then return false, 'Not enough shelf room.' end
    if not exports.ox_inventory:RemoveItem(src, args.item, amount) then return false, 'You do not have that many.' end
    addStock(store, st, args.item, def, amount)
    save(store.id); registerShop(store); ledger(store.id, 'shelved', amount, pd.citizenid, args.item)
    return true, ('%d on the shelf.'):format(amount)
end

-- Step 1 stand-in for delivery runs: the order lands at once, paid from the till.
function actions.startImportJob(src, store, st, pd, args)
    if not O.InstantRestock then return false, 'Orders come by delivery run.' end
    local def = Owned.itemDef(args.item, st.categories)
    local batches = math.floor(tonumber(args.batches) or 0)
    if not def or batches < 1 or batches > 10 then return false, 'Pick 1 to 10 boxes.' end
    local amount = def.batch * batches
    local cost = def.cost * amount
    if Owned.stockTotal(st) + amount > Owned.capacity(store, st) then return false, 'Not enough shelf room.' end
    if st.balance < cost then return false, ('The till needs $%d.'):format(cost) end
    st.balance = st.balance - cost
    addStock(store, st, args.item, def, amount)
    save(store.id); registerShop(store); ledger(store.id, 'order', -cost, pd.citizenid, ('%dx %s'):format(amount, args.item))
    return true, ('%d %s on the shelf for $%d.'):format(amount, def.label, cost)
end

function actions.depositMoney(src, store, st, pd, args)
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount < 1 then return false, 'Not an amount.' end
    if not exports.qbx_core:RemoveMoney(src, O.StoreAccount, amount, 'dps-shops deposit ' .. store.id) then return false, 'Not enough money.' end
    st.balance = st.balance + amount
    save(store.id); ledger(store.id, 'deposit', amount, pd.citizenid)
    return true, ('$%d into the till.'):format(amount)
end

function actions.withdrawMoney(src, store, st, pd, args)
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount < 1 or amount > st.balance then return false, 'The till does not have that much.' end
    st.balance = st.balance - amount
    exports.qbx_core:AddMoney(src, O.StoreAccount, amount, 'dps-shops withdraw ' .. store.id)
    save(store.id); ledger(store.id, 'withdraw', -amount, pd.citizenid)
    return true, ('$%d to your bank.'):format(amount)
end

function actions.hirePlayer(src, store, st, pd, args)
    local target = tonumber(args.serverId)
    local tpd = target and player(target)
    if not tpd then return false, 'Nobody with that ID.' end
    if tpd.citizenid == st.owner or st.staff[tpd.citizenid] then return false, 'Already works here.' end
    local n = 0
    for _ in pairs(st.staff) do n = n + 1 end
    if n >= Owned.typeOf(store).maxStaff then return false, 'No room for more staff.' end
    if employedCount(tpd.citizenid) >= O.MaxStoresEmployed then return false, 'They already work at enough stores.' end
    local ped = GetPlayerPed(target)
    if #(GetEntityCoords(ped) - store.office) > 10.0 then return false, 'They need to be here with you.' end
    st.staff[tpd.citizenid] = { role = 1, commission = 0, name = fullName(tpd) }
    save(store.id); ledger(store.id, 'hired', 0, pd.citizenid, tpd.citizenid)
    return true, fullName(tpd) .. ' hired as Clerk.'
end

function actions.firePlayer(src, store, st, pd, args)
    if not st.staff[args.cid] then return false, 'Not on the staff.' end
    st.staff[args.cid] = nil
    save(store.id); ledger(store.id, 'fired', 0, pd.citizenid, args.cid)
    return true, 'Let go.'
end

function actions.changeRole(src, store, st, pd, args, role)
    local s = st.staff[args.cid]
    local r = math.floor(tonumber(args.role) or 0)
    if not s or r < 1 or r > 3 or r > role then return false, 'Pick a role up to your own.' end
    s.role = r
    save(store.id)
    return true, 'Now ' .. O.RoleNames[r] .. '.'
end

function actions.giveCommission(src, store, st, pd, args)
    local s = st.staff[args.cid]
    local c = math.floor(tonumber(args.commission) or -1)
    if not s or c < 0 or c > 50 then return false, '0 to 50 percent.' end
    s.commission = c
    save(store.id)
    return true, ('Commission %d%%.'):format(c)
end

function actions.buyUpgrade(src, store, st, pd, args)
    local price, lvl = Owned.upgradePrice(store, args.key, st)
    if not price then return false, lvl end
    if st.balance < price then return false, ('The till needs $%d.'):format(price) end
    st.balance = st.balance - price
    st.upgrades[args.key] = lvl
    save(store.id); ledger(store.id, 'upgrade', -price, pd.citizenid, args.key .. ' ' .. lvl)
    return true, ('%s upgrade now level %d.'):format(args.key, lvl)
end

function actions.buyCategory(src, store, st, pd, args)
    local c = O.Categories[args.key]
    if not c or not Owned.typeAllowsCategory(store, args.key) then return false, 'Not a line this store can carry.' end
    if st.categories[args.key] then return false, 'Already carried.' end
    if Owned.categorySlotsLeft(store, st) < 1 then return false, 'No room for another product line.' end
    if st.balance < c.buyPrice then return false, ('The till needs $%d.'):format(c.buyPrice) end
    st.balance = st.balance - c.buyPrice
    st.categories[args.key] = true
    save(store.id); registerShop(store); ledger(store.id, 'line', -c.buyPrice, pd.citizenid, args.key)
    return true, c.label .. ' added.'
end

function actions.sellCategory(src, store, st, pd, args)
    local c = O.Categories[args.key]
    if not c or not st.categories[args.key] then return false, 'Not carried.' end
    for item in pairs(c.items) do
        if st.stock[item] and st.stock[item].amount > 0 then return false, 'Sell or move its stock first.' end
    end
    st.categories[args.key] = nil
    for item in pairs(c.items) do st.stock[item] = nil end
    st.balance = st.balance + c.sellPrice
    save(store.id); registerShop(store); ledger(store.id, 'line', c.sellPrice, pd.citizenid, args.key)
    return true, c.label .. ' dropped.'
end

-- buyStore is the one action a stranger may take; every other one goes through the role table.
lib.callback.register('dps-shops:owned:act', function(src, id, action, args)
    if type(action) ~= 'string' or not actions[action] then return false, 'Unknown action.' end
    local store, st, pd, role = gate(src, id, action ~= 'buyStore' and action or nil)
    if not store then return false, st end
    if action ~= 'buyStore' and not st.owner then return false, 'Nobody owns this store yet.' end
    return actions[action](src, store, st, pd, type(args) == 'table' and args or {}, role)
end)

-- ---------- start ----------
CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS dps_shop_stores (
        id VARCHAR(32) PRIMARY KEY, owner VARCHAR(64) NULL, name VARCHAR(40) NULL,
        balance BIGINT NOT NULL DEFAULT 0, data LONGTEXT NOT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS dps_shop_ledger (
        id INT AUTO_INCREMENT PRIMARY KEY, store_id VARCHAR(32) NOT NULL, kind VARCHAR(16) NOT NULL,
        amount BIGINT NOT NULL DEFAULT 0, citizenid VARCHAR(64) NULL, note VARCHAR(80) NULL,
        at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY (store_id, at))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS dps_shop_spots (
        id VARCHAR(32) PRIMARY KEY, type VARCHAR(32) NULL, buy_price INT NULL, sell_price INT NULL,
        office LONGTEXT NULL, counters LONGTEXT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]])
    MySQL.query.await('ALTER TABLE dps_shop_spots ADD COLUMN IF NOT EXISTS garage LONGTEXT NULL')
    for _, r in ipairs(MySQL.query.await('SELECT * FROM dps_shop_spots') or {}) do
        local o = r.office and json.decode(r.office)
        local g = r.garage and json.decode(r.garage)
        local cs = {}
        for _, c in ipairs(r.counters and json.decode(r.counters) or {}) do cs[#cs + 1] = vector3(c.x, c.y, c.z) end
        spots[r.id] = { office = o and vector3(o.x, o.y, o.z) or nil, counters = cs,
                        garage = g and vector4(g.x, g.y, g.z, g.w) or nil }
        if r.type then extra[r.id] = { type = r.type, buyPrice = r.buy_price, sellPrice = r.sell_price } end
    end
    refreshList()
    local rows = MySQL.query.await('SELECT id, owner, name, balance, data FROM dps_shop_stores') or {}
    local saved = {}
    for _, r in ipairs(rows) do saved[r.id] = r end
    for _, def in ipairs(list) do
        local store = storeOf(def.id)
        local st = Owned.blankState(store)
        local r = saved[store.id]
        if r and r.owner then
            local d = json.decode(r.data) or {}
            st.owner, st.name, st.balance = r.owner, r.name, tonumber(r.balance) or 0
            st.upgrades = d.upgrades or st.upgrades
            st.categories = d.categories or st.categories
            st.stock = d.stock or {}
            st.staff = d.staff or {}
            st.jobs = d.jobs or {}
        end
        stores[store.id] = st
        registerShop(store)
    end
    for _, w in ipairs(Owned.configWarnings(Config)) do print('[dps-shops] owned config: ' .. w) end
    local placed, owned = 0, 0
    for _, def in ipairs(list) do
        if Owned.isPlaced(storeOf(def.id)) then placed = placed + 1 end
        if stores[def.id].owner then owned = owned + 1 end
    end
    print(('[dps-shops] owned stores: %d defined, %d placed, %d owned'):format(#list, placed, owned))
    GlobalState['dps-shops:owned'] = os.time()   -- clients reload their zones when this changes
end)

-- ---------- placing stores in game (admins) ----------
local function saveSpot(id)
    local sp = spots[id] or {}
    local cs = {}
    for _, c in ipairs(sp.counters or {}) do cs[#cs + 1] = { x = c.x, y = c.y, z = c.z } end
    local e = extra[id]
    MySQL.prepare.await('INSERT INTO dps_shop_spots (id, type, buy_price, sell_price, office, counters, garage) VALUES (?, ?, ?, ?, ?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE type = VALUES(type), buy_price = VALUES(buy_price), sell_price = VALUES(sell_price), ' ..
        'office = VALUES(office), counters = VALUES(counters), garage = VALUES(garage)',
        { id, e and e.type, e and e.buyPrice, e and e.sellPrice,
          sp.office and json.encode({ x = sp.office.x, y = sp.office.y, z = sp.office.z }) or nil, json.encode(cs),
          sp.garage and json.encode({ x = sp.garage.x, y = sp.garage.y, z = sp.garage.z, w = sp.garage.w }) or nil })
end

local function placed(id)
    local store = storeOf(id)
    stores[id] = stores[id] or Owned.blankState(store)
    registerShop(store)
    GlobalState['dps-shops:owned'] = os.time()
end

local function here(src)
    local c = GetEntityCoords(GetPlayerPed(src))
    return vector3(math.floor(c.x * 100 + 0.5) / 100, math.floor(c.y * 100 + 0.5) / 100, math.floor(c.z * 100 + 0.5) / 100)
end

local function tell(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Shops', description = msg, type = kind or 'inform', duration = 8000 })
end

lib.addCommand('shopoffice', { help = 'Owned shops: set this store\'s office (where the owner manages it) to where you stand',
    params = { { name = 'id', type = 'string', help = 'store id, e.g. market_1 (see /shoplist)' } }, restricted = 'group.admin' },
function(src, a)
    if not storeOf(a.id) then return tell(src, 'No store ' .. a.id .. '. /shoplist shows them.', 'error') end
    spots[a.id] = spots[a.id] or { counters = {} }
    spots[a.id].office = here(src)
    saveSpot(a.id); placed(a.id)
    tell(src, a.id .. ': office set.' .. (Owned.isPlaced(storeOf(a.id)) and ' Store is open.' or ' Now add a counter with /shopcounter.'), 'success')
end)

lib.addCommand('shopcounter', { help = 'Owned shops: add a counter (where customers buy) where you stand',
    params = { { name = 'id', type = 'string', help = 'store id' } }, restricted = 'group.admin' },
function(src, a)
    if not storeOf(a.id) then return tell(src, 'No store ' .. a.id .. '. /shoplist shows them.', 'error') end
    spots[a.id] = spots[a.id] or { counters = {} }
    table.insert(spots[a.id].counters, here(src))
    saveSpot(a.id); placed(a.id)
    tell(src, ('%s: counter %d added.'):format(a.id, #spots[a.id].counters) .. (Owned.isPlaced(storeOf(a.id)) and ' Store is open.' or ' Now set the office with /shopoffice.'), 'success')
end)

lib.addCommand('shopgarage', { help = 'Owned shops: set where this store\'s delivery truck parks (stand there, facing the way out)',
    params = { { name = 'id', type = 'string', help = 'store id' } }, restricted = 'group.admin' },
function(src, a)
    if not storeOf(a.id) then return tell(src, 'No store ' .. a.id .. '. /shoplist shows them.', 'error') end
    local ped = GetPlayerPed(src)
    local c = here(src)
    spots[a.id] = spots[a.id] or { counters = {} }
    spots[a.id].garage = vector4(c.x, c.y, c.z, math.floor(GetEntityHeading(ped) * 10 + 0.5) / 10)
    saveSpot(a.id)
    tell(src, a.id .. ': truck spot set. Delivery runs start and end here.', 'success')
end)

lib.addCommand('shopclear', { help = 'Owned shops: remove a store\'s office and counters (it closes; owner and stock stay)',
    params = { { name = 'id', type = 'string', help = 'store id' } }, restricted = 'group.admin' },
function(src, a)
    if not storeOf(a.id) then return tell(src, 'No store ' .. a.id, 'error') end
    spots[a.id] = { counters = {} }
    saveSpot(a.id)
    exports.ox_inventory:RegisterShop(SHOP_PREFIX .. a.id, { name = 'closed', inventory = {}, locations = {} })
    GlobalState['dps-shops:owned'] = os.time()
    tell(src, a.id .. ' closed. Place it again with /shopoffice and /shopcounter.', 'success')
end)

lib.addCommand('shopnew', { help = 'Owned shops: add a new store (then place it with /shopoffice and /shopcounter)',
    params = { { name = 'type', type = 'string', help = '247store or ammunation' },
               { name = 'price', type = 'number', help = 'price to buy it' } }, restricted = 'group.admin' },
function(src, a)
    if not O.Types[a.type] then return tell(src, 'Type must be one of: 247store, ammunation', 'error') end
    local n = 1
    while storeOf('store_' .. n) do n = n + 1 end
    local id = 'store_' .. n
    extra[id] = { type = a.type, buyPrice = math.floor(a.price), sellPrice = math.floor(a.price / 2) }
    refreshList()
    spots[id] = { counters = {} }
    saveSpot(id)
    stores[id] = Owned.blankState(storeOf(id))
    tell(src, ('New store %s. Stand at the office spot and type /shopoffice %s'):format(id, id), 'success')
end)

lib.addCommand('shoplist', { help = 'Owned shops: list stores, placed or not, nearest first', restricted = 'group.admin' },
function(src)
    local me = GetEntityCoords(GetPlayerPed(src))
    local rows = {}
    for _, def in ipairs(list) do
        local store = storeOf(def.id)
        local ref = store.office or store.lcOffice
        rows[#rows + 1] = { id = def.id, d = ref and #(me - ref) or 99999, placed = Owned.isPlaced(store),
                            owner = stores[def.id] and stores[def.id].owner, type = def.type }
    end
    table.sort(rows, function(a, b) return a.d < b.d end)
    TriggerClientEvent('dps-shops:owned:list', src, rows)
end)

-- For the AI clerks (server/ai.lua): the placed store nearest these coords, as plain facts.
function OwnedStoreNear(coords, radius)
    local best, bestD
    for _, def in ipairs(list) do
        local store = storeOf(def.id)
        if Owned.isPlaced(store) then
            for _, c in ipairs(store.counters) do
                local d = #(coords - c)
                if d <= radius and (not bestD or d < bestD) then best, bestD = store, d end
            end
        end
    end
    if not best then return nil end
    local st = stores[best.id]
    local items = {}
    for _, it in ipairs(Owned.customerInventory(best, st)) do
        local def = Owned.itemDef(it.name, st.owner and st.categories or nil)
        items[#items + 1] = { label = def and def.label or it.name, price = it.price, amount = it.count }
    end
    return { id = best.id, name = label(best, st), owned = st.owner ~= nil, items = items }
end

-- For server/runs.lua (same resource). Not an export: other resources go through the callbacks.
OwnedInternal = {
    stores = stores, storeOf = storeOf, gate = gate, save = save, ledger = ledger,
    registerShop = registerShop, player = player, fullName = fullName, tell = tell,
}
