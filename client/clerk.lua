Clerk = {}
local owned = {}         -- id -> ped (this client spawned it)
local pedCache = {}      -- id -> last-seen ped for a clerk I do not own (validated before reuse)
local greeted = {}       -- id -> true once greeted this visit (spawn-point visit)
local chatterToken = {}  -- id -> current chatter generation; a stale closure compares and dies quietly
local spawning = {}      -- id -> true while spawnClerk is mid-flight (holds a granted claim)
local cancelled = {}     -- id -> true when the player left before an in-flight spawn finished
local inside = {}        -- id -> true while this player is inside the wider keep ring
local retried = {}       -- id -> true once an unwound spawn has been retried this visit
local nearGreet = {}     -- id -> true while this player is inside the greet ring

-- Never let a mis-set config turn idle chatter into a stutter.
local function chatterDelay()
    local s = tonumber(Config.ChatterSeconds) or 60
    if s < 5 then s = 5 end
    return s * 1000
end

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

-- Counter coords are the CENTRE of the clerk: they come from a player standing
-- at the spot. CreatePed places by the feet, so it gets z - 1.0, while every
-- SetEntityCoordsNoOffset places by the centre and gets this. The ground probe
-- only wins when the height it implies is close to the configured one, so a
-- slightly wrong SPOT z cannot leave the clerk floating or buried, and a badly
-- wrong probe (a roof, a basement) cannot move him at all.
local function seatZ(counter)
    local found, groundZ = GetGroundZFor_3dCoord(counter.coords.x, counter.coords.y, counter.coords.z, false)
    if found then
        local centre = groundZ + 1.0
        if math.abs(centre - counter.coords.z) <= 1.5 then return centre end
    end
    return counter.coords.z
end

local spawnClerk   -- forward: an unwound spawn restarts itself through cancelSpawn
local startSpawn   -- forward: the one way a spawn is ever started
local clerkReady   -- forward: assigned once the greet helpers exist

-- One retry per spawn-point visit, and only while the player is still inside
-- and the counter is still empty: an exit-then-re-enter during an in-flight
-- spawn would otherwise leave the counter dark until the next boundary crossing.
local function retrySpawn(counter)
    -- Checked again here, not only when the retry was armed: 250 ms is long
    -- enough for the player to have walked back out of the ring.
    if not inside[counter.id] then return end
    startSpawn(counter)
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

-- spawning[id] is already true when this runs: startSpawn sets it before handing
-- the work to a thread, so ox_lib's points thread is never blocked on a callback.
spawnClerk = function(counter)
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
        SetEntityCoordsNoOffset(ped, counter.coords.x, counter.coords.y, seatZ(counter), false, false, false)

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
        if Config.Debug then
            lib.print.info(('dps-shops: clerk up at %s'):format(counter.id))
        end
        -- The player may have walked to the counter while this was in flight.
        if clerkReady then clerkReady(counter) end
        return
    end

    if status == 'rejected' then
        -- Release contract: on a false answer from `registered` the server has
        -- either released this claim itself or is keeping it for a clerk that is
        -- already registered. Either way the client deletes its ped and does NOT
        -- call release, and does not retry: a retry would be rejected again.
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
        spawning[counter.id] = nil
        cancelled[counter.id] = nil
        return
    end

    cancelSpawn(counter, ped)
end

-- The one way a spawn is ever started. It claims the flight flag on the caller's
-- own thread (so two onEnter calls cannot both start one) and then gets out of
-- the way: ox_lib's points thread must never wait on a server callback. The
-- pcall is the last line of defence for the flag invariant — no path may leave
-- spawning[id] true.
startSpawn = function(counter)
    local id = counter.id
    if spawning[id] or owned[id] then return end
    if Clerk.pedOf(id) then return end
    spawning[id] = true
    CreateThread(function()
        local ok, err = pcall(spawnClerk, counter)
        if not ok then
            lib.print.error(('dps-shops: spawn thread for %s died: %s'):format(id, tostring(err)))
            spawning[id] = nil
            cancelled[id] = nil
        end
    end)
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
    SetTimeout(chatterDelay(), function() chatterTick(counter, token) end)
end

local function startChatter(counter)
    local token = (chatterToken[counter.id] or 0) + 1
    chatterToken[counter.id] = token
    SetTimeout(chatterDelay(), function() chatterTick(counter, token) end)
