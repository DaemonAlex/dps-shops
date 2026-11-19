-- AI clerks, server side: registers each placed clerk as a talking NPC with dps-ainpcs, answers its live-facts
-- export, and keeps the shops' memory of trouble (who robbed or threatened a clerk). Costs nothing until someone
-- talks to a clerk: no loops, and the facts come from tables already in memory.
if not (Config.AIClerks and Config.AIClerks.Enabled) then return end

local RES = GetCurrentResourceName()
local AINPC = 'dps-ainpcs'
local MEMORY_DAYS = 60            -- how long a shop remembers trouble
local incidents = {}              -- citizenid -> { { counter, kind, at }, ... } newest first
local lastBought = {}             -- src -> os.time() of their last purchase at an owned shop counter

-- ---------- memory of trouble ----------
local function cidOf(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData.citizenid, p and p.PlayerData
end

function RecordShopIncident(counter, src, reason)
    local cid, pd = cidOf(src)
    if not cid then return end
    local name = pd.charinfo and ((pd.charinfo.firstname or '') .. ' ' .. (pd.charinfo.lastname or '')) or nil
    local list = incidents[cid] or {}
    table.insert(list, 1, { counter = counter.id, kind = reason, at = os.time() })
    incidents[cid] = list
    MySQL.insert('INSERT INTO dps_shop_incidents (counter_id, kind, citizenid, name) VALUES (?, ?, ?, ?)',
        { counter.id, reason, cid, name })
end

-- What a clerk half-remembers someone doing, by incident kind (the sentence reads "the one who ... this store").
local DID = {
    robbery = 'held up',
    fuel_theft = 'drove off without paying for fuel at',
    fuel_driveoff = 'ripped the hose off a pump at',
}

-- Trouble outside the door (dps-fuel: fuel theft, a ripped pump hose). The nearest counter's clerk remembers it.
exports('RecordIncidentNear', function(coords, src, reason, radius)
    if type(reason) ~= 'string' or not DID[reason] then return false end
    local best, bd
    for _, counter in ipairs(Config.Counters) do
        local d = #(counter.coords - vector3(coords.x, coords.y, coords.z))
        if d <= (radius or 60.0) and (not bd or d < bd) then best, bd = counter, d end
    end
    if not best then return false end
    RecordShopIncident(best, src, reason)
    return true
end)

function ShopCustomerBought(src) lastBought[src] = os.time() end
AddEventHandler('playerDropped', function() lastBought[source] = nil end)

-- What this clerk knows about this person: trouble here, and trouble at the same kind of shop elsewhere (word gets around).
local function history(counter, cid)
    local here, elsewhere = {}, 0
    local kind = Shops.personaKey(counter)
    for _, inc in ipairs(incidents[cid] or {}) do
        if inc.counter == counter.id then
            here[#here + 1] = inc
        else
            local other = Shops.counterById(Config, inc.counter)
            if other and Shops.personaKey(other) == kind then elsewhere = elsewhere + 1 end
        end
    end
    return here, elsewhere
end

local function ago(t)
    local d = os.time() - t
    if d < 3600 then return 'less than an hour ago' end
    if d < 86400 then return 'earlier today' end
    local days = math.floor(d / 86400)
    return days == 1 and 'yesterday' or (days .. ' days ago')
end

-- ---------- live facts for one reply ----------
local function playerFacts(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return {} end
    local f = {}
    local w = exports.ox_inventory:GetCurrentWeapon(src)
    if w then f.armed, f.weapon = true, (w.label or 'weapon'):lower() end
    f.masked = GetPedDrawableVariation(ped, 1) > 0
    return f
end

exports('ClerkContext', function(npcId, src)
    local counter = Shops.counterById(Config, ShopAI.counterIdOf(npcId))
    if not counter then return nil end
    local store = OwnedStoreNear and OwnedStoreNear(counter.coords, 30.0) or nil
    local facts = {
        state = ShopsCounterState and ShopsCounterState(counter.id) or 'idle',
        night = Shops.isNight(tonumber(os.date('%H')), Config),
        store = store,
        player = src and playerFacts(src) or {},
    }
    local text = ShopAI.contextText(counter, facts)
    local cid = src and cidOf(src)
    if cid then
        local here, elsewhere = history(counter, cid)
        if #here > 0 then
            -- Slow burn (Damon: "keep it chill at first"): one incident is only a hunch; it firms up with repeats.
            local last = here[1]
            if #here == 1 then
                text = text .. ('\nThis person looks familiar. You think they might be the one who %s this store %s, but you are not sure '
                    .. 'and you do not accuse anyone over a hunch. Play it cool: say something casual in your own words, in the spirit of "you look familiar" or "have you been in here before?" (never those exact words), then keep an eye on them. '
                    .. 'Only if they act shady or admit it do you get firm.'):format(
                    DID[last.kind] or 'pulled a weapon in', ago(last.at))
            else
                text = text .. ('\nYou are fairly sure this is the person who has caused trouble here before (%d times, last one %s). '
                    .. 'You stay calm but you do not want them in the store: short answers, and you suggest they shop somewhere else.'):format(
                    #here, ago(last.at))
            end
        elseif elsewhere > 0 then
            text = text .. '\nSomething about this person rings a bell, maybe from what other shop clerks have said. Nothing you would say out loud; you just keep an eye on them.'
        end
    end
    return text
end)

-- The client asks whether its player is someone this clerk should watch (cheap: memory and one export).
lib.callback.register('dps-shops:ai:known', function(src, counterId)
    local counter = Shops.counterById(Config, counterId)
    local cid = counter and cidOf(src)
    if not cid then return false, false end
    local here, elsewhere = history(counter, cid)
    local bought = lastBought[src] and (os.time() - lastBought[src]) < 600 or false
    return (#here > 0 or elsewhere > 0), bought
end)

-- The clerk turns to watch someone: only the client that runs the clerk can move it, so pass it on.
RegisterNetEvent('dps-shops:ai:watch', function(counterId, reason)
    local src = source
    local counter = Shops.counterById(Config, counterId)
    if not counter or type(reason) ~= 'string' then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - counter.coords) > Config.AIClerks.Watch.radius + 5.0 then return end
    local owner = ShopsClerkOwner and ShopsClerkOwner(counterId)
    if owner then TriggerClientEvent('dps-shops:ai:watchPlayer', owner, counterId, src, reason) end
end)

-- ---------- registering the clerks with dps-ainpcs ----------
local function register()
    if GetResourceState(AINPC) ~= 'started' then return end
    local n = 0
    for _, c in ipairs(Config.Counters) do
        if Shops.isPlaced(c) then
            local d = ShopAI.definition(c)
            local h = d.homeLocation
            d.homeLocation = vector4(h.x, h.y, h.z, h.w)
            d.contextExport = { resource = RES, name = 'ClerkContext' }
            exports[AINPC]:UnregisterExternalNPC(d.id)
            if exports[AINPC]:RegisterExternalNPC(d) then n = n + 1 end
        end
    end
    print(('[dps-shops] AI clerks: %d registered with %s'):format(n, AINPC))
end

AddEventHandler('onResourceStart', function(res)
    if res == AINPC or res == RES then SetTimeout(2000, register) end
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS dps_shop_incidents (
        id INT AUTO_INCREMENT PRIMARY KEY, counter_id VARCHAR(40) NOT NULL, kind VARCHAR(16) NOT NULL,
        citizenid VARCHAR(64) NOT NULL, name VARCHAR(80) NULL,
        at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY (citizenid), KEY (at))]])
    local rows = MySQL.query.await(('SELECT counter_id, kind, citizenid, UNIX_TIMESTAMP(at) AS t FROM dps_shop_incidents '
        .. 'WHERE at > NOW() - INTERVAL %d DAY ORDER BY at DESC'):format(MEMORY_DAYS)) or {}
    for _, r in ipairs(rows) do
        local list = incidents[r.citizenid] or {}
        list[#list + 1] = { counter = r.counter_id, kind = r.kind, at = tonumber(r.t) }
        incidents[r.citizenid] = list
    end
    print(('[dps-shops] shops remember %d incidents from the last %d days'):format(#rows, MEMORY_DAYS))
end)
