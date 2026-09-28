local claims = Shops.Claims.new()
local counters = {}   -- id -> { netId, state, until, salt, reaction }

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
    if not claims:claim(id, src) then return false end
    local persona = Shops.persona(counter, Config)
    return true, Shops.pedFor(persona, id, rec.salt), rec.salt
end)

lib.callback.register('dps-shops:server:registered', function(src, id, netId)
    if claims:ownerOf(id) ~= src then return false end
    local rec = counterRecord(id)
    rec.netId = netId
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 then Entity(ent).state:set('dpsShop', id, true) end
    return true
end)

lib.callback.register('dps-shops:server:release', function(src, id)
    if not claims:release(id, src) then return false end
    local rec = counterRecord(id)
    rec.netId = nil
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, id in ipairs(claims:bySource(src)) do
        claims:release(id, src)
        counterRecord(id).netId = nil
    end
end)

AddEventHandler('entityRemoved', function(entity)
    if not DoesEntityExist(entity) then return end
    local state = Entity(entity).state
    local id = state and state.dpsShop
    if not id then return end
    local rec = counters[id]
    if rec and rec.netId and NetworkGetEntityFromNetworkId(rec.netId) == entity then
        rec.netId = nil
        local owner = claims:ownerOf(id)
        if owner then claims:release(id, owner) end
    end
end)

function MarkDead(id)
    local rec = counterRecord(id)
    rec.state = 'dead'
    rec.until_ = os.time() + Config.RespawnSeconds
    rec.netId = nil
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
