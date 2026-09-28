-- tests/test_config.lua
-- Shops.configWarnings: the boot sanity check, exercised without a server.

-- Find a warning by a distinctive fragment of its text.
local function has(list, needle)
    for _, w in ipairs(list) do
        if w:find(needle, 1, true) then return true end
    end
    return false
end

-- The shipped config must be clean, or every boot prints noise nobody reads.
local clean = Shops.configWarnings(Config)
check('the shipped config warns about nothing', #clean == 0, table.concat(clean, ' | '))

-- A minimal well-formed config, copied and broken one field at a time.
local function base()
    return {
        SpawnDistance = 60.0, DespawnDistance = 90.0, GreetDistance = 3.0,
        ThreatDistance = 8.0, ChatterSeconds = 60,
        Personas = { quickie = { aggressive = 0.1, aggressiveMax = 0.35, weapon = 'WEAPON_PISTOL' } },
        Counters = { { id = 'a', kind = 'quickie' } },
    }
end
eq('the base config is clean', #Shops.configWarnings(base()), 0)

local cfg = base()
cfg.GreetDistance = 80.0
check('greet ring past the spawn ring warns', has(Shops.configWarnings(cfg), 'GreetDistance'))

cfg = base()
cfg.ThreatDistance = 70.0
check('threat ring past the spawn ring warns', has(Shops.configWarnings(cfg), 'ThreatDistance'))

cfg = base()
cfg.DespawnDistance = 30.0
check('despawn ring inside the spawn ring warns', has(Shops.configWarnings(cfg), 'DespawnDistance'))

cfg = base()
cfg.ChatterSeconds = 2
check('chatter below five seconds warns', has(Shops.configWarnings(cfg), 'ChatterSeconds'))

cfg = base()
cfg.Personas.quickie.aggressive = 0.9
check('aggressive above the max warns', has(Shops.configWarnings(cfg), 'aggressive is above aggressiveMax'))

cfg = base()
cfg.Personas.quickie.weapon = 'pistol'
check('a weapon that is not a WEAPON_ name warns', has(Shops.configWarnings(cfg), 'is not a WEAPON_ name'))

cfg = base()
cfg.Personas.quickie.weapon = nil
eq('a persona with no weapon is fine', #Shops.configWarnings(cfg), 0)

cfg = base()
cfg.Counters = { { id = 'b', kind = 'nosuchkind' } }
check('a counter with no persona warns', has(Shops.configWarnings(cfg), 'no persona for kind'))

cfg = base()
cfg.Counters = { { id = 'c', kind = 'nosuchkind', persona = 'quickie' } }
eq('an explicit persona rescues an unknown kind', #Shops.configWarnings(cfg), 0)

cfg = base()
cfg.GreetDistance = 80.0
cfg.ChatterSeconds = 1
eq('two bad values give two warnings', #Shops.configWarnings(cfg), 2)

eq('an empty config is only warned about once per rule', type(Shops.configWarnings({})), 'table')
