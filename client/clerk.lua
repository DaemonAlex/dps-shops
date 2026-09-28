Clerk = {}
local owned = {}         -- id -> ped (this client spawned it)
local pedCache = {}      -- id -> last-seen ped for a clerk I do not own (validated before reuse)
local greeted = {}       -- id -> true once greeted this visit (spawn-point visit)
local chatterToken = {}  -- id -> current chatter generation; a stale closure compares and dies quietly

local function loadModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    lib.requestModel(hash, 5000)
    return hash
end

function Clerk.say(ped, list)
    if not ped or not DoesEntityExist(ped) or not list or #list == 0 then return end
    PlayPedAmbientSpeechNative(ped, list[math.random(#list)], 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
end

-- This client's view of a counter's clerk: mine if I spawned it, otherwise a
-- cached ped validated against the dpsShop statebag, otherwise a pool scan
-- (only reached when the cache is empty or stale).
function Clerk.pedOf(id)
    local ped = owned[id]
    if ped and DoesEntityExist(ped) then
        pedCache[id] = ped
        return ped
    end
    ped = pedCache[id]
    if ped and DoesEntityExist(ped) and Entity(ped).state.dpsShop == id then
        return ped
    end
    pedCache[id] = nil
    for _, p in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(p) and Entity(p).state.dpsShop == id then
            pedCache[id] = p
            return p
        end
    end
    return nil
end

local function spawnClerk(counter)
    local ok, model, salt = lib.callback.await('dps-shops:server:claim', false, counter.id)
    if not ok then return end
    local hash = loadModel(model)
    if not hash then
        lib.callback.await('dps-shops:server:release', false, counter.id)
        return
    end
    local ped = CreatePed(4, hash, counter.coords.x, counter.coords.y, counter.coords.z - 1.0, counter.heading, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then
        lib.callback.await('dps-shops:server:release', false, counter.id)
        return
    end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)

    -- A slightly wrong SPOT z should not leave the clerk floating or buried;
    -- only correct it when solid ground turns up close to the configured z.
    local found, groundZ = GetGroundZFor_3dCoord(counter.coords.x, counter.coords.y, counter.coords.z, false)
    if found and math.abs(groundZ - counter.coords.z) <= 1.5 then
        SetEntityCoordsNoOffset(ped, counter.coords.x, counter.coords.y, groundZ, false, false, false)
    end

    local persona = Shops.persona(counter, Config)
    TaskStartScenarioInPlace(ped, persona.scenario, 0, true)

    local netId = NetworkGetNetworkIdFromEntity(ped)
    SetNetworkIdCanMigrate(netId, false)
    local reg = lib.callback.await('dps-shops:server:registered', false, counter.id, netId)
    if not reg then
        DeleteEntity(ped)
        return
    end
    owned[counter.id] = ped
    pedCache[counter.id] = ped
end

local function despawnClerk(counter)
    local ped = owned[counter.id]
    owned[counter.id] = nil
    pedCache[counter.id] = nil
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    lib.callback.await('dps-shops:server:release', false, counter.id)
end

-- Greet once per spawn-point visit. Skipped quietly (without consuming the
-- once-per-visit flag) when the clerk is missing, dead, mid-reaction or in
-- aftermath, so a real greeting can still happen once things calm down and
-- the player crosses the greet boundary again.
local function attemptGreet(counter)
    if greeted[counter.id] then return end
    local ped = Clerk.pedOf(counter.id)
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    local st = Entity(ped).state
    if st.reaction or st.aftermath then return end
    greeted[counter.id] = true
    TaskLookAtEntity(ped, cache.ped, 3000, 2048, 3)
    Clerk.say(ped, Shops.persona(counter, Config).greet)
end

-- Chatter is a SetTimeout chain, never a loop. `token` pins this chain to one
-- greet-point visit: stopChatter bumps chatterToken[id], so the next time this
-- closure wakes up the comparison fails and it drops itself without rescheduling.
local chatterTick
chatterTick = function(counter, token)
    if chatterToken[counter.id] ~= token then return end
    local ped = Clerk.pedOf(counter.id)
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    local st = Entity(ped).state
    if st.reaction or st.aftermath then return end
    if math.random() < 0.3 then
        Clerk.say(ped, Shops.persona(counter, Config).chatter)
    end
    SetTimeout(Config.ChatterSeconds * 1000, function() chatterTick(counter, token) end)
end

local function startChatter(counter)
    local token = (chatterToken[counter.id] or 0) + 1
    chatterToken[counter.id] = token
    SetTimeout(Config.ChatterSeconds * 1000, function() chatterTick(counter, token) end)
end

local function stopChatter(id)
    chatterToken[id] = (chatterToken[id] or 0) + 1
end

for _, counter in ipairs(Config.Counters) do
    if not (counter.coords.x == 0.0 and counter.coords.y == 0.0 and counter.coords.z == 0.0) then
        -- SPOT placeholders (Roxwood bait shop, as of this task) stay dark: no points at all.
        local spawnPoint = lib.points.new({ coords = counter.coords, distance = Config.SpawnDistance })
        function spawnPoint:onEnter()
            if not Clerk.pedOf(counter.id) then spawnClerk(counter) end
        end
        function spawnPoint:onExit()
            greeted[counter.id] = nil
            if owned[counter.id] then despawnClerk(counter) end
        end

        local greetPoint = lib.points.new({ coords = counter.coords, distance = Config.GreetDistance })
        function greetPoint:onEnter()
            attemptGreet(counter)
            startChatter(counter)
        end
        function greetPoint:onExit()
            stopChatter(counter.id)
        end
    end
end

RegisterNetEvent('dps-shops:client:counterState', function(id, state)
    if state == 'dead' then
        greeted[id] = nil
        owned[id] = nil
        pedCache[id] = nil
        stopChatter(id)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(owned) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    for _, ped in pairs(owned) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    owned, pedCache, greeted, chatterToken = {}, {}, {}, {}
end)
