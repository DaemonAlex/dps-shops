# dps-shops

Shop clerk NPCs for a Qbox FiveM server. Clerks stand at named counters, greet
and chat with customers using in-game voice lines, and react when threatened.
This is layer 1 of the project: clerks only. Player-owned shops come later
(see Roadmap).

## What the clerks do

Every clerk stands at one fixed counter, spawned only for players who walk
close enough, and despawned again once everyone backs off.

**Greeting and chatter.** The first time a player crosses the greet ring
around a counter, the clerk looks at them and plays one greeting voice line.
While the player stays in that ring, the clerk has a chance (30%, checked
once per chatter interval) to play an idle chatter line. All of it is the
game's built-in ambient speech system played through the ped's own voice —
there is no text, no chat message, and nothing written to screen. This
matches a voice-only server: nothing here needs to be read.

**Threats.** A threat is either:
- a weapon aimed at the clerk, from inside `Config.ThreatDistance`, held
  steady for `Config.AimSeconds` — checked server-side (the client only
  reports that an aim happened; the server reads the player's actual weapon
  off its own view of that player's ped), or
- a register robbery reported by a store-robbery script through the
  `RobberyThreat` export (see below).

The server decides how the clerk reacts and tells every client at once, so
everyone watching that counter sees the same outcome. There are two
reactions:

- **Submissive.** The clerk throws up their hands, plays a frightened voice
  line, and after `Config.Reaction.handsUpSeconds` drops the hands-up pose
  for a cowed idle stance. The silent alarm still fires (see Police
  dispatch) — a submissive clerk never fights, but always calls it in.
- **Aggressive.** The clerk curses, then after the persona's `drawDelay`
  draws a real weapon (if one can be resolved for the robber who threatened
  them) and fights back with the persona's accuracy. This clerk can kill.
  A clerk who cannot draw (no weapon on the persona, or the robber has
  since left the area) folds into the submissive reaction instead.

A persona with no `weapon` configured (see Personas below) never rolls
aggressive at all — the chance is forced to zero.

The reaction lasts `Config.Reaction.seconds`. An aggressive clerk never
chases a robber further than `Config.Reaction.huntLimit` from the counter;
past that, or once the robber is out of sight, the clerk is planted back
behind the counter, armed, until the window ends. At the end of the window
the clerk returns to work and the counter enters an **aftermath** window
(`Config.Aftermath.seconds`, an hour by default): no greetings, no chatter,
but a jumpier clerk — the next threat on that counter gets `Config.Aftermath.
aggressiveBonus` added to its aggressive chance, whether or not this is the
same clerk (see clerk death and respawn below).

**Death and respawn.** A clerk is invincible except during a reaction or its
immediate aftermath gap. If the owning client reports the clerk's health at
or below 100 (the point at which a ped is dead on the 100–200 scale) while
the counter is in a reacting or aftermath state, the server marks the
counter dead. The body stays for `Config.Reaction.corpseSeconds`, then is
removed. The counter is empty — no clerk, no greeting, no threat — for
`Config.RespawnSeconds` (ten minutes by default), then a new clerk spawns
for the next player who walks up. The replacement clerk inherits the
aftermath flag if the counter was still inside its aftermath window when it
died.

**One clerk per counter.** Ownership of a counter's clerk is a server-side
claim held by exactly one client at a time (whichever player's game spawns
and drives that ped). Every other nearby player sees the same networked ped
over the network — there is never a second clerk, or a clerk that behaves
differently for different onlookers, no matter how many players are near.

## Personas

A counter's `kind` picks a persona from `Config.Personas`, which supplies the
ped models, scenario, voice lines, and (if any) weapon and fight stats.

| Persona | Used for | Default stance | Weapon |
|---|---|---|---|
| `quickie` | convenience stores (24/7-style counters) | can fight (10%, up to 35%) | `WEAPON_PISTOL` |
| `boutique` | clothing shops | never fights | none |
| `mechanic` | garages/mechanic counters | often fights (55%, up to 85%) | `WEAPON_WRENCH` |
| `guncounter` | gun stores | usually fights (70%, up to 95%) | `WEAPON_PUMPSHOTGUN` |
| `pharmacist` | pharmacy/medical counters | never fights | none |
| `roxwood` | Roxwood-region counters | can fight (33%, up to 70%) | `WEAPON_MUSKET` |

"Default stance" is the persona's `aggressive` chance before any bonuses;
"up to" is `aggressiveMax`, the hard ceiling after every bonus is added.

A counter in the `roxwood` region always gets the `roxwood` persona instead
of its `kind`, unless the counter sets a `persona` field of its own — that
field, when present, always wins over both `kind` and region.

## What it is for

A shop with nobody behind the counter feels like a vending machine. This puts a clerk there who
notices you, says hello in their own voice, and reacts when a gun comes out: some put their hands
up, some fight back, and either way a silent alarm can go to the police. Robbing a shop becomes a
scene with a person in it.

## On its own, and with other scripts

**On its own.** With Qbox and `ox_lib`, clerks stand at their counters, greet, chatter and react
to threats. Everything is spoken with the game's own voices. Nothing is written on screen, which
suits a voice-only server.

**With a paid police computer (wasabi_mdt).** A threatened clerk trips a silent alarm that
arrives as a dispatch call. Officers get the shop and the reason without anyone typing it.

**With a store-robbery script.** A register or safe robbery can call the `RobberyThreat` export,
so the clerk reacts to the robbery itself and not only to a gun. It is optional. Without it,
clerks still react to weapons.

**With a shop or inventory script.** Clerks do not sell anything themselves. They stand where
your shop script already has its counter, so the two fit together without either knowing about
the other.

## Requirements

From `fxmanifest.lua`:

- `ox_lib`
- `qbx_core`
- `wasabi_mdt` (for the silent alarm dispatch — see Police dispatch)

Optional:

- A store-robbery script that calls the `RobberyThreat` export before
  sending its own dispatch (see Store-robbery integration). Nothing breaks
  if none is installed; register robberies simply never threaten a clerk.

No database tables and no items are used by this resource.

## Install

1. Copy the `dps-shops` folder into your `resources` tree (or into a bucket
   that is already `ensure`d in `server.cfg`).
2. `ensure dps-shops`, or restart the server if you added it to a bucket
   that is already ensured.
3. Add your counters (next section) — with no counters configured, the
   resource starts, prints its boot line, and does nothing else.

## Adding a counter

Each row in `Config.Counters` is one shop clerk:

```lua
{ id = 'sandy_247', label = 'Sandy Shores 24/7', kind = 'quickie', region = 'sandy',
  coords = vector3(1959.28, 3740.55, 32.34), heading = 300.0 }
```

- `id` — unique key for this counter. Used for claims, statebags, and the
  per-counter robbery cooldown.
- `label` — shown in the dispatch call as the location name.
- `kind` — which persona to use (see Personas), unless `region == 'roxwood'`
  or `persona` overrides it.
- `persona` — optional. Names a persona directly, overriding both `kind`
  and the Roxwood region rule.
- `region` — one of `ls`, `sandy`, `paleto`, `roxwood`. Picks which
  departments get the alarm (`Config.AlarmDepartments`) and, for `roxwood`,
  the default persona.
- `coords` — a `vector3`. This is the **centre** of the clerk's body, taken
  by standing a player at the spot: the client that spawns the ped adjusts
  for the game's foot-anchored placement, and separately probes the ground
  so a slightly-off z still seats the clerk correctly (a probe result too
  far from the configured z is ignored, so a bad probe on a roof or
  basement can't move the clerk at all).
- `heading` — which way the clerk faces (their facing direction while
  working the counter).

A counter left at `vector3(0.0, 0.0, 0.0)` — the placeholder used before a
real spot has been captured — is skipped entirely: no spawn point, no greet
point, no threat point, nothing. Use it as a way to reserve a counter's
row before you have its coordinates.

## Config reference

**Distances** (all in metres/game units)
- `Config.SpawnDistance` (60.0) — a player this close claims and spawns the clerk.
- `Config.DespawnDistance` (90.0) — the clerk despawns only once a player goes this far out. Larger than `SpawnDistance` on purpose (hysteresis), so a player pacing near the spawn ring doesn't make the clerk flicker in and out.
- `Config.GreetDistance` (3.0) — inside this ring, the clerk greets and chatters.
- `Config.ThreatDistance` (8.0) — a weapon aimed at the clerk from further away than this is ignored.

**Timing**
- `Config.AimSeconds` (0.6) — how long an aim must hold steady before it is reported as a threat.
- `Config.ChatterSeconds` (60) — at most one idle chatter line per this many seconds (the code floors this at 5 seconds no matter how low it's set).
- `Config.RespawnSeconds` (600) — how long a counter stays empty after its clerk dies.
- `Config.Reaction.seconds` (120) — how long a reaction (submissive or aggressive) lasts before the clerk returns to work.
- `Config.Reaction.corpseSeconds` (30) — how long a killed clerk's body stays before it's removed.
- `Config.Reaction.huntLimit` (40.0) — how far a fighting clerk will chase a robber from the counter before being pulled back.
- `Config.Reaction.handsUpSeconds` (6) — how long a submissive clerk holds the hands-up pose before dropping to a cowed idle.
- `Config.Aftermath.seconds` (3600) — how long a counter stays jumpy (no greet/chatter, bonus to the next aggressive roll) after a reaction ends.

**Reaction odds**
- `Config.Aftermath.aggressiveBonus` (0.25) — added to the aggressive chance for a threat that happens while the counter is still inside its aftermath window.
- `Config.NightHours` (`from = 22, to = 5`) — the hour range (24-hour, wraps past midnight) that counts as night.
- `Config.NightBonus` (0.15) — added to the aggressive chance during those hours.
- `Config.CrowdBonus` (0.10) — added per extra visible robber beyond the first, capped at two extra robbers (so at most +0.20 from crowd size).

**Alarm departments**
- `Config.AlarmDepartments` — a table keyed by region (`ls`, `sandy`, `paleto`, `roxwood`), each a list of job names that receive the dispatch for that region. See Police dispatch.

**Reaction constants** (per persona, inside `Config.Personas`)
- `peds` — list of ped models this persona can spawn as (one is picked per counter, stably, so the same counter keeps the same model between spawns until a death bumps it).
- `scenario` — the idle scenario the clerk plays while working.
- `greet` / `chatter` / `fright` / `anger` — lists of ambient speech context names played on greeting, idle chatter, a submissive reaction, and the start of an aggressive reaction.
- `aggressive` — base chance (0.0–1.0) this persona rolls aggressive on a threat, before bonuses.
- `aggressiveMax` — hard ceiling on the aggressive chance after every bonus.
- `weapon` — the `WEAPON_*` name drawn on an aggressive reaction, or `nil` if this persona never fights (forces the aggressive chance to 0 regardless of `aggressive`).
- `drawDelay` — milliseconds between the anger line and the weapon coming out.
- `accuracy` — the ped accuracy value (0–100) set on the clerk while fighting.
- `alarmDelay` — milliseconds after the reaction starts before the silent alarm dispatch fires.

**Personas**
- `Config.Personas` — the table described above, keyed by persona name.

**Counters**
- `Config.Counters` — the list described in "Adding a counter" above.

**Debug**
- `Config.Debug` (false) — prints extra boot and threat lines to the server console.

### Boot sanity warnings

At boot, `dps-shops` prints one info line with the counter and persona count,
then checks the config and prints a warning for each problem it finds:

- *"GreetDistance is larger than SpawnDistance"* — the greet ring reaches
  past the ring that spawns the clerk in the first place, so a player could
  be greeted before there's anyone there.
- *"ThreatDistance is larger than SpawnDistance"* — a threat could be aimed
  from where no clerk has spawned yet.
- *"DespawnDistance is smaller than SpawnDistance"* — the clerk would spawn
  and despawn on the same spot (no hysteresis at all).
- *"ChatterSeconds is below 5"* — idle lines would overlap; the code floors
  the actual delay at 5 seconds regardless, so this is a config cleanup
  reminder, not a live problem.
- *"persona X: aggressive is above aggressiveMax"* — that persona's base
  chance already exceeds its own ceiling.
- *"persona X: weapon Y is not a WEAPON_ name"* — a typo'd or non-standard
  weapon name on that persona.
- *"counter X: no persona for kind Y"* — that counter's `kind` (or
  `persona`, or the Roxwood default) doesn't match any key in
  `Config.Personas`, so it will fall back to `quickie` at runtime.

These warnings are printed once at boot and do not stop the resource from
starting.

## How the odds work

The aggressive chance for a given threat is built up from the persona's
base rate, then capped at the persona's ceiling:

1. Start with `persona.aggressive`.
2. If the threat happens during `Config.NightHours`, add `Config.NightBonus`.
3. Add `Config.CrowdBonus` once per extra robber beyond the first, up to two
   extra robbers (so 0, 1, or 2 robbers beyond the first add 0, +0.10, or
   +0.20).
4. If the counter is still inside its aftermath window, add
   `Config.Aftermath.aggressiveBonus`.
5. Cap the total at `persona.aggressiveMax`.
6. A persona with no `weapon` always returns 0, regardless of the above.

**Worked example** — a `mechanic` persona (`aggressive = 0.55`,
`aggressiveMax = 0.85`), threatened at 2 AM (night) by two robbers
(one extra beyond the first), on a counter with no aftermath running:

```
0.55 (base)
+ 0.15 (night)
+ 0.10 (one extra robber)
= 0.80, capped at 0.85 -> 0.80
```

That counter has an 80% chance of rolling aggressive for that threat.

## Police dispatch

The silent alarm goes out through `wasabi_mdt`'s `CreateDispatch` export (the
call is skipped, harmlessly, if `wasabi_mdt` isn't started). It fires after
the persona's `alarmDelay`, for both reaction kinds — an aggressive clerk
still hits the alarm on the way to fighting back.

Departments are picked by the counter's `region` from `Config.
AlarmDepartments`: `ls`, `sandy`, and `paleto` all page `police`, `bcso`, and
`sasp`. A region not listed falls back to the `ls` list. Add a line for a region to page
other departments.

The dispatch is a `robbery` type, code `10-31`, titled `Silent alarm:
<counter label>`, with the description `The clerk hit the alarm. Robbery in
progress.`, priority 1, and metadata marking one suspect with weapons
involved and no injuries reported.

## Store-robbery integration (optional)

Any script that runs a register robbery can call the server export
`RobberyThreat(src)` before sending its own dispatch, so the clerk reacts
(and the shop's own alarm rules apply) instead of the robbery script raising
its own alarm on top.

`RobberyThreat(src)`:

- Takes the source player's server id.
- Finds that player's ped and position; if either is missing, returns
  `false`.
- Finds the nearest configured, placed counter within `Config.
  ThreatDistance + 2.0` of the player. If none is in range, returns `false`.
- Otherwise runs the same accept/refuse path a weapon-aim threat goes
  through — including the state checks (a counter mid-reaction or dead
  refuses) and a **per-counter cooldown of 600 seconds**: a second robbery
  call on the same counter inside that window is refused.
- Returns `true` if the clerk accepted the threat and rolled a reaction
  (submissive or aggressive — the caller isn't told which), `false` if the
  clerk refused for any reason (no counter in range, cooldown, dead,
  mid-reaction, or an unresolved argument).

The caller is expected to send its own dispatch only when this returns
`false` — when it returns `true`, the clerk's own silent alarm (see Police
dispatch) already covers it.

## For developers

**Server export**
- `RobberyThreat(src)` — described above.
- `GetCounterState(id)` — returns the current state string for a counter
  (`idle`, `reacting`, `aftermath`, or `dead`), retiring an aftermath window
  that has already expired before returning it.

**Client-visible statebags**, set on the clerk ped entity:
- `dpsShop` (string) — the counter id this ped belongs to. Set once, at
  registration, and never cleared.
- `reaction` (table or `nil`) — `{ kind = 'aggressive'|'submissive', at =
  <os.time()>, by = <server id of the threatening player>, incident =
  <number> }` while a reaction is live, `nil` once it ends. Any resource can
  read this to know a clerk is mid-reaction.
- `aftermath` (`true` or `nil`) — set while the counter is inside its
  aftermath window.

There is no client event API beyond the statebags above; other resources
that want to poke a clerk (as m-StoreRobbery-style scripts do) should call
the `RobberyThreat` export from their own server-side handler rather than
firing a client event into this resource.

**Running the tests**

From the resource root, with no FiveM instance needed:

```
lua5.4 tests/run.lua
```

This loads `config.lua` and `shared/shops.lua` directly under stock Lua
(with small stubs for `vector3` and `joaat`), then runs every file in
`tests/` (`test_persona.lua`, `test_reaction.lua`, `test_claims.lua`,
`test_config.lua`) and exits non-zero if anything fails.

## Performance notes

- **Nobody near a counter:** just three `ox_lib` points per configured,
  placed counter (spawn ring, greet ring, and the wider despawn/keep ring)
  sitting idle. No threads, no per-frame checks, no ped exists yet.
- **A player near a counter but not aiming:** the `client/threat.lua` point
  callback runs once per frame for a nearby player, and for an unarmed
  player that's exactly one native (`IsPedArmed`) before it returns — the
  common case is intentionally cheap. Chatter is a `SetTimeout` chain, not a
  loop, so it costs nothing between ticks.
- **During a reaction:** the owning client runs a one-second `SetTimeout`
  chain (`watchReaction`) that checks the fighting clerk's target and
  distance, plus whatever the game's own combat AI costs while
  `TaskCombatPed` is active. Every client watching (not owning) the clerk
  pays nothing extra — they just see the networked ped and its statebag.
  All of this stops the moment the reaction ends or the clerk dies.

## Roadmap

Layer 2 is player-owned shops: an owner buys or leases a configured
counter, stock arrives by delivery rather than existing for free, the owner
chooses their clerk's stance (or keeps the default persona behavior from
this layer), and the till is a society account rather than a private
balance.

## License

MIT. See `LICENSE`.

## Recent changes

- **12 November 2026.** README: what it is for, how it works alone and with paid scripts, other DPS scripts.
- **9 November 2026.** New counter: Paleto Hunting Store, a gun-counter clerk.
- **1 November 2026.** Three counters added and waiting for a position: Lester Family Pharmacy, Strawberry Pharmacy and Strawberry Corner Store. A counter with no position set does not spawn a clerk.
- **31 October 2026.** The Roxwood alarm list is gone, because the Roxwood departments no longer exist on DelPerroSands. The `roxwood` persona is still in the config for servers that use it.

## Other DPS scripts

All of these are made for DelPerroSands and run together on one Qbox server. Each one works on
its own. The ones marked "pairs with" do more when both are running.

| Script | What it does |
|---|---|
| [dps-inventory](https://github.com/DaemonAlex/dps-inventory) | The inventory: ox_inventory with equipment slots, backpacks, armour plates and a self status panel, in the DelPerroSands colours. |
| [dps-medical](https://github.com/DaemonAlex/dps-medical) | Patient records, illness and diagnostic tests. A companion to wasabi_ambulance. Pairs with dps-inventory: symptoms and diagnoses show on the status panel. |
| [dps-insurance](https://github.com/DaemonAlex/dps-insurance) | Ties m-Insurance into the MDT, impound, hospital and medical chart. Pairs with dps-medical. |
| [dps-studio](https://github.com/DaemonAlex/dps-studio) | Build rooms, doors and portals in game from one panel (`/studio`), with owners and managers so staff do not have to support them. |
| [dps-fleet](https://github.com/DaemonAlex/dps-fleet) | Vehicle browser and workshop on one panel: extras, liveries and mods for emergency vehicles. |
| [dps-parking](https://github.com/DaemonAlex/dps-parking) | Parking with valet, impound, violations and reserved spots. |
| [dps-vehiclepersistence](https://github.com/DaemonAlex/dps-vehiclepersistence) | Vehicles stay where they were parked. Pairs with dps-parking. |
| [dps-towjob](https://github.com/DaemonAlex/dps-towjob) | Queue-based tow job with jg-mechanic integration. |
| [dps-services](https://github.com/DaemonAlex/dps-services) | Request a tow and follow it live on the lb-phone and lb-tablet. Pairs with dps-towjob. |
| [dps-autoshops](https://github.com/DaemonAlex/dps-autoshops) | Self-service repair shops when no mechanic is on duty. |
| [dps-cityworker](https://github.com/DaemonAlex/dps-cityworker) | City infrastructure job and career. |
| [dps-ainpcs](https://github.com/DaemonAlex/dps-ainpcs) | NPCs you can talk to, with trust, quests and intel. |
| [dps-badpeds](https://github.com/DaemonAlex/dps-badpeds) | Police interaction with NPCs: stops, arrests, intel and jail records. |
| [dps-gangwars](https://github.com/DaemonAlex/dps-gangwars) | Ambient gang NPCs, territory population and war reinforcements. |
| [dps-rotations](https://github.com/DaemonAlex/dps-rotations) | Moves dealers, harvests and other spots on a fixed schedule. |
| [dps-trains](https://github.com/DaemonAlex/dps-trains) | The train system. Pairs with dps-trains-stock, dps-traintools and dps-transitapp. |
| [dps-transitapp](https://github.com/DaemonAlex/dps-transitapp) | Live train arrival boards on the lb-phone. |
| [dps-faceplant](https://github.com/DaemonAlex/dps-faceplant) | City help, reports and staff tools on the lb-phone and lb-tablet. |
| [dps-chat](https://github.com/DaemonAlex/dps-chat) | A command box for voice-only servers. No chat feed. |
| [dps-filmmode](https://github.com/DaemonAlex/dps-filmmode) | One key hides every HUD layer and gives a smooth free camera for recording. |
