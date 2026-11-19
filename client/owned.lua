-- Owned shops, client side: counter and office spots (ox_target) and the owner's office menus (ox_lib).
if not (Config.Owned and Config.Owned.Enabled) then return end

local zones = {}

local function notify(ok, msg)
    lib.notify({ title = 'Store', description = msg or (ok and 'Done.' or 'Could not do that.'), type = ok and 'success' or 'error' })
end

local function act(id, action, args, after)
    local ok, msg = lib.callback.await('dps-shops:owned:act', false, id, action, args)
    notify(ok, msg)
    if after then after(ok) end
    return ok
end

local openOffice -- forward

local function money(n) return ('$%s'):format(tostring(math.floor(n or 0)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end

-- ---------- office pages ----------
local function productsMenu(v)
    local opts = {}
    for _, p in ipairs(v.products) do
        opts[#opts + 1] = {
            title = p.label, description = ('%s · %d on the shelf · sells at %s'):format(p.line, p.amount, money(p.price)),
            onSelect = function()
                local sub = {}
                sub[#sub + 1] = { title = 'Set the price', description = ('%s to %s'):format(money(p.min), money(p.max)),
                    disabled = v.role < Config.Owned.Roles.setPrice, onSelect = function()
                        local r = lib.inputDialog(p.label .. ' price', { { type = 'number', label = 'Price', default = p.price, min = p.min, max = p.max } })
                        if r then act(v.id, 'setPrice', { item = p.item, price = r[1] }, function() openOffice(v.id) end) end
                    end }
                sub[#sub + 1] = { title = 'Put some on the shelf from my pockets', disabled = v.role < Config.Owned.Roles.storeProductFromInventory,
                    onSelect = function()
                        local r = lib.inputDialog(p.label, { { type = 'number', label = 'How many', min = 1, default = 1 } })
                        if r then act(v.id, 'storeProductFromInventory', { item = p.item, amount = r[1] }, function() openOffice(v.id) end) end
                    end }
                local function run(cb, ...)
                    local ok, msg = lib.callback.await(cb, false, v.id, ...)
                    notify(ok, msg)
                end
                if not Config.Owned.InstantRestock then
                    sub[#sub + 1] = { title = 'Drive a delivery run', icon = 'truck',
                        description = ('%d %s for %s from the till · you drive'):format(p.run, p.label, money(p.runCost)),
                        disabled = v.role < Config.Owned.Roles.startImportJob or not v.hasGarage,
                        onSelect = function() run('dps-shops:run:import', p.item) end }
                    sub[#sub + 1] = { title = 'Post it on the delivery board', icon = 'clipboard-list',
                        description = ('%d %s for %s, plus what you pay the driver'):format(p.run, p.label, money(p.runCost)),
                        disabled = v.role < Config.Owned.Roles.createJob or not v.hasGarage,
                        onSelect = function()
                            local r = lib.inputDialog('Driver pay', { { type = 'number', label = 'Reward for the driver ($)',
                                min = Config.Owned.Runs.boardMinReward, default = Config.Owned.Runs.boardMinReward } })
                            if r then run('dps-shops:run:post', p.item, r[1]) end
                        end }
                    sub[#sub + 1] = { title = 'Export some', icon = 'right-from-bracket',
                        description = ('Sell to a buyer at %s each · up to %d per truck'):format(money(p.export), p.run),
                        disabled = v.role < Config.Owned.Roles.startExportJob or not v.hasGarage or p.amount < 1,
                        onSelect = function()
                            local r = lib.inputDialog('Export ' .. p.label, { { type = 'number', label = 'How many',
                                min = 1, max = math.min(p.amount, p.run), default = math.min(p.amount, p.run) } })
                            if r then run('dps-shops:run:export', p.item, r[1]) end
                        end }
                end
                if Config.Owned.InstantRestock then
                    sub[#sub + 1] = { title = 'Order boxes', description = ('%d per box · %s each to the store'):format(p.batch, money(p.cost)),
                        disabled = v.role < Config.Owned.Roles.startImportJob, onSelect = function()
                            local r = lib.inputDialog(p.label .. ' order', { { type = 'slider', label = 'Boxes', min = 1, max = 10, default = 1 } })
                            if r then act(v.id, 'startImportJob', { item = p.item, batches = r[1] }, function() openOffice(v.id) end) end
                        end }
                end
                lib.registerContext({ id = 'dps_own_prod', title = p.label, menu = 'dps_own_products', options = sub })
                lib.showContext('dps_own_prod')
            end,
        }
    end
    lib.registerContext({ id = 'dps_own_products', title = 'Products', menu = 'dps_own_office', options = opts })
    lib.showContext('dps_own_products')
end

local function staffMenu(v)
    local opts = {
        { title = 'Hire someone standing here', icon = 'user-plus', disabled = v.role < Config.Owned.Roles.hirePlayer,
          description = ('%d of %d staff'):format(#v.staff, v.maxStaff), onSelect = function()
              local r = lib.inputDialog('Hire', { { type = 'number', label = 'Their ID', min = 1 } })
              if r then act(v.id, 'hirePlayer', { serverId = r[1] }, function() openOffice(v.id) end) end
          end },
    }
    for _, s in ipairs(v.staff) do
        opts[#opts + 1] = { title = s.name, description = ('%s · %d%% commission'):format(s.roleName, s.commission or 0),
            onSelect = function()
                lib.registerContext({ id = 'dps_own_person', title = s.name, menu = 'dps_own_staff', options = {
                    { title = 'Change role', disabled = v.role < Config.Owned.Roles.changeRole, onSelect = function()
                        local r = lib.inputDialog('Role', { { type = 'select', label = 'Role', default = tostring(s.role), options = {
                            { value = '1', label = 'Clerk' }, { value = '2', label = 'Manager' }, { value = '3', label = 'Partner' } } } })
                        if r then act(v.id, 'changeRole', { cid = s.cid, role = tonumber(r[1]) }, function() openOffice(v.id) end) end
                    end },
                    { title = 'Set commission', disabled = v.role < Config.Owned.Roles.giveCommission, onSelect = function()
                        local r = lib.inputDialog('Commission', { { type = 'slider', label = 'Percent of their sales', min = 0, max = 50, default = s.commission or 0 } })
                        if r then act(v.id, 'giveCommission', { cid = s.cid, commission = r[1] }, function() openOffice(v.id) end) end
                    end },
                    { title = 'Let go', icon = 'user-minus', disabled = v.role < Config.Owned.Roles.firePlayer, onSelect = function()
                        if lib.alertDialog({ header = 'Let ' .. s.name .. ' go?', content = 'They lose access to this store.', cancel = true }) == 'confirm' then
                            act(v.id, 'firePlayer', { cid = s.cid }, function() openOffice(v.id) end)
                        end
                    end },
                } })
                lib.showContext('dps_own_person')
            end }
    end
    lib.registerContext({ id = 'dps_own_staff', title = 'Staff', menu = 'dps_own_office', options = opts })
    lib.showContext('dps_own_staff')
end

local function upgradesMenu(v)
    local opts = {}
    local names = { stock = 'Bigger stockroom', truck = 'Bigger delivery truck', relationship = 'Better supplier deals' }
    for _, u in ipairs(v.upgrades) do
        opts[#opts + 1] = { title = names[u.key] or u.key, description = u.price and ('Level %d → %d for %s'):format(u.level, u.next, money(u.price)) or 'Top level',
            progress = u.level * 20, disabled = not u.price or v.role < Config.Owned.Roles.buyUpgrade,
            onSelect = function() act(v.id, 'buyUpgrade', { key = u.key }, function() openOffice(v.id) end) end }
    end
    lib.registerContext({ id = 'dps_own_upgrades', title = 'Upgrades', menu = 'dps_own_office', options = opts })
    lib.showContext('dps_own_upgrades')
end

local function linesMenu(v)
    local opts = {}
    for _, l in ipairs(v.lines) do
        opts[#opts + 1] = { title = l.label, icon = l.carried and 'check' or 'plus',
            description = l.carried and ('Carried · drop it for %s back'):format(money(l.sellPrice)) or ('Add for %s'):format(money(l.buyPrice)),
            disabled = v.role < Config.Owned.Roles[l.carried and 'sellCategory' or 'buyCategory'],
            onSelect = function() act(v.id, l.carried and 'sellCategory' or 'buyCategory', { key = l.key }, function() openOffice(v.id) end) end }
    end
    lib.registerContext({ id = 'dps_own_lines', title = ('Product lines (%d more allowed)'):format(math.max(0, v.slotsLeft)), menu = 'dps_own_office', options = opts })
    lib.showContext('dps_own_lines')
end

local function bankMenu(v)
    lib.registerContext({ id = 'dps_own_bank', title = 'Till', menu = 'dps_own_office', options = {
        { title = 'Balance', description = v.balance and money(v.balance) or 'Hidden for your role', icon = 'cash-register' },
        { title = 'Put money in', icon = 'arrow-down', disabled = v.role < Config.Owned.Roles.depositMoney, onSelect = function()
            local r = lib.inputDialog('Put money in', { { type = 'number', label = 'From your bank', min = 1 } })
            if r then act(v.id, 'depositMoney', { amount = r[1] }, function() openOffice(v.id) end) end
        end },
        { title = 'Take money out', icon = 'arrow-up', disabled = v.role < Config.Owned.Roles.withdrawMoney, onSelect = function()
            local r = lib.inputDialog('Take money out', { { type = 'number', label = 'To your bank', min = 1 } })
            if r then act(v.id, 'withdrawMoney', { amount = r[1] }, function() openOffice(v.id) end) end
        end },
    } })
    lib.showContext('dps_own_bank')
end

local function boardMenu(id, back)
    local list = lib.callback.await('dps-shops:run:board', false, id)
    if not list then return notify(false, 'Come to the office.') end
    local opts = {}
    if #list == 0 then opts[1] = { title = 'No deliveries wanted right now', icon = 'clipboard' } end
    for _, j in ipairs(list) do
        opts[#opts + 1] = { title = ('%d %s'):format(j.amount, j.label), icon = j.taken and 'truck-moving' or 'truck',
            description = j.taken and 'A driver is on it' or ('Pays %s · take the store truck to the pickup and back'):format(money(j.reward)),
            disabled = j.taken, onSelect = function()
                local ok, msg = lib.callback.await('dps-shops:run:take', false, id, j.id)
                notify(ok, msg)
            end }
    end
    lib.registerContext({ id = 'dps_own_board', title = 'Delivery jobs', menu = back, options = opts })
    lib.showContext('dps_own_board')
end

local function myJobsMenu(v)
    local opts = {}
    if #v.jobs == 0 then opts[1] = { title = 'Nothing posted', description = 'Post jobs from a product on the Shelves page', icon = 'clipboard' } end
    for _, j in ipairs(v.jobs) do
        opts[#opts + 1] = { title = ('%d %s'):format(j.amount, j.label), icon = j.taken and 'truck-moving' or 'clipboard-list',
            description = j.taken and 'A driver is on it' or ('Offering %s · select to take it down (money back)'):format(money(j.reward)),
            disabled = j.taken or v.role < Config.Owned.Roles.deleteJob, onSelect = function()
                local ok, msg = lib.callback.await('dps-shops:run:unpost', false, v.id, j.id)
                notify(ok, msg); openOffice(v.id)
            end }
    end
    lib.registerContext({ id = 'dps_own_myjobs', title = 'Posted deliveries', menu = 'dps_own_office', options = opts })
    lib.showContext('dps_own_myjobs')
end

openOffice = function(id)
    local v, err = lib.callback.await('dps-shops:owned:view', false, id)
    if not v then return notify(false, err) end
    if not v.owned then
        lib.registerContext({ id = 'dps_own_office', title = v.name, options = {
            { title = 'This store is for sale', description = money(v.buyPrice) .. ' from your bank', icon = 'store' },
            { title = 'Buy it', icon = 'key', onSelect = function()
                if lib.alertDialog({ header = 'Buy ' .. v.name .. '?', content = money(v.buyPrice) .. ' comes out of your bank.', cancel = true }) == 'confirm' then
                    act(id, 'buyStore', {}, function(ok) if ok then openOffice(id) end end)
                end
            end },
        } })
        return lib.showContext('dps_own_office')
    end
    if v.role == 0 then return notify(false, 'Staff only.') end
    lib.registerContext({ id = 'dps_own_office', title = ('%s · %s'):format(v.name, v.roleName), options = {
        { title = 'Shelves', description = ('%d of %d spaces used'):format(v.stocked, v.capacity), icon = 'boxes-stacked',
          progress = v.capacity > 0 and math.floor(v.stocked * 100 / v.capacity) or 0, onSelect = function() productsMenu(v) end },
        { title = 'Till', description = v.balance and money(v.balance) or nil, icon = 'cash-register', onSelect = function() bankMenu(v) end },
        { title = 'Staff', description = ('%d of %d'):format(#v.staff, v.maxStaff), icon = 'users', onSelect = function() staffMenu(v) end },
        { title = 'Product lines', icon = 'tags', onSelect = function() linesMenu(v) end },
        { title = 'Posted deliveries', description = v.hasGarage and (#v.jobs .. ' on the board') or 'No truck spot yet (admin: /shopgarage)',
          icon = 'clipboard-list', onSelect = function() myJobsMenu(v) end },
        { title = 'Upgrades', icon = 'arrow-up-right-dots', onSelect = function() upgradesMenu(v) end },
        { title = 'Rename the store', icon = 'pen', disabled = v.role < Config.Owned.Roles.renameStore, onSelect = function()
            local r = lib.inputDialog('Store name', { { type = 'input', label = 'Name', default = v.name, min = 3, max = 30 } })
            if r then act(id, 'renameStore', { name = r[1] }, function() openOffice(id) end) end
        end },
        { title = 'Sell the store', icon = 'right-from-bracket', disabled = v.role < 4,
          description = ('%s plus the till'):format(money(v.sellPrice)), onSelect = function()
            if lib.alertDialog({ header = 'Sell ' .. v.name .. '?', content = 'You get ' .. money(v.sellPrice) .. ' plus what is in the till. Staff lose their jobs.', cancel = true }) == 'confirm' then
                act(id, 'sellStore', {})
            end
        end },
    } })
    lib.showContext('dps_own_office')
end

-- ---------- zones ----------
local function clearZones()
    for _, z in ipairs(zones) do exports.ox_target:removeZone(z) end
    zones = {}
end

local function buildZones()
    clearZones()
    local list = lib.callback.await('dps-shops:owned:spots', false) or {}
    for _, s in ipairs(list) do
        zones[#zones + 1] = exports.ox_target:addSphereZone({ coords = s.office, radius = 0.8, debug = Config.Debug, options = {
            { name = 'dps_own_office_' .. s.id, icon = 'fa-solid fa-store', label = 'Store office', distance = 2.0,
              onSelect = function() openOffice(s.id) end },
            { name = 'dps_own_board_' .. s.id, icon = 'fa-solid fa-truck', label = 'Delivery jobs', distance = 2.0,
              onSelect = function() boardMenu(s.id) end },
        } })
        for i, c in ipairs(s.counters) do
            zones[#zones + 1] = exports.ox_target:addSphereZone({ coords = c, radius = 0.7, debug = Config.Debug, options = {
                { name = ('dps_own_counter_%s_%d'):format(s.id, i), icon = 'fa-solid fa-basket-shopping', label = 'Shop at ' .. s.name, distance = 2.0,
                  onSelect = function() exports.ox_inventory:openInventory('shop', { type = 'dps_owned_' .. s.id, id = i }) end },
            } })
        end
    end
end

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    buildZones()
end)
AddStateBagChangeHandler('dps-shops:owned', 'global', function() SetTimeout(500, buildZones) end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then clearZones() end end)

-- /shoplist answer: nearest stores first, with a jump for placing them.
RegisterNetEvent('dps-shops:owned:list', function(rows)
    local opts = {}
    for i, r in ipairs(rows) do
        if i > 40 then break end
        opts[#opts + 1] = { title = r.id .. (r.placed and '' or '  (not placed)'), icon = r.placed and 'check' or 'location-dot',
            description = ('%s · %s · %dm away'):format(r.type, r.owner and 'owned' or 'for sale', math.floor(r.d)) }
    end
    lib.registerContext({ id = 'dps_own_list', title = 'Stores (nearest first)', options = opts })
    lib.showContext('dps_own_list')
end)
