-- AI clerks, client side: hands each clerk ped this player can see to dps-ainpcs (so "Talk to" works), and keeps
-- an eye on the player while they are in the shop. Light on purpose: nothing runs until the player is near a
-- counter, then one check a second; the server is asked about the player's history once per visit and once a minute.
if not (Config.AIClerks and Config.AIClerks.Enabled) then return end

local AINPC = 'dps-ainpcs'
local W = Config.AIClerks.Watch
local attached = {}   -- counterId -> ped handed to dps-ainpcs

-- Remarks are the game's own voice lines, so they cost nothing. A familiar face gets small talk, not insults.
local REMARKS = {
    loitering = { 'GENERIC_HOWS_IT_GOING', 'CHAT_STATE' },
    known     = { 'GENERIC_HI', 'CHAT_STATE' },
    masked    = { 'GENERIC_CURSE_MED', 'GENERIC_INSULT_MED' },
    armed     = { 'GENERIC_CURSE_MED', 'GENERIC_SHOCKED_MED' },
}

local function ainpcOn() return GetResourceState(AINPC) == 'started' end

local function attach(counter, ped)
    if not ainpcOn() then return end
    if attached[counter.id] == ped then return end
    if exports[AINPC]:AttachExternalNPC(ShopAI.npcId(counter.id), ped) then attached[counter.id] = ped end
end

local function detach(counter)
    if not attached[counter.id] then return end
    attached[counter.id] = nil
    if ainpcOn() then exports[AINPC]:DetachExternalNPC(ShopAI.npcId(counter.id)) end
end

local function watchCounter(counter, point)
    local secondsHere, lastSent, known, bought, lastAsked = 0, 0, false, false, -60
    while point.isInside do
        local ped = Clerk.pedOf(counter.id)
        if ped and DoesEntityExist(ped) and not IsEntityDead(ped) and not Entity(ped).state.reaction then
            attach(counter, ped)
        else
            detach(counter)
        end

        local me = PlayerPedId()
        local inShop = #(GetEntityCoords(me) - counter.coords) <= W.radius
        secondsHere = inShop and secondsHere + 1 or 0
        if inShop and ped then
            local now = GetGameTimer() // 1000
            if now - lastAsked >= 60 then
                lastAsked = now
                known, bought = lib.callback.await('dps-shops:ai:known', false, counter.id)
            end
            local reason = ShopAI.watchReason({
                armed = IsPedArmed(me, 4),
                masked = GetPedDrawableVariation(me, 1) > 0,
                secondsHere = secondsHere,
                bought = bought,
            })
            if not reason and known then reason = 'known' end
            if reason and now - lastSent >= W.lineCooldown
                and not (ainpcOn() and exports[AINPC]:IsTalking()) then
                lastSent = now
                TriggerServerEvent('dps-shops:ai:watch', counter.id, reason)
            end
        end
        Wait(1000)
    end
    detach(counter)
end

CreateThread(function()
    for _, counter in ipairs(Config.Counters) do
        if Shops.isPlaced(counter) then
            local point = lib.points.new({ coords = counter.coords, distance = 25.0 })
            function point:onEnter() CreateThread(function() watchCounter(counter, self) end) end
        end
    end
end)

-- Only the client running the clerk can move it: turn its head to the player and say something.
RegisterNetEvent('dps-shops:ai:watchPlayer', function(counterId, targetSrc, reason)
    local ped = Clerk.pedOf(counterId)
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) or not NetworkHasControlOfEntity(ped) then return end
    local target = GetPlayerFromServerId(targetSrc)
    if target == -1 then return end
    TaskLookAtEntity(ped, GetPlayerPed(target), 8000, 2048, 3)
    Clerk.say(ped, REMARKS[reason] or REMARKS.loitering)
end)

-- After a talk dps-ainpcs hands the clerk back: back to the counter pose, if this client runs it.
AddEventHandler('dps-ainpcs:externalReleased', function(npcId, ent)
    local id = ShopAI.counterIdOf(npcId)
    local counter = id and Shops.counterById(Config, id)
    if not counter or not DoesEntityExist(ent) or not NetworkHasControlOfEntity(ent) then return end
    TaskStartScenarioInPlace(ent, Shops.persona(counter, Config).scenario, 0, true)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, counter in ipairs(Config.Counters) do detach(counter) end
end)
