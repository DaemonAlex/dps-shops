-- Delivery runs (step 2), client side: a blip and route to the next stop, and a prompt to load or unload when
-- the player is there in the store's truck. Nothing runs unless this player is on a run.
if not (Config.Owned and Config.Owned.Enabled) then return end

local run      -- { netId, point, garage, kind, label, amount, loadSeconds, stage }
local blip

local function setStop(coords, text)
    if blip then RemoveBlip(blip) end
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 478)
    SetBlipColour(blip, 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandSetBlipName(blip)
end

local function stop()
    run = nil
    if blip then RemoveBlip(blip) blip = nil end
    lib.hideTextUI()
end

local function myTruck()
    if not run then return nil end
    local veh = NetworkDoesNetworkIdExist(run.netId) and NetToVeh(run.netId) or 0
    return veh ~= 0 and veh or nil
end

local function arrive()
    local busy = run.stage == 'out' and (run.kind == 'export' and 'Unloading' or 'Loading') or 'Unloading'
    if not lib.progressBar({ duration = run.loadSeconds * 1000, label = busy .. ' ' .. run.label .. '...',
        canCancel = true, disable = { move = true, car = true, combat = true } }) then return end
    local ok, msg, garage = lib.callback.await('dps-shops:run:arrive', false)
    lib.notify({ title = 'Delivery', description = msg, type = ok and 'success' or 'error' })
    if ok and garage then
        run.stage = 'back'
        setStop(vector3(garage.x, garage.y, garage.z), 'Store truck spot')
    end
end

local function watch()
    CreateThread(function()
        local shown = false
        while run do
            local sleep = 1000
            local target = run.stage == 'out' and run.point or vector3(run.garage.x, run.garage.y, run.garage.z)
            local ped = PlayerPedId()
            local veh = myTruck()
            local near = veh and GetVehiclePedIsIn(ped, false) == veh and #(GetEntityCoords(veh) - target) < 12.0
            if near then
                sleep = 0
                if not shown then
                    lib.showTextUI(('[E] %s'):format(run.stage == 'out' and (run.kind == 'export' and 'Unload for the buyer' or 'Load up') or 'Unload at the store'))
                    shown = true
                end
                if IsControlJustPressed(0, 38) then lib.hideTextUI(); shown = false; arrive() end
            elseif shown then
                lib.hideTextUI(); shown = false
            end
            Wait(sleep)
        end
    end)
end

RegisterNetEvent('dps-shops:run:started', function(r)
    run = r
    run.stage = 'out'
    setStop(r.point, r.kind == 'export' and 'Buyer' or 'Pickup')
    lib.notify({ title = 'Delivery', type = 'inform', duration = 10000,
        description = ('Truck %s is out back. %d %s. You have %d minutes.'):format(r.plate, r.amount, r.label, r.minutes) })
    watch()
end)

RegisterNetEvent('dps-shops:run:ended', function(why)
    stop()
    if why then lib.notify({ title = 'Delivery', description = why, type = 'error' }) end
end)

-- /shoprunquit: give up the run you are on (the truck goes back to the depot).
RegisterCommand('shoprunquit', function()
    if not run then return end
    if lib.alertDialog({ header = 'Give up the run?', content = 'The truck and its load are lost.', cancel = true }) == 'confirm' then
        lib.callback.await('dps-shops:run:quit', false)
    end
end, false)
