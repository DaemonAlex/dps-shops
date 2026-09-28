Config = {}

Config.Debug = false
Config.SpawnDistance = 60.0        -- a player this close claims and spawns the clerk
Config.DespawnDistance = 90.0      -- the owner this far away deletes it
Config.GreetDistance = 3.0
Config.ChatterSeconds = 60         -- at most one idle line per customer per minute
Config.ThreatDistance = 8.0        -- a weapon aimed at the clerk from further away is ignored
Config.AimSeconds = 0.6            -- how long the aim must hold before it counts
Config.RespawnSeconds = 600        -- a killed clerk comes back after ten minutes
Config.Aftermath = { seconds = 3600, aggressiveBonus = 0.25 }
Config.NightHours = { from = 22, to = 5 }
Config.NightBonus = 0.15           -- added to the aggressive chance at night
Config.CrowdBonus = 0.10           -- per extra visible robber, up to +0.20

-- Departments the silent alarm goes to, by region. Roxwood is its own county.
Config.AlarmDepartments = {
    ls      = { 'police', 'bcso', 'sasp' },
    sandy   = { 'police', 'bcso', 'sasp' },
    paleto  = { 'police', 'bcso', 'sasp' },
    roxwood = { 'rpd', 'rcso' },
}

-- Personas. Speech names are the game's own contexts; the ped model's own voice
-- speaks them, which is where the difference between a shopkeeper, a boutique
-- girl and a mechanic comes from. weapon = nil means the persona never fights.
Config.Personas = {
    quickie = {
        peds = { 'mp_m_shopkeep_01', 's_m_m_ammucountry' },
        scenario = 'WORLD_HUMAN_STAND_MOBILE',
        greet = { 'GENERIC_HI', 'GENERIC_HOWS_IT_GOING' },
        chatter = { 'CHAT_STATE', 'GENERIC_THANKS' },
        fright = { 'GENERIC_FRIGHTENED', 'GENERIC_SHOCKED_HIGH' },
        anger = { 'GENERIC_CURSE_MED' },
        aggressive = 0.10, aggressiveMax = 0.35,
        weapon = 'WEAPON_PISTOL', drawDelay = 1800, accuracy = 25, alarmDelay = 4000,
    },
    boutique = {
        peds = { 'a_f_y_hipster_02', 'a_f_y_business_02', 'a_m_y_hipster_01' },
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        greet = { 'GENERIC_HI', 'GENERIC_HOWS_IT_GOING' },
        chatter = { 'CHAT_STATE' },
        fright = { 'GENERIC_FRIGHTENED', 'SCREAM_TERROR' },
        anger = { 'GENERIC_INSULT_MED' },
        aggressive = 0.0, aggressiveMax = 0.0,
        weapon = nil, drawDelay = 0, accuracy = 0, alarmDelay = 6000,
    },
    mechanic = {
        peds = { 's_m_y_xmech_01', 's_m_m_autoshop_01', 's_m_y_xmech_02' },
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        greet = { 'GENERIC_HI' },
        chatter = { 'GENERIC_HOWS_IT_GOING' },
        fright = { 'GENERIC_SHOCKED_MED' },
        anger = { 'GENERIC_CURSE_HIGH', 'GENERIC_INSULT_HIGH' },
        aggressive = 0.55, aggressiveMax = 0.85,
        weapon = 'WEAPON_WRENCH', drawDelay = 900, accuracy = 40, alarmDelay = 8000,
    },
    guncounter = {
        peds = { 's_m_m_ammucountry', 's_m_y_ammucity_01' },
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        greet = { 'GENERIC_HI' },
        chatter = { 'CHAT_STATE' },
        fright = { 'GENERIC_SHOCKED_MED' },
        anger = { 'GENERIC_WAR_CRY', 'GENERIC_CURSE_HIGH' },
        aggressive = 0.70, aggressiveMax = 0.95,
        weapon = 'WEAPON_PUMPSHOTGUN', drawDelay = 1200, accuracy = 55, alarmDelay = 2500,
    },
    pharmacist = {
        peds = { 's_m_m_doctor_01', 's_f_y_scrubs_01' },
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        greet = { 'GENERIC_HI' },
        chatter = { 'GENERIC_THANKS' },
        fright = { 'GENERIC_FRIGHTENED' },
        anger = { 'GENERIC_CURSE_MED' },
        aggressive = 0.0, aggressiveMax = 0.0,
        weapon = nil, drawDelay = 0, accuracy = 0, alarmDelay = 3000,
    },
    roxwood = {
        peds = { 'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02', 'a_f_m_fatcult_01', 's_m_m_trucker_01' },
        scenario = 'WORLD_HUMAN_SMOKING',
        greet = { 'GENERIC_HI', 'GENERIC_HOWS_IT_GOING' },
        chatter = { 'CHAT_STATE', 'GENERIC_THANKS' },
        fright = { 'GENERIC_FRIGHTENED' },
        anger = { 'GENERIC_CURSE_HIGH', 'GENERIC_WAR_CRY' },
        aggressive = 0.33, aggressiveMax = 0.70,
        weapon = 'WEAPON_MUSKET', drawDelay = 1500, accuracy = 45, alarmDelay = 5000,
    },
}

-- Counters. kind picks the persona (region 'roxwood' overrides any kind with the
-- roxwood persona unless persona is set explicitly). coords = where the clerk
-- stands, heading = which way they face the customer.
Config.Counters = {
    { id = 'sandy_247',      label = 'Sandy Shores 24/7',   kind = 'quickie',  region = 'sandy',   coords = vector3(1959.28, 3740.55, 32.34), heading = 300.0 },   -- SPOT: counter spot inside the Sandy 24/7 (shop at 1961.48, 3739.96)
    { id = 'rox_baitshop',   label = 'Roxwood Bait Shop',   kind = 'quickie',  region = 'roxwood', coords = vector3(0.0, 0.0, 0.0), heading = 0.0 },              -- SPOT: Damon /spot rox_baitshop
    { id = 'ls_binco_straw', label = 'Binco Strawberry',    kind = 'boutique', region = 'ls',      coords = vector3(75.85, -1392.61, 29.38), heading = 180.0 },    -- SPOT: confirm the counter spot
}
