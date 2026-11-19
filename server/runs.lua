-- Delivery runs (step 2), server side. One run per player at a time:
--   import  - staff drive the store truck to a pickup, load, drive back, unload: stock goes on the shelves
--   export  - staff load stock from the shelves, drive it to a buyer: the export price goes in the till
--   job     - a store posts an import on its delivery board (paid up front from the till); any player can
--             take it and is paid the reward when the goods are unloaded
-- The server checks each stage itself: the player has to be in the store's truck, at the right place.
if not (Config.Owned and Config.Owned.Enabled) then return end

local O, R = Config.Owned, Config.Owned.Runs
local I = OwnedInternal
local runs = {}        -- src -> run
local plateN = math.random(0, 9999)
local STAGE_REACH = 15.0

local function truckOf(run)
    local veh = run.netId and NetworkGetEntityFromNetworkId(run.netId)
    return (veh and veh ~= 0 and DoesEntityExist(veh)) and veh or nil
end

local function endRun(src, run, why)
    runs[src] = nil
    local veh = truckOf(run)
    if veh then DeleteEntity(veh) end
    if run.plate and GetResourceState('wasabi_carlock') == 'started' then
        pcall(function() exports['wasabi_carlock']:RemoveKey(src, run.plate) end)
    end
    TriggerClientEvent('dps-shops:run:ended', src, why)
end

-- Every board job a run failed to finish goes back on the board for someone else.
local function jobBack(run)
    if run.kind ~= 'job' then return end
    local st = I.stores[run.store]
    for _, j in ipairs(st.jobs or {}) do
        if j.id == run.jobId then j.takenBy = nil end
    end
    I.save(run.store)
end

local function spawnTruck(src, store, st)
    local g = store.garage
    local model = Owned.truckModel(store, st)
    local veh = CreateVehicleServerSetter(joaat(model), 'automobile', g.x, g.y, g.z, g.w)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(50) end
    if not DoesEntityExist(veh) then return nil end
    plateN = plateN + 1
    local plate = Owned.plate(R.platePrefix, plateN)
    SetVehicleNumberPlateText(veh, plate)
    if GetResourceState('wasabi_carlock') == 'started' then
        pcall(function() exports['wasabi_carlock']:GiveKey(src, plate) end)
    end
    return NetworkGetNetworkIdFromEntity(veh), plate, model
end

local function begin(src, store, st, run)
    if runs[src] then return false, 'You are already on a run.' end
    if not store.garage then return false, 'This store has no truck spot yet. An admin sets it with /shopgarage.' end
    local points = run.kind == 'export' and O.ExportPoints or O.Pickups
    run.point = Owned.pickPoint(points, store.office, math.random, R.pickupMin, R.pickupMax)
    local netId, plate, model = spawnTruck(src, store, st)
    if not netId then return false, 'The truck would not come out. Try again.' end
    run.netId, run.plate, run.stage = netId, plate, 'out'
    run.deadline = os.time() + R.minutes * 60
    runs[src] = run
    TriggerClientEvent('dps-shops:run:started', src, {
        netId = netId, plate = plate, model = model, point = run.point, garage = store.garage,
        kind = run.kind, label = run.label, amount = run.amount, loadSeconds = R.loadSeconds, minutes = R.minutes,
    })
    return true, ('Truck %s is out back. Go get the %s.'):format(plate, run.label)
end

-- ---------- starting runs (from the store office) ----------
local function product(st, item)
    return Owned.itemDef(item, st.categories)
end

