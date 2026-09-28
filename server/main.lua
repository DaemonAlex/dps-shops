local claims = Shops.Claims.new()

-- Ownership lives in `claims`, not here: this record only tracks a
-- claimed counter's clerk state (netId/state/timers) once claimed.
local counters = {}   -- id -> { netId, state, until_, salt, reaction, claimedAt }

-- src -> os.time() of the last ACCEPTED threat call, the per-source rate limit.
local threatLast = {}
-- src -> GetGameTimer() of the last REFUSED threat call, so a client that keeps
-- asking costs nothing: the refusal is answered before any native runs.
local rejectLast = {}

local function counterRecord(id)
    counters[id] = counters[id] or { state = 'idle', salt = 0 }
    return counters[id]
end

-- Every read of a counter's state goes through here, so an aftermath window that
-- has run out is retired the moment anything looks at it.
local function stateOf(rec)
    if not rec then return 'idle' end
    local s = Shops.stateOf(rec.state, rec.until_, os.time())
    if s ~= rec.state then
        rec.state = s
        rec.until_ = nil
    end
    return s
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
    local state = stateOf(rec)
    if state == 'dead' and rec.until_ and os.time() < rec.until_ then return false end
    if state == 'dead' then rec.state = 'idle'; rec.until_ = nil; rec.salt = rec.salt + 1 end
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
    -- A counter that was robbed stays jumpy across respawns: hand the fresh
    -- clerk the aftermath flag. stateOf retires a window that has run out.
    if stateOf(rec) == 'aftermath' then
        Entity(ent).state:set('aftermath', true, true)
    end
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
    threatLast[src] = nil
    rejectLast[src] = nil
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

-- ---------------------------------------------------------------------------
-- Threats, reactions, the silent alarm, the aftermath window and clerk death.
-- The reaction is rolled here, once per counter per incident, and replicated
-- through the ped's statebag so every client sees the same one.
-- ---------------------------------------------------------------------------

local ReactionSeconds = 120   -- how long a clerk stays out of position
local ThreatRateSeconds = 5   -- at most one accepted threat call per source
local RejectRateMs = 1000     -- and a refused caller waits a second before the next

