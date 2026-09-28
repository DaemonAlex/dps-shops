-- A weapon aimed at a clerk for Config.AimSeconds, from inside
-- Config.ThreatDistance, reports one threat to the server. The server decides
-- everything that follows; this file never renders a reaction.

local aimingSince = {}   -- id -> game time the current aim started
local reported = {}      -- id -> game time of the last report sent
local pedAt = {}         -- id -> { ped = ped, at = game time } so the per-frame
                         --       check never runs Clerk.pedOf's pool scan twice a second

local ReportCooldown = 10000   -- ms; the server rate-limits again on its side
local PedLookupCooldown = 1000 -- ms between pool scans for a clerk we do not own

-- The clerk for this counter, cheap enough to ask for every frame: the cached
-- handle is kept while it still exists and still carries the counter's statebag.
local function clerkPed(id)
    local c = pedAt[id]
    if c and c.ped and DoesEntityExist(c.ped) and Entity(c.ped).state.dpsShop == id then
        return c.ped
    end
    local now = GetGameTimer()
    if c and now - c.at < PedLookupCooldown then return c.ped end
    local ped = Clerk.pedOf(id)
    pedAt[id] = { ped = ped, at = now }
    return ped
end

-- Advisory only: the server clamps this to 1..4 and never trusts it further.
local function countRobbers(counter)
    local n = 1
    for _, pid in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pid)
        if p ~= 0 and p ~= cache.ped and DoesEntityExist(p) and not IsEntityDead(p)
            and #(GetEntityCoords(p) - counter.coords) < Config.ThreatDistance
            and IsPedArmed(p, 7) then
            n = n + 1
        end
    end
    return n > 4 and 4 or n
end

-- The callback is awaited on its own thread so the per-frame check never yields.
-- The reason is all the client gets to say: the server reads the weapon itself.
local function report(id, reason, robbers)
    CreateThread(function()
        lib.callback.await('dps-shops:server:threat', false, id, reason, robbers)
    end)
end

-- The only per-frame work in this resource. An unarmed player costs exactly one
-- native and returns, which is the common case by a wide margin.
local function myThreat(counter)
    if not IsPedArmed(cache.ped, 7) then
        aimingSince[counter.id] = nil
        return
    end
    local now = GetGameTimer()
    if (reported[counter.id] or 0) + ReportCooldown > now then return end
    local ped = clerkPed(counter.id)
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then
        aimingSince[counter.id] = nil
        return
    end
    if Entity(ped).state.reaction then
        aimingSince[counter.id] = nil
        return
    end
    if not (IsPlayerFreeAiming(cache.playerId) and IsPlayerFreeAimingAtEntity(cache.playerId, ped)) then
        aimingSince[counter.id] = nil
        return
    end
    aimingSince[counter.id] = aimingSince[counter.id] or now
    if now - aimingSince[counter.id] < Config.AimSeconds * 1000 then return end
    reported[counter.id] = now
    aimingSince[counter.id] = nil
    report(counter.id, 'aim', countRobbers(counter))
end

-- A convenience alias for anything that wants to poke the clerk at whatever
-- counter the player is standing at. m-StoreRobbery does NOT use this: its
-- decision is made server side through the RobberyThreat export, so nothing
-- awaits across a resource boundary. Harmless either way, because the server
-- applies the same distance gate, reject limiter and 600 s per-counter limit.
AddEventHandler('dps-shops:client:robberyStarted', function()
    local pos = GetEntityCoords(cache.ped)
    for _, counter in ipairs(Config.Counters) do
        if Shops.isPlaced(counter)
            and #(pos - counter.coords) < Config.ThreatDistance then
            reported[counter.id] = GetGameTimer()
            report(counter.id, 'robbery', 1)
        end
    end
end)

for _, counter in ipairs(Config.Counters) do
    if Shops.isPlaced(counter) then
        -- SPOT placeholders stay dark, exactly as in client/clerk.lua.
        local point = lib.points.new({ coords = counter.coords, distance = Config.ThreatDistance })
        function point:nearby() myThreat(counter) end
        function point:onExit() aimingSince[counter.id] = nil end
    end
end

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    aimingSince, reported, pedAt = {}, {}, {}
end)