end

local function stopChatter(id)
    chatterToken[id] = (chatterToken[id] or 0) + 1
end

-- The player can beat the clerk to the counter: when a spawn finishes while they
-- are already standing in the greet ring, greet now instead of making them walk
-- out and back in to cross the boundary again.
clerkReady = function(counter)
    if not nearGreet[counter.id] then return end
    attemptGreet(counter)
    startChatter(counter)
end

for _, counter in ipairs(Config.Counters) do
    if Shops.isPlaced(counter) then
        -- SPOT placeholders (Roxwood bait shop, as of this task) stay dark: no points at all.

        -- Hysteresis: the clerk appears on entering the inner ring and only goes
        -- away on leaving the wider one, so a player pacing the boundary does not
        -- make him flicker. `inside` follows the wider ring.
        local keepPoint = lib.points.new({ coords = counter.coords, distance = Config.DespawnDistance })
        function keepPoint:onEnter()
            inside[counter.id] = true
        end
        function keepPoint:onExit()
            inside[counter.id] = nil
            retried[counter.id] = nil
            greeted[counter.id] = nil
            if spawning[counter.id] then cancelled[counter.id] = true end
            if owned[counter.id] then
                -- never on the points thread: despawn awaits the release callback
                CreateThread(function() despawnClerk(counter) end)
            end
        end

        local spawnPoint = lib.points.new({ coords = counter.coords, distance = Config.SpawnDistance })
        function spawnPoint:onEnter()
            startSpawn(counter)
        end

        local greetPoint = lib.points.new({ coords = counter.coords, distance = Config.GreetDistance })
        function greetPoint:onEnter()
            nearGreet[counter.id] = true
            attemptGreet(counter)
            startChatter(counter)
        end
        function greetPoint:onExit()
            nearGreet[counter.id] = nil
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
local BagRetries = 10
local ReactionCfg = Config.Reaction or {}
local HandsUpSeconds = ReactionCfg.handsUpSeconds or 6
local CorpseSeconds = ReactionCfg.corpseSeconds or 30
local HuntLimit = ReactionCfg.huntLimit or 40.0   -- the clerk never chases further than this

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
    SetEntityCoordsNoOffset(ped, counter.coords.x, counter.coords.y, seatZ(counter), false, false, false)
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
    SetEntityCoordsNoOffset(ped, counter.coords.x, counter.coords.y, seatZ(counter), false, false, false)
    SetEntityHeading(ped, counter.heading)
    TaskStandStill(ped, ((Config.Reaction and Config.Reaction.seconds) or 120) * 1000)
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
        -- A clerk who somehow failed to draw must not stand there in a combat
        -- task with empty hands: he folds instead.
        if not HasPedGotWeapon(ped, joaat(persona.weapon), false) then
            foldUp(ped, counter, persona, incident)
            return
        end
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
    -- This handler fires for every clerk on the server. A client that owns none
    -- of them has nothing to do and must not pay for a thread to find that out.
    if not next(owned) then return end
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

RegisterNetEvent('dps-shops:client:counterState', function(id, state)
    if state == 'dead' then
        greeted[id] = nil
        owned[id] = nil
        pedCache[id] = nil
        fighting[id] = nil
        stopChatter(id)
        return
    end
    if state == 'free' then
        -- The counter is claimable again. Players already standing inside the
        -- ring never cross a point boundary, so this is the only thing that can
        -- refill it for them. The random delay spreads several of them out; the
        -- server's claim is still the lock, so a loser simply gets a false.
        if not inside[id] or spawning[id] or owned[id] then return end
        if Clerk.pedOf(id) then return end
        local counter = Shops.counterById(Config, id)
        if not counter then return end
        SetTimeout(math.random(250, 1500), function()
            if not inside[id] then return end
            startSpawn(counter)
        end)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(owned) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    TriggerServerEvent('dps-shops:server:releaseAll')
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    for _, ped in pairs(owned) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    owned, pedCache, greeted, chatterToken, nearGreet = {}, {}, {}, {}, {}
    spawning, cancelled, inside, retried, fighting = {}, {}, {}, {}, {}
    TriggerServerEvent('dps-shops:server:releaseAll')
end)