lib.callback.register('dps-shops:run:import', function(src, id, item)
    local store, st, pd = I.gate(src, id, 'startImportJob')
    if not store then return false, st end
    if not st.owner then return false, 'Nobody owns this store yet.' end
    local def = product(st, item)
    if not def then return false, 'Not a product this store carries.' end
    local amount = Owned.runCapacity(store, st, def)
    local room = Owned.capacity(store, st) - Owned.stockTotal(st)
    if room < 1 then return false, 'The shelves are full.' end
    amount = math.min(amount, room)
    local cost = Owned.importCost(store, st, def, amount)
    if st.balance < cost then return false, ('The till needs $%d for this load.'):format(cost) end
    local ok, msg = begin(src, store, st, { kind = 'import', store = id, item = item, amount = amount, label = def.label, cost = cost })
    if ok then
        st.balance = st.balance - cost
        I.save(id); I.ledger(id, 'import', -cost, pd.citizenid, ('%dx %s'):format(amount, item))
    end
    return ok, msg
end)

lib.callback.register('dps-shops:run:export', function(src, id, item, amount)
    local store, st, pd = I.gate(src, id, 'startExportJob')
    if not store then return false, st end
    local def = product(st, item)
    local s = st.stock[item]
    amount = math.floor(tonumber(amount) or 0)
    if not def or not s or amount < 1 or amount > s.amount then return false, 'Not that many on the shelves.' end
    if amount > Owned.runCapacity(store, st, def) then return false, 'That will not fit in the truck.' end
    local ok, msg = begin(src, store, st, { kind = 'export', store = id, item = item, amount = amount, label = def.label,
        value = Owned.exportValue(def, amount) })
    if ok then
        s.amount = s.amount - amount
        if s.amount <= 0 and not s.price then st.stock[item] = nil end
        I.save(id); I.registerShop(store); I.ledger(id, 'export', 0, pd.citizenid, ('%dx %s loaded'):format(amount, item))
    end
    return ok, msg
end)

-- ---------- the delivery board ----------
local jobN = 0
lib.callback.register('dps-shops:run:post', function(src, id, item, reward)
    local store, st, pd = I.gate(src, id, 'createJob')
    if not store then return false, st end
    local def = product(st, item)
    reward = math.floor(tonumber(reward) or 0)
    if not def then return false, 'Not a product this store carries.' end
    if reward < R.boardMinReward then return false, ('Offer at least $%d.'):format(R.boardMinReward) end
    st.jobs = st.jobs or {}
    if #st.jobs >= R.boardMaxJobs then return false, 'The board is full.' end
    local amount = Owned.runCapacity(store, st, def)
    local cost = Owned.importCost(store, st, def, amount)
    if st.balance < cost + reward then return false, ('The till needs $%d (goods plus the driver).'):format(cost + reward) end
    st.balance = st.balance - cost - reward
    jobN = jobN + 1
    table.insert(st.jobs, { id = ('%d-%d'):format(os.time(), jobN), item = item, amount = amount, cost = cost, reward = reward })
    I.save(id); I.ledger(id, 'job', -(cost + reward), pd.citizenid, ('%dx %s, driver $%d'):format(amount, item, reward))
    return true, ('Posted: %d %s, $%d to the driver.'):format(amount, def.label, reward)
end)

lib.callback.register('dps-shops:run:unpost', function(src, id, jobId)
    local store, st, pd = I.gate(src, id, 'deleteJob')
    if not store then return false, st end
    for i, j in ipairs(st.jobs or {}) do
        if j.id == jobId then
            if j.takenBy then return false, 'A driver is on it.' end
            table.remove(st.jobs, i)
            st.balance = st.balance + j.cost + j.reward
            I.save(id); I.ledger(id, 'job', j.cost + j.reward, pd.citizenid, 'cancelled')
            return true, 'Taken off the board. The money is back in the till.'
        end
    end
    return false, 'No such job.'
end)

