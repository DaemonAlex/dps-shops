local claims = Shops.Claims.new()

-- Ownership lives in `claims`, not here: this record only tracks a
-- claimed counter's clerk state (netId/state/timers) once claimed.
local counters = {}   -- id -> { netId, state, until_, salt, reaction, claimedAt }

local function counterRecord(id)
    counters[id] = counters[id] or { state = 'idle', salt = 0 }
    return counters[id]
end

local function nearCounter(src, counter, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    return #(pos - counter.coords) <= maxDist
end

lib.callback.register('dps-shops:server:claim', function(src, id)
    local counter = Shops.counterById(Config, id)
    if not counter then return false end
    if not nearCounter(src, counter, Config.SpawnDistance + 10.0) then return false end
    local rec = counterRecord(id)
    if rec.state == 'dead' and rec.until_ and os.time() < rec.until_ then return false end
    if rec.state == 'dead' then rec.state = 'idle'; rec.salt = rec.salt + 1 end
    local owner = claims:ownerOf(id)
    if owner and not rec.netId and rec.claimedAt and os.time() - rec.claimedAt > 15 then
        claims:release(id, owner)
        rec.claimedAt = nil
    end
    if not claims:claim(id, src) then return false end
    rec.claimedAt = os.time()
    local persona = Shops.persona(counter, Config)
    return true, Shops.pedFor(persona, id, rec.salt), rec.salt
end)

lib.callback.register('dps-shops:server:registered', function(src, id, netId)
    if claims:ownerOf(id) ~= src then return false end
    local rec = counterRecord(id)
    if rec.netId then return false end
    if type(netId) ~= 'number' then
        claims:release(id, src)
        rec.netId = nil
        rec.claimedAt = nil
        return false
    end
    local counter = Shops.counterById(Config, id)
    local ent = NetworkGetEntityFromNetworkId(netId)
    local valid = counter and ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 1
        and not IsPedAPlayer(ent) and #(GetEntityCoords(ent) - counter.coords) <= 5.0
    if not valid then
        claims:release(id, src)
        rec.netId = nil
        rec.claimedAt = nil
        return false
    end
    rec.netId = netId
    Entity(ent).state:set('dpsShop', id, true)
    return true
end)

lib.callback.register('dps-shops:server:release', function(src, id)
    if not claims:release(id, src) then return false end
    local rec = counterRecord(id)
    rec.netId = nil
    rec.claimedAt = nil
    return true
end)

-- Shared by the drop handler and the client's own "I am leaving" event: release
-- every claim this source holds without waiting on any callback to resolve
-- (a callback await during resource stop or a drop may never come back).
local function releaseAllFor(src)
    for _, id in ipairs(claims:bySource(src)) do
        claims:release(id, src)
        local rec = counterRecord(id)
        rec.netId = nil
        rec.claimedAt = nil
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    releaseAllFor(src)
end)

RegisterNetEvent('dps-shops:server:releaseAll', function()
    local src = source
    releaseAllFor(src)
end)

AddEventHandler('entityRemoved', function(entity)
    local ok, id = pcall(function() return Entity(entity).state.dpsShop end)
    if not ok then id = nil end
    if not id then
        for cid, rec in pairs(counters) do
            if rec.netId and NetworkGetEntityFromNetworkId(rec.netId) == entity then
                id = cid
                break
            end
        end
    end
    if not id then return end
    local rec = counters[id]
    if rec and rec.netId and NetworkGetEntityFromNetworkId(rec.netId) == entity then
        rec.netId = nil
        rec.claimedAt = nil
        local owner = claims:ownerOf(id)
        if owner then claims:release(id, owner) end
    end
end)

function MarkDead(id)
    local rec = counterRecord(id)
    rec.state = 'dead'
    rec.until_ = os.time() + Config.RespawnSeconds
    rec.netId = nil
    rec.claimedAt = nil
    local owner = claims:ownerOf(id)
    if owner then claims:release(id, owner) end
    TriggerClientEvent('dps-shops:client:counterState', -1, id, 'dead')
end

exports('GetCounterState', function(id)
    local rec = counters[id]
    return rec and rec.state or 'idle'
end)

local personaCount = 0
for _ in pairs(Config.Personas) do personaCount = personaCount + 1 end
lib.print.info(('dps-shops: %d counters, %d personas'):format(#Config.Counters, personaCount))
