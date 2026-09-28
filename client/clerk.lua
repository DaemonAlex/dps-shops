Clerk = {}
local owned = {}         -- id -> ped (this client spawned it)
local pedCache = {}      -- id -> last-seen ped for a clerk I do not own (validated before reuse)
local greeted = {}       -- id -> true once greeted this visit (spawn-point visit)
local chatterToken = {}  -- id -> current chatter generation; a stale closure compares and dies quietly
local spawning = {}      -- id -> true while spawnClerk is mid-flight (holds a granted claim)
local cancelled = {}     -- id -> true when the player left before an in-flight spawn finished
local inside = {}        -- id -> true while this player is inside the spawn point
local retried = {}       -- id -> true once an unwound spawn has been retried this visit

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

-- Where the clerk stands: the configured spot, nudged to solid ground only when
-- ground turns up close to the configured z, so a slightly wrong SPOT z cannot
-- leave the clerk floating or buried.
local function counterZ(counter)
    local found, groundZ = GetGroundZFor_3dCoord(counter.coords.x, counter.coords.y, counter.coords.z, false)
    if found and math.abs(groundZ - counter.coords.z) <= 1.5 then return groundZ end
    return counter.coords.z - 1.0
end

local spawnClerk   -- forward: an unwound spawn restarts itself through cancelSpawn

-- One retry per spawn-point visit, and only while the player is still inside
-- and the counter is still empty: an exit-then-re-enter during an in-flight
-- spawn would otherwise leave the counter dark until the next boundary crossing.
local function retrySpawn(counter)
    if not inside[counter.id] then return end
    if spawning[counter.id] then return end
    if Clerk.pedOf(counter.id) then return end
    spawnClerk(counter)
end

-- Undo an in-flight spawn that was cancelled or failed: drop any ped already
-- created, hand the claim back, clear both flight flags, then re-arm one spawn
-- if the player never actually left.
local function cancelSpawn(counter, ped)
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    lib.callback.await('dps-shops:server:release', false, counter.id)
    spawning[counter.id] = nil
    cancelled[counter.id] = nil
    if inside[counter.id] and not retried[counter.id] then
        retried[counter.id] = true
        SetTimeout(250, function() retrySpawn(counter) end)
    end
end

spawnClerk = function(counter)
    spawning[counter.id] = true

    local ok, model = lib.callback.await('dps-shops:server:claim', false, counter.id)
    if not ok then
        spawning[counter.id] = nil
        cancelled[counter.id] = nil
        return
    end

    -- Everything past the granted claim runs inside one pcall. lib.requestModel
    -- throws on a timeout or a bad model and any native below can error too; a
    -- throw here would leak the claim and leave spawning[id] true forever, so
    -- every exit routes through the status check below. `ped` is an upvalue so
    -- a throw after CreatePed still hands the handle back for deletion.
    local ped
    local okRun, status = pcall(function()
        if cancelled[counter.id] then return 'cancel' end

        local hash = loadModel(model)
        if not hash then return 'fail' end
        if cancelled[counter.id] then return 'cancel' end

        ped = CreatePed(4, hash, counter.coords.x, counter.coords.y, counter.coords.z - 1.0, counter.heading, true, true)
        SetModelAsNoLongerNeeded(hash)
        if not DoesEntityExist(ped) then ped = nil return 'fail' end
        if cancelled[counter.id] then return 'cancel' end

        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, false)
        SetPedCanRagdollFromPlayerImpact(ped, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetEntityCoordsNoOffset(ped, counter.coords.x, counter.coords.y, counterZ(counter), false, false, false)

        TaskStartScenarioInPlace(ped, Shops.persona(counter, Config).scenario, 0, true)

        local netId = NetworkGetNetworkIdFromEntity(ped)
        SetNetworkIdCanMigrate(netId, false)
        if not lib.callback.await('dps-shops:server:registered', false, counter.id, netId) then
            return 'rejected'
        end
        if cancelled[counter.id] then return 'cancel' end
        return 'ok'
    end)

    if not okRun then
        lib.print.error(('dps-shops: spawn for %s failed: %s'):format(counter.id, tostring(status)))
        status = 'fail'
    end

    if status == 'ok' then
        owned[counter.id] = ped
        pedCache[counter.id] = ped
        spawning[counter.id] = nil
        cancelled[counter.id] = nil
        retried[counter.id] = nil
        return
    end

    if status == 'rejected' then
        -- The server already released the claim itself on a rejected
        -- registration, and a retry would only be rejected again.
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
        spawning[counter.id] = nil
        cancelled[counter.id] = nil
        return
    end

    cancelSpawn(counter, ped)
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

