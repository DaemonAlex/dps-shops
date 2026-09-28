Shops = {}

function Shops.regionOf(counter)
    return (counter and counter.region) or 'ls'
end

function Shops.alarmDepartments(region, cfg)
    cfg = cfg or Config
    return (cfg.AlarmDepartments and cfg.AlarmDepartments[region]) or cfg.AlarmDepartments.ls
end

-- A counter with SPOT placeholder coords is not on the map yet: no points, no
-- clerk, no threats. One test instead of five copies of the same comparison.
function Shops.isPlaced(counter)
    local c = counter and counter.coords
    if not c then return false end
    return not (c.x == 0.0 and c.y == 0.0 and c.z == 0.0)
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

-- A client's robber count is advisory; keep it inside the range the crowd bonus
-- can actually use (one extra robber is +CrowdBonus, two or more is the cap).
function Shops.clampRobbers(n)
    n = math.floor(tonumber(n) or 1)
    if n < 1 then return 1 end
    if n > 4 then return 4 end
    return n
end

-- One robbery-hook threat per counter per ten minutes.
Shops.RobberyCooldown = 600

-- The melee group, by name. The server cannot call GetWeapontypeGroup (it is not
-- in the server native table), so the gun flag is derived from this list on both
-- sides instead. A weapon missing from the list simply counts as a gun.
Shops.MeleeWeapons = {
    'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_NIGHTSTICK', 'WEAPON_HAMMER', 'WEAPON_BAT',
    'WEAPON_GOLFCLUB', 'WEAPON_CROWBAR', 'WEAPON_BOTTLE', 'WEAPON_DAGGER', 'WEAPON_HATCHET',
    'WEAPON_KNUCKLE', 'WEAPON_MACHETE', 'WEAPON_FLASHLIGHT', 'WEAPON_SWITCHBLADE',
    'WEAPON_POOLCUE', 'WEAPON_WRENCH', 'WEAPON_BATTLEAXE', 'WEAPON_STONE_HATCHET',
    'WEAPON_CANDYCANE', 'WEAPON_ACIDPACKAGE',
}

local meleeHashes
function Shops.isMeleeHash(hash)
    if not meleeHashes then
        meleeHashes = {}
        for _, name in ipairs(Shops.MeleeWeapons) do meleeHashes[joaat(name)] = true end
    end
    return meleeHashes[hash] == true
end

-- Collapse an aftermath window that has run out. 'dead' is deliberately left
-- alone: the claim path owns that expiry because it also has to bump the salt.
function Shops.stateOf(state, until_, now)
    state = state or 'idle'
    if state == 'aftermath' and (not until_ or now >= until_) then return 'idle' end
    return state
end

-- The whole accept/refuse decision for a threat, with no natives in it.
-- ctx = { reason = 'aim'|'robbery', armed, state, until_, lastRobberyAt, now }
-- Returns accepted, aftermath, why. An unknown reason always refuses; an 'aim'
-- from an unarmed player always refuses; a counter mid-reaction or dead refuses;
-- a counter still inside its aftermath window accepts AND carries the bonus.
function Shops.threatDecision(ctx)
    ctx = ctx or {}
    local now = ctx.now or 0
    if ctx.reason ~= 'aim' and ctx.reason ~= 'robbery' then return false, false, 'reason' end
    if ctx.reason == 'aim' and not ctx.armed then return false, false, 'unarmed' end
    local state = Shops.stateOf(ctx.state, ctx.until_, now)
    if state == 'reacting' then return false, false, 'reacting' end
    if state == 'dead' then return false, false, 'dead' end
    if ctx.reason == 'robbery' and ctx.lastRobberyAt
        and (now - ctx.lastRobberyAt) < Shops.RobberyCooldown then
        return false, false, 'cooldown'
    end
    return true, state == 'aftermath', 'ok'
end

-- Per-source rate limit: true when the call must be dropped.
function Shops.throttled(last, now, window)
    if not last then return false end
    return (now - last) < (window or 5)
end

-- Config sanity, printed once at boot. Pure: it takes a config table and returns
-- a list of human-readable warnings, so it can be tested without a server.
function Shops.configWarnings(cfg)
    cfg = cfg or Config
    local out = {}
    local function add(s) out[#out + 1] = s end

    if (cfg.GreetDistance or 0) > (cfg.SpawnDistance or 0) then
        add('GreetDistance is larger than SpawnDistance: the greet ring reaches past the spawn ring')
    end
    if (cfg.ThreatDistance or 0) > (cfg.SpawnDistance or 0) then
        add('ThreatDistance is larger than SpawnDistance: a threat can be aimed where no clerk spawns')
    end
    if (cfg.DespawnDistance or 0) < (cfg.SpawnDistance or 0) then
        add('DespawnDistance is smaller than SpawnDistance: clerks will spawn and despawn on the spot')
    end
    if (cfg.ChatterSeconds or 0) < 5 then
        add('ChatterSeconds is below 5: idle lines would overlap (the timer clamps to 5)')
    end

    for key, p in pairs(cfg.Personas or {}) do
        if (p.aggressive or 0) > (p.aggressiveMax or 0) then
            add(('persona %s: aggressive is above aggressiveMax'):format(tostring(key)))
        end
        if type(p.weapon) == 'string' and p.weapon:sub(1, 7) ~= 'WEAPON_' then
            add(('persona %s: weapon %s is not a WEAPON_ name'):format(tostring(key), p.weapon))
        end
    end

    for _, c in ipairs(cfg.Counters or {}) do
        if not (cfg.Personas or {})[Shops.personaKey(c)] then
            add(('counter %s: no persona for kind %s'):format(tostring(c.id), tostring(c.kind)))
        end
    end

    return out
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
