Shops = {}

function Shops.regionOf(counter)
    return (counter and counter.region) or 'ls'
end

function Shops.alarmDepartments(region, cfg)
    cfg = cfg or Config
    return (cfg.AlarmDepartments and cfg.AlarmDepartments[region]) or cfg.AlarmDepartments.ls
end

function Shops.counterById(cfg, id)
    for _, c in ipairs((cfg or Config).Counters or {}) do
        if c.id == id then return c end
    end
    return nil
end

-- Roxwood counters speak Roxwood unless the counter names its persona.
function Shops.personaKey(counter)
    if not counter then return 'quickie' end
    if counter.persona then return counter.persona end
    if counter.region == 'roxwood' then return 'roxwood' end
    return counter.kind or 'quickie'
end

function Shops.persona(counter, cfg)
    cfg = cfg or Config
    return cfg.Personas[Shops.personaKey(counter)] or cfg.Personas.quickie
end

-- A stable pick per counter so the same clerk works the same counter (until a respawn).
function Shops.pedFor(persona, counterId, salt)
    local list = persona and persona.peds
    if not list or #list == 0 then return nil end
    local h = salt or 0
    for i = 1, #counterId do h = (h * 31 + counterId:byte(i)) % 2147483647 end
    return list[(h % #list) + 1]
end

function Shops.isNight(hour, cfg)
    local n = (cfg or Config).NightHours
    if n.from > n.to then return hour >= n.from or hour <= n.to end
    return hour >= n.from and hour <= n.to
end

-- Rounded to 6 decimal places so additive decimal bonuses (0.10, 0.15, 0.25 ...)
-- land on the exact values the config/tests expect instead of drifting on the
-- last bit of an IEEE-754 double (e.g. 0.10 + 2*0.10 landing one ULP off 0.30).
local function round6(x) return math.floor(x * 1e6 + 0.5) / 1e6 end

function Shops.aggressiveChance(persona, ctx, cfg)
    cfg = cfg or Config
    if not persona.weapon then return 0 end
    local chance = persona.aggressive or 0
    if Shops.isNight(ctx.hour or 12, cfg) then chance = chance + (cfg.NightBonus or 0) end
    local extra = math.max(0, math.min((ctx.robbers or 1) - 1, 2))
    chance = chance + extra * (cfg.CrowdBonus or 0)
    if ctx.aftermath then chance = chance + (cfg.Aftermath.aggressiveBonus or 0) end
    return round6(math.min(chance, persona.aggressiveMax or 1))
end

function Shops.rollReaction(persona, ctx, rnd, cfg)
    local chance = Shops.aggressiveChance(persona, ctx, cfg)
    return ((rnd or math.random)() < chance) and 'aggressive' or 'submissive'
end

Shops.Claims = {}
Shops.Claims.__index = Shops.Claims
function Shops.Claims.new() return setmetatable({ owner = {} }, Shops.Claims) end
function Shops.Claims:claim(id, src)
    if self.owner[id] then return false end
    self.owner[id] = src
    return true
end
function Shops.Claims:release(id, src)
    if self.owner[id] ~= src then return false end
    self.owner[id] = nil
    return true
end
function Shops.Claims:ownerOf(id) return self.owner[id] end
function Shops.Claims:bySource(src)
    local out = {}
    for id, s in pairs(self.owner) do if s == src then out[#out + 1] = id end end
    return out
end
