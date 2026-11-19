Config = {}

Config.Debug = false               -- extra boot/threat lines in the console
Config.SpawnDistance = 60.0        -- a player this close claims and spawns the clerk
Config.DespawnDistance = 90.0      -- and only deletes it again this far out (hysteresis)
Config.GreetDistance = 3.0
Config.ChatterSeconds = 60         -- at most one idle line per customer per minute (floor 5)
Config.ThreatDistance = 8.0        -- a weapon aimed at the clerk from further away is ignored
Config.AimSeconds = 0.6            -- how long the aim must hold before it counts
Config.RespawnSeconds = 600        -- a killed clerk comes back after ten minutes
Config.Aftermath = { seconds = 3600, aggressiveBonus = 0.25 }

-- How a reaction plays out once the server has rolled it.
Config.Reaction = {
    seconds = 120,          -- the clerk is out of position this long, then goes back to work
    corpseSeconds = 30,     -- a killed clerk's body lies there this long, then the counter is empty
    huntLimit = 40.0,       -- a fighting clerk never chases further than this from his counter
    handsUpSeconds = 6,     -- hands held up this long before the head goes down
}
Config.NightHours = { from = 22, to = 5 }
Config.NightBonus = 0.15           -- added to the aggressive chance at night
Config.CrowdBonus = 0.10           -- per extra visible robber, up to +0.20

-- Departments the silent alarm goes to, by region. Roxwood is its own county.
Config.AlarmDepartments = {
    ls      = { 'police', 'bcso', 'sasp' },
    sandy   = { 'police', 'bcso', 'sasp' },
    paleto  = { 'police', 'bcso', 'sasp' },
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
    -- DPS 2026-11-09: Paleto hunting store (Prompt MLO at the Bayview Lodge), the huntingstore business. Damon /spot #256 "counter clerk".
    { id = 'paleto_hunting',  label = 'Paleto Hunting Store', kind = 'guncounter', region = 'paleto', coords = vector3(-674.12, 5835.28, 17.34), heading = 53.4 },
    -- DPS 2026-11-01 PHARMACY COUNTERS (Damon: "cool we can add those locations"). The three new
    -- pharmacy MLOs are RSC7 binary, so their interiors carry no readable coordinates: these wait
    -- on a /spot from Damon, same as rox_baitshop did. Persona 'pharmacist' already exists.
    { id = 'pharm_lester',   label = 'Lester Family Pharmacy', kind = 'pharmacist', region = 'ls',    coords = vector3(0.0, 0.0, 0.0), heading = 0.0 },   -- SPOT: /spot pharm_lester  (downtown, block dt1_25)
    { id = 'pharm_dip',      label = 'Strawberry Pharmacy',    kind = 'pharmacist', region = 'ls',    coords = vector3(0.0, 0.0, 0.0), heading = 0.0 },   -- SPOT: /spot pharm_dip     (Strawberry, block ss1_12)
    { id = 'dip_corner_store', label = 'Strawberry Corner Store', kind = 'quickie', region = 'ls',  coords = vector3(0.0, 0.0, 0.0), heading = 0.0 },   -- SPOT: /spot dip_store    (next door to the pharmacy)
}

-- AI clerks (step 3). Talking goes through dps-ainpcs: the model, voice, memory, trust and limits are its settings,
-- not these. Here is only who each kind of clerk is. Off, or dps-ainpcs not running: clerks greet and react as before.
Config.AIClerks = {
    Enabled = true,
    Watch = {                       -- clerks keep an eye on people
        loiterSeconds = 120,        -- this long near the shelves without buying: the clerk watches and checks in
        radius = 10.0,              -- how close counts as "in the shop"
        lineCooldown = 45,          -- seconds between the clerk's remarks to the same player
    },
    -- names are picked per counter and stay the same (until the clerk is replaced)
    Names = {
        quickie    = { 'Raj', 'Dennis', 'Tony', 'Marisol', 'Gus', 'Hector', 'Linda', 'Omar' },
        boutique   = { 'Brianna', 'Jade', 'Tyler', 'Sienna', 'Marco' },
        mechanic   = { 'Big Earl', 'Dusty', 'Ramon', 'Kev' },
        guncounter = { 'Hank', 'Wade', 'Cody', 'Darlene' },
        pharmacist = { 'Dr. Patel', 'Gloria', 'Mr. Kim' },
    },
    Kinds = {
        quickie = {
            voice = 'male_street',
            who = 'You work the till at a small 24/7 convenience store. Long shifts, bad coffee, you have seen every kind of customer. You are polite to people who are polite, short with people who waste your time, and you keep one eye on anyone acting shady.',
            samples = { "Pump four? Nah, we don't do pumps. Snacks, smokes, that's it.", "You buying that or just holding it?",
                        "Hey. Cold drinks in the back, coffee's fresh. Ish.", "Card or cash? Machine's slow, give it a sec." },
        },
        boutique = {
            voice = 'female_young',
            who = 'You work the floor at a clothing store. Friendly, a bit bored, quick to hype a fit. You notice who is browsing and who is stuffing things in a bag.',
            samples = { "Oh that colour is so you. Fitting rooms are in the back.", "Let me know if you need a size, okay?",
                        "We just got new stuff in on the left wall." },
        },
        mechanic = {
            voice = 'male_gruff',
            who = 'You run the counter at a garage. Gruff, honest, no patience for tyre-kickers. You talk prices straight and you do not get pushed around.',
            samples = { "What's it doing? Don't tell me 'a noise', everything makes a noise.", "Parts are parts. Labour's extra.",
                        "You touch my tools, you buy my tools." },
        },
        guncounter = {
            voice = 'male_old',
            who = 'You work a gun counter. Calm, watchful, by-the-book: licence first, no exceptions. You have a weapon under the counter and everyone knows it.',
            samples = { "Licence on the counter first, then we talk.", "Muzzle down, friend. Always.",
                        "That one's a good pick. Recoil's soft." },
        },
        pharmacist = {
            voice = 'female_mature',
            who = 'You work the pharmacy counter. Kind, careful, professional. You never hand anything over without the right paperwork and you notice people who seem desperate.',
            samples = { "Do you have a prescription with you?", "Take it with food, and no driving tonight.",
                        "Anything else I can help you with today?" },
        },
    },
}
