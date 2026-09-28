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
    local list = persona.peds
    if #list == 0 then return nil end
    local h = salt or 0
    for i = 1, #counterId do h = (h * 31 + counterId:byte(i)) % 2147483647 end
    return list[(h % #list) + 1]
end