local function entityOf(rec)
    if not rec or not rec.netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(rec.netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    return ent
end

-- Fires for BOTH reaction kinds: a clerk who decides to fight still slaps the
-- silent alarm on the way. wasabi_mdt is the only dispatch on this server.
local function alarm(counter)
    if GetResourceState('wasabi_mdt') ~= 'started' then return end
    local ok, err = pcall(function()
        exports.wasabi_mdt:CreateDispatch({
            type = 'robbery',
            code = '10-31',
            title = 'Silent alarm: ' .. counter.label,
            description = 'The clerk hit the alarm. Robbery in progress.',
            location = counter.label,
            coords = { x = counter.coords.x + 0.0, y = counter.coords.y + 0.0, z = counter.coords.z + 0.0 },
            priority = 1,
            departments = Shops.alarmDepartments(Shops.regionOf(counter), Config),
            metadata = { caller_name = counter.label, weapons_involved = true, injuries_reported = false, suspects = 1 },
        })
    end)
    if not ok then
        lib.print.error(('dps-shops: alarm for %s failed: %s'):format(counter.id, tostring(err)))
    end
end

-- End of the reaction window: the clerk goes back to work, the counter keeps
-- the aftermath flag so the next threat rolls with the bonus and nobody is
-- greeted while it lasts. `incident` pins this timer to the incident that
-- started it, so a timer left over from an earlier one cannot end a later one.
local function endReaction(id, incident)
    local rec = counters[id]
    if not rec or rec.incident ~= incident then return end
    if rec.state ~= 'reacting' then return end
    rec.state = 'aftermath'
    rec.until_ = os.time() + Config.Aftermath.seconds
    rec.reaction = nil
    local ent = entityOf(rec)
    if not ent then return end
    Entity(ent).state:set('reaction', nil, true)
    Entity(ent).state:set('aftermath', true, true)
end

-- The one accept path, shared by the aim callback and the RobberyThreat export:
-- state gate, entity check, the roll, the statebag and the two timers. Returns
-- the reaction kind, or nil when the counter refuses. Callers have already
-- proved the source is near this counter.
local function tryThreat(counter, src, reason, robbers, gun, armed)
    local id = counter.id
    local rec = counterRecord(id)
    stateOf(rec)
    local now = os.time()
    local accepted, aftermath = Shops.threatDecision({
        reason = reason,
        armed = armed,
        state = rec.state,
        until_ = rec.until_,
        lastRobberyAt = rec.lastRobberyAt,
        now = now,
    })
    if not accepted then return nil end
    local ent = entityOf(rec)
    if not ent then return nil end

    if reason == 'robbery' then rec.lastRobberyAt = now end

    local persona = Shops.persona(counter, Config)
    local kind = Shops.rollReaction(persona, {
        hour = tonumber(os.date('%H')),
        robbers = Shops.clampRobbers(robbers),
        aftermath = aftermath,
        gun = gun,
    }, nil, Config)

    -- One token per incident: every timer this call starts, here and on the
    -- clients, checks it before touching anything.
    rec.incident = (rec.incident or 0) + 1
    local n = rec.incident
    rec.state = 'reacting'
    rec.reaction = kind
    rec.until_ = nil
    Entity(ent).state:set('aftermath', nil, true)
    Entity(ent).state:set('reaction', { kind = kind, at = now, by = src, incident = n }, true)

    SetTimeout(persona.alarmDelay or 4000, function()
        if not counters[id] or counters[id].incident ~= n then return end
        alarm(counter)
    end)
    SetTimeout(ReactionSeconds * 1000, function() endReaction(id, n) end)
    return kind
end

-- `reason` is 'aim' (a weapon held on the clerk) or 'robbery' (the store-robbery
-- script pulling the register). The client never says what it is holding: for an
-- 'aim' the weapon is read from the server's own view of the player's ped.
lib.callback.register('dps-shops:server:threat', function(src, id, reason, robbers)
    -- Cheap argument checks first, then the reject limiter, so a caller that was
    -- just refused costs nothing: no native runs past this point for them.
    if reason ~= 'aim' and reason ~= 'robbery' then return nil end
    local counter = Shops.counterById(Config, id)
    if not counter then return nil end
    local tick = GetGameTimer()
    if Shops.throttled(rejectLast[src], tick, RejectRateMs) then return nil end
    local now = os.time()
    if Shops.throttled(threatLast[src], now, ThreatRateSeconds) then
        rejectLast[src] = tick
        return nil
    end
    if not nearCounter(src, counter, Config.ThreatDistance + 2.0) then
        rejectLast[src] = tick
        return nil
    end

    -- A robber pulling a register holds a lockpick, not a gun, so only the aim
    -- path checks the weapon; an unarmed aim is refused by Shops.threatDecision.
    local gun = true
    local armed = true
    if reason == 'aim' then
        local w = GetSelectedPedWeapon(GetPlayerPed(src))
        armed = (w ~= nil) and w ~= joaat('WEAPON_UNARMED')
        gun = armed and not Shops.isMeleeHash(w)
    end

    local kind = tryThreat(counter, src, reason, robbers, gun, armed)
    if not kind then
        rejectLast[src] = tick
        return nil
    end
    threatLast[src] = now
    return kind
end)

-- Server export for the m-StoreRobbery hook. The decision stays on this side of
-- the resource boundary: the vendor's server handler asks, and only creates its
-- own dispatch when the answer is false. Nothing awaits across resources.
exports('RobberyThreat', function(src)
    src = tonumber(src)
    if not src then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    local maxDist = Config.ThreatDistance + 2.0
    local best, bestDist
    for _, counter in ipairs(Config.Counters) do
        if not (counter.coords.x == 0.0 and counter.coords.y == 0.0 and counter.coords.z == 0.0) then
            local d = #(pos - counter.coords)
            if d <= maxDist and (not bestDist or d < bestDist) then
                best, bestDist = counter, d
            end
        end
    end
    if not best then return false end
    return tryThreat(best, src, 'robbery', 1, true, true) ~= nil
end)

-- Only the owning client reports its own clerk's death, and the server checks
-- the body before it believes it: peds die at 100 on the 100-200 health scale.
-- A clerk is invincible outside a reaction or its immediate aftermath, so a
-- death report in any other state is a lie by definition. Aftermath counts
-- because a clerk can be shot in the gap before invincibility comes back.
lib.callback.register('dps-shops:server:clerkDead', function(src, id)
    if claims:ownerOf(id) ~= src then return false end
    local rec = counters[id]
    if not rec or not rec.netId then return false end
    local state = stateOf(rec)
    if state ~= 'reacting' and state ~= 'aftermath' then return false end
    local ent = NetworkGetEntityFromNetworkId(rec.netId)
    local gone = not ent or ent == 0 or not DoesEntityExist(ent)
    if not gone and GetEntityHealth(ent) > 100 then return false end
    MarkDead(id)
    return true
end)

exports('GetCounterState', function(id)
    return stateOf(counters[id])
end)

local personaCount = 0
for _ in pairs(Config.Personas) do personaCount = personaCount + 1 end
lib.print.info(('dps-shops: %d counters, %d personas'):format(#Config.Counters, personaCount))