-- Chatter is a SetTimeout chain, never a loop. token pins this chain to one
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
            inside[counter.id] = true
            if spawning[counter.id] then return end
            if not Clerk.pedOf(counter.id) then spawnClerk(counter) end
        end
        function spawnPoint:onExit()
            inside[counter.id] = nil
            retried[counter.id] = nil
            greeted[counter.id] = nil
            if spawning[counter.id] then cancelled[counter.id] = true end
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

-- ---------------------------------------------------------------------------
-- Rendering the server's reaction. The roll happened on the server; this only
-- plays it, and only on the client that owns the ped, so every player sees one
-- clerk doing one thing.
-- ---------------------------------------------------------------------------

local HandsUpDict = 'random@mugging3'
local HandsUpAnim = 'handsup_standing_base'
local HandsUpSeconds = 6
local CorpseSeconds = 30
local BagRetries = 10
local HuntLimit = 40.0   -- the clerk never chases a robber further than this from his counter

local fighting = {}      -- id -> incident number for which the clerk actually drew

-- Every client timer in this section checks the incident token before it acts,
-- so a timer left over from an earlier incident can never touch a later one.
local function onIncident(ped, incident)
    if not ped or not DoesEntityExist(ped) then return false end
    local r = Entity(ped).state.reaction
    return r ~= nil and r.incident == incident
end

-- GetPlayerFromServerId returns -1 for a player this client cannot see, and
-- GetPlayerPed(-1) is the LOCAL ped: resolving it carelessly makes the clerk
-- attack whoever is standing there. 0 means "no robber".
local function robberPed(by)
    local pid = by and GetPlayerFromServerId(by) or -1
    if pid == -1 then return 0 end
    local p = GetPlayerPed(pid)
    if not p or p == 0 or not DoesEntityExist(p) or IsEntityDead(p) then return 0 end
    return p
end

-- Back to work after the reaction window: no weapon, no combat attributes, no
-- tasks, invincible and frozen on the spot again, running the persona's scenario
-- as if nothing had happened.
local function returnToCounter(ped, counter, id)
    if id then fighting[id] = nil end
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    ClearPedTasksImmediately(ped)
    RemoveAllPedWeapons(ped, true)
    SetPedAccuracy(ped, 0)
    SetPedCombatAttributes(ped, 46, false)
    SetPedCombatAttributes(ped, 5, false)
    SetEntityInvincible(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetEntityCoordsNoOffset(ped, counter.coords.x, counter.coords.y, counterZ(counter), false, false, false)
    SetEntityHeading(ped, counter.heading)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, Shops.persona(counter, Config).scenario, 0, true)
end

-- The robber is gone: stop fighting, stand the clerk back behind his counter
-- facing out, still armed, until the reaction window closes. He never leaves
-- the shop to hunt.
local function holdAtCounter(ped, counter)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    ClearPedTasks(ped)
    SetEntityCoordsNoOffset(ped, counter.coords.x, counter.coords.y, counterZ(counter), false, false, false)
    SetEntityHeading(ped, counter.heading)
    TaskStandStill(ped, 120000)   -- covers the rest of any reaction window
end

local function foldUp(ped, counter, persona, incident)
    Clerk.say(ped, persona.fright)
    pcall(lib.requestAnimDict, HandsUpDict, 3000)
    if not onIncident(ped, incident) or IsEntityDead(ped) then return end
    TaskPlayAnim(ped, HandsUpDict, HandsUpAnim, 8.0, -8.0, -1, 49, 0, false, false, false)
    SetTimeout(HandsUpSeconds * 1000, function()
        if not onIncident(ped, incident) or IsEntityDead(ped) then return end
        ClearPedTasks(ped)
        -- head down, hands low: still cowed, but not stuck in the hands-up loop
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_BUM_STANDING', 0, true)
    end)
end

