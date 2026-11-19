-- AI clerks: pure helpers (no natives) for naming, the character sheet sent to dps-ainpcs, the live facts, and
-- deciding when a clerk keeps an eye on someone. tests/test_ai.lua checks them without a server.
ShopAI = {}

function ShopAI.npcId(counterId) return 'shopclerk_' .. counterId end

function ShopAI.counterIdOf(npcId)
    return type(npcId) == 'string' and npcId:match('^shopclerk_(.+)$') or nil
end

-- Same name for the same counter every time; a respawn after a death (salt) may bring someone new.
function ShopAI.clerkName(counter, salt, cfg)
    cfg = cfg or Config
    local kind = Shops.personaKey(counter)
    local pool = (cfg.AIClerks.Names[kind]) or cfg.AIClerks.Names.quickie
    local h = salt or 0
    for i = 1, #counter.id do h = (h * 31 + counter.id:byte(i)) % 2147483647 end
    return pool[(h % #pool) + 1]
end

function ShopAI.kindOf(counter, cfg)
    cfg = cfg or Config
    local kind = Shops.personaKey(counter)
    return cfg.AIClerks.Kinds[kind] or cfg.AIClerks.Kinds.quickie
end

-- The character sheet dps-ainpcs keeps for this clerk.
function ShopAI.definition(counter, salt, cfg)
    local k = ShopAI.kindOf(counter, cfg)
    local name = ShopAI.clerkName(counter, salt, cfg)
    local c = counter.coords
    return {
        id = ShopAI.npcId(counter.id),
        name = name,
        voice = k.voice,
        trustCategory = 'civilian',
        homeLocation = { x = c.x, y = c.y, z = c.z, w = counter.heading or 0.0 },
        systemPrompt = ('Your name is %s. You work at %s. %s You are behind the counter at work, so you keep it short and '
            .. 'get back to the next customer. You only sell what the shelves list says; if they want something else, '
            .. 'tell them where it is not, not where it is. You never hand over money or goods for free.'):format(
            name, counter.label or 'a shop', k.who),
        voiceSamples = k.samples,
        calibration = 'A normal customer gets normal service. A mask, a gun in hand or a fresh robbery changes that: '
            .. 'you get careful, short and ready to hit the alarm, but you do not start a fight over words.',
    }
end

local function money(n) return '$' .. tostring(math.floor(n or 0)) end

-- Live facts for one reply. f = {
--   state = 'idle'|'reacting'|'aftermath'|..., night = bool,
--   store = { name, owned = bool, items = { { label, price, amount } } } or nil,
--   player = { masked = bool, armed = bool, weapon = string|nil, regular = bool } }
function ShopAI.contextText(counter, f)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(('You are at the counter of %s.'):format(counter.label or 'the shop'))
    if f.night then add('It is the middle of the night shift.') end
    if f.state == 'aftermath' then
        add('This store was robbed within the last hour. You are shaken, jumpy and you do not trust strangers right now.')
    elseif f.state and f.state ~= 'idle' then
        add('Something bad is happening in the store right now. You are scared.')
    end
    if f.store then
        if f.store.owned then
            add(('The store is %s. It has an owner; you work for them.'):format(f.store.name or 'privately owned'))
        else
            add('Nobody has bought this store yet; it is for sale at the office if anyone asks.')
        end
        local items = f.store.items or {}
        if #items > 0 then
            local parts = {}
            for i = 1, math.min(#items, 12) do
                local it = items[i]
                parts[#parts + 1] = it.amount and ('%s %s (%d left)'):format(it.label, money(it.price), it.amount)
                                               or ('%s %s'):format(it.label, money(it.price))
            end
            add('On the shelves: ' .. table.concat(parts, ', ') .. '.')
        else
            add('The shelves are empty. Nothing to sell until the owner restocks.')
        end
    end
    local p = f.player or {}
    if p.masked then add('The person talking to you is wearing a mask. That makes you very uneasy; you want it off before you help them.') end
    if p.armed then add(('The person talking to you has a %s out in their hand. You want it put away. Now.'):format(p.weapon or 'weapon')) end
    if p.regular then add('You have seen this customer before; they are a regular.') end
    return table.concat(lines, '\n')
end

-- Should the clerk keep an eye on this player? Returns a reason or nil. w = { masked, armed, secondsHere, bought }
function ShopAI.watchReason(w, cfg)
    cfg = cfg or Config
    if w.armed then return 'armed' end
    if w.masked then return 'masked' end
    if not w.bought and (w.secondsHere or 0) >= cfg.AIClerks.Watch.loiterSeconds then return 'loitering' end
    return nil
end