-- Anyone at the office can read the board and take a job.
lib.callback.register('dps-shops:run:board', function(src, id)
    local store = I.storeOf(id)
    if not store or not store.office then return nil end
    if #(GetEntityCoords(GetPlayerPed(src)) - store.office) > 4.0 then return nil end
    local st = I.stores[id]
    local out = {}
    for _, j in ipairs(st.jobs or {}) do
        local def = product(st, j.item)
        out[#out + 1] = { id = j.id, label = def and def.label or j.item, amount = j.amount, reward = j.reward, taken = j.takenBy ~= nil }
    end
    return out
end)

lib.callback.register('dps-shops:run:take', function(src, id, jobId)
    local store = I.storeOf(id)
    if not store or not store.office or #(GetEntityCoords(GetPlayerPed(src)) - store.office) > 4.0 then return false, 'Come to the office.' end
    local st = I.stores[id]
    local pd = I.player(src)
    for _, j in ipairs(st.jobs or {}) do
        if j.id == jobId then
            if j.takenBy then return false, 'Someone already took it.' end
            local def = product(st, j.item)
            local ok, msg = begin(src, store, st, { kind = 'job', store = id, item = j.item, amount = j.amount,
                label = def and def.label or j.item, jobId = j.id, reward = j.reward })
            if ok then j.takenBy = pd and pd.citizenid or tostring(src); I.save(id) end
            return ok, msg
        end
    end
    return false, 'That job is gone.'
end)

-- ---------- stages ----------
-- 'out': at the pickup (or the buyer, for exports). 'back': at the store's truck spot.
lib.callback.register('dps-shops:run:arrive', function(src)
    local run = runs[src]
    if not run then return false, 'No run.' end
    local veh = truckOf(run)
    if not veh then endRun(src, run, 'The truck is gone. Run lost.'); jobBack(run); return false, 'The truck is gone.' end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= veh then return false, 'Bring the truck.' end
    if GetVehicleEngineHealth(veh) <= 0 then endRun(src, run, 'The truck is wrecked. Run lost.'); jobBack(run); return false, 'Wrecked.' end
    local store = I.storeOf(run.store)
    local here = GetEntityCoords(veh)
    if run.stage == 'out' then
        if #(here - run.point) > STAGE_REACH then return false, 'Not there yet.' end
        if run.kind == 'export' then
            -- sold at the buyer; the money goes to the till when the truck is back
            run.stage = 'back'
            return true, 'Sold. Take the truck back to the store.', store.garage
        end
        run.stage = 'back'
        return true, 'Loaded. Take it back to the store.', store.garage
    end
    if run.stage == 'back' then
        if #(here - vector3(store.garage.x, store.garage.y, store.garage.z)) > STAGE_REACH then return false, 'Not at the store yet.' end
        local st = I.stores[run.store]
        local pd = I.player(src)
        if run.kind == 'export' then
            st.balance = st.balance + run.value
            I.ledger(run.store, 'export', run.value, pd and pd.citizenid, ('%dx %s sold'):format(run.amount, run.item))
        else
            local def = product(st, run.item)
            if def then
                local s = st.stock[run.item] or { amount = 0, price = def.price }
                s.amount = s.amount + run.amount
                st.stock[run.item] = s
            end
            I.ledger(run.store, 'delivered', 0, pd and pd.citizenid, ('%dx %s'):format(run.amount, run.item))
            if run.kind == 'job' then
                for i, j in ipairs(st.jobs or {}) do
                    if j.id == run.jobId then table.remove(st.jobs, i) break end
                end
                exports.qbx_core:AddMoney(src, 'bank', run.reward, 'dps-shops delivery job')
            end
            I.registerShop(store)
        end
        I.save(run.store)
        endRun(src, run, nil)
        if run.kind == 'job' then return true, ('Delivered. $%d paid to your bank.'):format(run.reward) end
        if run.kind == 'export' then return true, ('Done. $%d went in the till.'):format(run.value) end
        return true, ('Done. %d %s on the shelves.'):format(run.amount, run.label)
    end
    return false, 'No run.'
end)

lib.callback.register('dps-shops:run:quit', function(src)
    local run = runs[src]
    if not run then return false end
    endRun(src, run, 'Run called off.'); jobBack(run)
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    local run = runs[src]
    if run then endRun(src, run, nil); jobBack(run) end
end)

-- The only loop: once a minute, call off runs that ran out of time.
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, run in pairs(runs) do
            if now > run.deadline then endRun(src, run, 'Out of time. Run lost.'); jobBack(run) end
        end
    end
end)