-- Real weapon, real accuracy: an aggressive clerk can kill, by design. He fights
-- the robber the server named and nobody else; if that robber cannot be resolved
-- when the weapon would come out, the clerk folds instead.
local function fightBack(ped, counter, persona, data, id)
    local incident = data.incident
    Clerk.say(ped, persona.anger)
    SetTimeout(persona.drawDelay or 1500, function()
        if not onIncident(ped, incident) or IsEntityDead(ped) then return end
        local robber = robberPed(data.by)
        if robber == 0 then
            foldUp(ped, counter, persona, incident)
            return
        end
        GiveWeaponToPed(ped, joaat(persona.weapon), 60, false, true)
        SetPedDropsWeaponsWhenDead(ped, false)
        SetPedAccuracy(ped, persona.accuracy or 30)
        SetPedCombatAttributes(ped, 46, true)   -- always fight
        SetPedCombatAttributes(ped, 5, true)    -- will fight an armed ped
        SetPedCombatRange(ped, 0)
        SetPedFleeAttributes(ped, 0, false)
        fighting[id] = incident
        TaskCombatPed(ped, robber, 0, 16)
    end)
end

local function react(ped, counter, data, id)
    local persona = Shops.persona(counter, Config)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    if data.kind == 'aggressive' and persona.weapon then
        fightBack(ped, counter, persona, data, id)
    else
        foldUp(ped, counter, persona, data.incident)
    end
end

-- The owner watches its own clerk while a reaction is on: no thread, a one
-- second timer chain that stops when the incident ends or the ped dies. It also
-- bounds the fight: once the robber is gone, dead or far from the counter, the
-- clerk is planted back behind it.
local watchReaction
watchReaction = function(id, counter, incident, by, held)
    local ped = owned[id]
    if not ped or not DoesEntityExist(ped) then return end
    if IsEntityDead(ped) then
        owned[id] = nil
        pedCache[id] = nil
        greeted[id] = nil
        fighting[id] = nil
        stopChatter(id)
        lib.callback.await('dps-shops:server:clerkDead', false, id)
        -- The counter must end up visibly empty: the body lies there, then goes.
        SetTimeout(CorpseSeconds * 1000, function()
            if DoesEntityExist(ped) and IsEntityDead(ped) then DeleteEntity(ped) end
        end)
        return
    end
    if not onIncident(ped, incident) then return end
    if not held and fighting[id] == incident then
        local robber = robberPed(by)
        if robber == 0 or #(GetEntityCoords(robber) - counter.coords) > HuntLimit then
            held = true
            holdAtCounter(ped, counter)
        end
    end
    SetTimeout(1000, function() watchReaction(id, counter, incident, by, held) end)
end

-- One handler for the whole reaction life cycle. GetEntityFromStateBagName can
-- return 0 for a frame or two after the bag lands, so it is given a few tries.
AddStateBagChangeHandler('reaction', nil, function(bagName, _, value)
    CreateThread(function()
        local ent
        for _ = 1, BagRetries do
            ent = GetEntityFromStateBagName(bagName)
            if ent and ent ~= 0 and DoesEntityExist(ent) then break end
            Wait(50)
        end
        if not ent or ent == 0 or not DoesEntityExist(ent) then return end
        local id = Entity(ent).state.dpsShop
        -- Only the owner drives the ped; everyone else just watches it over the network.
        if not id or owned[id] ~= ent then return end
        local counter = Shops.counterById(Config, id)
        if not counter then return end
        if value then
            greeted[id] = nil
            stopChatter(id)
            react(ent, counter, value, id)
            watchReaction(id, counter, value.incident, value.by, false)
        else
            returnToCounter(ent, counter, id)
        end
    end)
end)

-- Read by the m-StoreRobbery hook: a store with a live clerk raises the clerk's
-- own silent alarm, so the vendor dispatch must not fire a second one.
exports('ClerkNearby', function(dist)
    dist = tonumber(dist) or Config.GreetDistance
    local pos = GetEntityCoords(cache.ped)
    for _, counter in ipairs(Config.Counters) do
        if not (counter.coords.x == 0.0 and counter.coords.y == 0.0 and counter.coords.z == 0.0)
            and #(pos - counter.coords) <= dist then
            local ped = Clerk.pedOf(counter.id)
            if ped and DoesEntityExist(ped) and not IsEntityDead(ped) then return true end
        end
    end
    return false
end)

RegisterNetEvent('dps-shops:client:counterState', function(id, state)
    if state == 'dead' then
        greeted[id] = nil
        owned[id] = nil
        pedCache[id] = nil
        fighting[id] = nil
        stopChatter(id)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(owned) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    TriggerServerEvent('dps-shops:server:releaseAll')
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    for _, ped in pairs(owned) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    owned, pedCache, greeted, chatterToken = {}, {}, {}, {}
    spawning, cancelled, inside, retried, fighting = {}, {}, {}, {}, {}
    TriggerServerEvent('dps-shops:server:releaseAll')
end)
