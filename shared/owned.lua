-- Owned shops: pure rules, no natives, so tests/run.lua can check them without a server.
-- A store's saved state looks like:
--   { owner = citizenid|nil, name = string, balance = number,
--     upgrades = { stock = 0..5, truck = 0..5, relationship = 0..5 },
--     categories = { food_market = true, ... },          -- product lines the store carries
--     stock = { water = { amount = 10, price = 4 }, ... },
--     staff = { [citizenid] = { role = 1..3, commission = 0..50, name = string } } }
Owned = {}

local OWNER_ROLE = 4

function Owned.cfg(cfg) return (cfg or Config).Owned end

function Owned.storeById(id, cfg)
    for _, s in ipairs(Owned.cfg(cfg).Stores) do
        if s.id == id then return s end
    end
    return nil
end

-- A store opens only once an admin has placed its office and at least one counter in game.
function Owned.isPlaced(spot)
    return spot ~= nil and spot.office ~= nil and spot.counters ~= nil and #spot.counters > 0
end

-- Store list = the config's stores plus any an admin added in game (extra = { [id] = { type, buyPrice, sellPrice } }).
function Owned.allStores(extra, cfg)
    local list, seen = {}, {}
    for _, s in ipairs(Owned.cfg(cfg).Stores) do list[#list + 1] = s; seen[s.id] = true end
    local ids = {}
    for id in pairs(extra or {}) do if not seen[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local e = extra[id]
        list[#list + 1] = { id = id, type = e.type, buyPrice = e.buyPrice, sellPrice = e.sellPrice }
    end
    return list
end

function Owned.typeOf(store, cfg)
    return store and Owned.cfg(cfg).Types[store.type] or nil
end

-- The product definition and the category it belongs to, searched only in the categories given
-- (a store may only stock what its product lines allow).
function Owned.itemDef(item, cats, cfg)
    local all = Owned.cfg(cfg).Categories
    for cat in pairs(cats or all) do
        local c = all[cat]
        if c and c.items[item] then return c.items[item], cat end
    end
    return nil
end

-- A fresh state for a store nobody owns: its type's default product lines, nothing else.
function Owned.blankState(store, cfg)
    local t = Owned.typeOf(store, cfg)
    local cats = {}
    for _, c in ipairs(t and t.defaultCategories or {}) do cats[c] = true end
    return { owner = nil, name = nil, balance = 0, upgrades = { stock = 0, truck = 0, relationship = 0 },
             categories = cats, stock = {}, staff = {} }
end

function Owned.roleOf(state, citizenid)
    if not state or not citizenid then return 0 end
    if state.owner == citizenid then return OWNER_ROLE end
    local s = state.staff and state.staff[citizenid]
    return s and s.role or 0
end

-- Is this role allowed this action? Unknown actions are owner-only.
function Owned.allowed(role, action, cfg)
    local need = Owned.cfg(cfg).Roles[action] or OWNER_ROLE
    return (role or 0) >= need
end

function Owned.capacity(store, state, cfg)
    local t = Owned.typeOf(store, cfg)
    if not t then return 0 end
    local lvl = (state and state.upgrades and state.upgrades.stock) or 0
    local up = t.upgrades.stock
    return t.capacity + ((up and up.levels[lvl + 1]) or 0)
end

function Owned.stockTotal(state)
    local n = 0
    for _, s in pairs(state and state.stock or {}) do n = n + (s.amount or 0) end
    return n
end

-- Whole dollars within the product's min/max; nil if not a number.
function Owned.clampPrice(def, price)
    price = tonumber(price)
    if not def or not price or price ~= price then return nil end
    price = math.floor(price + 0.5)
    if price < def.min then price = def.min end
    if price > def.max then price = def.max end
    return price
end

-- What a customer sees at the counter, in ox_inventory shop format, sorted by name.
-- Owned: only what is in stock, at the owner's price, with the count left.
-- Unowned: every product of the default lines at list price, without a count when the
-- config says unowned stores never run out.
function Owned.customerInventory(store, state, cfg)
    local o = Owned.cfg(cfg)
    local list = {}
    if state and state.owner then
        for item, s in pairs(state.stock or {}) do
            local def = Owned.itemDef(item, state.categories, cfg)
            if def and (s.amount or 0) > 0 then
                list[#list + 1] = { name = item, price = s.price or def.price, count = s.amount }
            end
        end
    elseif o.UnownedFullStock then
        local blank = Owned.blankState(store, cfg)
        for cat in pairs(blank.categories) do
            for item, def in pairs(o.Categories[cat].items) do
                list[#list + 1] = { name = item, price = def.price }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- The till's share and the clerk's share of a sale. Commission is a whole percent, 0..50.
function Owned.saleSplit(total, commission)
    commission = math.max(0, math.min(50, math.floor(tonumber(commission) or 0)))
    local staff = math.floor(total * commission / 100)
    return total - staff, staff
end

-- How many store product lines the type allows on top of what is carried now.
function Owned.categorySlotsLeft(store, state, cfg)
    local t = Owned.typeOf(store, cfg)
    local n = 0
    for _ in pairs(state.categories or {}) do n = n + 1 end
    return (t and t.maxCategories or 0) - n
end

function Owned.typeAllowsCategory(store, cat, cfg)
    local t = Owned.typeOf(store, cfg)
    for _, c in ipairs(t and t.categories or {}) do
        if c == cat then return true end
    end
    return false
end

function Owned.upgradePrice(store, key, state, cfg)
    local t = Owned.typeOf(store, cfg)
    local up = t and t.upgrades[key]
    if not up then return nil, 'no such upgrade' end
    local lvl = (state.upgrades and state.upgrades[key]) or 0
    if lvl >= 5 then return nil, 'already at the top level' end
    return up.price * (lvl + 1), lvl + 1
end

-- 3 to 30 letters, digits, spaces and & ' . - only.
function Owned.cleanName(name)
    if type(name) ~= 'string' then return nil end
    name = name:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if #name < 3 or #name > 30 or name:find("[^%w %&'%.%-]") then return nil end
    return name
end

function Owned.configWarnings(cfg)
    local o = Owned.cfg(cfg)
    local w = {}
    if not o then return w end
    local seen = {}
    for _, s in ipairs(o.Stores) do
        if seen[s.id] then w[#w + 1] = 'owned store id used twice: ' .. s.id end
        seen[s.id] = true
        if not o.Types[s.type] then w[#w + 1] = s.id .. ': unknown store type ' .. tostring(s.type) end
        if s.sellPrice > s.buyPrice then w[#w + 1] = s.id .. ': sells back for more than it costs' end
    end
    for name, t in pairs(o.Types) do
        for _, c in ipairs(t.categories) do
            if not o.Categories[c] then w[#w + 1] = name .. ': unknown product line ' .. c end
        end
    end
    for cname, c in pairs(o.Categories) do
        for item, d in pairs(c.items) do
            if d.min > d.price or d.price > d.max then w[#w + 1] = cname .. '/' .. item .. ': price outside min..max' end
            if d.cost > d.max then w[#w + 1] = cname .. '/' .. item .. ': costs the owner more than the highest shelf price' end
        end
    end
    return w
end
