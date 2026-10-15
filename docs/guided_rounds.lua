-- HD2-Addon: mods/cancan2333/guided_rounds
-- Author: cancan2333 & SoS2430
-- Mod: Guided Rounds v1.8.5
--
-- WHAT v4.13 DOES - THE CLUSTER MODE GOES BACK TO FACTORY, FLAK STAYS GUIDED
--   The user asked for exactly this: put the launcher's ammunition back to
--   normal and keep the tracking on the flak round only.  Guiding the cluster
--   round is what took its burst away - the burst belongs to the round, and a
--   borrowed seeker round does not scatter the bomblets - so the cluster fire
--   mode now keeps its factory round, its factory 0.25 s fuse, its factory
--   burst and its 25 bomblets, and the bomblet row is left alone too.  Only the
--   flak fire mode gets the borrowed seeker (launcher_seeker), which is the one
--   thing that came out of all this working.  flak_only=1 is shipped; set it to
--   0 to bring the guided swarm back for people who want to experiment.
--
-- WHAT v4.12 FIXES - WE WERE PATCHING THE WRONG ROWS ENTIRELY
--   Live: "高射模式主弹药追踪但 Flak 不产生子弹药；集束模式不追踪且没有 25 颗".
--   The live log showed the two rows this addon had been writing:
--       #312  250 m/s  life 1.500 s  prox 2.00 m   <- we called it "cluster"
--       #311  140 m/s  life 10.00 s  prox 0.00 m
--   Offline says #312 is the FLAK round (type 301: life 1.5, proximity 2.0 m)
--   and #311 is not a rocket at all - it is the Male Agitator's weapon row
--   (rpm 700, type 300: calibre 10, 140 m/s, life 10 s, NO unit at +0x80).
--   So every version up to v4.11 (a) wrote the seeker onto a civilian NPC's
--   gun, (b) never touched the cluster fire mode at all, which is why the
--   cluster round stayed dumb, and (c) picked the flak round as "the cluster
--   round" because of the two rows it had, the flak one had the shorter fuse -
--   and then turned the flak round into 25 darts with no explosion left, which
--   is exactly "Flak 不产生子弹药".
--   The +576 field we took for "the other fire mode" is simply not that.
--   Both fire modes are now found the way the export proves they can be told
--   apart: theirs are the only two ProjectileSettings rows carrying the
--   launcher's projectile unit.  Cluster = the timed one (no proximity fuse),
--   flak = the proximity one.  See launcher_rows() and PL.scan() below.
--
-- WHAT v4.11 DOES - THE CLUSTER MODE BECOMES A GUIDED SWARM
--   A projectile spawned by an explosion can never carry a seeker (that is
--   structural, see the airburst section), but one spawned by a WEAPON can -
--   so stop spawning them from the explosion and let the weapon do it: num_projectiles (+0x1C) is the shotgun field and one shipped row already
--   carries 25.  The cluster burst is removed at the same time (both
--   explosion_type_on_impact +0x90 and explosion_type_expire +0x9C go to 0),
--   otherwise each of the 25 darts would detonate and spawn 25 more.  Each
--   dart keeps the borrowed seeker and is bound to its OWN enemy, taken round
--   robin over the ranked aim cone, so they fan out.  Each dart takes the
--   CLUSTER BOMBLET's DamageInfoType, so 25 guided darts hit for exactly what
--   the factory burst of 25 bomblets hit for.  swarm_count=0 restores the
--   airburst behaviour of v4.10.  The flak row is never touched.
--
-- WHAT v4.10 DOES - THE BURST NOW HAPPENS WHERE THE ROCKET ARRIVES
--   The cluster mode is a plain 0.25 SECOND TIMER, and that is the whole story
--   behind "it goes off too early".  Offline the launcher has two rocket rows:
--       Cluster  type  94  life 0.25 s  proximity 0.0  -> explosion 286 -> 25 x 227
--       Flak     type 301  life 1.50 s  proximity 2.0  -> explosion 310 -> 25 x  77
--   Same unit, same 250 m/s, and the cluster one carries NO proximity fuse at
--   all: it bursts a quarter of a second after it leaves the tube whatever it
--   borrowed, i.e. about 20 m out.  Blaming the seeker for that was wrong.
--   Now that the rocket itself homes (v4.9), the fix is obvious: give the round
--   time to fly and, optionally, the proximity fuse its sibling already has, so
--   the 25 bomblets land where it arrives.  Two fields: life_time +0x34 and
--   explosion_proximity +0x94 on the cluster rocket's own row.
--   And the bomblets themselves will never home - that is structural now, see
--   the airburst section below: in the whole export there is not one
--   ProjectileSettings row whose unit carries a SeekingMissileComponent, and
--   not one explosion that spawns such a row.
--
-- WHAT v4.9 FIXES - THE ROCKET WAS IN THE MANAGER AND WE IGNORED IT
--   v4.8 was the right idea and still did nothing, and the live log says
--   exactly why:
--     SEEK payload=96  first seen (src=653, ...)
--     SEEK payload=312 first seen (src=653, ...)
--     BURST seeking manager high=7 - payloads seen so far: 312x186 96x58 236x755
--   so the rocket really does reach the seeking manager, carrying the launcher's
--   own weapon id in its source slot - and all 33 bindings in that mission still
--   carried payload 236, the APW-1 round.  The rocket was never bound once.
--   The reason is the "is this mine?" test: it asked ctx.wset[src].leased, i.e.
--   "did WE lease a per-weapon settings row for the weapon that fired this?".
--   The launcher can never have one - two fire modes means its resource row
--   holds an alternate settings index at +576, which the lease gate rejects - so
--   ctx.wset has no entry for it and every rocket was answered with "not mine".
--   v4.9 recognises the rocket by its source weapon id instead, remembered for a
--   few seconds so a round still in flight after you holster the launcher keeps
--   its target, and binds it with the seeker entity launcher_seeker picked.
--   Second change: launcher_seeker is a SEPARATE key from cluster_seeker and
--   defaults to 0, the P-92 warrant.  With the MLS-4X commando entity the burst
--   went off far too early, which smells like the commando missile's own fuse
--   rather than the launcher's; the warrant round carries no such thing, and the
--   rocket has a source weapon, so a TargetLock seeker works on it here even
--   though it never worked on a bomblet.
--
-- WHAT v4.8 DOES - GUIDE THE ROCKET INSTEAD OF THE BOMBLETS
--   Four versions tried to give the 25 bomblets themselves a seeker.  The v4.7
--   live log closed the question: every one of its 89 bindings carried payload
--   236 (the main round), the payload census logged nothing else, and bombs=0
--   for the whole mission - even with the MLS-4X package properly resident.  The
--   burst is spawned by an explosion as lightweight ballistic projectiles: row
--   233's +0x80 decides what they look like (which is why v4.4 visibly swapped
--   them) but no actor carrying a SeekingMissileComponent is ever created, so
--   there is nothing there to home.  Swapping that field again is pointless.
--   What CAN be guided is the rocket that CARRIES the burst - it is a weapon
--   round exactly like the APW-1's, and the lease already proves those work.
--   Its own projectile row keeps the proximity fuse, so it still bursts; it just
--   bursts on top of whatever it flew into.
--   The launcher has two fire modes (Cluster and Flak), which is exactly why its
--   resource row fails the lease gate: +576 holds the index of the SECOND row.
--   So there is no per-weapon copy to write to - both factory rows are patched
--   in place.  The cost is that while this is on it applies to every RL-77 in
--   the session, not only yours, which is why it rides on cluster_guide rather
--   than being always on, and why the factory value goes straight back when you
--   drop the launcher, press F7 or leave.
--
-- WHAT v4.7 FIXED - THE FLICKER AND THE LOG FLOOD
--   The live log of v4.6 (2026-10-03) ended with 3757 pairs of
--     "READY - APW-1 located, guidance armed"
--     "WAIT settings_alternate_settings_not_zero"
--   in 54 seconds, i.e. exactly one of each PER FRAME.  Two bugs:
--   1. note() is called from inside lease(), which runs BEFORE the end of
--      step().  lease() failing did not stop step(), so the very same frame
--      printed WAIT (from lease) and then READY (from the unconditional reset
--      at the end of step()).  Every frame, forever.  Fixed by stamping the
--      frame a WAIT was raised on and only printing READY on a frame with no
--      WAIT at all, plus a 5 s cooldown on both lines so a condition that
--      genuinely flaps cannot flood the log either.
--   2. The RL-77 can never take a per-weapon settings row: its resource row
--      has a non-zero "alternate settings" pointer (it has two fire modes),
--      which the lease gate rejects.  v4.6 retried that every single frame.
--      Fixed by remembering the refusal per weapon id and skipping it.  The
--      launcher does not need the lease anyway - it only has to be in the
--      weapons= list so ctx.rl77_id is set, which is what arms the cluster
--      phase.
--   Both are pure log/state bugs, but 160 file open+write+close per second on
--   a 19 MB log inside the game's own update() is what the user saw as the
--   picture stuttering / flickering.
--   Also fixed: the MLS-4X / Patriot asset request used hd2.weapon(), which
--   only knows PRIMARY weapons.  A support weapon needs hd2.support_weapon()
--   and the exosuit hd2.vehicle(), so the bomblet seeker package was never
--   actually loaded - a bomblet that spawns with a non-resident unit has no
--   SeekingMissileComponent at all, which is the most likely reason it never
--   shows up in the seeking manager.
--   Added: every distinct runtime payload seen in the seeking manager is now
--   logged once, so the next log says outright whether the bomblet registers
--   under a different projectile type than the row we patched.
--
-- APW-1 ANTI-MATERIAL RIFLE - GUIDED ROUNDS THAT LOCK ONTO ENEMIES  (v3.0)
--
-- WHAT v1.x GOT WRONG, AND WHAT THIS VERSION DOES INSTEAD
--   v1.x tried to make the lock reticle appear by hunting two magic values
--   (ability 2541, crosshair pair 16/3) INSIDE the 616-byte settings row that
--   the P-11 Stim Homing addon edits.  The live log proved both are absent
--   there.  They are absent because that row is ProjectileWeaponComponentData:
--
--     +0x00 u32 projectile_type      +0x04..0x10 f32 rounds_per_minute (xyz)
--     +0x28 u64 projectile_entity    <- the P-11 mod writes here (offset 40)
--     ... 616 bytes total
--
--   The reticle lives in a DIFFERENT component: WeaponDataComponentData.
--
--   Offline data (Data/entities/WeaponDataComponentData.json, build 1.006.301):
--
--                       crosshair_type   secondary_crosshair_type
--     P-92 Warrant            16 (=Javelin)      16 (=Javelin)
--     P-33 Missile Pistol     16                 16
--     FAF-14 Spear            16                  0
--     StA-X3 W.A.S.P.         16                  0
--     AR-23 Liberator          4                  0
--     BR-14 Adjudicator        4                  0
--     R-63CS Diligence CS      4                  0
--     APW-1 Anti-Materiel      3                  0
--
--   Every weapon in the game that can lock on has crosshair_type 16
--   (CrosshairWeaponType_Javelin).  The APW-1 has 3.  THAT is the missing
--   piece, and it is not in the row v1.x was editing.
--
-- WHAT THIS ADDON DOES
--   1) +0x28 of the APW's ProjectileWeaponComponentData (cloned into a
--      per-weapon instance slot so the shared resource row is untouched):
--      0 -> 0x8053DA4358971392, the P-92 Warrant projectile.  Its
--      SeekingMissileComponentData has targeting_mode = 2 (TargetLock), so the
--      engine's own lock-on pipeline applies.
--   2) crosshair_type of the APW's WeaponDataComponentData: 3 -> 16, so the
--      Javelin lock reticle is drawn and the native target lock runs.
--      The offset is NOT hardcoded: it is located at runtime by voting across
--      the eight weapons above, so it survives a layout change.
--   3) Damage: the leased round is the P-92's, whose projectile settings row
--      carries DamageInfoType 90.  The APW-1's own round carries 199.  This
--      addon writes 199 over 90 for as long as it is armed, so the APW-1 keeps
--      its vanilla damage.  Restored on disarm / shutdown.
--   4) Fallback: if the engine does not bind a target by itself, this addon
--      binds one (aim cone, enemies only) to the projectile as it spawns,
--      exactly like the published P-11 Stim Homing addon.
--
-- WHAT v3.4 ADDS - AN ADDON-OWNED RETICLE
--   The game's own Javelin reticle could not be switched on: the
--   WeaponDataComponentData LDLD block does not exist in the live process and
--   the content-signature route never confirmed a row.  So the addon now draws
--   its own reticle with the same calls the P-11 Stim Homing addon uses for its
--   orange/green aiming circle:
--       sr.World.create_screen_gui(ui_world,'scale',1,1)
--       sr.Gui.triangle(gui, a, b, c, 100, sr.Color(...))
--   As of v3.5 that attempt is abandoned and the option is OFF by default: the
--   log proved the addon cannot reach the stingray screen-gui API in the live
--   process.  The drawing code stays in the file (dead unless reticle=1) only so
--   it can be retried later; nothing in the guidance pipeline depends on it.

-- WHAT v4.4 ADDS - RL-77 AIRBURST CLUSTER BOMBLETS GET THE SAME SEEKER
--   The launcher has two fire modes and they are ONE settings row:
--       projectile_type                = 301   flak:   life 1.5 s, proximity 2.0
--                                                      -> blast 310 -> 25 x type 77
--       weapon_function_projectile_type=  94   cluster: life 0.25 s
--                                                      -> blast 286 -> 25 x type 227
--   Type 227 is the CLUSTER BOMBLET: calibre 40, speed 25, mass 100,
--   gravity 4.0, life_time 0.0, arming 1.0.  Nothing else in the game spawns it
--   (one explosion row points at it, no weapon fires it), so it can be patched
--   in place instead of cloned.
--   Two writes make it a guided round:
--     +0x80 projectile_unit_path -> the P-92 Warrant projectile entity, the same
--           entity the lease installs.  That is where SeekingMissileComponentData
--           lives; the bomblet keeps its own ProjectileSettings row, so its
--           damage (270) and its blast (7) stay the vanilla ones.
--     +0x34 life_time 0.0 -> cluster_life.  The factory value is zero, and a
--           homing round that never expires is the known leak.
--   They are then bound like any other round, to the target the launcher itself
--   is aiming at (its last lock if there was one, otherwise its own muzzle cone),
--   so all 25 bomblets converge on the thing you locked instead of scattering.
--
-- WHAT v4.6 FIXES - THE BOMBLET SEEKS NOTHING BECAUSE IT HAS NO WEAPON TO LOCK
--   WITH.  Live log, one whole mission with the patch applied: 79 bindings and
--   every one of them payload=236, the main rocket.  Not one bomblet - the type
--   the row carries - ever registered in the seeking manager, bombs=0 from start
--   to finish.  The write itself is fine (the row read back with the new unit),
--   so the seeker is the problem, not the patch: the P-92 warrant seeker runs
--   SeekingMissileTargetingMode 2 = TargetLock, and the whole v4.4 idea of
--   "bomblets chase the launcher lock" needs a lock SOURCE.  A bomblet is
--   spawned by an explosion; there is no weapon behind it, so nothing ever
--   offers it a target and the seeker never switches on.
--   The fix is a seeker that acquires by itself.  Offline the game ships 27
--   SeekingMissileComponentData entities and four targeting modes; the two rows
--   with movement_should_be_processed_by_projectile_system = 1 (the MLS-4X
--   commando missile and the Patriot exosuit rocket, both Guidance) are seekers
--   built to steer a PROJECTILE rather than to fly a missile themselves, which
--   is exactly the shape of a bomblet, so they lead the list.
--   The G-50 Seeker grenade cannot be used as the template: its hash
--   0x2D398D1EC35E0838 appears in the offline export once, as an
--   ExplosiveComponentData with mode 2 = ExplosiveMode_External, and no
--   ProjectileSettings row points at it.  It is an actor with its own AI, not a
--   projectile, so there is no component to transplant.
--   cfg.cluster_seeker now picks one of eight; cluster_autofix stops an old cfg
--   that still says 0 from silently using the one seeker that cannot work.

-- ===================================================================
-- MODULE MAP - what lives where (line numbers move, these names do not)
-- ===================================================================
--   paths + logging ......... ensure_dir  use_flat_dir  log
--   Win32 / ffi plumbing .... kernel  user  rd  write_bytes  write_default_cfg
--   numeric helpers ......... ptr_ok  u32  i32  u64  f32  fbytes  word
--                             num_or  hash8  hexs  hexa
--   caps and bounds ......... LOG_MAX_LINES  SET_ROW_MAX  PUB_MAX
--   engine offsets .......... R                    (game.dll base + fixed offs)
--   data tables ............. TARGETS (enemy hashes)  CLUSTER  WATCH
--                             SEEK_LIST (seeker entities)  SEEKER_ASSET
--   cfg ..................... cfg  the cfg loader  state.save_cfg_key
--   weapon list ............. WEAPONS / WEAPONS_TXT  parse_weapons
--   per-weapon lease ........ resource_row  resolve_settings  lease  sync_leases
--   data-library scans ...... dl_collect  dl_validate  dl_scan  dl.cached
--   phases .................. damage  ballistics  cluster  launcher
--                             PL.phase (airburst)  seeker
--   targeting ............... refresh_targets  LOS  best_for  pick_target
--                             bomb_aim
--   binding ................. publish  bind_projectiles
--   driver .................. phase  step  my_update  shutdown
--   options menu ............ menu_step
--   lock UI ................. reticle_step
-- ===================================================================

local KEY = 'Hd2ApwGuidance3'
local REVISION = 'guided-rounds-v1.8.5'
if rawget(_G, KEY) then return end
local state = { frame = 0, writes = 0, binds = 0, armed = false, leased = false, failures = 0,
                sh_note = {} }
rawset(_G, KEY, state)

local ok_ffi, ffi = pcall(require, 'ffi')
if not ok_ffi or not ffi then return end
pcall(ffi.cdef, [[
    void *GetModuleHandleA(const char *name);
    void *GetProcAddress(void *module, const char *name);
]])

-- On a fresh install the folder under LOCALAPPDATA does not exist yet, and
-- io.open(...,'w') on a missing folder just fails silently - the user ends up
-- with no cfg and no log until they create the folder by hand.  So make it.
-- IMPORTANT: this uses CreateDirectoryA through FFI, never os.execute.  A shell
-- out (cmd.exe / mkdir) is what made the game start to a black screen on at
-- least one machine, so it is gone for good.  If the folder still cannot be
-- made we fall back to plain files in LOCALAPPDATA, which always exists.
local CD = nil
local function ensure_dir(path)
    if not path or not CD then return false end
    local ok = pcall(CD, path, nil)
    return ok == true
end

local OUT_DIR, CFG_PATH, LOG_PATH
local APP_DIR
do
    local b = os.getenv('LOCALAPPDATA')
    if b then
        APP_DIR = b
        OUT_DIR = b .. '\\Hd2ApwGuidance'
        CFG_PATH = OUT_DIR .. '\\apw_guidance.cfg'
        LOG_PATH = OUT_DIR .. '\\ApwGuidance.log'
    end
end
-- last resort: drop the subfolder and write straight into LOCALAPPDATA
local function use_flat_dir()
    if not APP_DIR then return false end
    OUT_DIR = APP_DIR
    CFG_PATH = APP_DIR .. '\\apw_guidance.cfg'
    LOG_PATH = APP_DIR .. '\\ApwGuidance.log'
    return true
end
-- The log is opened, appended to and closed for every single line, so a
-- condition that fires every frame can grow it without bound.  The cap keeps
-- one bad mission from filling the disk; the counter counts lines offered.
local LOG_MAX_LINES = 20000
local lines = 0
local log_dir_ok = nil
local function log(line)
    if not LOG_PATH then return end
    lines = lines + 1
    if lines > LOG_MAX_LINES then return end
    if log_dir_ok ~= true then
        -- keep trying until the folder exists; before the FFI block runs there
        -- is no CreateDirectoryA yet, so the first few lines may be dropped
        if CD then ensure_dir(OUT_DIR) end
        local probe = LOG_PATH and io.open(LOG_PATH, 'a') or nil
        if probe then probe:close(); log_dir_ok = true else return end
    end
    pcall(function()
        local f = io.open(LOG_PATH, 'a')
        if f then f:write(os.date('%H:%M:%S') .. ' ' .. line .. '\n'); f:close() end
    end)
end
if rawget(_G, 'Hd2ApwGuidance') or rawget(_G, 'Hd2ApwGuidance2') then
    log('WARNING: an older APW-1 guidance addon is loaded too - disable it in the manager')
end

local kernel = ffi.C.GetModuleHandleA('kernel32')
local RPM, WPM, VP, VQ, KS
if kernel ~= nil then
    local p = ffi.C.GetProcAddress(kernel, 'ReadProcessMemory')
    if p ~= nil then RPM = ffi.cast('int (*)(void *, const void *, void *, size_t, void *)', p) end
    p = ffi.C.GetProcAddress(kernel, 'WriteProcessMemory')
    if p ~= nil then WPM = ffi.cast('int (*)(void *, void *, const void *, size_t, void *)', p) end
    p = ffi.C.GetProcAddress(kernel, 'VirtualProtect')
    if p ~= nil then VP = ffi.cast('int (*)(void *, size_t, uint32_t, void *)', p) end
    p = ffi.C.GetProcAddress(kernel, 'VirtualQuery')
    if p ~= nil then VQ = ffi.cast('size_t (*)(const void *, void *, size_t)', p) end
    p = ffi.C.GetProcAddress(kernel, 'CreateDirectoryA')
    if p ~= nil then CD = ffi.cast('int (*)(const char *, void *)', p) end
end
local user = ffi.C.GetModuleHandleA('user32')
if user ~= nil then
    local p = ffi.C.GetProcAddress(user, 'GetAsyncKeyState')
    if p ~= nil then KS = ffi.cast('int16_t (*)(int)', p) end
end
if not RPM or not WPM or not VP then log('memory API unavailable - abort'); return end
-- now that CreateDirectoryA is available, make the folder for real.  If it
-- still will not work, fall back to plain files in LOCALAPPDATA so the cfg and
-- the log always get written somewhere the user can find.
if OUT_DIR then
    ensure_dir(OUT_DIR)
    local probe = io.open(LOG_PATH, 'a')
    if probe then
        probe:close()
    elseif use_flat_dir() then
        log_dir_ok = nil
        log('NOTE: could not use ' .. tostring(APP_DIR) .. '\\Hd2ApwGuidance, '
            .. 'writing the cfg and the log straight into ' .. tostring(APP_DIR))
    end
end
local PROC = ffi.cast('void *', -1)
local buf = ffi.new('uint8_t[65536]')
local got = ffi.new('size_t[1]')
local oldp = ffi.new('uint32_t[1]')
local backp = ffi.new('uint32_t[1]')
local mbi = ffi.new('uint8_t[48]')

-- One definition of "this number could be an address in this process": above
-- the lowest user-space page and below the 47-bit user limit.  Every pointer
-- that comes out of memory, out of the cfg or out of the engine is checked with
-- it, so no path can hand a garbage value to ReadProcessMemory/VirtualProtect.
--
-- It MUST be declared above rd() below.  A local only exists from the line that
-- declares it onwards, so a reference written above it compiles to a GLOBAL
-- read - nil at run time, "attempt to call global 'ptr_ok'" on the first call.
local function ptr_ok(a)
    return type(a) == 'number' and a >= 65536 and a < 0x800000000000
end
-- cfg values come from a file the user may edit by hand.  A missing, infinite
-- or NaN value used to travel all the way into a comparison somewhere else: an
-- infinity in target_interval, for instance, silently stopped the enemy list
-- from ever being rebuilt again.  num_or keeps such a value at the shipped
-- default instead.
local function num_or(v, fallback)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

local function rd(a, n)
    if not ptr_ok(a) then return nil end
    if type(n) ~= 'number' or n < 1 or n > 65536 then return nil end
    got[0] = 0
    if RPM(PROC, ffi.cast('const void *', a), buf, n, got) == 0 then return nil end
    if tonumber(got[0]) ~= n then return nil end
    return ffi.string(buf, n)
end
local function u32(s, o)
    if type(s) ~= 'string' then return nil end
    local a, b, c, d = s:byte(o + 1, o + 4)
    -- string.byte returns fewer values than asked for when the string ends
    -- early, so "a is there but d is not" is possible.  Every byte has to be
    -- present, or the missing one turns the arithmetic below into a Lua error.
    if not a or not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end
local function i32(s, o)
    local v = u32(s, o)
    if not v then return nil end
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end
local function u64(s, o)
    local lo, hi = u32(s, o), u32(s, o + 4)
    if not lo or not hi then return nil end
    return lo + hi * 4294967296
end
local function f32(s, o)
    local a, b, c, d = s:byte(o + 1, o + 4)
    if not d then return nil end
    local sign = (d >= 128) and -1 or 1
    local exp = (d % 128) * 2 + math.floor(c / 128)
    local mant = (c % 128) * 65536 + b * 256 + a
    if exp == 0 then return sign * mant * 2 ^ (-149) end
    if exp == 255 then return nil end
    return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end
local function finite(v)
    return type(v) == 'number' and v == v and math.abs(v) < 100000
end
local function near(a, b, tol)
    return type(a) == 'number' and type(b) == 'number' and math.abs(a - b) <= (tol or 0.01)
end
local function ptr8(a)
    local s = rd(a, 8)
    if not s then return nil end
    local v = u64(s, 0)
    if not ptr_ok(v) then return nil end
    return v
end
local function word(n)
    n = math.floor(n) % 4294967296
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

-- IEEE-754 single -> 4 little endian bytes (no string.pack in this Lua state)
local function fbytes(x)
    x = tonumber(x) or 0
    if x ~= x then x = 0 end
    local sign = 0
    if x < 0 then sign = 1; x = -x end
    local s = sign * 0x80000000
    if x == 0 then return word(s) end
    if x > 3.4028234663852886e38 then return word(s + 0x7F800000) end
    local m, e = math.frexp(x)          -- x = m * 2^e, 0.5 <= m < 1
    local biased = e - 1 + 127
    if biased >= 255 then return word(s + 0x7F800000) end
    if biased <= 0 then                 -- subnormal
        local n = math.floor(x * 2 ^ 149 + 0.5)
        return word(s + (n < 0x800000 and n or 0x7FFFFF))
    end
    local mant = math.floor((m * 2 - 1) * 0x800000 + 0.5)
    if mant >= 0x800000 then mant = mant - 0x800000; biased = biased + 1 end
    return word(s + biased * 0x800000 + mant)
end
local function mul32(a, b)
    local p = ffi.new('uint64_t', a) * ffi.new('uint64_t', b)
    return tonumber(ffi.cast('uint32_t', p))
end
local function intersects(a, b)
    local bit = 1
    while bit <= 0x80000000 do
        if a % (bit * 2) >= bit and b % (bit * 2) >= bit then return true end
        bit = bit * 2
    end
    return false
end
local function hexs(s)
    if type(s) ~= 'string' then return '?' end
    local t = {}
    for i = 1, #s do t[i] = string.format('%02X', s:byte(i)) end
    return table.concat(t)
end
local function hexa(a)
    return type(a) == 'number' and string.format('0x%X', a) or '?'
end
local function write_bytes(a, bytes)
    -- a value that cannot be an address never reaches VirtualProtect: the call
    -- would only fail, and logging it would flood the file on a hot path
    if type(bytes) ~= 'string' or #bytes < 1 or not ptr_ok(a) then return false end
    oldp[0] = 0
    if VP(ffi.cast('void *', a), #bytes, 0x40, oldp) == 0 then
        log('write refused at ' .. hexa(a) .. ' (VirtualProtect failed)')
        return false
    end
    local ok = (WPM(PROC, ffi.cast('void *', a), bytes, #bytes, got) ~= 0) and (tonumber(got[0]) == #bytes)
    VP(ffi.cast('void *', a), #bytes, oldp[0], backp)
    if not ok then
        log('write refused at ' .. hexa(a) .. ' (WriteProcessMemory failed)')
        return false
    end
    if rd(a, #bytes) ~= bytes then
        log('write refused at ' .. hexa(a) .. ' (read-back mismatch)')
        return false
    end
    state.writes = state.writes + 1
    return true
end

-- Every 8 byte resource hash in this file is written the way the cfg file and
-- the community hash tables write it, and turned into the bytes the game
-- actually stores by hash8():
--   hash8('0x89C5493E08CA4207') -> 07 42 CA 08 3E 49 C5 89
-- decimal string -> divided by 256, exact (Lua numbers cap out at 2^53)
local function divmod256(s)
    local q, r = {}, 0
    for i = 1, #s do
        local d = r * 10 + (s:byte(i) - 48)
        local qq = math.floor(d / 256)
        r = d - qq * 256
        q[#q + 1] = string.char(48 + qq)
    end
    local qs = table.concat(q):gsub('^0+', '')
    return (qs == '' and '0' or qs), r
end

-- '0x89C5493E08CA4207' or '9927421484392399367' -> the 8 bytes the game stores
local function hash8(tok)
    if type(tok) ~= 'string' then return nil end
    tok = tok:gsub('^%s+', ''):gsub('%s+$', '')
    if tok == '' then return nil end
    local hex = tok:match('^0[xX](%x+)$')
    if hex then
        if #hex > 16 then return nil end
        if #hex < 16 then hex = string.rep('0', 16 - #hex) .. hex end
        local out = {}
        for i = 15, 1, -2 do out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16)) end
        return table.concat(out)
    end
    if not tok:match('^%d+$') then return nil end
    local s, out = tok, {}
    for _ = 1, 8 do
        local r
        s, r = divmod256(s)
        out[#out + 1] = string.char(r)
    end
    if s ~= '0' then return nil end          -- more than 64 bits
    return table.concat(out)
end


-- ---------------------------------------------------------------- constants
-- manager offsets, folded into one table: the main chunk only gets 200 locals
local R = {
    entity = 0x346bf98, weapon = 0x33266d8, attach = 0x3326dc0,
    health = 0x3326688, faction = 0x3326cb8, player = 0x3326468,
    pose = 0x3326ce0, mission = 0x33266a0, seeking = 0x3326df0,
    publish = 0xfd97e0,
}
local EXE_UNIT_REGISTRY = 0x1a100f0

local FIELD_TARGET = 0xAC08FE53
local FIELD_NODE = 0x69A47345
local GUIDANCE_NODE = 16
local UNBOUND = 0x7fff

local ROW_SIZE = 616
local SET_TBL_OFF = 0xf12e80
local SET_ROW_OFF = 0x21e0
local SET_ENTRIES = 542
-- Highest row index the settings table can hold.  The per-weapon override copy
-- lands in this range and the launcher sweep walks exactly these rows; 272 is
-- the row count, not the 616 byte stride above.
local SET_ROW_MAX = 272

local APW_B = hash8('0x89C5493E08CA4207')          -- APW-1 Anti-Materiel Rifle
local P92_ENTITY_B = hash8('0x8053DA4358971392')    -- P-92 Warrant projectile
-- the entity we lease, overridable from the cfg (seek_entity=).  It is the
-- thing that carries the seeker AND its own mesh, so a different entity is
-- the only way to get a different looking (or a meshless) guided round.
local LEASE = { bytes = P92_ENTITY_B, txt = '0x8053DA4358971392' }
local ZERO8 = string.rep('\0', 8)

-- data library: ProjectileSettings block
local DL_PROJECTILES = 0xBD4042C2
-- data library: WeaponDataComponentData block (djb2 variant of the type name,
-- same hash the other LDLD types use: ProjectileSettings -> 0xBD4042C2).
-- data library: ExplosionSettings block (holds the shrapnel spawn of the R-36)
local DL_EXPLOSION = 0x2AEA2592
local EXP_REC = 144
local PROJ_REC = 272
-- R-36 Eruptor (Model) 0xB6AFF2195568767F
-- The P-92 Warrant WEAPON resource (not its projectile) is
--   string.char(0x2D,0xA4,0x67,0x65,0xFF,0x34,0x89,0xCF)  (0xCF8934FF6567A42D).
-- Its settings row +0 holds the projectile type we want the blast to spawn.
-- Written inline at the one call site: this chunk is at LuaJIT's 200-local cap.
local PROJ_OFF_CALIBRE = 0x18
local PROJ_OFF_SPEED = 0x20
local PROJ_OFF_MASS = 0x24
local PROJ_OFF_DRAG = 0x28
local PROJ_OFF_GRAVITY = 0x2C
local PROJ_OFF_DAMAGE = 0x3C
local PROJ_OFF_UNIT   = 0x80      -- projectile_unit_path: the bullet's mesh
local PROJ_OFF_EXPLODE = 0x90     -- explosion_type_on_impact (derived, see the log)
-- RL-77 Airburst Rocket Launcher (Model) 0x26E40437EA275296, and the factory
-- shape of the cluster bomblet row (ProjectileSettings type 227 in 1.006.301).
-- Nothing is matched by TYPE NUMBER - those drift on every patch - the row is
-- recognised by six floats that only it carries.  Type 77 (the flak shrapnel of
-- the SAME weapon) shares calibre/speed/mass/gravity and differs only in
-- life_time (0.8 vs 0.0) and arming_distance (15 vs 1), which is exactly why
-- those two are part of the gate.
local CLUSTER = {
    weapon = hash8('0x26E40437EA275296'),   -- RL-77 Airburst Rocket Launcher
    life_off = 0x34, arming_off = 0xA0,
    calibre = 40, speed = 25, mass = 100, gravity = 4, life = 0, arming = 1,
    row = nil,
    max_unit = 9,          -- highest index in units[] / names[] below
    -- v4.6: WHICH projectile entity the bomblet borrows.  A bomblet is spawned
    -- by an EXPLOSION, not by a weapon, so there is no weapon to give it a lock.
    -- The live log proves what that costs: with 0 (the P-92 warrant, mode 2 =
    -- TargetLock) the burst never registers in the seeking manager at all - 79
    -- binds in a mission, every single one of them the main rocket, bombs=0 from
    -- start to finish.  A TargetLock seeker with nothing to lock simply never
    -- switches on, so the bomblet has to acquire on its own.
    -- Offline (Data/enums/SeekingMissileTargetingMode.txt plus all 27 rows of
    -- Data/entities/SeekingMissileComponentData.json):
    --   0 Behavior   - the target comes from the actor behaviour (Hulk, Gunship
    --                  and Rocket Devastator rockets use this)
    --   1 Guidance   - the seeker acquires by itself
    --   2 TargetLock - needs a target somebody else locked
    --   3 External   - waits for a target somebody publishes
    -- The two rows flagged movement_should_be_processed_by_projectile_system=1
    -- (1 and 2 here) are seekers that STEER A PROJECTILE instead of moving a
    -- missile themselves, which is exactly what a bomblet is, so they lead.
    -- NOTE on the G-50 Seeker grenade: it is not driven by a
    -- SeekingMissileComponentData at all.  Its hash 0x2D398D1EC35E0838 appears
    -- in the offline export ONCE, as an ExplosiveComponentData whose mode is
    -- 2 <=> ExplosiveMode_External, and no ProjectileSettings row points at it -
    -- the grenade is an actor with its own AI, not a projectile.  Its homing
    -- therefore cannot be transplanted onto a bomblet; the self acquiring
    -- seekers below are the projectile sized equivalent of the same idea.
    units = {
        [0] = hash8('0x8053DA4358971392'),
        [1] = hash8('0x527470C9D5F2B3C7'),
        [2] = hash8('0xA526DC7D89FF696D'),
        [3] = hash8('0xDDDB2910FF2B24E9'),
        [4] = hash8('0xAFD03C31434B6EE5'),
        [5] = hash8('0x9AB148DEEFF42556'),
        [6] = hash8('0x5FC0C53098B1B220'),
        [7] = hash8('0x30FBC4FD513C35E9'),
        -- v4.9: 8 and 9 are the two the Suzuka lock-on MLS-4X mod actually
        -- uses.  Offline they sit in the SAME class as the P-92 warrant -
        -- TargetingMode 2 (TargetLock) and
        -- movement_should_be_processed_by_projectile_system = 1, max_lifetime
        -- 30 s - so they need a target to be published (which is what this
        -- addon does anyway) and they steer the projectile, they do not fly a
        -- missile of their own.  That is exactly why they are the two to try
        -- after 0 for the ROCKET: a Guidance seeker (1 / 2) acquires on its own
        -- and that is what made the cluster burst go off far too early.
        [8] = hash8('0xA1470A4DAB237264'),
        [9] = hash8('0x1A4323835B84CEA7'),    },
    names = {
        [0] = 'P-92 warrant, TargetLock (proven not to home: no weapon to lock with)',
        [1] = 'MLS-4X commando missile, Guidance, steers a projectile',
        [2] = 'Patriot exosuit rocket, Guidance, steers a projectile',
        [3] = 'Mini Missile Silo missile, Guidance (sentry, self acquiring)',
        [4] = 'plain Guidance seeker (moves the missile itself)',
        [5] = 'enemy homing rocket, Behaviour (Hulk / Gunship / Devastator)',
        [6] = 'Behaviour seeker, fast 90 mps, 3 s',
        [7] = 'Vox Engine, External (waits for a published target)',
        [8] = 'P-33 missile pistol round, TargetLock, steers a projectile',
        [9] = 'FAF-14 Spear rocket, TargetLock, steers a projectile',
    },
}
-- (the picker lives next to cfg further down: a local declared there is not
--  visible from up here, Lua resolves locals lexically)
-- P-92 warrant round (ProjectileType 314) and its programmable variant (308)
local P92_DAMAGE_ID = 90
local APW_DAMAGE_ID = 199

-- WeaponDataComponentData voters.  key = 8 byte little-endian model hash,
-- f158 = float at row+0x158 (a stable per-weapon constant used to prove we
-- found the right table and the right stride), xh/sx = the two crosshair ids.

-- Same voters, addressed by ROW INDEX inside the LDLD block (offline export
-- 1.006.301, struct_size 1208, 346 rows).  Used when the hash table that maps
-- model hash -> row index cannot be located; the vote is on the crosshair ids
-- themselves, so it does not depend on any float staying the same.

-- static enemy resource hashes (8 byte little-endian key -> english name)
local TARGETS = {
    [hash8('0x0002BA767DF856F3')] = "Marauder",
    [hash8('0x070BC8D3E18BB8F9')] = "Devastator Gun (Model)",
    [hash8('0x089833D2880D9E06')] = "Incendiary MG Raider",
    [hash8('0x08E6FFC2474287BD')] = "Overseer MK2",
    [hash8('0x09DFB04B2E578BC3')] = "Incendiary Rocket Trooper",
    [hash8('0x09FE0BE51A23396C')] = "Female Agiator",
    [hash8('0x0AB7B92B131C228C')] = "Rupture Charger",
    [hash8('0x0ADC9F9173AD8E1D')] = "Voteless Medium",
    [hash8('0x0CF9B9B95EDFEF81')] = "Elevated Overseer Rifle (Model)",
    [hash8('0x0DB407EDE5603524')] = "Conflagration Devastator Gun (Mode",
    [hash8('0x10081ACEF6163EF6')] = "Bile Warrior",
    [hash8('0x137988CEA16458F7')] = "Hulk Bruiser",
    [hash8('0x16023E554FEE830E')] = "Cyborg Tank LMG",
    [hash8('0x1897BDD32105D2DC')] = "Hulk Scorcher MK2",
    [hash8('0x19806B4FB83FDF7C')] = "Obtruder Weapon (Model)",
    [hash8('0x19E18B46EC55D94A')] = "Stingray",
    [hash8('0x1A7FCDFF98C664B0')] = "Charger",
    [hash8('0x1B5B9AC4F96B36E5')] = "Incendiary Commissar",
    [hash8('0x1C6981CA2FB69508')] = "Factory Strider Gatling MK4",
    [hash8('0x1D8D9AA0502F866E')] = "Predator Hunter Vomit",
    [hash8('0x1E66EE1F6F7FD00E')] = "Hulk Obliterator",
    [hash8('0x1F0A91729C0004E0')] = "Spore Burst Hunter",
    [hash8('0x20B9C7734DAEAD65')] = "Veracitor",
    [hash8('0x212710DA2E8366F5')] = "Crescent Overseer Charge Gun (Mode",
    [hash8('0x215CE160A17BE4CD')] = "Jet Brigade Commissar",
    [hash8('0x257D805CAA7E10C0')] = "Shotgun Trooper",
    [hash8('0x282EB766C1FFA6A1')] = "Gunship",
    [hash8('0x297434E9E8A4CD5A')] = "Gatekeeper Plasma Sniper Left (Mod",
    [hash8('0x2A12104F2853AE16')] = "Rocket Raider",
    [hash8('0x2A346BF4552997E2')] = "Scout Strider HMG (Model)",
    [hash8('0x2D1636F2EE8A6306')] = "Conscript Blade (Model)",
    [hash8('0x2D62A25F36C08F33')] = "Gunship Turret",
    [hash8('0x2ED3696E12A14D4C')] = "Heavy Devastator Gun (Model)",
    [hash8('0x30CF04B2EC8C9BD4')] = "Scout Raider",
    [hash8('0x30F2DEE2333F227A')] = "Jammer Factory Strider",
    [hash8('0x31BAE74D2F064D8D')] = "Annihilator Tank MK2",
    [hash8('0x32541FC4EC7C9CDC')] = "Warrior MK3",
    [hash8('0x32CDEADA234FB8DF')] = "Jet Brigade Hulk Bruiser",
    [hash8('0x336AFDB6F784F639')] = "Warp Ship Shield",
    [hash8('0x33B3E0CE8D179EEC')] = "Jet Brigade Devastator Backpack (M",
    [hash8('0x34DFD23365472E9E')] = "Obtruder",
    [hash8('0x356DE4A7808EF3E3')] = "Vox Engine Gatling Right",
    [hash8('0x36390775D61159EB')] = "Annihilator Tank Fusion Repeater",
    [hash8('0x36AA99CCE5E60146')] = "Bile Spewer",
    [hash8('0x390E6B3D2F26BD70')] = "Factory Strider Gatling MK2 (Left)",
    [hash8('0x397FB7E4883AF100')] = "Reinforced Scout Strider Rocke Rig",
    [hash8('0x3AAFBA89B53B0F63')] = "Factory Strider Gatling (Right)",
    [hash8('0x3AFF5FD7D5450B99')] = "Charger Behemoth",
    [hash8('0x3C7F77F1A7467349')] = "Hivelord Vomit MK2",
    [hash8('0x3D0E03E2D574E1CA')] = "Hunter MK2",
    [hash8('0x3D2FE75B0DC50142')] = "Gatekeeper Plasma Sniper Right (Mo",
    [hash8('0x3E0537D606438FEA')] = "Hulk Scorcher",
    [hash8('0x4019623142351CB6')] = "Trooper MK3",
    [hash8('0x426B3DF007BE9F18')] = "MG Raider Backpack",
    [hash8('0x44458A2C52B002FB')] = "Voteless Heavy",
    [hash8('0x453FE22C634EB30F')] = "Gatekeeper",
    [hash8('0x48C91E42B9F16512')] = "Factory Strider Gatling MK3",
    [hash8('0x495435D51F47411F')] = "Agitator Grenade (Model)",
    [hash8('0x49674794A165EDA8')] = "Shredder Tank Fusion Autocannon",
    [hash8('0x4E342031A9D5C4F9')] = "Leviathan Beam Turret (Model)",
    [hash8('0x4E97FB073BDC7A4B')] = "Warrior MK2 (Captive)",
    [hash8('0x4FB6077F1597691D')] = "Berserker Chainsaw (Model)",
    [hash8('0x51C6132EC1D10E7E')] = "Cyborg Tank Gatling",
    [hash8('0x51EEA86BF6997E4E')] = "Scavenger MK2",
    [hash8('0x52018DEB9AB6827E')] = "Jet Brigade Trooper (Crash)",
    [hash8('0x529DFE4C4C881324')] = "Nursing Spewer Vomit",
    [hash8('0x53D8919D7B8ABD67')] = "Annihilator Tank",
    [hash8('0x543AD246BCB333D4')] = "Radical Shotgun (Model)",
    [hash8('0x54E107DACF6929CB')] = "Berserker MK2",
    [hash8('0x57EED0EAC346CD9D')] = "Incendiary Devastator",
    [hash8('0x57F11209295752B5')] = "Pyro Trooper Backpack (Model)",
    [hash8('0x58B2B86C11369241')] = "Incendiary MG Devastator",
    [hash8('0x5B596A4D21BC91A3')] = "Hulk HMG (Model)",
    [hash8('0x5CA832447445C0BA')] = "Hunter MK3",
    [hash8('0x5D142C3A73EBC634')] = "Barrager Tank Ballistic Missile",
    [hash8('0x6021E22338333D88')] = "Nursing Spewer",
    [hash8('0x604A794EC45BB820')] = "Elevated Overseer",
    [hash8('0x611BA777783B08A2')] = "Vox Engine Cannon Turret",
    [hash8('0x6290E1DEBC0D884B')] = "Cyborg's Grenade (Model)",
    [hash8('0x63DF3D07B7424588')] = "Barrager Tank",
    [hash8('0x64090088502435DD')] = "Shrieker",
    [hash8('0x64BA5F030B114EC1')] = "Raider",
    [hash8('0x672F7DA17F3BA34A')] = "Tentacle",
    [hash8('0x67381F685E9B69A8')] = "Agitator Hand Cannon (Model)",
    [hash8('0x67DC32DCA4F02D33')] = "Fleshmob",
    [hash8('0x68BA814FF35BF19C')] = "Conscript MG (Model)",
    [hash8('0x6A7A54D5FB3A6D17')] = "Factory Strider Gatling MK5",
    [hash8('0x6B202392F4AB605E')] = "Spore Charger",
    [hash8('0x6DAB2EADF5D8B692')] = "Hulk Firebomber",
    [hash8('0x6F91BC8002875E76')] = "Bile Spewer Vomit",
    [hash8('0x705362AD578943F6')] = "Crescent Overseer Mortar Gun (Mode",
    [hash8('0x71B285B6D2B161C9')] = "Conscript Cannon (Model)",
    [hash8('0x728421351D440EBC')] = "Spore Burst Warrior",
    [hash8('0x72A83E49CED6DB3D')] = "Bile Spitter",
    [hash8('0x746A7F3BEDA32699')] = "Male Radical",
    [hash8('0x74E2285C01DA4F71')] = "Warp Ship",
    [hash8('0x767977BD472A62DA')] = "Bile Spewer Artillery",
    [hash8('0x76E9644BCD3F341B')] = "Dragonroach Vomit",
    [hash8('0x78E1497571012C47')] = "Voteless Light",
    [hash8('0x7ACB4BD753B71DE0')] = "Leviathan Beam Turret Right (Model",
    [hash8('0x7B48CACDBACB3881')] = "Trooper MK2",
    [hash8('0x7EA558204D0FFC29')] = "Overseer Shield",
    [hash8('0x7ECE5304F868F6B3')] = "Trooper (No Package)",
    [hash8('0x82A87AD8D595B2BA')] = "Pyro Trooper",
    [hash8('0x8372619B2702D743')] = "War Strider Cannon Left (Model)",
    [hash8('0x843D18D4B5512B63')] = "Factory Strider Cannon Turret",
    [hash8('0x856E9710E45E760F')] = "Jet Brigade Raider",
    [hash8('0x883401AF2A98A5F6')] = "Predator Hunter",
    [hash8('0x8A4DE24951A1726D')] = "Hulk Obliterator Rocket Launcher (",
    [hash8('0x8DBF99607BD8E550')] = "Harvester Arc Weapon (Model)",
    [hash8('0x8F2158C7E969E2AB')] = "Stingray Plasma Cannon (Model)",
    [hash8('0x8F3A6DE385966F9E')] = "Conscript Shotgun (Model)",
    [hash8('0x8FB47DD28B398CF7')] = "Annihilator Tank Heavy Fusion Cann",
    [hash8('0x8FC2784308E9BA99')] = "Hulk Obliterator Flag (Model)",
    [hash8('0x8FF0A839830A7692')] = "Scavenger",
    [hash8('0x9076EEED17FCEE35')] = "Reinforced Scout Strider",
    [hash8('0x91EBD77931110AFC')] = "Heavy Devastator MK3",
    [hash8('0x960B48A421A3FAAA')] = "Dragonroach",
    [hash8('0x9647B00CC3A9D36F')] = "Rocket Devastator",
    [hash8('0x965EAE5A51ACDD4A')] = "Harvester",
    [hash8('0x96BA14C9EBB49CE1')] = "Hulk",
    [hash8('0x972BAAC825D4D165')] = "Annihilator Tank Heavy Fusion Repe",
    [hash8('0x98152772A72F7838')] = "Dropship",
    [hash8('0x9951ECAE4E403070')] = "Conscript Flare Gun (Model)",
    [hash8('0x99870D0755F9CE68')] = "Conscript Rocket Launcher (Model)",
    [hash8('0x9A8A3AAE287B230C')] = "Scavenger MK3",
    [hash8('0x9AB036439F74C115')] = "War Strider Cannon Right (Model)",
    [hash8('0x9C7EF47A463D5327')] = "Overseer Lightspear (Model)",
    [hash8('0x9D8827FED763650E')] = "Male Agitator",
    [hash8('0x9E2E17F2CCCCAFDD')] = "Bile Titan",
    [hash8('0x9E53A0971179344C')] = "Hivelord Vomit MK1",
    [hash8('0x9F57782F00E6ED20')] = "Trooper",
    [hash8('0xA05BD1EC67B3AC4C')] = "Charger Behemoth MK2",
    [hash8('0xA1F37BF2A40FBDE4')] = "Hive Guard",
    [hash8('0xA35207C6F2150806')] = "Rupture Warrior",
    [hash8('0xA381A11C07D3EB94')] = "Rupture Spewer",
    [hash8('0xA4552F97033392F4')] = "Jet Brigade MG Raider",
    [hash8('0xA6A68D8AF177F3A1')] = "Berserker",
    [hash8('0xA71AAFD82C6EBC92')] = "Commissar",
    [hash8('0xA8173FBA5DEC35C3')] = "Reinforced Scout Strider Rocke Lef",
    [hash8('0xAAB438596F5E8FD9')] = "Pouncer",
    [hash8('0xAC60E78435098C9D')] = "Watcher",
    [hash8('0xAE57FCDB49F74E98')] = "Trooper MK2 MG",
    [hash8('0xAE63E525853D7044')] = "Devastator MK3",
    [hash8('0xAF0F9B3A163787A5')] = "Jet Brigade Trooper",
    [hash8('0xB056F8FC74ABA02D')] = "Cannon Trooper",
    [hash8('0xB2A6FA1E4284C7E6')] = "Warrior(Spawned)",
    [hash8('0xB4ED319B39F5457B')] = "MG Raider",
    [hash8('0xB5DBC0C240C921AD')] = "Incendiary Berserker",
    [hash8('0xB846CDCF41967725')] = "Hulk Firebomber Grenade Launcher (",
    [hash8('0xB8580CAC32214FC0')] = "Cyborg Tank Cannon Turret",
    [hash8('0xB92435FBF60F0748')] = "Heavy Devastator MK2",
    [hash8('0xB940C889D77F8219')] = "Jet Brigade Hulk Backpack (Model)",
    [hash8('0xB971B1141E1CBFAC')] = "Factory Strider Scrambler",
    [hash8('0xBB37F12D0F46690F')] = "Hulk Scorcher Saw MK2 (Model)",
    [hash8('0xBC242702FB46B7E7')] = "Vox Engine",
    [hash8('0xBCB3210CF8EF49D3')] = "Conscript Rifle (Model)",
    [hash8('0xBE39E313A1E46BB9')] = "Warrior MK2",
    [hash8('0xBE743B2FAA3A6E26')] = "Jet Brigade Devastator",
    [hash8('0xC222E5F15E289E85')] = "Elevated Overseer Grenade",
    [hash8('0xC2B9EB21B06F8378')] = "Hulk Firebomber Flag (Model)",
    [hash8('0xC39E7FD97E974E5E')] = "Radical Smoke Grenade (Model)",
    [hash8('0xC3C1BBA1F445A81E')] = "Gunship Rocket Pods",
    [hash8('0xC626D2BB495A202D')] = "Devastator",
    [hash8('0xC6449FFD9EA3779C')] = "Shredder Tank",
    [hash8('0xC6A5BB8B319217AC')] = "Harvester Beam (Model)",
    [hash8('0xC8378469E1936877')] = "Hulk Rocket Launcher (Model)",
    [hash8('0xC89ED7AC3E425B25')] = "Hulk Scorcher Saw (Model)",
    [hash8('0xC9AF550ACBEC004C')] = "War Strider HE Grenade",
    [hash8('0xC9BCCCB0A54A82A4')] = "Incendiary Rocket Devastator",
    [hash8('0xCB85E7F7FF8855F4')] = "Harvester Plasma Cannon (Model)",
    [hash8('0xCBB1BA3366009C3A')] = "Female Radical",
    [hash8('0xCBCE5F5F0310EF15')] = "Conscript Pistol (Model)",
    [hash8('0xCC7022FDD172089B')] = "Nursing Spewer MK2",
    [hash8('0xCCAE5264ACD591B7')] = "Bile Spewer MK2",
    [hash8('0xCED70B42C32CBED1')] = "Rupture Spewer Acid Grenade",
    [hash8('0xD1E990BAF22D5A52')] = "Predator Stalker",
    [hash8('0xD1F232A6929E6D44')] = "Incendiary MG Devastator Gun (Mode",
    [hash8('0xD37E8D120D2836E3')] = "Factory Strider",
    [hash8('0xD3CD6F0CA83BB51E')] = "Reinforced Scout Strider Fullcover",
    [hash8('0xD465D9C7F77A07CB')] = "Hivelord",
    [hash8('0xD522FD4748D443A5')] = "Brood Commander",
    [hash8('0xD5792F6856B06BA4')] = "Jet Brigade Berserker",
    [hash8('0xD63FCBFF0851B7AF')] = "Harvester MK2",
    [hash8('0xD6FB1326FC0A95C1')] = "Gatekeeper Plasma Gatling Right (M",
    [hash8('0xD8CBC4A807A6D035')] = "Brawler",
    [hash8('0xD9511E9F6BD62E3F')] = "Hunter",
    [hash8('0xDA40BB347C7447F2')] = "Overseer",
    [hash8('0xDB964631BE1CF501')] = "Spore Burst Scavenger",
    [hash8('0xDCF8E74212FBEE3B')] = "Impaler",
    [hash8('0xDFBACBD977A948DC')] = "Scavenger MK2 (Captive)",
    [hash8('0xE0353177F1329573')] = "Conflagration Devastator",
    [hash8('0xE2E62FDD39407FE3')] = "Jet Brigade Conscript Backpack",
    [hash8('0xE44EC9F9B3FE1D2A')] = "Jet Brigade Hulk Scorcher",
    [hash8('0xE683D2CA5618D74A')] = "Incendiary Raider",
    [hash8('0xE8A244FFA3A48FE4')] = "Harvester Broken Beam (Model)",
    [hash8('0xE8F19A0AA958E46D')] = "Crescent Overseer",
    [hash8('0xEACEE39FA017B495')] = "Warrior",
    [hash8('0xEE00BFE8FF769F70')] = "Scout Strider Cabin (Model)",
    [hash8('0xEE4DEE909FF50D5E')] = "Gatekeeper Plasma Gatling Left (Mo",
    [hash8('0xEF04CB84D097A497')] = "Spore Burst Bile Titan",
    [hash8('0xEF570293245A17C2')] = "War Strider",
    [hash8('0xF196069E7E14C497')] = "Leviathan Beam Turret Left (Model)",
    [hash8('0xF22D027B37BEF107')] = "Leviathan",
    [hash8('0xF2881F5807348116')] = "Vox Engine Gatling Left",
    [hash8('0xF2B4A99D1B0E40C8')] = "Hulk Scorcher Flamer (Model)",
    [hash8('0xF4C0B6C9218FB571')] = "Pyro Trooper Flamer (Model)",
    [hash8('0xF5247DE3ABFB822B')] = "Watcher Arc Weapon (Model)",
    [hash8('0xF540CA9D9D4A422E')] = "Stalker",
    [hash8('0xF66D0BAD8693779A')] = "Rocket Devastator MK2",
    [hash8('0xF79CD8BB654397DF')] = "Alpha Commander",
    [hash8('0xF8131632AA867107')] = "Scout Strider",
    [hash8('0xF8B5A81A86D5D4EB')] = "Heavy Devastator",
    [hash8('0xF96257FCAE258CAA')] = "Defeat Devastator Shield (Model)",
    [hash8('0xFB9937035D652C43')] = "Trooper",
    [hash8('0xFC8DEC78BE8AB47D')] = "Devastator MK2 Spawn",
    [hash8('0xFEB484EE972469F7')] = "Incendiary Devastator Shield (Mode",
    -- added by build_mod.py: Illuminate units missing from the
    -- build-1.006.301 export (source: 绝地潜兵2资源ID.xlsx / 哈希表-整合)
    [hash8('0xCC188F0C80505C6C')] = "Wretch",
    [hash8('0x905809A4C28D8A45')] = "Crusher",
    [hash8('0x0883366204E1CCC5')] = "Gazer",
    [hash8('0xE8E7D998FCBD32F8')] = "Illuminate Tesla Tower",
    [hash8('0x4446E7312B401E69')] = "Illuminate Scrambler Battery",
    -- added by build_mod.py (P16): the OTHER HALF of the tower and the
    -- scrambler. Both are two entities in the sheet, and the row that was
    -- missing is the one a round actually hits.
    [hash8('0x0D382AE7FFEA9D45')] = "Lightning Spire",
    [hash8('0x1445DF29152C9BE2')] = "Illuminate Scrambler",
}

local base, exe_base
do
    local h = ffi.C.GetModuleHandleA('game.dll')
    if h == nil then h = ffi.C.GetModuleHandleA('Game.dll') end
    if h then base = tonumber(ffi.cast('uintptr_t', h)) end
    local e = ffi.C.GetModuleHandleA(nil)
    if e then exe_base = tonumber(ffi.cast('uintptr_t', e)) end
end
if not base then log('game.dll not found - abort'); return end
local PUBLISH_PREFIX = ('48896c241856415641574883ec30488b05a32749024d8bf0448bfa8be9488b70')
    :gsub('..', function(x) return string.char(tonumber(x, 16)) end)
local PUBLISH_OK = (rd(base + R.publish, #PUBLISH_PREFIX) == PUBLISH_PREFIX)
if not PUBLISH_OK then log('WARNING: publish signature at game.dll+0xFD97E0 does not match - fallback binding disabled') end
local PUBLISH = ffi.cast('void (*)(uint32_t, uint32_t, const void *)', base + R.publish)

-- open addressed hash map shared by every manager in this build.
local function slot(map, key, limit)
    local h = rd(map, 20)
    if not h then return nil, nil, nil, 'map_unreadable' end
    local b = u64(h, 0)
    local n, empty, mult = u32(h, 8), u32(h, 12), u32(h, 16)
    if not ptr_ok(b) then return nil, nil, nil, 'map_base' end
    if not n or n == 0 or n > limit then return nil, nil, nil, 'map_size' end
    if key == empty then return nil, nil, nil, 'empty_key' end
    local product = mul32(key, mult)
    local probes = n
    if probes > 128 then probes = 128 end
    for probe = 0, probes - 1 do
        local a = b + 8 * ((product + probe) % n)
        local row = rd(a, 8)
        if not row then return nil, nil, nil, 'map_row_unreadable' end
        local k = u32(row, 0)
        if k == key then
            local v = u32(row, 4)
            return a, row, (v ~= 0xffffffff) and v or nil, n
        end
        if k == empty then return a, row, nil, n end
    end
    return nil, nil, nil, 'probe_limit'
end

local function entity(a)
    local b = rd(a, 24)
    if not b then return nil end
    local id, unit, net, flags = u32(b, 8), u32(b, 12), u32(b, 16), u32(b, 20)
    if not id or not unit or not net or not flags then return nil end
    if id == 0 and unit == 0 and net == 0 then return nil end
    return { address = a, resource = b:sub(1, 8), id = id, unit = unit, net = net, flags = flags }
end

local function bone(unit, node)
    if not exe_base or type(unit) ~= 'number' or type(node) ~= 'number' then return nil end
    if node < 0 or node >= 1024 then return nil end
    local reg = ptr8(exe_base + EXE_UNIT_REGISTRY)
    if not reg then return nil end
    local index = unit % 0x400000
    local generation = math.floor(unit / 0x400000) % 256
    local cb = rd(reg + 0x98, 4)
    if not cb then return nil end
    local count = u32(cb, 0)
    if not count or count > 0x400000 or index >= count then return nil end
    local ga = ptr8(reg + 0xa0)
    if not ga then return nil end
    local gb = rd(ga + index, 1)
    if not gb or gb:byte(1) ~= generation then return nil end
    local oa = ptr8(reg + 0x88)
    if not oa then return nil end
    local object = ptr8(oa + 8 * index)
    if not object then return nil end
    local ib = rd(object + 8, 4)
    if not ib or u32(ib, 0) ~= unit then return nil end
    local bb = rd(object + 0x70, 4)
    if not bb then return nil end
    local bones = u32(bb, 0)
    if not bones or bones < 1 or bones > 1024 or node >= bones then return nil end
    local ba = ptr8(object + 0x88)
    if not ba then return nil end
    local b = rd(ba + node * 64, 64)
    if not b then return nil end
    local x, y, z = f32(b, 48), f32(b, 52), f32(b, 56)
    local fx, fy, fz = f32(b, 16), f32(b, 20), f32(b, 24)
    if not (finite(x) and finite(y) and finite(z)) then return nil end
    if not (finite(fx) and finite(fy) and finite(fz)) then return x, y, z, nil, nil, nil end
    return x, y, z, fx, fy, fz
end

-- ------------------------------------------------------------------ cfg
local CFGVER = 16
local cfg = { enable = 1, autostart = 1, key = 118, cone_deg = 12, max_dist = 250,
              -- scope: the lock cone is FOV compensated so the ring keeps the
              -- same on-screen size at every zoom.  scope_fix=1 uses the other
              -- model while a scope is in use: ring = original ring x
              -- scope_scale, which follows the magnification.  See update_cone().
              scope_fix = 0, scope_scale = 0.3,
              apw_damage = 1, lua_bind = 1,
              bind_delay = 0.25, debug = 0, round_speed = 0, round_gravity = -1,
              cone_fallback = 0, seek_key = 121, seek_cycle = 0,
              require_assets = 1,
              seek_speed = 0, seek_accel = 0, seek_ptr = 0,
              warrant_type = 0,
              ship_scan = 0, proj_ptr = 0,
              los_check = 1, los_desc = 0, los_debug = 0,              los_foliage = 1,
              scan_ms = 4, target_interval = 20,
              cluster_guide = 1, cluster_life = 3, cluster_delay = 0.05,
              cluster_seeker = 1, cluster_autofix = 1,
              launcher_seeker = 0,
              rocket_life = 1.5, rocket_prox = 0,
              swarm_count = 25, swarm_split = 1,
              -- v4.13: 1 = the RL-77 keeps its FACTORY cluster mode and only the
              -- flak round is guided.  See flak_only below.
              flak_only = 1,
              -- P2: 1 = lock friendly Helldivers only. Enemies are not
              -- locked at all while this is on.
              lock_helldivers = 0,
              -- P3: 1 = draw the stock lock markers.
              lock_reticle = 1,
              -- P3: 1 = draw the aim-cone range ring.
              range_ring = 1,
              -- P3: 1 = draw the wire box on the locked target.
              target_box = 1 }
-- which seeker entity the RL-77 cluster bomblets borrow (see CLUSTER.units).
-- 0 = the P-92 warrant, the same one the main round uses (needs a weapon lock)
-- 1 = MLS-4X commando missile, Guidance, steers a projectile
-- 2 = Patriot exosuit rocket, Guidance, steers a projectile
-- 3 = Mini Missile Silo missile, Guidance
-- 4 = plain Guidance seeker
-- 5 = enemy homing rocket, Behaviour
-- 6 = Behaviour seeker, fast and short lived
-- 7 = Vox Engine, External, waits for a published target
-- 0 is kept only so an old cfg still means what it meant; it is the ONE
-- combination that is proven not to home, so until the value is actually set to
-- something else it is upgraded to 1 (cluster_autofix=0 turns that off).
local function cluster_seeker()
    local m = tonumber(cfg.cluster_seeker) or 0
    if m ~= m or m < 0 or m > 7 or m ~= math.floor(m) then m = 0 end
    if m == 0 and cfg.cluster_autofix ~= 0 then
        if not state.seeker_autofix then
            state.seeker_autofix = true
            log('CLUSTER seeker 0 is the P-92 warrant, a TargetLock seeker, and a '
                .. 'bomblet has no weapon to lock with - that is the combination '
                .. 'that never homed. Using 1 (MLS-4X commando, Guidance, self '
                .. 'acquiring) instead. Set cluster_seeker=0 together with '
                .. 'cluster_autofix=0 to force the old behaviour.')
        end
        m = 1
    end
    return CLUSTER.units[m], CLUSTER.names[m], m
end
-- Which seeker entity the ROCKET itself borrows (v4.9).  This is a different
-- question from the bomblet one: the rocket is fired by a weapon, so it has a
-- source weapon id and a TargetLock seeker - the P-92 warrant, the one that works
-- for the APW-1 - is fine here.  Default 0.  The live log is why this is
-- separate: with the MLS-4X commando entity the rocket reached the seeking
-- manager (payload 96 / 312, src = the launcher) but the cluster burst went off
-- far too early, which smells like the commando missile's own fuse rather than
-- the launcher's; the warrant round carries no such thing.
local function launcher_seeker()
    local m = tonumber(cfg.launcher_seeker) or 0
    if m ~= m or m < 0 or m > 9 or m ~= math.floor(m) then m = 0 end
    return CLUSTER.units[m], CLUSTER.names[m], m
end
local function write_default_cfg()
    if not CFG_PATH then return end
    ensure_dir(OUT_DIR)
    local w = io.open(CFG_PATH, 'w')
    if not w then
        ensure_dir(OUT_DIR)          -- the folder may just have been missing
        w = io.open(CFG_PATH, 'w')
        if not w then return end
    end
    w:write(table.concat({
        ('cfgver=%d'):format(CFGVER),
        '# APW-1 guided rounds - v3.24 + RL-77 cluster bomblets (v4.4)',
        '# DEFAULT ON: enable=1 + autostart=1 means the addon arms itself as soon',
        '#                as the game starts.  You do NOT have to press anything.',
        '#                F7 (key) RESTARTS it: everything it wrote is put back',
        '#                and taken again, which clears the occasional state',
        '#                where it stops locking.  To switch the addon OFF',
        '#                use the MODS tab, or set enable=0 below.',
        'weapons=0x89C5493E08CA4207',
        '# prio_targets  weapons that prefer the BIGGEST enemy over the',
        '#                one nearest the crosshair. Set from the MODS tab.',
        'prio_targets=',
        '# prio_small    weapons that prefer the SMALLEST enemy instead.',
        'prio_small=',
        'enable=1',
        'autostart=1',
        'key=118',
        'round_speed=0',
        'round_gravity=-1',
        'seek_cycle=0',
        'require_assets=1',
        '# asset_weapon=P-92 Warrant',
        'seek_key=121',
        '# seek_entity=0x8053DA4358971392',
        '# seek_speed   SPEED OF THE GUIDED ROUND, m/s. 0 = leave the game value.',
        '#              The leased round does NOT take its speed from the',
        '#              ProjectileSettings row (that one still says 1300, and that is',
        '#              what round_speed rewrites).  It is driven by the',
        '#              SeekingMissileComponentData of the P-92 Warrant projectile,',
        '#              which ships as starting = minimum = preferred = 90 m/s -',
        '#              that is why guided rounds crawl.  This sets all three.',
        '#              Try 600 to 900 first; too fast and it cannot turn.',
        '# seek_accel   optional: the seeker acceleration (game value 200).',
        'seek_speed=0',
        'seek_accel=0',
        'seek_ptr=0',
        'warrant_type=0',
        'ship_scan=0',
        'proj_ptr=0',
        'scan_ms=4',
        'target_interval=20',
        'apw_damage=1',
        'lua_bind=1',
        'bind_delay=0.25',
        'cone_fallback=0',
        'cone_deg=12',
        'max_dist=250',
        '# scope_fix    0 = SHIPPED. The lock cone is compensated by the camera',
        '#              FOV, so the range ring keeps the SAME pixel radius at',
        '#              every zoom: hipfire and a scope lock the same area on',
        '#              screen. 1 = follow the magnification instead - while a',
        '#              scope is in use the ring is the ORIGINAL ring (the one',
        '#              that grows with the zoom) times scope_scale below.',
        'scope_fix=0',
        '# scope_scale  The decimal scope_fix multiplies the original ring by.',
        '#              1.0 = the original behaviour (the ring grows with the',
        '#              magnification and a strong scope can push it off screen),',
        '#              0.3 = a third of that, 0.05 = a small ring at any zoom.',
        '#              Only while a scope is in use; hipfire is never scaled.',
        'scope_scale=0.3',
        'debug=0',
        '# cluster_guide  Give the RL-77 Airburst cluster bomblets the seeker.',
        '#                Only runs while the launcher is one of the weapons in',
        '#                the weapons= list AND in your hands. 1 = on.',
        'cluster_guide=1',
        '# cluster_life   Seconds a bomblet may live. The factory value is 0.0,',
        '#                which means it never expires - a homing round that',
        '#                never expires is the known leak, so this is written',
        '#                together with the seeker.',
        'cluster_life=3',
        '# cluster_delay  Seconds before a bomblet may be given a target. Small',
        '#                on purpose: the cluster rocket bursts after 0.25 s, so',
        '#                the bomblets only have a moment to be bound.',
        'cluster_delay=0.05',
        '# cluster_seeker Which seeker entity the bomblet borrows.',
        '#                0 = the P-92 warrant, the same one the main round uses.',
        '#                    Its targeting mode is TargetLock, so it needs a',
        '#                    weapon to provide the lock - and a bomblet is',
        '#                    spawned by an explosion, not by a weapon. This is',
        '#                    the one combination that is proven NOT to home.',
        '#                1 = MLS-4X commando missile. Guidance, and it steers a',
        '#                    projectile instead of flying the missile itself.',
        '#                2 = Patriot exosuit rocket. Same shape as 1.',
        '#                3 = Mini Missile Silo missile. Guidance, self acquiring.',
        '#                4 = a plain Guidance seeker.',
        '#                5 = the enemy homing rocket (Hulk / Gunship / Devastator).',
        '#                    Behaviour driven, so it needs an actor behaviour.',
        '#                6 = a Behaviour seeker, fast and short lived.',
        '#                7 = Vox Engine. External, it waits for a published',
        '#                    target, which is what this addon does anyway.',
        'cluster_seeker=1',
        '# cluster_autofix 0 is broken by design, so until cluster_seeker is set',
        '#                 to something else 0 is quietly upgraded to 1. Set this',
        '#                 to 0 as well if you really want the P-92 warrant.',
        'cluster_autofix=1',
        '# launcher_seeker Which seeker entity the ROCKET itself borrows. This is',
        '#                 a different question from the bomblet one: the rocket',
        '#                 is fired by a weapon, so it has a source weapon id and',
        '#                 a TargetLock seeker works on it - 0, the P-92 warrant,',
        '#                 the same one the APW-1 uses, is shipped. With 1 the',
        '#                 rocket borrowed the commando missile fuse and the burst',
        '#                 went off far too early, so try 0 first.',
        '#                 0 - 7 are the same list as cluster_seeker. 8 is the',
        '#                 P-33 missile pistol round and 9 the FAF-14 Spear',
        '#                 rocket - both TargetLock like 0, and both are what the',
        '#                 Suzuka lock-on MLS-4X mod uses.',
        'launcher_seeker=0',
        '# rocket_life   Seconds the CLUSTER round may fly before it bursts.',
        '#               The factory value is 0.25 s, a plain timer with no ',
        '#               proximity fuse at all, so the round always burst about '
            .. '20 m out however good its guidance was - that is the',
        '#               "it goes off too early" nobody could pin on a seeker.',
        '#               1.5 is what the flak round of the same gun uses. 0 means',
        '#               leave the factory value alone.',
        'rocket_life=1.5',
        '# rocket_prox   Metres. Give the cluster round the proximity fuse it does',
        '#               not ship with, so it bursts when it ARRIVES instead of on',
        '#               a timer. The flak round uses 2.0. 0 means leave it off.',
        'rocket_prox=0',
        '# swarm_count  2 or more turns the CLUSTER mode into a guided swarm:',
        '#               the weapon itself fires that many guided darts per shot',
        '#               instead of one rocket that bursts, and each dart is bound',
        '#               to its own target. 25 is shipped, which is exactly how',
        '#               many bomblets the factory burst scattered - and each dart',
        '#               takes the bomblet damage, so the burst still hits for the',
        '#               same total. 0 or 1 keeps the airburst behaviour above.',
        '#               The flak mode is never touched.',
        'swarm_count=25',
        '# swarm_split  1 = hand the darts DIFFERENT targets (round robin over',
        '#               what is in the aim cone) so they fan out. 0 = every dart',
        '#               chases the same enemy as the launcher is aiming at.',
        'swarm_split=1',
        '# flak_only    1 = SHIPPED. The RL-77 keeps its factory cluster mode -',
        '#               no seeker on the round, no swarm, the burst scatters its',
        '#               25 bomblets exactly as Arrowhead made it - and only the',
        '#               FLAK round gets the borrowed seeker. Set 0 to give the',
        '#               cluster mode the swarm above as well.',
        'flak_only=1',
    }, '\n') .. '\n')
    w:close()
end

-- Rewrite ONE key inside the live cfg and leave every comment and every other
-- line exactly where it is.  Used to remember the projectile table address
-- between launches.  Everything is inside pcall: a locked or missing file must
-- never be able to break the addon.
function state.save_cfg_key(key, value)
    -- (a field on state, not a top-level local: this chunk sits right at
    --  LuaJIT's 200-local cap and one more `local function` breaks the load)
    if not CFG_PATH then return false end
    local wrote = false
    local ok = pcall(function()
        local f = io.open(CFG_PATH, 'r')
        if not f then return end
        local lines = {}
        for line in f:lines() do lines[#lines + 1] = line end
        f:close()
        local pat = '^%s*' .. key .. '%s*='
        local hit = false
        for i = 1, #lines do
            if lines[i]:find(pat) then
                lines[i] = key .. '=' .. tostring(value)
                hit = true
            end
        end
        if not hit then lines[#lines + 1] = key .. '=' .. tostring(value) end
        local w = io.open(CFG_PATH, 'w')
        if not w then return end
        w:write(table.concat(lines, '\n') .. '\n')
        w:close()
        wrote = true
    end)
    return ok and wrote
end
-- ---- the weapon list -------------------------------------------------------
-- Any number of weapon resource hashes, written in the cfg as
--   weapons=0x89C5493E08CA4207,0xB6AFF2195568767F
-- (hash as it appears in Hash.csv, either 0x-hex or decimal).  Every weapon in
-- the list gets exactly the APW-1 treatment: its rounds spawn the P-92 Warrant
-- projectile entity (that is where the seeker lives) while the ballistics row
-- stays the weapon's own, so the damage stays the weapon's own too.
local WEAPONS = { APW_B }
local WEAPONS_TXT = { '0x89C5493E08CA4207' }

-- P16: the units the debug trace reports on. Not a whitelist - every row
-- here is already in TARGETS - just the names the log should use.
local WATCH = {
    [hash8('0x0D382AE7FFEA9D45')] = "Lightning Spire",
    [hash8('0x1445DF29152C9BE2')] = "Illuminate Scrambler",
    [hash8('0x78E1497571012C47')] = "Voteless Light",
    [hash8('0x0ADC9F9173AD8E1D')] = "Voteless Medium",
    [hash8('0x44458A2C52B002FB')] = "Voteless Heavy",
    [hash8('0xE8E7D998FCBD32F8')] = "Tesla Tower",
    [hash8('0x4446E7312B401E69')] = "Scrambler Battery",
    [hash8('0x67DC32DCA4F02D33')] = "Fleshmob",
}



-- Seeker entities we can lease instead of the P-92 one.  turn = the max turn
-- speed inside that entity's SeekingMissileComponentData, so swapping changes
-- both the look and how hard the round can turn.  Cycled live with seek_key.
local ASSET_WEAPON = 'P-92 Warrant'
-- v4.6: the bomblet can borrow a seeker that belongs to another weapon's
-- package (1 = MLS-4X commando, 2 = Patriot exosuit, 3 = the missile silo).  If
-- that package is not resident the bomblets spawn with a missing-material icon
-- or not at all, so ask the runtime for it too.  Names that the runtime does
-- not know are only logged - the P-92 request must never be lost because of it.
-- v4.7: hd2.weapon() only knows PRIMARY weapons.  MLS-4X Commando and the
-- missile silo are support weapons and the Patriot is a vehicle, so the v4.6
-- request threw "unknown reviewed weapon alias" and the bomblet seeker package
-- was never actually loaded - a unit that spawns with no resident package has
-- no SeekingMissileComponent, which is the best explanation left for a bomblet
-- that never reaches the seeking manager.  Ask through the right builder now.
local SEEKER_ASSET = {
    [1] = { kind = 'support_weapon', name = 'MLS-4X Commando' },
    [2] = { kind = 'vehicle',        name = 'EXO-45 Patriot Exosuit' },
    [3] = { kind = 'support_weapon', name = 'MS-11 Solo Silo' },
    -- v4.9: the two the Suzuka mod uses.  The P-33 is a sidearm so it goes
    -- through hd2.weapon() like the P-92 does; the Spear is a support weapon.
    [8] = { kind = 'weapon',         name = 'P-33 Missile Pistol' },
    [9] = { kind = 'support_weapon', name = 'FAF-14 Spear' },
}
local function asset_start()
    if cfg.require_assets ~= 1 then return end
    local ok, hd2 = pcall(require, 'mods/skyeshade/hd2runtime')
    if not ok or type(hd2) ~= 'table' or not hd2.require_assets then
        log('ASSET the shared HD2Runtime is not installed - the leased projectile '
            .. 'will keep showing the missing-material icon')
        return
    end
    local ok2, watch = pcall(function()
        local targets = { hd2.weapon(ASSET_WEAPON) }
        -- v4.9: the bomblet and the rocket can borrow DIFFERENT entities now, so
        -- both packages have to be resident or the one that is missing spawns
        -- with no SeekingMissileComponent at all
        local wanted = {}
        local _, _, smode = cluster_seeker()
        local _, _, lmode = launcher_seeker()
        wanted[#wanted + 1] = { smode, 'bomblet' }
        if lmode ~= smode then wanted[#wanted + 1] = { lmode, 'rocket' } end
        for _, w2 in ipairs(wanted) do
            local extra = SEEKER_ASSET[w2[1]]
            if extra then
                local okw, w = pcall(hd2[extra.kind], extra.name)
                if okw and type(w) == 'table' then
                    targets[#targets + 1] = w
                    log(('ASSET also asking for the %s seeker package %s (%s)')
                        :format(w2[2], extra.name, extra.kind))
                else
                    log(('ASSET the %s seeker package %s could not be resolved as a '
                         .. '%s (%s) - only the P-92 one is loaded')
                        :format(w2[2], extra.name, extra.kind, tostring(w)))
                end
            end
        end
        return hd2.require_assets({ id = 'apw-lease', targets = targets })
    end)
    if not ok2 or type(watch) ~= 'table' then
        log('ASSET require_assets refused: ' .. tostring(watch))
        return
    end
    state.asset_watch = watch
    log(('ASSET asked the runtime to load the package of %s (status=%s)')
        :format(ASSET_WEAPON, tostring(watch.status)))
end

local SEEK_LIST = {
    { h = '0x8053DA4358971392', note = 'P-92 Warrant, turn 30 (default)' },
    { h = '0x1597AF7289E1BE93', note = 'unnamed, turn 35' },
    { h = '0x4C7E5EC4D0D1BB11', note = 'unnamed, turn 20' },
    { h = '0x14CC0DB942F6D7F2', note = 'W.A.S.P., turn 18' },
    { h = '0xA1470A4DAB237264', note = 'P-33 Missile Pistol, turn 18' },
    { h = '0x6EE6B14CEC32392D', note = 'unnamed, turn 13' },
    { h = '0x1A4323835B84CEA7', note = 'FAF-14 Spear, turn 13' },
}
for _, e in ipairs(SEEK_LIST) do e.bytes = hash8(e.h) end
-- forward: set_seek (the F10 seeker cycle) must be able to re-lease, and
-- sync_leases is defined much further down.  A reference to it written as a
-- plain name here would be read as a GLOBAL - nil - because a local only exists
-- from the line that declares it onwards.
local sync_leases
local function set_lease(h)
    if not h then return end
    local t = {}
    for i = #h, 1, -1 do t[#t + 1] = string.format('%02X', h:byte(i)) end
    LEASE.bytes, LEASE.txt = h, '0x' .. table.concat(t)
end
local function set_seek(i)
    local e = SEEK_LIST[i]
    if not e or not e.bytes then return end
    state.seek_idx = i
    set_lease(e.bytes)
    LEASE.txt = e.h
    log(('SEEK ENTITY #%d = %s  (%s) - re-leasing, fire a round and look at it')
        :format(i, e.h, e.note))
    -- put the old value back first, then write the new one, so the restore
    -- check never refuses because the slot holds a value we no longer expect
    pcall(sync_leases, false)
    pcall(sync_leases, true)
end
-- P17: one counter row per watched resource, created on first sight. A field on
-- state, not a local, for the usual reason: this chunk is at the local ceiling.
-- It lives on state and keeps its counters on state, NOT on ctx: this block sits
-- above `local ctx`, so any ctx reference in here would resolve to the global ctx,
-- which is nil - the same trap that once made the whole addon fail to load.
function state.watch_open(res)
    local name = res and WATCH and WATCH[res]
    if not name then return nil end
    state.watch = state.watch or {}
    local row = state.watch[name]
    if not row then
        row = { seen = 0, wanted = 0, health = 0, faction = 0, pose = 0, usable = 0 }
        state.watch[name] = row
    end
    return row
end

local function parse_weapons(text)
    local list, txt = {}, {}
    -- An empty (or "none") list has to be honoured: the options menu can switch
    -- every weapon off, and without this the old list would simply survive.
    local s = tostring(text)
    if s:match('^%s*$') or s:match('^%s*[Nn][Oo][Nn][Ee]%s*$') then
        WEAPONS, WEAPONS_TXT = list, txt
        return
    end
    for tok in s:gmatch('[0-9A-Fa-fXx]+') do
        local b = hash8(tok)
        if b then
            local dup = false
            for _, v in ipairs(list) do if v == b then dup = true; break end end
            if not dup then list[#list + 1] = b; txt[#txt + 1] = tok end
        end
    end
    if #list > 0 then
        WEAPONS, WEAPONS_TXT = list, txt
    else
        -- the line was there but held nothing usable: saying so beats silently
        -- keeping the previous list while the user stares at the cfg
        log('WEAPONS the weapons= line held no usable hash - the previous list '
            .. 'is kept')
    end
end

local saved_ptrs = {}
if CFG_PATH then
    local f = io.open(CFG_PATH, 'r')
    if not f then
        write_default_cfg()
    else
        local ver = 0
        for line in f:lines() do
            local k, v = line:match('^%s*([%a%d_]+)%s*=%s*([%w%.%-]+)')
            local n = tonumber(v)
            if k == 'cfgver' then ver = n or 0 end
            if k == 'proj_ptr' or k == 'seek_ptr' then saved_ptrs[k] = n end
            if k and n and cfg[k] ~= nil then cfg[k] = n end
            local wl = line:match('^%s*weapons%s*=%s*(.-)%s*$')
            if wl then parse_weapons(wl) end
            -- P10: the priority list is only KEPT here, never parsed. `local ctx`
            -- is declared BELOW this loader, so writing ctx.prio from inside it
            -- indexed the GLOBAL ctx - nil - and the addon failed to load outright
            -- the moment the cfg actually carried a prio_targets line. It went
            -- unnoticed only because the key was missing from every cfg that had
            -- been written, so the branch never ran; adding the line by hand
            -- produced: load failed: ... attempt to index global 'ctx' (a nil
            -- value), which takes the whole MODS tab with it. state does exist
            -- here; refresh_targets turns the text into ctx.prio.
            local pl = line:match('^%s*prio_targets%s*=%s*(.-)%s*$')
            if pl then state.prio_txt = pl end
            local psl = line:match('^%s*prio_small%s*=%s*(.-)%s*$')
            if psl then state.prio_small_txt = psl end
            local se = line:match('^%s*seek_entity%s*=%s*(.-)%s*$')
            if se then
                local h = hash8(se:match('[0-9A-Fa-fXx]+') or '')
                if h then set_lease(h) end
            end
            local aw = line:match('^%s*asset_weapon%s*=%s*(.-)%s*$')
            if aw and #aw > 0 then ASSET_WEAPON = aw end
            local ms = line:match('^%s*model_swap%s*=%s*(.-)%s*$')
            if ms then
                local h = hash8(ms:match('[0-9A-Fa-fXx]+') or '')
                if h then state.model_swap = h end
            end
        end
        f:close()
        if ver ~= CFGVER then
            local old = CFG_PATH .. '.v' .. tostring(ver) .. '.bak'
            pcall(os.remove, old)
            pcall(os.rename, CFG_PATH, old)
            write_default_cfg()
            -- keep the remembered block addresses so an upgrade does not have to
            -- pay for a full walk of the process again
            for _, k in ipairs({ 'proj_ptr', 'seek_ptr' }) do
                if saved_ptrs[k] then
                    state.save_cfg_key(k, string.format('%d', saved_ptrs[k]))
                end
            end
            log('cfg upgraded to v' .. CFGVER .. ' (old file kept as ' .. old .. ')')
        end
    end
end

-- ------------------------------------------------------------------ state
-- declared here, not next to the phases that use them, because switching to
-- another whitelisted weapon has to clear them (see find_apw_weapon) and Lua
-- resolves locals lexically - a later `local` would be a different variable
local dl_rows = nil     -- damage rows of the weapon currently in hand
local bl_rows = nil     -- ballistics row of the weapon currently in hand

local lease             -- forward: find_apw_weapon has to unlease the old weapon
local proj_types        -- forward: the projectile table walk fills it in
local ctx               -- forward: forget_weapon below needs it, the table is
                        -- filled in further down (Lua resolves locals lexically)

-- everything that belongs to the weapon we were looking at a moment ago.
-- (it lives here so find_apw_weapon does not have to touch these four locals
--  directly - a function may only close over 60 of them and it is right at the
--  limit)
local function forget_weapon()
    ctx.apw_proj_type, ctx.warrant_type = nil, nil
    ctx.bomb_lock = nil
    dl_rows, bl_rows = nil, nil; state.mod_rows = nil
    ctx.origin, ctx.forward, ctx.forward_valid = nil, nil, nil
    ctx.aim_pose, ctx.aim_txt = nil, nil
    ctx.cam_origin, ctx.cam_forward = nil, nil
end

ctx = {
    em = nil, wm = nil, am = nil, hm = nil, fm = nil, sm = nil,
    avatar_id = nil, avatar_resource = nil, self_mask = nil,
    weapon_id = nil, weapon_unit = nil,
    settings_addr = nil, settings_kind = nil,
    origin = nil, forward = nil,
    targets = {}, target = nil,
    mission = false, last_reason = nil, seek_active = 0,
    wd = nil, dl = nil,
    held = nil, wset = nil,
    -- RL-77 cluster bomblets (v4.4)
    rl77_id = nil,      -- weapon id of the carried Airburst Rocket Launcher
    bomb_type = nil,    -- projectile type of its cluster bomblet row
    bomb_lock = nil,    -- {net, name, at} the last target the launcher locked
}

-- v4.7: ctx.wait_frame stamps the frame this was raised on.  step() must not
-- print READY on a frame that also raised a WAIT - that pairing printed two
-- lines every single frame in v4.6 (3757 pairs in 54 s).  The 300 frame
-- cooldown is what keeps a condition that genuinely flaps from flooding too:
-- worst case is one WAIT and one READY every five seconds.
local NOTE_GAP = 300
local function note(reason)
    ctx.wait_frame = state.frame
    if ctx.last_reason ~= reason then
        ctx.last_reason = reason
        if (state.frame - (ctx.note_at or -99999)) > NOTE_GAP then
            ctx.note_at = state.frame
            log('WAIT ' .. tostring(reason))
        end
    end
end

local function resolve_avatar()
    local pm = ptr8(base + R.player)
    if not pm then return false, 'no_player_manager' end
    local ar = u32(rd(pm + 0x3a8, 4), 0)
    if not ar or ar == 0 or ar == 0xffffffff then return false, 'no_avatar_ref' end
    local em = ptr8(base + R.entity)
    if not em then return false, 'no_entity_manager' end
    ctx.em = em
    local _, _, ei = slot(em + 0xf22ec8, ar, 1048576)
    if not ei then return false, 'avatar_not_registered' end
    if ei >= 262144 then return false, 'avatar_index_out_of_range' end
    local av = entity(em + 0xf32f18 + 24 * ei)
    if not av then return false, 'avatar_unreadable' end
    if av.net ~= ar or av.flags % 4 ~= 1 then return false, 'avatar_not_local' end
    ctx.avatar_id = av.id
    -- P2: the local avatar's entity resource is the reference for every other
    -- Helldiver, so no external hash list is needed and no game update can stale it.
    ctx.avatar_resource = av.resource
    local fm = ptr8(base + R.faction)
    if fm then
        ctx.fm = fm
        local _, _, fi = slot(fm + 0x12050, av.id, 131072)
        if fi and fi < 16384 then
            local ma = ptr8(fm + 0x12078)
            if ma then ctx.self_mask = u32(rd(ma + 4 * fi, 4), 0) end
        end
    end
    return true
end

local function faction_of(id)
    if not ctx.fm then return nil, nil end
    local _, _, fi = slot(ctx.fm + 0x12050, id, 131072)
    if not fi or fi >= 16384 then return nil, nil end
    local ma, ca = ptr8(ctx.fm + 0x12078), ptr8(ctx.fm + 0x12070)
    if not ma or not ca then return nil, nil end
    return u32(rd(ma + 4 * fi, 4), 0), u32(rd(ca + 96 * fi, 4), 0)
end

local function whitelisted(res)
    for i = 1, #WEAPONS do if res == WEAPONS[i] then return WEAPONS_TXT[i] end end
    return nil
end

-- Every whitelisted weapon you are carrying, not just the first one found.
-- This matters the moment you list more than one: your primary stays attached to
-- you (on your back) the whole mission, so it always shows up first in the
-- weapon array and used to swallow all the attention - the support weapon,
-- which only exists once the mission has started, never got set up at all.
-- split into two so find_apw_weapon stays well under Lua's 60-upvalue limit
local function apply_held(held)
    if #held == 0 then
        ctx.held = held
        ctx.rl77_id = nil
        return false, 'apw_not_in_hands'
    end
    local changed = (not ctx.held) or (#ctx.held ~= #held)
    if not changed then
        for i, h in ipairs(held) do if ctx.held[i].id ~= h.id then changed = true; break end end
    end
    if changed then
        for _, h in ipairs(held) do
            log('WEAPON carried: ' .. tostring(h.txt) .. ' id=' .. tostring(h.id))
        end
        forget_weapon()
    end
    ctx.held = held
    -- the first one drives the aim cone; the lease covers all of them
    ctx.weapon_id, ctx.weapon_unit = held[1].id, held[1].unit
    ctx.weapon_res, ctx.weapon_txt = held[1].res, held[1].txt
    -- the RL-77 is the only weapon with a cluster burst to guide, so the
    -- cluster phase and the bomblet binding both key off this one id
    ctx.rl77_id = nil
    for _, h in ipairs(held) do
        if h.res == CLUSTER.weapon then ctx.rl77_id = h.id; break end
    end
    if ctx.rl77_id then
        ctx.rl77_recent = { id = ctx.rl77_id, at = state.frame }
    end
    return true
end

local function collect_held(am, pa, total)
    local parent_base = ptr8(am + 0x40)
    local held = {}
    for n = 0, total - 1 do
        local obj = u64(pa, 8 * n)
        if ptr_ok(obj) then
            local w = entity(obj)
            local hit = w and whitelisted(w.resource)
            if hit and w.flags % 4 == 1 then
                local _, _, ai = slot(am + 0x20, w.id, 32768)
                if ai and ai < 16384 and parent_base then
                    local att = rd(parent_base + 48 * ai, 20)
                    if att and u32(att, 4) == ctx.avatar_id then
                        local dup = false
                        for _, h in ipairs(held) do
                            if h.id == w.id then dup = true; break end
                        end
                        if not dup then
                            held[#held + 1] = { id = w.id, unit = w.unit,
                                                res = w.resource, txt = hit }
                        end
                    end
                end
            end
        end
    end
    return held
end

local function find_apw_weapon()
    local wm = ptr8(base + R.weapon)
    if not wm then return false, 'no_weapon_manager' end
    ctx.wm = wm
    local am = ptr8(base + R.attach)
    if not am then return false, 'no_attachment_manager' end
    ctx.am = am
    local nb = rd(wm + 0x38, 4)
    if not nb then return false, 'weapon_count_unreadable' end
    local total = u32(nb, 0)
    if not total or total < 1 then return false, 'no_weapons' end
    if total > 1024 then total = 1024 end
    local we = ptr8(wm + 0x68)
    if not we then return false, 'no_weapon_array' end
    local pa = rd(we, 8 * total)
    if not pa then return false, 'weapon_array_unreadable' end
    return apply_held(collect_held(am, pa, total))
end

-- remembers the R-36's weapon id so the binder accepts the fragments it spawns
-- returns a pose table {origin, forward, valid} for one weapon, or nil
local function pose_of(wid, unit)
    if not wid then return nil end
    local wd = ptr8(base + R.pose)
    if not wd then return nil end
    local _, _, wi = slot(wd + 48, wid, 32768)
    if not wi or wi >= 16384 then return nil end
    local arr = ptr8(wd + 88)
    if not arr then return nil end
    local wb = rd(arr + 1008 * wi, 228)
    if not wb then return nil end
    local count, index = u32(wb, 216), u32(wb, 220)
    if not count or not index or count < 1 or count > 24 or index >= count then return nil end
    local node = u32(wb, 120 + 4 * index)
    if not node then return nil end
    local x, y, z, fx, fy, fz = bone(unit, node)
    if not x then return nil end
    local pose = { origin = { x, y, z }, forward = { 0, 0, 1 }, valid = false }
    if fx then
        local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
        if fl >= 0.5 and fl <= 1.5 then
            pose.forward = { fx, fy, fz }
            pose.valid = true
        end
    end
    return pose
end

local function weapon_pose()
    if not ctx.weapon_id then return false, 'no_weapon' end
    -- P4: with more than one whitelisted weapon on you, held[1] is usually the
    -- primary slung on your back, so the aim cone used to start behind you the
    -- moment the weapon in hand was the support weapon. The reticle module picks
    -- the pose of the weapon actually in hand - the one aligned with the camera -
    -- and publishes it as ctx.aim_pose; prefer it while there is a choice.
    local pose = (ctx.held and #ctx.held > 1) and ctx.aim_pose or nil
    if not pose then pose = pose_of(ctx.weapon_id, ctx.weapon_unit) end
    if not pose then return false, 'muzzle_pose_unavailable' end
    ctx.origin, ctx.forward, ctx.forward_valid = pose.origin, pose.forward, pose.valid
    if not ctx.forward_valid and ctx.warned_forward ~= true then
        ctx.warned_forward = true
        log('NOTE muzzle bone carries no usable forward vector - picking the nearest enemy instead of a cone')
    end
    return true
end

-- a pose for every weapon we carry: with two weapons on the list the first one
-- is the one on your back, so its muzzle cannot be used to aim the other one
local function refresh_poses()
    ctx.pose = {}
    for _, h in ipairs(ctx.held or {}) do
        local pose = pose_of(h.id, h.unit)
        if pose then ctx.pose[h.id] = pose end
    end
end

-- ------------------------------------------- per-weapon settings lease (+40)
local function resource_row(want)
    if not ctx.em then return nil, nil end
    want = want or ctx.weapon_res or APW_B
    local tb = ptr8(ctx.em + SET_TBL_OFF)
    if not tb then return nil, nil end
    for first = 0, SET_ENTRIES - 1, 512 do
        local cnt = math.min(512, SET_ENTRIES - first)
        local rows = rd(tb + 16 * first, 16 * cnt)
        if rows then
            for k = 0, cnt - 1 do
                if rows:sub(k * 16 + 1, k * 16 + 8) == want then
                    local idx = u32(rows, k * 16 + 8)
                    if idx and idx < SET_ROW_MAX then
                        local addr = tb + SET_ROW_OFF + ROW_SIZE * idx
                        local row = rd(addr, ROW_SIZE)
                        if row then return addr, row end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function resolve_settings(wid, res, txt)
    wid = wid or ctx.weapon_id
    res = res or ctx.weapon_res or APW_B
    txt = txt or ctx.weapon_txt
    if not ctx.wm or not wid then return nil, nil, 'no_weapon' end
    local count_b, cap_b = rd(ctx.wm + 0xc8, 4), rd(ctx.wm + 0x30, 4)
    if not count_b or not cap_b then return nil, nil, 'settings_count_unreadable' end
    local count, scap = u32(count_b, 0), u32(cap_b, 0)
    if not count or not scap or scap < 1 or scap > 4096 or count > scap then
        return nil, nil, 'settings_bounds'
    end
    local data = ptr8(ctx.wm + 0xd0)
    if not data then return nil, nil, 'settings_array_missing' end
    local faddr, fbytes, findex, fcap = slot(ctx.wm + 0x90, wid, 8192)
    if findex then
        local addr = data + ROW_SIZE * findex
        local row = rd(addr, ROW_SIZE)
        if row then return addr, row, 'instance' end
    end
    if not faddr or not fbytes then return nil, nil, 'forward_map_unavailable' end
    if count >= scap then return nil, nil, 'settings_full' end
    local raddr, rrow = resource_row(res)
    if not rrow then return nil, nil, 'resource_row_missing' end
    -- the row was found by the weapon's own resource hash, so instead of the old
    -- "rpm must be 400" test (APW-only) just require a sane number
    local rpm = f32(rrow, 8)
    if not rpm or rpm <= 0 or rpm >= 5000 then return nil, nil, 'resource_row_rpm_bad' end
    if res and ctx.rpm_logged ~= res then
        ctx.rpm_logged = res
        log(('WEAPON resource row %s rpm=%.0f'):format(tostring(txt), rpm))
    end
    if u32(rrow, 576) ~= 0 then return nil, nil, 'alternate_settings_not_zero' end
    local addr = data + ROW_SIZE * count
    local previous = rd(addr, ROW_SIZE)
    if not previous then return nil, nil, 'slot_unreadable' end
    local raddr2, rbytes = slot(ctx.wm + 0xb0, count, 8192)
    if not raddr2 or not rbytes then return nil, nil, 'reverse_map_unavailable' end
    if u32(rbytes, 0) == count then return nil, nil, 'reverse_slot_occupied' end
    if (count + 1) * 2 >= fcap then return nil, nil, 'map_load_limit' end
    if not write_bytes(addr, rrow) then return nil, nil, 'copy_failed' end
    if not write_bytes(raddr2, word(count) .. word(wid)) then return nil, nil, 'reverse_write_failed' end
    if not write_bytes(ctx.wm + 0xc8, word(count + 1)) then return nil, nil, 'count_write_failed' end
    if not write_bytes(faddr, word(wid) .. word(count)) then return nil, nil, 'forward_write_failed' end
    local row = rd(addr, ROW_SIZE)
    if not row then return nil, nil, 'created_row_unreadable' end
    log(('SETTINGS per-weapon override created: slot=%d addr=%s (copied from resource row %s)')
        :format(count, hexa(addr), hexa(raddr or 0)))
    return addr, row, 'created'
end

-- one per-weapon settings row per weapon we carry, so every listed weapon that
-- is on you gets the seeker, not just whichever one happens to be first
function lease(on, wid, res, txt)
    wid = wid or ctx.weapon_id
    res = res or ctx.weapon_res or APW_B
    txt = txt or ctx.weapon_txt
    if not wid then return false end
    ctx.wset = ctx.wset or {}
    local rec = ctx.wset[wid]
    if not rec then
        -- v4.7: a weapon whose resource row carries alternate settings (the
        -- RL-77 and every other gun with two fire modes) can NEVER take a
        -- per-weapon row.  v4.6 asked again every frame, which is where the
        -- 3757 WAIT lines came from.  Remember the refusal and stay quiet; the
        -- entry is dropped again when the weapon leaves your hands.
        if ctx.wdead and ctx.wdead[wid] then return false end
        local addr, row0, kind = resolve_settings(wid, res, txt)
        if not addr then
            note('settings_' .. tostring(kind))
            if kind == 'alternate_settings_not_zero' or kind == 'resource_row_rpm_bad'
               or kind == 'forward_map_unavailable' then
                ctx.wdead = ctx.wdead or {}
                ctx.wdead[wid] = kind
                log(('SETTINGS %s cannot take a per-weapon row (%s) - it keeps its '
                     .. 'own fire mode settings, so it is left alone from now on')
                    :format(tostring(txt), tostring(kind)))
            end
            return false
        end
        rec = { addr = addr, kind = kind }
        ctx.wset[wid] = rec
        ctx.settings_addr, ctx.settings_kind = addr, kind
    end
    local addr = rec.addr
    local row = rd(addr, ROW_SIZE)
    if not row then note('settings_row_unreadable'); return false end
    -- 0 is not a valid projectile type: a recycled slot reads back as all zeros,
    -- and that would pin the damage phase to a type that does not exist
    if not ctx.apw_proj_type or ctx.apw_proj_type == 0 then
        ctx.apw_proj_type = u32(row, 0)
        log(('PROJECTILE %s own round type=%d (the damage of this weapon is kept)')
            :format(tostring(txt), ctx.apw_proj_type))
    end
    local rpm = f32(row, 8)
    if not rpm or rpm <= 0 or rpm >= 5000 then
        -- The per-weapon override slot went bad.  Those slots are created on the
        -- fly and the game recycles them (weapon dropped, respawn, a long mission
        -- with a lot going on), and a recycled slot reads back as rpm=0.  The old
        -- build just refused from then on, which is the "lock-on dies halfway
        -- through the round" report - it kept the dead address cached, so it
        -- refused on every frame for the rest of the mission.
        -- The weapon's own resource row is found by its hash, so it is always the
        -- right data: copy it back over the slot and carry on.
        if (state.frame - (ctx.repair_at or -9999)) <= 30 then
            if ctx.rpm_bad ~= true then
                ctx.rpm_bad = true
                log(('SETTINGS row %s reads rpm=%s - waiting for the repair retry')
                    :format(hexa(addr), tostring(rpm)))
            end
            return false
        end
        ctx.repair_at = state.frame
        local fixed = false
        local _, rrow2 = resource_row(res)
        if rrow2 then
            local rrpm = f32(rrow2, 8)
            if rrpm and rrpm > 0 and rrpm < 5000 and u32(rrow2, 576) == 0
               and write_bytes(addr, rrow2) then
                local back = rd(addr, ROW_SIZE)
                local rpm2 = back and f32(back, 8) or nil
                if rpm2 and rpm2 > 0 and rpm2 < 5000 then
                    row = back
                    fixed = true
                end
            end
        end
        if not fixed then
            -- not repairable: forget the cached row so the next frame looks for
            -- it again instead of refusing on a dead address forever
            ctx.wset[wid] = nil
            ctx.settings_addr, ctx.settings_kind = nil, nil
            if ctx.rpm_bad ~= 'lost' then
                ctx.rpm_bad = 'lost'
                log(('SETTINGS row %s is gone (rpm=%s) - dropped, will look for it again')
                    :format(hexa(addr), tostring(rpm)))
            end
            return false
        end
        if ctx.rpm_bad ~= 'fixed' then
            ctx.rpm_bad = 'fixed'
            log(('SETTINGS slot %s had gone stale (rpm=%s) - repaired from the resource '
                .. 'row, lock-on is back'):format(hexa(addr), tostring(rpm)))
        end
        -- the row was cleared, so the round type read off it may have been junk
        local pt = u32(row, 0)
        if pt and pt > 0 and pt < 8191 then ctx.apw_proj_type = pt end
    end
    local cur = row:sub(41, 48)
    if on then
        if cur == LEASE.bytes then
            rec.leased = true
            ctx.lease_frame = ctx.lease_frame or state.frame
            return true
        end
        if cur ~= ZERO8 then
            log('settings +40 holds ' .. hexs(cur) .. ' - refusing (another mod owns it)')
            return false
        end
        if write_bytes(addr + 40, LEASE.bytes) then
            rec.leased = true
            ctx.lease_frame = state.frame
            log(('LEASE ok  %s (%s) row=%s kind=%s  +40 : 8x00 -> P-92 warrant projectile')
                :format(tostring(txt), tostring(wid), hexa(addr), tostring(rec.kind)))
            return true
        end
        log('LEASE failed at ' .. hexa(addr + 40))
        return false
    else
        if cur == ZERO8 then rec.leased = false; return true end
        if cur ~= LEASE.bytes then
            log('settings +40 does not hold our value - leaving it alone'); return false
        end
        if write_bytes(addr + 40, ZERO8) then
            rec.leased = false
            log(('RESTORE ok  %s (%s) row=%s  +40 : warrant -> 8x00')
                :format(tostring(txt), tostring(wid), hexa(addr)))
            return true
        end
        return false
    end
end

-- lease every listed weapon you are carrying; give back the ones you dropped
sync_leases = function(on)
    ctx.wset = ctx.wset or {}
    local held = ctx.held or {}
    local n = 0
    for _, h in ipairs(held) do
        if on then
            if lease(true, h.id, h.res, h.txt) then n = n + 1 end
        else
            lease(false, h.id, h.res, h.txt)
        end
    end
    local gone = {}
    for wid in pairs(ctx.wset) do
        local still = false
        for _, h in ipairs(held) do
            if h.id == wid then still = true; break end
        end
        if not still then gone[#gone + 1] = wid end
    end
    for _, wid in ipairs(gone) do
        lease(false, wid)
        ctx.wset[wid] = nil
        -- picked up again later: give it a fresh chance (and it needs one, the
        -- weapon id is different after a respawn anyway)
        if ctx.wdead then ctx.wdead[wid] = nil end
    end
    state.leased = (n > 0)
    state.lease_n = n
    return state.leased
end

-- ===================================================================
-- WeaponDataComponentData: locate the table, then the crosshair slot.
-- ===================================================================
-- Data-library scan state.  It is declared HERE, above crosshair(), because
-- Lua locals are lexically scoped: a "local dl" written further down is not
-- visible to functions defined before it and they would read a nil global.
-- (That exact bug killed every v3.2 frame: "attempt to index global 'dl'".)
local dl = { regions = nil, ri = 1, roff = 0, prev = '', done = false, scanned = 0,
             sig = nil, sigi = 1, siglog = 0,
             budget_frame = -1, budget_left = 0, elapsed = 0, frames = 0 }
-- One scan budget per FRAME, shared by every phase that calls dl_scan().
-- Before this, damage() and ballistics() each took a full budget inside the same
-- frame, so "6 ms per frame" was really 12 ms and more.
local function dl_budget()
    if dl.budget_frame ~= state.frame then
        dl.budget_frame = state.frame
        local ms = num_or(cfg.scan_ms, 4)
        if ms < 0.5 then ms = 0.5 elseif ms > 20 then ms = 20 end
        dl.budget_left = ms / 1000
    end
    return dl.budget_left
end
-- what is still worth scanning for, given the options that are switched on
local function dl_needed()
    -- the cluster phase needs the same projectile table, but only while an
    -- RL-77 is actually in your hands - otherwise it would buy a full walk of
    -- the process for a weapon nobody is carrying
    local need_proj = (cfg.apw_damage == 1 or cfg.round_speed > 0
        or cfg.round_gravity >= 0
        or (cfg.cluster_guide == 1 and ctx.rl77_id)) and not ctx.dl
    local need_wd = false
    -- v3.22: the explosion block no longer DRIVES a scan.  It is picked up for
    -- free when the main pass happens to see it, but hunting for it is what cost
    -- a second 16.8 GB walk of the whole process on the ship on every launch -
    -- and in seven launches it was never found once, so nothing hunts for it
    -- any more (the R-36 fragment work lives in its own addon now).  It was
    -- ExplosionSettings +84 of the R-36 explosion), with a mission-only content
    -- hunt as the fallback, so a missing block costs nothing.
    local need_ex = false
    return need_proj or need_ex
end
-- ===================================================================
-- Data library: ProjectileSettings -> give the leased round APW damage
-- ===================================================================
local DL_SIG = 'LDLD' .. string.char(1, 0, 0, 0)
local dl_anchor = nil
do
    local ok, p = pcall(function()
        return tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', DL_SIG)))
    end)
    if ok and p and p > 0 then dl_anchor = p end
end
-- (the dl table itself is declared above crosshair(), see the comment there)

-- our own copy of each needle, so the scan can skip itself
local function str_addr(s)
    local ok, p = pcall(function()
        return tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', s)))
    end)
    if ok and p and p > 0 then return p end
    return nil
end

local function region_info(address)
    if not VQ then return nil end
    if VQ(ffi.cast('const void *', address), mbi, 48) ~= 48 then return nil end
    local s = ffi.string(mbi, 48)
    return { base = u64(s, 0), alloc = u64(s, 8), size = u64(s, 24),
             state = u32(s, 32), protect = u32(s, 36), kind = u32(s, 40) }
end

local function dl_collect()
    local list = {}
    local address = 65536
    while address < 0x800000000000 do
        local r = region_info(address)
        if not r or not r.size or r.size <= 0 then break end
        local prot = r.protect
        local readable = (prot == 2 or prot == 4 or prot == 8 or prot == 32 or prot == 64 or prot == 128)
        if r.state == 4096 and readable and (r.kind == 131072 or r.kind == 262144) and r.size >= 65536 then
            if not (dl_anchor and r.base <= dl_anchor and dl_anchor < r.base + r.size) then
                list[#list + 1] = { base = r.base, size = r.size }
            end
        end
        local nxt = r.base + r.size
        if nxt <= address then break end
        address = nxt
    end
    table.sort(list, function(a, b) return a.size > b.size end)
    return list
end

-- returns ptr, count, stride, type-id  (or nil)
local function dl_validate(win, at)
    if u32(win, at + 4) ~= 1 then return nil end
    local ty = u32(win, at + 8)
    if ty ~= DL_PROJECTILES then return nil end
    local size = u32(win, at + 12)
    local ptr = u64(win, at + 24)
    local cnt = u64(win, at + 32)
    if not ptr or not cnt or not size then return nil end
    if cnt < 64 or cnt > 8192 then return nil end
    if not ptr_ok(ptr) then return nil end
    local rem = size - 16
    if rem <= 0 or (rem % cnt) ~= 0 then return nil end
    local stride = rem / cnt
    if stride ~= PROJ_REC then return nil end
    return ptr, cnt, stride, ty
end

-- written once, when the scan stops: what it actually cost
local function dl_finish_log()
    if dl.logged then return end
    dl.logged = true
    local mb = dl.scanned / 1048576
    local secs = dl.elapsed
    log(('DLIB cost: %.1f s over %d frames, %d MB scanned (%.0f MB/s), budget=%s ms/frame')
        :format(secs, dl.frames, math.floor(mb),
                secs > 0.001 and (mb / secs) or 0, tostring(cfg.scan_ms or 4)))
end

-- Remember / reuse the address of the projectile table (v3.24).
-- Walking several GB of the process once per launch was the single biggest cost
-- of this addon, and most of it happened while sitting on the ship.  The address
-- is written into the cfg after the first successful search, and on the next
-- launch it is re-validated in full (magic, version, type id, stride, count and
-- a sample of the rows) before it is trusted - a moved address can therefore
-- never be used, it just costs one search again.
function dl.remember(addr)
    if not addr or (tonumber(cfg.proj_ptr) or 0) == addr then return end
    if state.save_cfg_key('proj_ptr', string.format('%d', addr)) then
        cfg.proj_ptr = addr
        log('DLIB remembered the projectile table address for the next launch: '
            .. hexa(addr))
    end
end
function dl.cached()
    if ctx.dl or dl.cache_tried then return end
    dl.cache_tried = true
    local p = tonumber(cfg.proj_ptr) or 0
    if not ptr_ok(p) then return end
    local head = rd(p, 64)
    if not head or head:sub(1, 8) ~= DL_SIG then   -- 'LDLD' + version 1
        log('DLIB remembered address is stale - searching again')
        return
    end
    local ptr, cnt, stride, ty = dl_validate(head, 0)
    if not ptr or ty ~= DL_PROJECTILES then
        log('DLIB remembered address is stale - searching again')
        return
    end
    if not rd(ptr, PROJ_REC) then
        log('DLIB remembered address is stale - searching again')
        return
    end
    local good = 0
    for k = 0, 7 do
        local idx = math.floor((cnt - 1) * k / 7)
        local t = u32(rd(ptr + PROJ_REC * idx, 4) or '', 0)
        if t and t > 0 and t < 100000 then good = good + 1 end
    end
    if good < 6 then
        log('DLIB remembered address is stale - searching again')
        return
    end
    ctx.dl = { records = ptr, count = cnt }
    log(('DLIB remembered address still valid: records=%s count=%d (0 MB scanned)')
        :format(hexa(ptr), cnt))
end

-- Walks the readable regions looking for the LDLD blocks we need:
--   ProjectileSettings        (per-round data, used for the damage id)
--   WeaponDataComponentData   (crosshair ids, used for the Javelin reticle)
local function dl_scan()
    -- v3.24: nothing this search finds is used outside a mission, and on the ship
    -- it walked several GB at scan_ms per frame while you were just standing
    -- there - the biggest single cost of the whole mod list.  Skip it entirely
    -- until a mission is running (ship_scan=1 restores the old behaviour).
    if cfg.ship_scan ~= 1 and ctx.mission ~= true then return ctx.dl end
    if not ctx.dl then dl.cached() end
    if dl.done then
        -- an option can be switched on AFTER the first pass already finished
        -- (the cfg is re-read every 300 frames).  Without this the block it needs
        -- would never be looked for, and the phase would fail in silence.
        if not dl.repass and dl_needed() then
            dl.done = false
            dl.repass = true
            dl.ri, dl.roff, dl.prev = 1, 0, ''
            log(('DLIB second pass - a newly enabled option needs another block '
                .. '(explosion=%s), walking %d regions again')
                :format('no',
                    dl.regions and #dl.regions or 0))
        else
            return ctx.dl
        end
    end
    if not dl_needed() then dl.done = true; return ctx.dl end
    if not dl.regions then
        dl.regions = dl_collect()
        log('DLIB candidate regions=' .. tostring(#dl.regions) ..
            ' (need: projectile=' .. tostring(not ctx.dl) ..
            ')')
        return nil
    end
    local start_budget = dl_budget()
    if start_budget <= 0 then return ctx.dl end     -- another phase already used it
    local deadline = os.clock() + start_budget
    dl.frames = dl.frames + 1
    if (state.frame % 300) == 0 and dl.regions then
        log(('DLIB progress: region %d/%d, %d MB, need proj=%s ex=%s%s')
            :format(dl.ri, #dl.regions, math.floor(dl.scanned / 1048576),
                ctx.dl and 'no' or 'yes',
                'no',
                dl.repass and ' (2nd pass)' or ''))
    end
    while os.clock() < deadline do
        local r = dl.regions[dl.ri]
        if not r then
            dl.done = true
            log(('DLIB scan finished (%d MB searched): projectile=%s weaponData=%s '
                .. 'explosion=%s sigHits=%d')
                :format(math.floor(dl.scanned / 1048576),
                        ctx.dl and 'found' or 'MISSING', ctx.wdl and 'found' or 'MISSING',
                        'not needed',
                        dl.sig and #dl.sig or 0))
            dl_finish_log()
            return ctx.dl
        end
        local remaining = r.size - dl.roff
        if remaining <= 0 then
            dl.ri, dl.roff, dl.prev = dl.ri + 1, 0, ''
        else
            local want = 65536            -- rd() caps a single read at 64 KB
            if want > remaining then want = remaining end
            local chunk = rd(r.base + dl.roff, want)
            dl.scanned = dl.scanned + want
            dl.roff = dl.roff + want
            if chunk then
                local wbase = r.base + dl.roff - want - #dl.prev
                local win = dl.prev .. chunk
                local from = 1
                while true do
                    local i = string.find(win, DL_SIG, from, true)
                    if not i then break end
                    local abs = wbase + i - 1
                    local skip = dl_anchor and (abs - dl_anchor > -4096 and abs - dl_anchor < 4096)
                    if not skip then
                        local ptr, cnt, stride, ty = dl_validate(win, i - 1)
                        if ptr then
                            if ty == DL_PROJECTILES then
                                if rd(ptr, PROJ_REC) and not ctx.dl then
                                    log(('DAMAGE projectile table found: magic=%s records=%s count=%d stride=%d')
                                        :format(hexa(abs), hexa(ptr), cnt, stride))
                                    ctx.dl = { records = ptr, count = cnt }
                                    dl.remember(abs)
                                end
                            end
                            if not dl_needed() then
                                dl.done = true
                                log(('DLIB stop early - everything this config needs is resolved (%d MB searched)')
                                    :format(math.floor(dl.scanned / 1048576)))
                                dl_finish_log()
                                return ctx.dl
                            end
                        end
                    end
                    from = i + 1
                end
                dl.prev = win:sub(-2048)
            else
                dl.prev = ''
            end
        end
    end
    local spent = os.clock() - (deadline - start_budget)
    if spent > 0 then
        dl.elapsed = dl.elapsed + spent
        dl.budget_left = dl.budget_left - spent
        if dl.budget_left < 0 then dl.budget_left = 0 end
    end
    return ctx.dl
end

local function dl_row_by_type(want)
    if not ctx.dl or not want then return nil end
    for i = 0, ctx.dl.count - 1 do
        local a = ctx.dl.records + PROJ_REC * i
        local head = rd(a, 4)
        if head and u32(head, 0) == want then return a end
    end
    return nil
end

-- legacy fallback: recognise the P-92 round by calibre/speed/mass only.
-- drag/gravity/type ids drift between patches, the shape does not.
local function dl_row_by_shape(dmg)
    if not ctx.dl then return nil end
    for i = 0, ctx.dl.count - 1 do
        local a = ctx.dl.records + PROJ_REC * i
        local rec = rd(a, PROJ_OFF_DAMAGE + 4)
        if rec and near(f32(rec, PROJ_OFF_CALIBRE), 12.0, 0.01)
            and near(f32(rec, PROJ_OFF_SPEED), 285.0, 1.0)
            and near(f32(rec, PROJ_OFF_MASS), 15.0, 0.5) then
            local d = u32(rec, PROJ_OFF_DAMAGE)
            if not dmg or d == dmg then
                log(('DAMAGE shape match @%s type=%s damage=%s')
                    :format(hexa(a), tostring(u32(rec, 0)), tostring(d)))
                return a, rec
            end
        end
    end
    return nil, nil
end

local dmg_multi_note = false
local function damage(on)
    if cfg.apw_damage ~= 1 then return true end
    -- each weapon already keeps its own damage (the ballistics row is untouched),
    -- and with two weapons leased there is no single "own damage id" to install
    if ctx.held and #ctx.held > 1 then
        if not dmg_multi_note then
            dmg_multi_note = true
            log('DAMAGE skipped: ' .. tostring(#ctx.held) .. ' weapons are in your hands, '
                .. 'each one keeps its own damage anyway')
        end
        return true
    end
    dl_scan()
    if not ctx.dl then return false end
    if not dl_rows then
        dl_rows = {}
        -- the damage id to install is read live from the APW round itself
        local want_dmg = APW_DAMAGE_ID
        if ctx.apw_proj_type then
            local a = dl_row_by_type(ctx.apw_proj_type)
            local d = a and u32(rd(a + PROJ_OFF_DAMAGE, 4) or '', 0) or nil
            if d and d > 0 and d < 100000 then
                want_dmg = d
                if state.dmg_live_logged ~= (ctx.apw_proj_type or 0) then
                    state.dmg_live_logged = ctx.apw_proj_type or 0
                    log(('DAMAGE round type=%d damage_id=%d (read live)')
                        :format(ctx.apw_proj_type, d))
                end
            else
                log('DAMAGE APW round type=' .. tostring(ctx.apw_proj_type) ..
                    ' not resolved in the projectile table - using ' .. tostring(APW_DAMAGE_ID))
            end
        end
        if ctx.warrant_type then
            local a = dl_row_by_type(ctx.warrant_type)
            if a then
                dl_rows[#dl_rows + 1] = { type = ctx.warrant_type, addr = a,
                                          orig = u32(rd(a + PROJ_OFF_DAMAGE, 4) or '', 0), want = want_dmg }
            else
                log('DAMAGE leased round type=' .. tostring(ctx.warrant_type) .. ' not in the projectile table')
            end
        end
        -- last resort, only if the runtime never told us which round we fire
        if #dl_rows == 0 and state.leased
            and (state.frame - (ctx.lease_frame or state.frame)) > 900 then
            local a, rec = dl_row_by_shape(P92_DAMAGE_ID)
            if a then
                dl_rows[#dl_rows + 1] = { type = 0, addr = a,
                                          orig = u32(rec, PROJ_OFF_DAMAGE), want = want_dmg }
            end
        end
        if #dl_rows == 0 then dl_rows = nil; return false end   -- try again
        for _, r in ipairs(dl_rows) do
            log(('DAMAGE target type=%s @%s damage %s -> %s')
                :format(tostring(r.type), hexa(r.addr), tostring(r.orig), tostring(r.want)))
        end
    end
    local all = true
    for _, r in ipairs(dl_rows) do
        local cur = u32(rd(r.addr + PROJ_OFF_DAMAGE, 4) or '', 0)
        if on then
            if cur == r.want then
                -- already right
            elseif cur == r.orig and r.orig and r.want and r.orig ~= r.want then
                if write_bytes(r.addr + PROJ_OFF_DAMAGE, word(r.want)) then
                    log(('DAMAGE ok  type=%s damage_id %d -> %d (APW-1 damage)')
                        :format(tostring(r.type), r.orig, r.want))
                else
                    all = false
                end
            else
                log(('DAMAGE type=%s holds %s - refusing'):format(tostring(r.type), tostring(cur)))
            end
        else
            if r.orig and cur == r.want and r.orig ~= r.want then
                if write_bytes(r.addr + PROJ_OFF_DAMAGE, word(r.orig)) then
                    log(('DAMAGE restored type=%s damage_id %d -> %d')
                        :format(tostring(r.type), r.want, r.orig))
                else
                    all = false
                end
            end
        end
    end
    return all
end

-- ------------------------------------------------------------------ ballistics
-- The round you actually fire keeps the APW-1 ProjectileSettings row (the
-- per-weapon lease only swaps the spawned *unit* at +40, which is where the
-- Warrant seeker component lives).  That row leaves the barrel at ~880 m/s, so
-- the seeker never gets time to turn.  This phase prints the live numbers and,
-- when you ask for it, rewrites speed / gravity for as long as you are armed.
local function ballistics_row()
    if not ctx.dl then return nil end
    local t = ctx.warrant_type or ctx.apw_proj_type
    local a = t and dl_row_by_type(t) or nil
    if not a and ctx.apw_proj_type then a = dl_row_by_type(ctx.apw_proj_type) end
    if not a and state.leased then a = dl_row_by_shape(nil) end
    return a, t
end

local function ballistics(on)
    dl_scan()
    if not ctx.dl then return false end
    if not bl_rows then
        local a, t = ballistics_row()
        if not a then return false end
        bl_rows = { addr = a, type = t or 0 }
        local rec = rd(a, 0x40)
        if not rec then bl_rows = nil; return false end
        local cal = f32(rec, PROJ_OFF_CALIBRE) or -1
        local spd = f32(rec, PROJ_OFF_SPEED) or -1
        local mas = f32(rec, PROJ_OFF_MASS) or -1
        local drg = f32(rec, PROJ_OFF_DRAG) or -1
        local grv = f32(rec, PROJ_OFF_GRAVITY) or -1
        bl_rows.speed = rd(a + PROJ_OFF_SPEED, 4)
        bl_rows.grav = rd(a + PROJ_OFF_GRAVITY, 4)
        if not bl_rows.speed or not bl_rows.grav then bl_rows = nil; return false end
        log(('BALLISTICS round type=%s @%s calibre=%.2f speed=%.1f mass=%.2f drag=%.3f gravity=%.3f')
            :format(tostring(t), hexa(a), cal, spd, mas, drg, grv))
    end
    local all = true
    local cs = rd(bl_rows.addr + PROJ_OFF_SPEED, 4)
    local cg = rd(bl_rows.addr + PROJ_OFF_GRAVITY, 4)
    local now_s, now_g = f32(cs or '', 0), f32(cg or '', 0)
    if cfg.round_speed > 0 then
        local want_s = cfg.round_speed
        if on then
            if math.abs((now_s or 0) - want_s) < 0.5 then
                -- already at the requested speed
            elseif write_bytes(bl_rows.addr + PROJ_OFF_SPEED, fbytes(want_s)) then
                log(('BALLISTICS speed %.1f -> %.1f m/s'):format(now_s or -1, want_s))
            else
                all = false
            end
        elseif bl_rows.speed and write_bytes(bl_rows.addr + PROJ_OFF_SPEED, bl_rows.speed) then
            log(('BALLISTICS speed restored to %.1f m/s'):format(f32(bl_rows.speed, 0) or -1))
        end
    end
    if cfg.round_gravity >= 0 then
        local want_g = cfg.round_gravity
        if on then
            if math.abs((now_g or 0) - want_g) < 0.01 then
                -- already at the requested gravity
            elseif write_bytes(bl_rows.addr + PROJ_OFF_GRAVITY, fbytes(want_g)) then
                log(('BALLISTICS gravity %.3f -> %.3f'):format(now_g or -1, want_g))
            else
                all = false
            end
        elseif bl_rows.grav and write_bytes(bl_rows.addr + PROJ_OFF_GRAVITY, bl_rows.grav) then
            log(('BALLISTICS gravity restored to %.3f'):format(f32(bl_rows.grav, 0) or -1))
        end
    end
    if not on then bl_rows = nil end
    return all
end

-- ------------------------------------------------ RL-77 cluster bomblets
-- The cluster burst spawns 25 bomblets from ONE ProjectileSettings row.  Nothing
-- else in the game uses that row, so it is patched in place: the spawned unit
-- becomes the warrant projectile (carrying SeekingMissileComponentData) and the
-- lifetime stops being zero.  The row keeps its own damage (270), its own blast
-- (7) and its own ballistics - only the entity it spawns changes, exactly like
-- the lease above.
-- One function on purpose: this chunk is at LuaJIT's 200 local slot cap.
local function cluster(on)
    if cfg.cluster_guide ~= 1 then return true end
    -- v4.13: flak_only leaves the launcher's ammunition exactly as shipped, and
    -- that includes the bomblets - no borrowed seeker unit, no extended life.
    if cfg.flak_only == 1 then on = false end
    -- launcher dropped or never picked up: give the row back if we still hold it
    if not ctx.rl77_id then on = false end
    if not on and not CLUSTER.row then
        if not ctx.cluster_note then
            ctx.cluster_note = 'idle'
            log('CLUSTER idle: the RL-77 is not in your hands. Add '
                .. '0x26E40437EA275296 to weapons= and carry the launcher.')
        end
        return true
    end
    if not CLUSTER.row then
        dl_scan()
        if not ctx.dl then return false end
        local found
        for i = 0, ctx.dl.count - 1 do
            local a = ctx.dl.records + PROJ_REC * i
            -- one read has to reach the LAST field of the gate (arming at +0xA0)
            local rec = rd(a, CLUSTER.arming_off + 4)
            if rec and #rec == CLUSTER.arming_off + 4
               and near(f32(rec, PROJ_OFF_CALIBRE), CLUSTER.calibre, 0.01)
               and near(f32(rec, PROJ_OFF_SPEED), CLUSTER.speed, 0.01)
               and near(f32(rec, PROJ_OFF_MASS), CLUSTER.mass, 0.01)
               and near(f32(rec, PROJ_OFF_GRAVITY), CLUSTER.gravity, 0.01)
               and near(f32(rec, CLUSTER.life_off), CLUSTER.life, 0.001)
               and near(f32(rec, CLUSTER.arming_off), CLUSTER.arming, 0.01) then
                found = a
                break
            end
        end
        if not found then
            if ctx.cluster_note ~= 'missing' then
                ctx.cluster_note = 'missing'
                log(('CLUSTER the bomblet row is not in the projectile table '
                    .. '(%d rows) - the factory shape changed, nothing was written')
                    :format(ctx.dl and ctx.dl.count or 0))
            end
            return false
        end
        ctx.cluster_note = nil
        local unit = rd(found + PROJ_OFF_UNIT, 8)
        local life = rd(found + CLUSTER.life_off, 4)
        if not unit or not life then return false end
        CLUSTER.row = { addr = found, type = u32(rd(found, 4) or '', 0) or 0,
                        unit = unit, life = life }
        ctx.bomb_type = CLUSTER.row.type
        log(('CLUSTER bomblet row: type=%s @%s unit=%s life=%.3f (RL-77 cluster burst)')
            :format(tostring(CLUSTER.row.type), hexa(found), hexs(unit),
                    f32(life, 0) or -1))
    end
    local r = CLUSTER.row
    local want_unit, want_name, mode = cluster_seeker()
    r.wrote, r.mode = want_unit, mode
    local cur = rd(r.addr + PROJ_OFF_UNIT, 8)
    local curl = rd(r.addr + CLUSTER.life_off, 4)
    if on then
        if cur ~= want_unit then
            local known = (cur == r.unit)
            if not known then
                for u = 0, CLUSTER.max_unit do
                    if cur == CLUSTER.units[u] then known = true break end
                end
            end
            if not known then
                log('CLUSTER bomblet unit is ' .. hexs(cur or '') .. ' - refusing')
                return false
            end
            if not write_bytes(r.addr + PROJ_OFF_UNIT, want_unit) then return false end
            log(('CLUSTER ok  type=%s +0x80 : bomblet unit -> %s (seeker %d %s)')
                :format(tostring(r.type), hexs(want_unit), mode, want_name))
        end
        local want = num_or(cfg.cluster_life, 0)
        if want and want > 0 then
            local now = f32(curl or '', 0)
            if not now or math.abs(now - want) > 0.01 then
                if write_bytes(r.addr + CLUSTER.life_off, fbytes(want)) then
                    log(('CLUSTER life %.2f -> %.2f s (0.0 never expires)')
                        :format(now or -1, want))
                end
            end
        end
        return true
    end
    local known = (cur == want_unit or cur == r.unit)
    if not known then
        for u = 0, CLUSTER.max_unit do
            if cur == CLUSTER.units[u] then known = true break end
        end
    end
    if known then
        write_bytes(r.addr + PROJ_OFF_UNIT, r.unit)
        log('CLUSTER restored type=' .. tostring(r.type) .. ' unit -> factory')
    end
    if curl and r.life and curl ~= r.life then
        write_bytes(r.addr + CLUSTER.life_off, r.life)
        log(('CLUSTER life restored to %.2f s'):format(f32(r.life, 0) or -1))
    end
    CLUSTER.row = nil
    ctx.bomb_type = nil
    ctx.bomb_lock = nil
    return true
end

-- ------------------------------------------------------------------ launcher
-- Guiding the CARRIER instead of the bomblets.
-- Four versions tried to make the 25 bomblets themselves home and every one of
-- them came back with the same live evidence - payload 236 (the main round) and
-- nothing else ever appears in the seeking manager, bombs=0 for the whole
-- mission.  That is consistent with the burst being spawned by the projectile
-- system as lightweight ballistic projectiles: row 233's +0x80 decides what they
-- LOOK like (which is why v4.4 visibly swapped them) but no actor with a
-- SeekingMissileComponent is ever created for them, so there is nothing to home.
--
-- The rocket that carries the burst is a different story - it is a weapon round
-- exactly like the APW-1's, and the APW-1 lease proves those can be swapped.  Its
-- own projectile row keeps the proximity fuse, so it still bursts; it just bursts
-- on top of whatever it flew into.
--
-- The launcher has two fire modes (Cluster and Flak), which is exactly why its
-- resource row fails the lease gate: +576 != 0 means it owns an ALTERNATE row,
-- and that field holds the second row's index.  There is no per-weapon copy to
-- write to, so both factory rows are patched in place.  Cost of that: while this
-- is on it applies to every RL-77 in the session, not only yours.  It is why the
-- phase rides on the same cluster_guide switch instead of being always on, and
-- why the factory value is put back the moment you drop the launcher or press F7.
-- v4.12: +576 IS NOT THE OTHER FIRE MODE.  Live (see the session log) it held
-- the index of a Male Agitator weapon row - rpm 700, a 140 m/s pistol round
-- whose unit is 0 - so every version up to v4.11 wrote the seeker onto a
-- civilian NPC's gun and never touched the cluster mode at all.  That is why
-- the cluster round stayed dumb ("集束模式不追踪") and why the row we called
-- "the cluster round, shortest fuse" was really the flak round: of the two rows
-- we had, the flak one (1.5 s) was simply shorter than the agitator's (10 s),
-- so the swarm was written over the flak round - "Flak 不产生子弹药".
--
-- The two fire modes are found the way the export proves they can be told
-- apart: theirs are the ONLY two ProjectileSettings rows that carry the
-- launcher's projectile unit.  Offline (1.006.301) that is unit
-- 3939411889253242210, held by type 94 (cluster: life 0.25 s, NO proximity
-- fuse) and type 301 (flak: life 1.50 s, 2.0 m) and by nothing else in the 337
-- rows.  So: seed the unit from any row the launcher's own resource hash owns,
-- then take EVERY fire mode row whose round carries that same unit.  Drift
-- proof, and it cannot pick up somebody else's weapon.
local LR = { rows = nil, note = nil }
-- one pass over the projectile table: type -> row address.  dl_row_by_type()
-- walks all 350 rows per call and the fire mode sweep below needs a lookup per
-- weapon row, so walking it 272 times would be 95k reads for one arming.
LR.proj_map = function()
    if LR.tmap then return LR.tmap end
    if not ctx.dl then return nil end
    local m = {}
    for i = 0, ctx.dl.count - 1 do
        local a = ctx.dl.records + PROJ_REC * i
        local t = u32(rd(a, 4) or '', 0)
        if t and t > 0 and not m[t] then m[t] = a end
    end
    LR.tmap = m
    return m
end
LR.rocket_of = function(row)
    local t = u32(row, 0)
    if not t or t <= 0 or t >= 8191 then return nil end
    local m = LR.proj_map()
    local a = m and m[t]
    local body = a and rd(a, PROJ_REC)
    if not body or #body ~= PROJ_REC then return nil end
    return {
        addr = a, type = t,
        unit = body:sub(PROJ_OFF_UNIT + 1, PROJ_OFF_UNIT + 8),
        speed = f32(body, PROJ_OFF_SPEED) or 0,
        cal = f32(body, PROJ_OFF_CALIBRE) or 0,
        life = f32(body, CLUSTER.life_off) or 0,
        prox = f32(body, 0x94) or 0,      -- explosion_proximity (PL.prox_off,
                                          -- declared further down this chunk)
    }
end
local function launcher_rows()
    if not ctx.em then return nil end
    if not ctx.dl then dl_scan() end
    if not ctx.dl then return nil end
    local want = CLUSTER.weapon
    local tb = ptr8(ctx.em + SET_TBL_OFF)
    if not tb then return nil end
    -- 1. seed: the rocket unit, read off a row the launcher's own hash owns
    local seed = nil
    for first = 0, SET_ENTRIES - 1, 512 do
        local cnt = math.min(512, SET_ENTRIES - first)
        local raw = rd(tb + 16 * first, 16 * cnt)
        if raw then
            for k = 0, cnt - 1 do
                if raw:sub(k * 16 + 1, k * 16 + 8) == want then
                    local idx = u32(raw, k * 16 + 8)
                    local row = idx and idx < SET_ROW_MAX
                                and rd(tb + SET_ROW_OFF + ROW_SIZE * idx, ROW_SIZE)
                    local pj = row and LR.rocket_of(row)
                    if pj and pj.unit ~= ZERO8 and pj.speed > 0 then
                        seed = pj.unit
                        break
                    end
                end
            end
        end
        if seed then break end
    end
    if not seed then return nil end
    -- 2. every fire mode row whose round carries that unit
    local out = {}
    for idx = 0, SET_ROW_MAX - 1 do
        local addr = tb + SET_ROW_OFF + ROW_SIZE * idx
        local row = rd(addr, ROW_SIZE)
        local pj = row and LR.rocket_of(row)
        if pj and pj.unit == seed then
            out[#out + 1] = { addr = addr, row = row, pj = pj, idx = idx }
            if #out >= 4 then break end
        end
    end
    if #out == 0 then return nil end
    -- 2b. how many ROUNDS carry that unit (the export says exactly two, the
    -- cluster round and the flak round).  If the sweep above found fewer fire
    -- mode rows than there are rounds, the missing one is configured somewhere
    -- else and the log has to say so instead of us quietly guiding one mode.
    local shared, more = {}, nil
    if ctx.dl then
        for i = 0, ctx.dl.count - 1 do
            local a = ctx.dl.records + PROJ_REC * i
            if rd(a + PROJ_OFF_UNIT, 8) == seed then
                shared[#shared + 1] = tostring(u32(rd(a, 4) or '', 0))
            end
        end
    end
    if #shared > #out then
        more = (' - %d round(s) share it but only %d fire mode row(s) were '
            .. 'found, so one mode is configured elsewhere'):format(#shared, #out)
    end
    log(('LAUNCHER the rocket unit is shared by %d round(s): %s%s')
        :format(#shared, table.concat(shared, ' '), more or ''))
    -- 3. which is which.  proximity is the better tell: it is what makes the
    --    flak round a flak round (offline 2.0 m) and the cluster round has none
    --    at all.  Fall back to the shorter fuse if that ever ties.
    if #out == 1 then
        out[1].kind = (out[1].pj.prox == 0) and 'cluster' or 'flak'
    else
        local timed = {}
        for i = 1, #out do
            if out[i].pj.prox == 0 then timed[#timed + 1] = i end
        end
        local ci
        if #timed == 1 then ci = timed[1]
        else
            ci = 1
            for i = 2, #out do
                if out[i].pj.life < out[ci].pj.life then ci = i end
            end
        end
        for i = 1, #out do out[i].kind = (i == ci) and 'cluster' or 'flak' end
    end
    return out
end

local function launcher(on)
    if cfg.cluster_guide ~= 1 then on = false end
    if not ctx.rl77_id then on = false end
    if not on and not LR.rows then return true end
    if not LR.rows then
        LR.rows = launcher_rows()
        if not LR.rows then
            LR.rows = nil
            if LR.note ~= 'missing' then
                LR.note = 'missing'
                log('LAUNCHER the RL-77 fire mode rows are not in the resource table '
                    .. '- the rocket itself stays unguided')
            end
            return false
        end
        LR.note = nil
        local at = {}
        for i, r in ipairs(LR.rows) do
            r.factory = r.row:sub(41, 48)
            at[#at + 1] = ('%s=%s'):format(r.kind or '?', hexa(r.addr))
            log(('LAUNCHER fire mode row %s [%s] factory +40=%s rpm=%.0f'
                 .. ' round type=%d speed=%.0f cal=%.0f life=%.3f prox=%.2f')
                :format(hexa(r.addr), r.kind or '?', hexs(r.factory),
                    f32(r.row, 8) or -1, r.pj and r.pj.type or 0,
                    r.pj and r.pj.speed or 0, r.pj and r.pj.cal or 0,
                    r.pj and r.pj.life or 0, r.pj and r.pj.prox or 0))
        end
        log('LAUNCHER ' .. #LR.rows .. ' row(s): ' .. table.concat(at, ' '))
    end
    local unit, name, mode = launcher_seeker()
    ctx.rocket_unit = unit
    for i, r in ipairs(LR.rows) do
        -- v4.13: flak_only - the cluster mode keeps its factory round.  Guiding
        -- it is what took the burst away (a borrowed seeker round does not
        -- scatter the bomblets), and the user asked for the launcher's ammo to
        -- behave exactly as shipped.  Only the flak round is patched.
        local on_row = not (cfg.flak_only == 1 and r.kind == 'cluster') and on
        local cur = rd(r.addr + 40, 8)
        local known = (cur == r.factory) or (cur == unit) or (cur == ZERO8)
                      or (cur == LEASE.bytes)
        if not known then
            for u = 0, CLUSTER.max_unit do
                if cur == CLUSTER.units[u] then known = true break end
            end
        end
        if not known then
            if LR.note ~= 'foreign' then
                LR.note = 'foreign'
                log('LAUNCHER row ' .. hexa(r.addr) .. ' holds ' .. hexs(cur or '')
                    .. ' at +40 - leaving it alone (another mod owns it)')
            end
        elseif on_row and cur ~= unit then
            if write_bytes(r.addr + 40, unit) then
                log(('LAUNCHER ok  row=%s +40 -> %s (seeker %d %s)')
                    :format(hexa(r.addr), hexs(unit), mode, name))
            end
        elseif (not on_row) and cur ~= r.factory then
            if write_bytes(r.addr + 40, r.factory) then
                log(('LAUNCHER restored row=%s +40 -> factory'):format(hexa(r.addr)))
            end
        end
    end
    if not on then LR.rows = nil end
    return true
end

-- ------------------------------------------------------------ the airburst
-- WHY THE CLUSTER BURST GOES OFF TOO EARLY - AND WHY THE BOMBLETS NEVER HOME
-- Offline (Data/settings/generated_projectile_settings.json, 1.006.301): the
-- RL-77 has TWO rocket rows, one per fire mode, both the same unit and the same
-- 250 m/s:
--   Cluster: type  94  life 0.25 s  proximity 0.0  -> explosion 286 -> 25 x type 227
--   Flak   : type 301  life 1.50 s  proximity 2.0  -> explosion 310 -> 25 x type   77
-- Type 227 (row index 101) is the cluster bomblet: calibre 40, speed 25, mass
-- 100, gravity 4, life 0.0, arming 1 - the exact six floats this addon hunts.
--
-- So the cluster mode is a PLAIN 0.25 SECOND TIMER. There is no proximity fuse
-- and nothing about a seeker in it: the rocket bursts a quarter of a second
-- after it leaves the tube no matter what it borrowed, which is why the user
-- saw it going off far too early and why blaming the seeker's fuse was wrong.
--
-- And the bomblets cannot be made to home, now for a structural reason and not
-- only for five versions of live evidence: in the WHOLE export there is not one
-- ProjectileSettings row whose unit carries a SeekingMissileComponent, and not
-- one explosion that spawns such a row. A projectile created by an explosion is
-- a lightweight ballistic thing by construction - row 227's +0x80 only decides
-- what it LOOKS like, which is why v4.4 visibly swapped them. That is also why
-- the seeking manager never sees payload 233: our own live census says so too
--   BURST seeking manager high=N - payloads seen so far: 236x128 96x85 312x758
-- three numbers, none of them the bomblet.
--
-- What CAN be done, and it lands the same result: the rocket is guided now, so
-- let the burst happen WHERE THE ROCKET ARRIVES. Two fields do it, life_time
-- (+0x34) and explosion_proximity (+0x94), on the cluster rocket's own row.

-- v4.11: the cluster mode becomes a GUIDED SWARM instead.
-- A projectile spawned by an explosion can never home (see above), but a
-- projectile spawned by a WEAPON can - so stop spawning them from the explosion
-- and let the weapon do it: num_projectiles (+0x1C) is the shotgun field, 31
-- rows in the export use it and one of them already ships 25. The cluster burst
-- has to be taken out at the same time (both explosion_type_on_impact +0x90 and
-- explosion_type_expire +0x9C go to 0) or every one of the 25 darts would
-- detonate and spawn 25 more - 625 bomblets from one trigger pull.
-- Each dart then keeps the launcher's borrowed seeker (launcher_seeker) and is
-- bound to its OWN target, so they fan out instead of stacking on one enemy.
-- Damage: the darts take the CLUSTER BOMBLET's DamageInfoType, so a burst of 25
-- guided darts hits for exactly what the factory burst of 25 bomblets hit for.
-- The flak row is never touched - two rows, two fire modes, one change.
local PL = { rows = nil, note = nil, prox_off = 0x94,
             num_off = 0x1C, expire_off = 0x9C }
-- (fields, not more top-level locals: this chunk is at LuaJIT's 200 local cap)
function PL.scan()
    -- v4.12: take the rows the launcher phase already classified.  Guessing
    -- again here by fuse length is exactly what went wrong: of the two rows we
    -- had, one was the flak round (1.5 s) and the other was a civilian pistol
    -- (10 s), so "shortest fuse" picked the flak round and turned IT into the
    -- swarm - while the real cluster round was never in the list at all.
    local src = LR.rows or launcher_rows()
    if not src then return nil end
    local seen = {}
    for i = 1, #src do
        local pj = src[i].pj
        local body = pj and rd(pj.addr, PROJ_REC)
        if body and #body == PROJ_REC then
            local lf, px = f32(body, CLUSTER.life_off), f32(body, PL.prox_off)
            if lf and px then
                seen[#seen + 1] = { addr = pj.addr, idx = pj.type,
                    kind = src[i].kind, life = lf, prox = px,
                    speed = f32(body, PROJ_OFF_SPEED) or 0,
                    num = u32(body, PL.num_off) or 0,
                    dmg = u32(body, PROJ_OFF_DAMAGE) or 0,
                    factory = {
                        [CLUSTER.life_off] = body:sub(CLUSTER.life_off + 1, CLUSTER.life_off + 4),
                        [PL.prox_off] = body:sub(PL.prox_off + 1, PL.prox_off + 4),
                        [PL.num_off] = body:sub(PL.num_off + 1, PL.num_off + 4),
                        [PROJ_OFF_EXPLODE] = body:sub(PROJ_OFF_EXPLODE + 1, PROJ_OFF_EXPLODE + 4),
                        [PL.expire_off] = body:sub(PL.expire_off + 1, PL.expire_off + 4),
                        [PROJ_OFF_DAMAGE] = body:sub(PROJ_OFF_DAMAGE + 1, PROJ_OFF_DAMAGE + 4),
                    } }
            end
        end
    end
    if #seen == 0 then return nil end
    -- cluster first, so PL.rows[1] is the row the swarm belongs on
    table.sort(seen, function(p, q)
        if p.kind == q.kind then return p.life < q.life end
        return p.kind == 'cluster'
    end)
    return seen
end
-- one u32 write, with the factory bytes put back when the value is off
function PL.set(r, off, want, tag)
    local cur = rd(r.addr + off, 4)
    if not cur then return false end
    local fac = r.factory[off]
    local isf = (off == CLUSTER.life_off or off == PL.prox_off)
    if want == nil then want = fac end
    if want == fac then
        if cur ~= fac then
            if write_bytes(r.addr + off, fac) then
                log('AIRBURST ' .. tag .. ' -> factory')
            end
        end
        return true
    end
    if cur == want then return true end
    if write_bytes(r.addr + off, want) then
        log(('AIRBURST %s %s -> %s'):format(tag,
            tostring(isf and f32(cur, 0) or u32(cur, 0)),
            tostring(isf and f32(want, 0) or u32(want, 0))))
        return true
    end
    return false
end
function PL.phase(on)
    if cfg.cluster_guide ~= 1 then on = false end
    -- v4.13: flak_only - the cluster round keeps its factory fuse, its factory
    -- burst and its factory damage.  Nothing of the swarm is written.
    if cfg.flak_only == 1 then on = false end
    if not ctx.rl77_id then on = false end
    local n = tonumber(cfg.swarm_count) or 0
    if n ~= n or n < 2 or n > 64 or n ~= math.floor(n) then n = 0 end
    if not on and not PL.rows then return true end
    if not PL.rows then
        dl_scan()
        if not ctx.dl then return false end
        PL.rows = PL.scan()
        if not PL.rows then
            PL.rows = nil
            if PL.note ~= 'missing' then
                PL.note = 'missing'
                log('AIRBURST no ProjectileSettings row belongs to the RL-77 fire '
                    .. 'modes - the cluster round is left alone')
            end
            return false
        end
        PL.note = nil
        for i, r in ipairs(PL.rows) do
            log(('AIRBURST rocket row #%d @%s speed=%.0f life=%.3f s prox=%.2f m'
                 .. ' num=%d dmg=%d   <- %s'):format(r.idx, hexa(r.addr),
                    r.speed, r.life, r.prox, r.num, r.dmg,
                    r.kind == 'cluster' and 'the CLUSTER round, this is the one '
                        .. 'the swarm goes on'
                        or 'the flak round, never touched'))
        end
    end
    local r = PL.rows[1]
    if on and r.kind ~= 'cluster' then
        -- v4.12: with only the flak round known, writing the swarm would take
        -- the flak bomblets away - say so once instead of doing it every frame
        if PL.note ~= 'nocluster' then
            PL.note = 'nocluster'
            log('AIRBURST the cluster fire mode was not found (only the flak '
                .. 'round is known) - the RL-77 is left as it is')
        end
        return true
    end
    if not on then n = 0 end
    if n > 1 then
        -- SWARM: the weapon fires them, the explosion does not
        PL.set(r, PL.num_off, word(n), 'darts per shot')
        PL.set(r, PROJ_OFF_EXPLODE, word(0), 'impact explosion')
        PL.set(r, PL.expire_off, word(0), 'expiry explosion')
        PL.set(r, PL.prox_off, nil, 'proximity fuse')
        local bd = CLUSTER.row and u32(rd(CLUSTER.row.addr + PROJ_OFF_DAMAGE, 4) or '', 0)
        if bd and bd > 0 and bd ~= r.dmg then
            PL.set(r, PROJ_OFF_DAMAGE, word(bd), 'dart damage -> the bomblet own')
        end
        local want_life = tonumber(cfg.rocket_life) or 0
        if want_life ~= want_life or want_life <= 0 or want_life > 10 then want_life = 0 end
        if want_life > 0 then
            PL.set(r, CLUSTER.life_off, fbytes(want_life), 'dart life')
        else
            -- rocket_life=0 means factory: 0.25 s, so the darts only reach ~60 m
            PL.set(r, CLUSTER.life_off, nil, 'dart life')
        end
        PL.note = 'swarm'
    else
        -- AIRBURST: keep the burst, just let the guided round reach the target
        local want_life = tonumber(cfg.rocket_life) or 0
        local want_prox = tonumber(cfg.rocket_prox) or 0
        -- disarm ALWAYS hands the row back, whether a value is configured or
        -- not - a configured fuse must not survive F7
        if not on then want_life, want_prox = 0, 0 end
        if want_life ~= want_life or want_life < 0 or want_life > 10 then want_life = 0 end
        if want_prox ~= want_prox or want_prox < 0 or want_prox > 50 then want_prox = 0 end
        if want_life > 0 then
            PL.set(r, CLUSTER.life_off, fbytes(want_life), 'cluster fuse')
        else
            PL.set(r, CLUSTER.life_off, nil, 'cluster fuse')
        end
        if want_prox > 0 then
            PL.set(r, PL.prox_off, fbytes(want_prox), 'proximity fuse')
        else
            PL.set(r, PL.prox_off, nil, 'proximity fuse')
        end
        PL.set(r, PL.num_off, nil, 'darts per shot')
        PL.set(r, PROJ_OFF_EXPLODE, nil, 'impact explosion')
        PL.set(r, PL.expire_off, nil, 'expiry explosion')
        PL.set(r, PROJ_OFF_DAMAGE, nil, 'damage')
    end
    if not on then PL.rows = nil end
    return true
end

-- ------------------------------------------------------------------ targets
local function refresh_targets()
    local hm = ptr8(base + R.health)
    if not hm then return false, 'no_health_manager' end
    hm = hm + 0x1008
    ctx.hm = hm
    local hh = rd(hm + 8, 16)
    if not hh then return false, 'health_header_unreadable' end
    local hcount = u32(hh, 12)
    if not hcount or hcount < 1 then return false, 'no_entities' end
    if hcount > 1024 then hcount = 1024 end
    local he, hd, hn = ptr8(hm + 0x40), ptr8(hm + 0x50), ptr8(hm + 0x58)
    if not he or not hd or not hn then return false, 'health_arrays_missing' end
    local pa = rd(he, 8 * hcount)
    if not pa then return false, 'health_array_unreadable' end
    -- ---- collect the candidates -----------------------------------------
    local list = {}
    for n = 0, hcount - 1 do
        local obj = u64(pa, 8 * n)
        if ptr_ok(obj) then
            local e = entity(obj)
            local want = e and e.id ~= ctx.avatar_id and e.net ~= UNBOUND
            -- P17: the watched-entity counters (debug only, see the log line)
            local w = (cfg.debug == 1 and e ~= nil) and state.watch_open(e.resource) or nil
            if w then w.seen = w.seen + 1 end
            if want then
                if cfg.lock_helldivers == 1 then
                    -- P2: friendly Helldivers only. Anything that is not the local
                    -- avatar's own entity type is skipped before the faction check.
                    want = (ctx.avatar_resource ~= nil and e.resource == ctx.avatar_resource)
                else
                    -- gate 1: the shipped whitelist
                    want = TARGETS[e.resource] ~= nil
                end
            end
            if want then
                if w then w.wanted = w.wanted + 1 end
                local hpb = rd(hd + 440 * n + 20, 4)
                local mxb = rd(hn + 28 * n + 20, 4)
                local stb = rd(hd + 440 * n + 412, 4)
                if hpb and mxb and stb then
                    local hp, mx, st = i32(hpb, 0), i32(mxb, 0), u32(stb, 0)
                    if hp and mx and st and hp > 0 and mx > 0 and hp <= mx and st == 0 then
                        if w then w.health = w.health + 1 end
                        local mask, pose_node = faction_of(e.id)
                        local accepted = true
                        if cfg.lock_helldivers == 1 then
                            -- P2: friendly means it shares our faction mask. An
                            -- unknown mask is accepted, because the entity resource
                            -- already matched the local avatar's own.
                            if mask and ctx.self_mask then accepted = intersects(mask, ctx.self_mask) end
                        else
                            if mask and ctx.self_mask then accepted = not intersects(mask, ctx.self_mask) end
                        end
                        if accepted and w then w.faction = w.faction + 1 end
                        if accepted and pose_node and pose_node < 1024 then
                            local x, y, z = bone(e.unit, pose_node)
                            -- P16: a unit whose pose node cannot be read used to be
                            -- dropped on the spot, so it could not be locked while it
                            -- stood in front of you. A Voteless that has lost its legs
                            -- is a different body with a different bone layout; the
                            -- root bone is the fallback.
                            if not x and pose_node ~= 0 then
                                x, y, z = bone(e.unit, 0)
                            end
                            if x then
                                if w then w.pose = w.pose + 1 end
                                list[#list + 1] = {
                                    id = e.id, net = e.net, unit = e.unit,
                                    name = TARGETS[e.resource]
                                        or (cfg.lock_helldivers == 1 and 'Helldiver' or nil),
                                    position = { x, y, z },
                                    res = e.resource,
                                    -- P17: usable is the count of records built
                                    -- P15: the bone that position came from, so the
                                    -- locked target can be re-read every frame
                                    node = pose_node,
                                    hp = hp, mx = mx,
                                }
                                if w then w.usable = w.usable + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    -- ---- diagnostics ----------------------------------------------------
    if cfg.lock_helldivers == 1 then
        -- one line per change of (avatar type, count), enough to tell "no teammate
        -- in the list at all" from "a teammate is there but out of the cone"
        local key = (ctx.avatar_resource and hexs(ctx.avatar_resource) or 'unknown') .. '/' .. #list
        if ctx.hl_note ~= key then
            ctx.hl_note = key
            log(('HELLDIVER LOCK: local avatar resource=%s, %d friendly avatar(s) in the health list')
                :format(ctx.avatar_resource and hexs(ctx.avatar_resource) or 'unknown', #list))
        end
    else
        ctx.hl_note = nil
    end
    -- P17: and out they go, every two seconds, for whichever watched unit was seen
    if cfg.debug == 1 and state.watch and (state.frame % 120) == 0 then
        local names = {}
        for name in pairs(state.watch) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local w = state.watch[name]
            log(('WATCH %s seen=%d wanted=%d health=%d faction=%d pose=%d usable=%d')
                :format(name, w.seen, w.wanted, w.health, w.faction, w.pose, w.usable))
        end
        state.watch = nil
    end
    -- ---- publish, and rebuild the per-weapon ordering sets --------------
    ctx.targets = list
    -- P10: the weapon in hand decides the order. aim_txt is published by the
    -- reticle and names the weapon the aim cone starts at; weapon_txt is the
    -- first one carried, and is the fallback when only one is.
    -- The priority list is PARSED HERE, not in the cfg loader: the loader runs
    -- before `local ctx` is declared, so building ctx.prio there indexed the
    -- global ctx and killed the whole load (see the note there).
    if ctx.prio_txt ~= state.prio_txt then
        ctx.prio_txt = state.prio_txt
        ctx.prio = {}
        if state.prio_txt then
            for tok in state.prio_txt:gmatch('[0-9A-Fa-fXx]+') do
                local b = hash8(tok)
                if b then ctx.prio[b] = true end
            end
        end
    end
    if ctx.prio_small_txt ~= state.prio_small_txt then
        ctx.prio_small_txt = state.prio_small_txt
        ctx.small = {}
        if state.prio_small_txt then
            for tok in state.prio_small_txt:gmatch('[0-9A-Fa-fXx]+') do
                local b = hash8(tok)
                if b then ctx.small[b] = true end
            end
        end
    end
    local who = hash8(ctx.aim_txt or '') or hash8(ctx.weapon_txt or '')
    ctx.big = who ~= nil and ctx.prio ~= nil and ctx.prio[who] == true
    ctx.smallest = who ~= nil and ctx.small ~= nil and ctx.small[who] == true
    -- P11: the guided weapon types, keyed the way the runtime prints an entity
    -- type (16 hex digits). The reticle draws the lock UI only while one of these
    -- is the weapon in hand.
    ctx.guided = {}
    for _, v in ipairs(WEAPONS_TXT) do
        local b = hash8(v)
        if b then
            local rev, fwd = {}, {}
            for i = 1, #b do
                rev[#rev + 1] = string.format('%02X', b:byte(#b + 1 - i))
                fwd[#fwd + 1] = string.format('%02X', b:byte(i))
            end
            ctx.guided[table.concat(rev)] = true
            ctx.guided[table.concat(fwd)] = true
        end
    end
    return true
end

local function aim_missing(src)
    ctx.aim_note = ctx.aim_note or {}
    if ctx.aim_note[src] then return end
    ctx.aim_note[src] = true
    log(('AIM weapon %s has no usable muzzle forward - cone_deg cannot filter it '
        .. '(cone_fallback=1 would lock the nearest enemy instead)')
        :format(tostring(src)))
end

-- scores every known enemy against ONE muzzle pose.
-- v4.11: with `want` it also returns the RANKED list, so a swarm of darts can
-- each be handed a DIFFERENT enemy instead of all chasing the same one.  The
-- first return value is unchanged, which keeps every old `local t = best_for(..)`
-- call site working.
-- P8: line of sight through the engine's own raycast. See the note in the
-- addon header. Nothing here runs unless cfg.los_check is turned on.
local LOS = (function()
    local fn
    -- exe_base, NOT base. The module table at the top of this file sets base from
    -- GetModuleHandleA('game.dll') and keeps the executable separately as
    -- exe_base, and the offset database records world_raycast as module="exe".
    -- base + 0x77DEC0 therefore aims into game.dll at an unrelated address, which
    -- is why v1.2.0 through v1.2.3 each died on the very first call however sane
    -- the arguments were. The standalone probe read its address from
    -- GetModuleHandleA(nil) - the exe - and never had the problem. The signature
    -- is checked here so a wrong address is reported rather than called.
    local okbind = pcall(function()
        if not exe_base then
            log('LOS no exe_base - line of sight disabled')
            return
        end
        local want = ('488bc44889581048897018574883ec708bd9')
            :gsub('..', function(x) return string.char(tonumber(x, 16)) end)
        local got = rd(exe_base + 0x77DEC0, #want)
        if got ~= want then
            log('LOS raycast signature does not match at exe_base+0x77DEC0')
            return
        end
        fn = ffi.cast('uint32_t (*)(uint32_t, const float *, const float *,'
            .. ' float, uint32_t, void *, uint32_t)', exe_base + 0x77DEC0)
        log(('LOS raycast bound at exe_base+0x77DEC0  (game.dll 0x%X, exe 0x%X)')
            :format(base or 0, exe_base))
    end)
    if not okbind or fn == nil then return nil end
    -- 16384, the size the standalone probe used, NOT a hand sized 2048. v1.2.0
    -- through v1.2.2 crashed on the very first call with a perfectly sane origin,
    -- and the only structural difference from the probe was this number. The
    -- database's hit_record_at = 1728 is the clue: the engine does not write the
    -- records where maxhits says it will, it writes them past 1728 - so a buffer
    -- sized from maxhits * stride is too small and the overflow lands in the lua
    -- heap. The probe never crashed because its buffer was always large.
    local MAXHITS, OUT = 8, 16384
    local out = ffi.new('uint8_t[' .. OUT .. ']')
    local o = ffi.new('float[3]')
    local d = ffi.new('float[3]')
    local api = { calls = 0, rays = 0, refused = 0, first_flags = 0 }
    -- speedtree_hit_flag, straight out of the offset database
    local SKIP = 0x800000
    -- A non-finite value must be refused BEFORE it reaches the engine: nan
    -- compares false against everything, so a guard written as
    -- `dist < 1 or dist > 400` lets it straight through, and a nan direction
    -- handed to a physics query is undefined behaviour at best. Target positions
    -- come out of this addon's own memory scan, so a bad one is a question of
    -- when, not if - v1.2.0 shipped without this and the game died the moment
    -- the filter armed.
    -- finite is not enough on its own: a huge but perfectly finite muzzle
    -- position handed to a physics query is just as undefined as a nan. 1e7 is
    -- far outside any playable coordinate, and the comparison also rejects nan
    -- and both infinities without needing to name them.
    local LIMIT = 1e7
    -- deliberately not the file-wide in_bounds(): this one is the world-space
    -- bound a physics query accepts, and it is named differently so the two
    -- rules cannot be confused at a call site
    local function in_bounds(n)
        return type(n) == 'number' and n == n and n <= LIMIT and n >= -LIMIT
    end
    function api.ray(desc, ox, oy, oz, dx, dy, dz, dist)
        if not (in_bounds(ox) and in_bounds(oy) and in_bounds(oz) and in_bounds(dx)
            and in_bounds(dy) and in_bounds(dz) and in_bounds(dist)) then
            api.refused = api.refused + 1
            return 0, nil, nil
        end
        o[0], o[1], o[2] = ox, oy, oz
        d[0], d[1], d[2] = dx, dy, dz
        ffi.fill(out, OUT, 0)
        api.rays = api.rays + 1
        local hits = tonumber(fn(desc or 0, o, d, dist, 0xFFFFFFFF, out, MAXHITS)) or 0
        if hits == 0 then return 0, nil, nil end
        -- Hit records the engine marks as something a round passes through - tree
        -- leaves are the obvious one - must not count as cover, or the sight test
        -- refuses a target that is only hidden by foliage while the bullet would
        -- have gone straight through it. The record carries a flags word at +32
        -- and the database names the foliage bit speedtree_hit_flag, so instead of
        -- hunting for a magic descriptor the list the engine already returned is
        -- walked for the first hit that does not carry it.
        local p = ffi.cast('uint8_t *', out)
        api.first_flags = ffi.cast('uint32_t *', p + 32)[0]
        for i = 0, hits - 1 do
            local rec = p + i * 44
            local flags = ffi.cast('uint32_t *', rec + 32)[0]
            local passable = cfg.los_foliage == 1 and flags % 0x1000000 >= SKIP
            if not passable then
                return hits, ffi.cast('float *', rec + 24)[0],
                    ffi.cast('uint32_t *', rec + 28)[0]
            end
        end
        -- every hit was pass-through geometry, so nothing solid is in the way
        return hits, nil, nil
    end
    -- P13: the same cast as api.ray, with every record written out instead of
    -- the first blocking one. Diagnostic only - nothing calls this while LOG
    -- SIGHT TEST is off, and it shares the same buffers.
    function api.trace(tag, desc, ox, oy, oz, dx, dy, dz, dist)
        if not (in_bounds(ox) and in_bounds(oy) and in_bounds(oz) and in_bounds(dx)
            and in_bounds(dy) and in_bounds(dz) and in_bounds(dist)) then return end
        o[0], o[1], o[2] = ox, oy, oz
        d[0], d[1], d[2] = dx, dy, dz
        ffi.fill(out, OUT, 0)
        local hits = tonumber(fn(desc or 0, o, d, dist, 0xFFFFFFFF, out, MAXHITS)) or 0
        local p = ffi.cast('uint8_t *', out)
        local n = hits
        if n > 8 then n = 8 end
        for i = 0, n - 1 do
            local rec = p + i * 44
            local flags = ffi.cast('uint32_t *', rec + 32)[0]
            local skipped = cfg.los_foliage == 1 and flags % 0x1000000 >= SKIP
            log(('LOS %s %d/%d dist=%.1f flags=0x%X mat=0x%X unit=%d %s')
                :format(tag, i + 1, hits, ffi.cast('float *', rec + 24)[0],
                    flags, ffi.cast('uint32_t *', rec + 36)[0],
                    ffi.cast('uint32_t *', rec + 28)[0],
                    skipped and 'SKIPPED-AS-FOLIAGE' or 'counts-as-cover'))
        end
    end

    -- at most this many rays per frame. best_for runs once per target and is
    -- called from several places per frame, so without a ceiling a busy frame
    -- could hand the physics engine hundreds of queries.
    local PER_FRAME = 64
    local budget_frame, budget_left = -1, 0
    -- true when something sits between from and to, closer than the target is
    function api.blocked(desc, fx, fy, fz, tx, ty, tz)
        api.calls = api.calls + 1
        if not (in_bounds(fx) and in_bounds(fy) and in_bounds(fz)
            and in_bounds(tx) and in_bounds(ty) and in_bounds(tz)) then
            api.refused = api.refused + 1
            return false
        end
        if budget_frame ~= state.frame then
            budget_frame, budget_left = state.frame, PER_FRAME
        end
        if budget_left <= 0 then return false end
        budget_left = budget_left - 1
        local dx, dy, dz = tx - fx, ty - fy, tz - fz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        -- written so that nan falls through to the refusal, unlike the
        -- `dist < 1 or dist > 400` this replaces
        if not (dist >= 1.0 and dist <= 400) then return false end
        local hits, hitd = api.ray(desc, fx, fy, fz, dx / dist, dy / dist, dz / dist, dist)
        if hits == 0 or hitd == nil or not in_bounds(hitd) then return false end
        return hitd < dist - 0.5
    end
    return api
end)()

local function best_for(o, f, valid, want)
    if not o or not f then return nil end
    local cone = (valid == true)
    local fl = math.sqrt(f[1] * f[1] + f[2] * f[2] + f[3] * f[3])
    if fl < 0.5 or fl > 1.5 then cone = false end
    local max_dist = num_or(cfg.max_dist, 250)
    -- ctx.cone_tan (published by the reticle's update_cone) is tan(effective
    -- half angle): already compensated for the camera FOV, and for the scope
    -- multiplier when that is switched on.  cos(atan(t)) = 1/sqrt(1+t^2), so
    -- the angle itself never has to be rebuilt here.  The ring uses the same
    -- number, which is what keeps "what is drawn" and "what is locked" equal.
    local cone_tan = tonumber(ctx.cone_tan)
    if not cone_tan or cone_tan ~= cone_tan or cone_tan < 0 then
        cone_tan = math.tan(math.rad(num_or(cfg.cone_deg, 12)))
    end
    local cos_limit = 1 / math.sqrt(1 + cone_tan * cone_tan)
    local best, best_score
    local acc
    if want and want > 1 then acc = {} end
    for _, c in ipairs(ctx.targets) do
        local p = c.position
        local dx, dy, dz = p[1] - o[1], p[2] - o[2], p[3] - o[3]
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist >= 0.01 and dist <= max_dist then
            local score
            if cone then
                local cos = (dx * f[1] + dy * f[2] + dz * f[3]) / (dist * fl)
                if cos >= cos_limit then
                    score = (1 - cos) * 1000 + dist / 1000
                    if ctx.big then
                        -- P10: biggest first. Max health carries a factor of a
                        -- million so it dominates, and the angle only breaks ties
                        -- between two enemies of the same size.
                        score = score - (c.mx or 0) * 1000000
                    elseif ctx.smallest then
                        -- P19: smallest first - the same trick, sign flipped.
                        score = score + (c.mx or 0) * 1000000
                    end
                end
            else
                score = dist
            end
            -- P14: the sight test starts at the WEAPON, not at the cone's apex.
            -- P6 put the acquisition cone on the camera so the ring and the marker
            -- sit where the player is looking, and the sight test inherited that
            -- origin - but in third person the camera is metres BEHIND and above
            -- the muzzle. Measured live over 94 rays: 36 of them had an obstacle
            -- the muzzle ray hit and the camera ray never reported at all, which is
            -- exactly "vegetation blocks the bullet and it still locks". The cone
            -- and the ranking stay on the camera axis; only the sight test moves
            -- to the muzzle, which is where the round actually starts.
            local sx, sy, sz = o[1], o[2], o[3]
            if ctx.origin then
                sx, sy, sz = ctx.origin[1], ctx.origin[2], ctx.origin[3]
            end
            if score and not (cfg.los_check == 1 and LOS
                and LOS.blocked(cfg.los_desc, sx, sy, sz, p[1], p[2], p[3])) then
                if acc then acc[#acc + 1] = { c = c, s = score }
                elseif (not best_score or score < best_score) then
                    best, best_score = c, score
                end
            end
        end
    end
    if not acc then return best end
    table.sort(acc, function(p, q) return p.s < q.s end)
    local out = {}
    for i = 1, math.min(#acc, want) do out[i] = acc[i].c end
    return out[1], out
end

local function pick_target()
    ctx.target = nil
    if not ctx.origin or not ctx.forward then return nil, 'no_muzzle_pose' end
    -- P6: acquire inside the cone the player can SEE. The range ring is a circle
    -- about the CAMERA - a cone with its apex there projects to exactly that
    -- circle at every depth - while this used to test from the muzzle, whose axis
    -- differs by several degrees in third person. That is wider than the whole
    -- cone at a tight LOCK ANGLE, so enemies outside the ring were acquired. The
    -- muzzle pose stays the fallback, and still drives the projectile binding.
    if ctx.cam_origin and ctx.cam_forward then
        ctx.target = best_for(ctx.cam_origin, ctx.cam_forward, true)
    else
        ctx.target = best_for(ctx.origin, ctx.forward, ctx.forward_valid)
    end
    -- logs the counters even with no muzzle pose, so a run where nothing was
    -- ever cast is distinguishable from a run where the filter never armed
    if cfg.los_debug == 1 and LOS and (state.frame % 120) == 0 then
        local dh, dhd, th, thd = 0, nil, 0, nil
        -- written BEFORE the call on purpose: v1.2.0 and v1.2.1 logged only after
        -- it, so a crash in the ray left a log with nothing in it at all
        log(('LOS enter f=%d origin=%s check=%d'):format(state.frame,
            ctx.origin and 'yes' or 'no', cfg.los_check))
        if ctx.origin then
            log(('LOS casting down from %s %s %s')
                :format(tostring(ctx.origin[1]), tostring(ctx.origin[2]),
                        tostring(ctx.origin[3])))
            dh, dhd = LOS.ray(cfg.los_desc, ctx.origin[1], ctx.origin[2],
                ctx.origin[3], 0.0, -1.0, 0.0, 100.0)
            log(('LOS down done hits=%s dist=%s'):format(tostring(dh),
                dhd and string.format('%.1f', dhd) or '-'))
            if ctx.target and ctx.target.position then
                local q = ctx.target.position
                local dx, dy, dz = q[1] - ctx.origin[1], q[2] - ctx.origin[2],
                    q[3] - ctx.origin[3]
                local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dl > 1 and dl < 400 then
                    log(('LOS casting at target dl=%.1f dir %.3f %.3f %.3f')
                        :format(dl, dx / dl, dy / dl, dz / dl))
                    th, thd = LOS.ray(cfg.los_desc, ctx.origin[1], ctx.origin[2],
                        ctx.origin[3], dx / dl, dy / dl, dz / dl, dl)
                    log(('LOS target done hits=%s dist=%s'):format(tostring(th),
                        thd and string.format('%.1f', thd) or '-'))
                end
            end
        end
        log(('LOS desc=%d check=%d calls=%d rays=%d refused=%d | down hits=%s dist=%s | target hits=%s dist=%s')
            :format(cfg.los_desc, cfg.los_check, LOS.calls, LOS.rays, LOS.refused,
                tostring(dh), dhd and string.format('%.1f', dhd) or '-',
                tostring(th), thd and string.format('%.1f', thd) or '-'))
        log(('LOS first hit flags = 0x%X (foliage bit 0x%X, skipping=%s)')
            :format(LOS.first_flags, 0x800000, cfg.los_foliage == 1 and 'yes' or 'no'))
        -- P13: every record of the three rays, so "which hit was skipped, and
        -- would a bullet have stopped there" is answerable from the log instead
        -- of guessed at. dist/flags/material/unit is the whole record. Each ray is
        -- guarded on its own origin: this runs outside the ctx.origin block above.
        if ctx.origin then
            LOS.trace('down', cfg.los_desc, ctx.origin[1], ctx.origin[2],
                ctx.origin[3], 0.0, -1.0, 0.0, 100.0)
        end
        if ctx.cam_origin and ctx.cam_forward then
            LOS.trace('aim-cam', cfg.los_desc, ctx.cam_origin[1], ctx.cam_origin[2],
                ctx.cam_origin[3], ctx.cam_forward[1], ctx.cam_forward[2],
                ctx.cam_forward[3], 120.0)
        end
        if ctx.origin and ctx.cam_forward then
            LOS.trace('aim-muz', cfg.los_desc, ctx.origin[1], ctx.origin[2],
                ctx.origin[3], ctx.cam_forward[1], ctx.cam_forward[2],
                ctx.cam_forward[3], 120.0)
        end
    end
    if not ctx.target then
        return nil, (ctx.forward_valid == true) and 'nothing_in_cone' or 'nothing_in_range'
    end
    -- P15: the marker has to sit on the enemy NOW. The scan above only runs every
    -- target_interval frames (20 by default - a third of a second), so the position
    -- handed to the reticle was that old: a walking enemy was marked a body length
    -- behind itself while the ring stayed exact. Re-reading the one bone the scan
    -- already chose costs a few reads a frame; a failed read keeps the old value.
    if ctx.target.unit and ctx.target.node then
        local tx, ty, tz = bone(ctx.target.unit, ctx.target.node)
        if tx then ctx.target.position = { tx, ty, tz } end
    end
    -- P15: with BIG FIRST on, one line per change of target saying what won and
    -- on which number, so the order can be checked from the log.
    if ctx.big then
        local t = ctx.target
        if ctx.big_note ~= t.id then
            ctx.big_note = t.id
            log(('BIG FIRST locked %s (max hp %s, hp now %s)')
                :format(tostring(t.name), tostring(t.mx), tostring(t.hp)))
        end
    else
        ctx.big_note = nil
    end
    return ctx.target
end

-- Which target the 25 cluster bomblets should chase.
-- The launcher's own lock is the freshest answer to "the target the airburst
-- launcher acquired with this mod": it is whatever the round you just fired was
-- actually bound to, whether this addon bound it or the engine did.  Only if the
-- launcher never got that far do we fall back to scoring its own muzzle cone,
-- and after that to the target the mod is showing for the weapon in your hands.
-- A lock stays usable for two seconds, which comfortably covers the 0.25 s the
-- cluster rocket lives plus the burst delay.
local function bomb_aim()
    local lock = ctx.bomb_lock
    if lock and (state.frame - lock.at) <= 120 then return lock end
    local ps = ctx.rl77_id and ctx.pose and ctx.pose[ctx.rl77_id]
    if ps then
        local t = best_for(ps.origin, ps.forward, ps.valid)
        if not t and cfg.cone_fallback == 1 then t = best_for(ps.origin, ps.forward, false) end
        if t then return { net = t.net, name = t.name, at = state.frame } end
    end
    return ctx.target
end

-- ------------------------------------------------------------------ binding
-- The engine is handed a pointer to the value, so every published buffer has
-- to stay alive for the rest of the session and none of them are ever freed.
-- That is why this is capped: past the cap the native notification is skipped,
-- while the binding itself (the write_bytes call below) keeps working.
local PUB_MAX = 8192
local pub_buffers = {}
local function publish(net, field, value)
    if not PUBLISH_OK then return false end
    if type(net) ~= 'number' or net == UNBOUND then return false end
    if #pub_buffers >= PUB_MAX then return false end
    local b = ffi.new('uint32_t[1]', math.floor(value) % 4294967296)
    pub_buffers[#pub_buffers + 1] = b
    return pcall(function() PUBLISH(net, field, b) end)
end

local function bind_projectiles()
    local sm = ptr8(base + R.seeking)
    if not sm then return false, 'no_seeking_manager' end
    ctx.sm = sm
    local h = rd(sm, 24)
    if not h then return false, 'seeking_header_unreadable' end
    local count, active, authority = u32(h, 8), u32(h, 12), u32(h, 16)
    if not count or not active or not authority then return false, 'seeking_counts_unreadable' end
    ctx.seek_active = active
    if active < 1 or count < 1 then return true end
    local limit = active
    if limit > 128 then limit = 128 end
    local entries, runtime, net = ptr8(sm + 0x38), ptr8(sm + 0x48), ptr8(sm + 0x50)
    if not entries or not runtime or not net then return false, 'seeking_arrays_missing' end
    local bulk = rd(runtime, 192 * limit)
    if not bulk then return false, 'seeking_runtime_unreadable' end
    local bound, natively_bound, not_ready, too_young = 0, 0, 0, 0
    -- ---- walk every live entry of the seeking manager ------------------
    for i = 0, limit - 1 do
        local o = 192 * i
        local payload, age, src = u32(bulk, o + 0x34), f32(bulk, o + 0x24), u32(bulk, o + 0x84)
        -- v4.7: every distinct payload the seeking manager ever carries is
        -- logged once.  Three versions have now failed to guide a bomblet and
        -- the whole time the only payload in the log was the main round's.  If
        -- the bomblet does register, it registers under SOME number - and it may
        -- well not be 233 any more, because we swapped its unit, so the row the
        -- projectile system looks up may be the borrowed missile's own row.
        -- ---- census: every distinct payload seen this session ----------
        if payload and payload ~= 0 then
            local seen = ctx.seen_payload
            if not seen then seen = {}; ctx.seen_payload = seen end
            local e = seen[payload]
            if not e then
                e = { n = 0, src = src, frame = state.frame }
                seen[payload] = e
                log(('SEEK payload=%d first seen (src=%s, bomblet row type=%s, '
                     .. 'own round type=%s)'):format(payload, tostring(src),
                        tostring(ctx.bomb_type), tostring(ctx.apw_proj_type)))
            end
            e.n = e.n + 1
        end
        -- A bomblet is spawned by the cluster burst, not by the weapon, so its
        -- "source weapon" slot is not the launcher.  Two ways to recognise it:
        -- its runtime payload is its projectile type (the number the cluster
        -- phase resolved), or - and the live log says this is worth trying - the
        -- entry simply has NO source weapon at all, because the explosion and
        -- not the weapon put it here.  Only while the launcher is in hand, so
        -- the fragments of somebody else's gun are left alone.
        -- ---- is this entry one of ours? ---------------------------------
        local bomb = ctx.bomb_type ~= nil and ctx.rl77_id ~= nil
            and (payload == ctx.bomb_type or src == 0)
        -- v4.9: the ROCKET is the one that actually reaches the seeking manager.
        -- It carries the launcher's own weapon id in src, and the launcher can
        -- never take a per-weapon row (two fire modes), so ctx.wset has no entry
        -- for it and the test below used to say "not mine" - the v4.8 log shows
        -- payload 96 and 312 with src = the launcher, in the manager, and never
        -- bound once.  The id is remembered for a few seconds so a rocket still
        -- in flight after you holster the launcher still gets its target.
        local rocket = cfg.cluster_guide == 1 and ctx.rl77_recent ~= nil
            and src == ctx.rl77_recent.id
            and (state.frame - ctx.rl77_recent.at) < 600
        local mine = src == ctx.weapon_id or ctx.weapon_id == nil
            or (ctx.wset and ctx.wset[src] and ctx.wset[src].leased)
            or bomb or rocket
        if mine then
            if bomb then ctx.bomb_seen = (ctx.bomb_seen or 0) + 1 end
            if rocket and payload and ctx.rocket_type ~= payload then
                ctx.rocket_type = payload
                log('LAUNCHER rocket registered in the seeking manager, payload='
                    .. tostring(payload))
            end
            if state.leased and payload and not ctx.warrant_type and not bomb
               and not rocket then
                ctx.warrant_type = payload
                log('PROJECTILE leased round type=' .. tostring(payload) .. ' (runtime payload)')
            end
            -- ---- arm and bind an entry that has no target yet ----------
            local nb = rd(net + 56 * i, 56)
            if nb then
                local tgt = u32(nb, 0)
                if tgt == UNBOUND then
                    too_young = too_young + 1
                    -- with several weapons listed, the shared target is the one
                    -- the FIRST weapon would aim at - and its muzzle is the one
                    -- on your back - so score this projectile against the pose
                    -- of the weapon that actually fired it
                    local aim, delay = ctx.target, num_or(cfg.bind_delay, 0.25)
                    if bomb then
                        -- 25 of them appear at once and they are all meant to
                        -- follow the launcher's own lock, not to each pick their
                        -- own - and they only live cluster_life seconds, so the
                        -- arm delay has to be short enough to matter
                        aim, delay = bomb_aim(), num_or(cfg.cluster_delay, 0.05)
                    else
                        -- v4.9: the rocket can burst within a quarter of a
                        -- second of leaving the tube, so it must not wait for
                        -- the main round's arm time - it gets the bomblet's
                        if rocket then delay = num_or(cfg.cluster_delay, 0.05) end
                        local ps = ctx.pose and ctx.pose[src]
                        -- P7: score on the SAME axis the reticle draws with, so the
                        -- round goes to the enemy the marker is on. ctx.target, and
                        -- therefore the marker, is best_for(cam_origin, cam_forward,
                        -- true) - the camera axis. Scoring from the firing weapon's
                        -- muzzle puts a second axis in play: in third person it sits
                        -- several degrees off the camera and best_for ranks purely by
                        -- angle, so two enemies standing together let the two axes
                        -- name different ones - marker on A, round into B. With one
                        -- axis they cannot disagree. ps is only read as .origin /
                        -- .forward / .valid below, so substituting it is enough.
                        if ps and ctx.cam_origin and ctx.cam_forward then
                            ps = { origin = ctx.cam_origin, forward = ctx.cam_forward,
                                   valid = true }
                        end
                        if ps then
                            -- v4.11: a swarm round gets its OWN enemy, taken
                            -- round robin over the ranked cone, so the 25 darts
                            -- fan out instead of all stacking on the same one
                            local sn = tonumber(cfg.swarm_count) or 0
                            if rocket and sn > 1 and cfg.swarm_split == 1 then
                                local first, ranked = best_for(ps.origin, ps.forward,
                                                               ps.valid, 24)
                                aim = first
                                if ranked and #ranked > 1 then
                                    ctx.swarm_seq = (ctx.swarm_seq or 0) + 1
                                    aim = ranked[((ctx.swarm_seq - 1) % #ranked) + 1]
                                end
                                if not aim and cfg.cone_fallback == 1 then
                                    local f2, r2 = best_for(ps.origin, ps.forward,
                                                             false, 24)
                                    aim = f2
                                    if r2 and #r2 > 1 then
                                        ctx.swarm_seq = (ctx.swarm_seq or 0) + 1
                                        aim = r2[((ctx.swarm_seq - 1) % #r2) + 1]
                                    end
                                end
                            else
                                aim = best_for(ps.origin, ps.forward, ps.valid)
                            end
                            if not aim and cfg.cone_fallback == 1 then
                                aim = best_for(ps.origin, ps.forward, false)  -- nearest instead
                            end
                            if not aim and ps.valid ~= true then
                                aim_missing(src)
                            end
                            -- no silent "nearest enemy" fallback: if the cone is empty
                            -- the round simply is not bound, otherwise cone_deg does
                            -- nothing at all and every shot locks in every direction
                        end
                    end
                    if bomb and not aim then
                        ctx.bomb_noaim = (ctx.bomb_noaim or 0) + 1
                    end
                    if cfg.lua_bind == 1 and aim and (not age or age >= delay) then
                        if nb:byte(0x35 + 1) ~= 1 then
                            not_ready = not_ready + 1
                            if bomb then
                                ctx.bomb_notready = (ctx.bomb_notready or 0) + 1
                            end
                        else
                            local ep = u64(rd(entries + 8 * i, 8) or '', 0)
                            if ptr_ok(ep) then
                                local e = entity(ep)
                                -- a bomblet borrowed whichever seeker entity
                                -- cluster_seeker picked, which is not always the
                                -- warrant the main round uses
                                local want_res = LEASE.bytes
                                if bomb and CLUSTER.row and CLUSTER.row.wrote then
                                    want_res = CLUSTER.row.wrote
                                elseif rocket and ctx.rocket_unit then
                                    want_res = ctx.rocket_unit
                                end
                                if bomb and e and e.resource ~= want_res then
                                    ctx.bomb_noent = (ctx.bomb_noent or 0) + 1
                                end
                                if e and e.resource == want_res and e.flags % 4 == 1 then
                                    local addr = net + 56 * i
                                    local bytes = word(aim.net) .. word(GUIDANCE_NODE)
                                    if write_bytes(addr, bytes) then
                                        local ok1 = publish(e.net, FIELD_NODE, GUIDANCE_NODE)
                                        local ok2 = publish(e.net, FIELD_TARGET, aim.net)
                                        bound = bound + 1
                                        state.binds = state.binds + 1
                                        ctx.engine_lock_at = state.frame
                                        if bomb then
                                            ctx.bomb_bound = (ctx.bomb_bound or 0) + 1
                                        end
                                        if src == ctx.rl77_id and not bomb then
                                            ctx.bomb_lock = { net = aim.net, name = aim.name,
                                                              at = state.frame }
                                        end
                                        log(('BIND #%d proj net=%u idx=%d payload=%s age=%s -> %s net=%u dist=%.1f (node=%s target=%s)')
                                            :format(state.binds, e.net, i, tostring(payload),
                                                age and string.format('%.3f', age) or '?',
                                                tostring(aim.name), aim.net,
                                                ctx.last_dist or -1, tostring(ok1), tostring(ok2)))
                                    else
                                        log('BIND failed to write target at ' .. hexa(addr))
                                    end
                                end
                            end
                        end
                    end
                else
                    natively_bound = natively_bound + 1
                    ctx.engine_lock_at = state.frame
                    -- the engine locked this one itself: that is still "the
                    -- target the launcher acquired", so remember it for the
                    -- bomblets that are about to spawn
                    if src == ctx.rl77_id and not bomb and tgt ~= UNBOUND then
                        ctx.bomb_lock = { net = tgt, name = 'launcher lock',
                                          at = state.frame }
                    end
                end
            end
        end
    end
    if cfg.debug == 1 and (bound + natively_bound + not_ready + too_young) > 0
        and (state.frame % 60) == 0 then   -- once a second, not once a frame
        log(('SEEK active=%d mine=%d bound=%d engine_bound=%d not_ready=%d too_young=%d')
            :format(active, limit, bound, natively_bound, not_ready, too_young))
    end
    -- ---- diagnostics (debug=1 only) ---------------------------------
    -- v4.5 diagnosis: is the bomblet even IN the seeking manager, and if it is,
    -- why did it not get a target?  Debug only, it is a read of every entry.
    if cfg.debug == 1 and (state.frame % 30) == 0 then
        local parts = {}
        local n = limit
        if n > 32 then n = 32 end
        for i = 0, n - 1 do
            local o = 192 * i
            local p2 = u32(bulk, o + 0x34)
            local a2 = f32(bulk, o + 0x24)
            local s2 = u32(bulk, o + 0x84)
            local t2 = u32(rd(net + 56 * i, 4) or '', 0)
            parts[#parts + 1] = ('%d:p%s/s%s/t%s/%.2f'):format(i, tostring(p2),
                tostring(s2), tostring(t2 or -1), a2 or -1)
        end
        log(('SEEKDUMP active=%d count=%d auth=%d %s'):format(active, count,
            authority, table.concat(parts, ' ')))
    end
    -- v4.7: a new high-water mark while the launcher is in your hands is the
    -- moment a burst would have to show up.  Dump the whole census so the log
    -- says outright what the 25 bomblets registered as - or that nothing did.
    if ctx.rl77_id and active > (ctx.seek_peak or 0) then
        ctx.seek_peak = active
        local parts = {}
        for p, e in pairs(ctx.seen_payload or {}) do
            parts[#parts + 1] = ('%dx%d'):format(p, e.n)
        end
        log(('BURST seeking manager high=%d - payloads seen so far: %s')
            :format(active, table.concat(parts, ' ')))
    end
    if (state.frame % 60) == 0 then
        local bs = ctx.bomb_seen or 0
        if bs > 0 or (ctx.bomb_noaim or 0) > 0 or (ctx.bomb_notready or 0) > 0
            or (ctx.bomb_noent or 0) > 0 then
            log(('BOMBLET seen=%d bound_ok=%d no_target=%d not_ready=%d wrong_entity=%d')
                :format(bs, ctx.bomb_bound or 0, ctx.bomb_noaim or 0,
                        ctx.bomb_notready or 0, ctx.bomb_noent or 0))
        end
    end
    return true
end

-- ===================================================================
-- Own reticle: screen overlay + world marker
-- ===================================================================
-- HD2 draws screen overlays through its UI world with
--   sr.World.create_screen_gui(world,'scale',1,1) + sr.Gui.triangle(gui,a,b,c,100,color)
-- That is exactly what the P-11 Stim Homing addon uses for its orange/green
-- aiming circle, and it needs no weapon resource at all - so it works even
-- though we never managed to reach the APW-1 WeaponData row.
-- Rules taken from that addon (all of them are load bearing):
--   * sr is the global 'stingray'
--   * every call must run inside sr.Script.temp_byte_count / set_temp_byte_count
--     (skipping it is a known crash)
--   * the UI world is any world that is not the mission world
--   * GUI coordinates are (screenX, 0, screenY), origin at the screen centre
--   * the triangles must NOT be refreshed every frame: HD2 makes the ring vanish
--     when they are updated at a colour change.  Rebuild only when resolution,
--     colour or visibility changes.
-- ------------------------------------------------------ P-92 seeker speed
-- WHY THIS EXISTS: the leased round does NOT take its speed from the
-- ProjectileSettings row (that row still says 1300, and that is the row
-- round_speed rewrites).  The movement is driven by the
-- SeekingMissileComponentData of the leased P-92 Warrant projectile, and out of
-- the box that component says starting_speed = minimum_speed = preferred_speed
-- = 90, which is why guided rounds crawl no matter what round_speed is set to.
-- This locates that one component row and rewrites the three speeds.
local SEEK_DL = 0xBF3A6789
local SEEK_REC = 272
local SEEK_MAX = 512
local SEEK_NEEDLE = 'LDLD' .. word(1) .. word(SEEK_DL)
local seek = { regions = nil, ri = 1, roff = 0, prev = '', scanned = 0,
               done = false, frames = 0 }
local sk_rows = nil

local function seek_header(at)
    local h = rd(at, 40)
    if not h or #h < 40 then return nil end
    if h:sub(1, 4) ~= 'LDLD' then return nil end
    if u32(h, 4) ~= 1 or u32(h, 8) ~= SEEK_DL then return nil end
    local ptr = u64(h, 24)
    local cnt = u32(h, 32) or 0
    if not ptr or cnt < 1 or cnt > SEEK_MAX then return nil end
    if not ptr_ok(ptr) then return nil end
    return ptr, cnt
end
-- The three speeds sit next to each other and on the Warrant they are all
-- equal (90 / 90 / 90) with acceleration 200 right behind them, so the row can
-- point at its own offsets instead of us trusting a derived constant.
local function seek_speeds(addr)
    local b = rd(addr, SEEK_REC)
    if not b or #b < SEEK_REC then return nil end
    for o = 0, SEEK_REC - 16, 4 do
        local s1, s2, s3, ac = f32(b, o), f32(b, o + 4), f32(b, o + 8), f32(b, o + 12)
        if s1 and s2 and s3 and ac and s1 == s2 and s1 == s3
           and s1 > 1 and s1 < 5000 and math.abs(ac - 200) < 1 then
            return o, s1, b:sub(o + 1, o + 12)
        end
    end
    for o = 0, SEEK_REC - 12, 4 do
        local s1, s2, s3 = f32(b, o), f32(b, o + 4), f32(b, o + 8)
        if s1 and s2 and s3 and s1 == s2 and s1 == s3 and s1 > 1 and s1 < 5000 then
            return o, s1, b:sub(o + 1, o + 12)
        end
    end
    return nil
end
local function seek_rows_at(at)
    local rows, cnt = seek_header(at)
    if not rows then return nil end
    local blob = rd(rows, cnt * SEEK_REC)
    if not blob or #blob < cnt * SEEK_REC then return nil end
    local j = string.find(blob, P92_ENTITY_B, 1, true)
    if not j then return nil end
    local row_base = rows + math.floor((j - 1) / SEEK_REC) * SEEK_REC
    local off, val, orig = seek_speeds(row_base)
    if not off then
        log(('SEEKER row @%s found but the speed triple is not where it should be '
            .. '- no write'):format(hexa(row_base)))
        return nil
    end
    sk_rows = { addr = row_base, off = off, orig = orig, accel_off = off + 12 }
    log(('SEEKER P-92 Warrant component row @%s, speeds at +0x%X = %.1f m/s')
        :format(hexa(row_base), off, val))
    return sk_rows
end
local function seek_find()
    if sk_rows then return sk_rows end
    local p = tonumber(cfg.seek_ptr) or 0
    if ptr_ok(p) then
        local r = seek_rows_at(p)
        if r then return r end
        log('SEEKER remembered block went stale - looking again')
        cfg.seek_ptr = 0
    end
    if seek.done then return nil end
    if not seek.regions then
        seek.regions = dl_collect()
        log('SEEKER looking for the SeekingMissileComponentData block in '
            .. tostring(#seek.regions) .. ' regions')
        return nil
    end
    local budget = dl_budget()
    if budget <= 0 then return nil end
    local deadline = os.clock() + budget
    seek.frames = seek.frames + 1
    while os.clock() < deadline do
        local r = seek.regions[seek.ri]
        if not r then
            seek.done = true
            log(('SEEKER block not found (%d MB walked) - the speed option stays '
                .. 'off, nothing else is affected'):format(math.floor(seek.scanned / 1048576)))
            return nil
        end
        local remaining = r.size - seek.roff
        if remaining <= 0 then
            seek.ri, seek.roff, seek.prev = seek.ri + 1, 0, ''
        else
            local want = 65536
            if want > remaining then want = remaining end
            local chunk = rd(r.base + seek.roff, want)
            seek.roff = seek.roff + want
            seek.scanned = seek.scanned + want
            if chunk then
                local wbase = r.base + seek.roff - want - #seek.prev
                local win = seek.prev .. chunk
                local from = 1
                while true do
                    local j = string.find(win, SEEK_NEEDLE, from, true)
                    if not j then break end
                    from = j + 1
                    local at = wbase + j - 1
                    if ptr_ok(at) and seek_header(at) then
                        state.save_cfg_key('seek_ptr', string.format('%d', at))
                        cfg.seek_ptr = at
                        log(('SEEKER block @%s (remembered for next launch)')
                            :format(hexa(at)))
                        local got = seek_rows_at(at)
                        if got then return got end
                        seek.done = true
                        return nil
                    end
                end
                seek.prev = win:sub(-64)
            else
                seek.ri, seek.roff, seek.prev = seek.ri + 1, 0, ''
            end
        end
    end
    return nil
end
local function seeker(on)
    if not on then
        if sk_rows and sk_rows.orig then
            if write_bytes(sk_rows.addr + sk_rows.off, sk_rows.orig) then
                log(('SEEKER speeds restored to %.1f m/s'):format(f32(sk_rows.orig, 0) or -1))
            end
            if sk_rows.accel_orig then
                write_bytes(sk_rows.addr + sk_rows.accel_off, sk_rows.accel_orig)
            end
        end
        sk_rows = nil
        return true
    end
    local w = num_or(cfg.seek_speed, 0)
    if w <= 0 then return true end
    local r = seek_find()
    if not r then return false end
    local cur = rd(r.addr + r.off, 12)
    if not cur then return false end
    local want = fbytes(w) .. fbytes(w) .. fbytes(w)
    if cur ~= want then
        if r.orig == nil then r.orig = cur end
        if not write_bytes(r.addr + r.off, want) then return false end
        log(('SEEKER P-92 speeds %.1f -> %.1f m/s'):format(f32(cur, 0) or -1, w))
    end
    if num_or(cfg.seek_accel, 0) > 0 then
        local ac = rd(r.addr + r.accel_off, 4)
        if ac and math.abs((f32(ac, 0) or 0) - cfg.seek_accel) > 0.5 then
            if r.accel_orig == nil then r.accel_orig = ac end
            write_bytes(r.addr + r.accel_off, fbytes(cfg.seek_accel))
            log(('SEEKER acceleration %.1f -> %.1f'):format(f32(ac, 0) or -1, cfg.seek_accel))
        end
    end
    return true
end

-- ------------------------------------------------------------------ driver
-- run one phase with a private pcall; the first failure of each phase is
-- written to the log once, later ones only bump the failure counter
local phase_err = {}
local function phase(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        state.failures = state.failures + 1
        if not phase_err[name] then
            phase_err[name] = true
            log('phase ' .. name .. ' error: ' .. tostring(err))
        end
    end
    return ok
end

local function step()
    local mode = ptr8(base + R.mission)
    if mode then ctx.mission = (u32(rd(mode + 8, 4), 0) or 0) ~= 0 end
    local ok, why = resolve_avatar()
    if not ok then note('avatar:' .. tostring(why)); return false end
    local ok2, why2 = find_apw_weapon()
    if not ok2 then
        note('weapon:' .. tostring(why2)); return false
    end
    -- the reticle only needs "the APW-1 is in your hands"; it must stay up even
    -- if the pose probe or the binding later fails
    ctx.weapon_at = state.frame
    local ok3, why3 = weapon_pose()
    if not ok3 then note('pose:' .. tostring(why3)); return false end
    if not sync_leases(true) then return false end
    dl_scan()                      -- also feeds the WeaponData block lookup
    -- every optional phase is isolated: a crash in the reticle or the damage
    -- patch must never stop the projectile binding (that cost us v3.2)
    if cfg.apw_damage == 1 then phase('damage', damage, true) end
    -- the model pass runs first so it still sees the untouched factory numbers
    phase('ballistics', ballistics, true)
    phase('cluster', cluster, true)
    phase('launcher', launcher, true)
    phase('airburst', PL.phase, true)
    if (cfg.seek_speed or 0) > 0 then phase('seeker', seeker, true) end
    local iv = num_or(cfg.target_interval, 20)
    if iv < 5 then iv = 5 elseif iv > 300 then iv = 300 end
    state.scan_age = (state.scan_age or 0) + 1
    if state.scan_age >= iv or #ctx.targets == 0 then
        state.scan_age = 0
        local ok4, why4 = refresh_targets()
        if not ok4 then note('targets:' .. tostring(why4)); return false end
    end
    refresh_poses()
    local t = pick_target()
    -- P11: the reticle reads this stamp to tell "the addon is still tracking
    -- this target" from "this is the last position it ever saw"
    ctx.target_at = state.frame
    if t and ctx.origin then
        local p = t.position
        local dx, dy, dz = p[1] - ctx.origin[1], p[2] - ctx.origin[2], p[3] - ctx.origin[3]
        ctx.last_dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    if (state.frame % 2) == 0 then phase('bind', bind_projectiles) end
    -- v4.7: a WAIT raised anywhere earlier in THIS frame cancels the READY
    -- line.  Printing both every frame is what filled the log with 7500 lines
    -- in under a minute and stuttered the picture.
    if ctx.last_reason ~= nil and ctx.wait_frame ~= state.frame then
        ctx.last_reason = nil
        if (state.frame - (ctx.ready_at or -99999)) > NOTE_GAP then
            ctx.ready_at = state.frame
            log('READY - APW-1 located, guidance armed')
        end
    end
    return true
end

-- ------------------------------------------------------- the options menu
-- The Vanilla Plus Megapack ships a native MODS tab on the escape menu
-- (mods/cowboybingus/mod_options_menu) that addons publish their knobs into.
-- It may load after this one, so registration is retried once a frame until its
-- table shows up and then never again.  With no megapack installed nothing below
-- ever runs and the cfg file stays the only way in, exactly as before.
--
-- The cfg FILE is the single source of truth: the menu is handed the file's
-- values when it appears, a change writes straight through to the file, and
-- whatever the menu snaps a value to is written back.
--
-- Everything lives inside ONE immediately-called function.  This file already
-- sits at LuaJIT's 200 local slot cap - one more chunk level local breaks the
-- load outright - so the whole bridge has to cost a single local: menu_step.
--
-- Two categories: APW GUIDED holds the knobs, APW WEAPONS holds one toggle per
-- weapon (the megapack allows 32 rows per category, and that is why the list is
-- 32 long and not the full 120 weapons the hash table knows - anything else
-- still works by editing the weapons= line in the cfg).
local menu_step = (function()
    -- 'zh' or 'en'.  The packer rewrites this one line for the English build,
    -- so both packages come out of the same source.
    -- The language the options are shown in.  Read when the menu asks for a
    -- text, never cached: the pack re-resolves these texts each time the escape
    -- menu opens, right after it observed the game's Text Language, so a
    -- language change in the game options is followed without a restart.
    local function language_code()
        local registry = rawget(_G, 'BingusTranslations')
        if type(registry) == 'table' then
            -- override: a translation pack that forced a language
            -- game_language: the tag of the game's Text Language ('zh-Hant')
            -- game_code: that setting's own code ('us', 'cn', 'tw') - the only
            --            one written when the tag is not known
            for _, key in ipairs({ 'override', 'game_language', 'game_code' }) do
                local value = registry[key]
                if type(value) == 'string' and value ~= '' then return value end
            end
        end
        -- no translation registry (nothing observed the language): ask the
        -- shared HD2Runtime, which knows the game's text language (0.31.2+) and
        -- its own UI language (0.31.1+), and give up quietly if it is absent
        local ok, hd2 = pcall(require, 'mods/skyeshade/hd2runtime')
        if ok and type(hd2) == 'table' then
            for _, namespace in ipairs({ hd2.text, hd2.ui }) do
                if type(namespace) == 'table' and type(namespace.language) == 'function' then
                    local got, code = pcall(namespace.language)
                    if got and type(code) == 'string' and code ~= '' and code ~= 'auto' then
                        return code
                    end
                end
            end
        end
        return nil
    end
    -- Chinese (both scripts) keeps the Chinese texts; anything else, including
    -- a language that cannot be read at all, gets English.
    local function chinese()
        local code = language_code()
        if type(code) ~= 'string' then return false end
        code = code:lower()
        return code == 'cn' or code == 'tw' or code == 'chs' or code == 'cht'
            or code:sub(1, 2) == 'zh'
    end
    local function L(en, zh) return chinese() and zh or en end
    -- The menu counts CHARACTERS, not bytes (v1.1+), so clip on a character
    -- boundary: half a Chinese character is not valid text and a text over the
    -- limit costs the whole row.
    local function clip(text, limit)
        if type(text) ~= 'string' then return text end
        if not limit or #text <= limit then return text end
        local count, at = 0, 1
        while at <= #text do
            local byte = text:byte(at)
            local size = byte < 0x80 and 1 or (byte < 0xE0 and 2 or (byte < 0xF0 and 3 or 4))
            at = at + size
            count = count + 1
            if count > limit then return text:sub(1, at - size - 1) end
        end
        return text
    end
    -- A text the menu can resolve now AND again when the escape menu opens
    -- (api version 2+).  An older menu takes strings only, so there the
    -- language is decided once, at registration.
    local menu_version = 1
    local function text(en, zh, limit)
        if menu_version >= 2 then
            return function() return clip(L(en, zh), limit) end
        end
        return clip(L(en, zh), limit)
    end

    local MOD_CTRL = 'GUIDED ROUNDS'
    local MOD_WEAP = 'GUIDED WEAPONS'

    -- #label is counted in BYTES: 64 bytes is 21 Chinese characters, so the
    -- Chinese labels stay short, and the 400 byte description limit is about
    -- 130 characters - both are checked before registering so a label that is
    -- too long can only ever drop its own description, never the whole row.
    local SLIDERS = {
        { k = 'cone_deg', min = 0, max = 60, step = 1,
          en = 'LOCK ANGLE (deg)', zh = '锁定角度（度）',
          d_en = 'How far off the barrel a target may sit and still be picked up. '
              .. '12 is the shipped value. Wider catches more, but starts grabbing '
              .. 'things you are not aiming at.',
          d_zh = '目标偏离枪口多少度仍会被锁定。出厂值是 12。调大更容易抓到目标，'
              .. '但也会开始锁到没在瞄的东西。' },
        { k = 'max_dist', min = 0, max = 500, step = 10,
          en = 'LOCK RANGE (m)', zh = '锁定距离（米）',
          d_en = 'Furthest target the round will accept, in metres. 250 is the '
              .. 'shipped value. Beyond about 300 the round usually expires first.',
          d_zh = '弹丸接受目标的最远距离，单位是米。出厂值 250。超过约 300 米时，'
              .. '弹丸通常先超时消失。' },
        { k = 'bind_delay', min = 0, max = 2, step = 0.05,
          en = 'ARM TIME AFTER MUZZLE (s)', zh = '出膛锁定生效时间（秒）',
          d_en = 'How long after leaving the barrel the round may be given a '
              .. 'target. 0.25 is the shipped value. Too small and the binding is '
              .. 'refused because the projectile is not ready yet.',
          d_zh = '弹丸出膛后多久才允许被指定目标。出厂值 0.25。设太小会被拒绝，'
              .. '因为弹丸实体还没准备好。' },
        { k = 'seek_speed', min = 0, max = 1500, step = 25,
          en = 'GUIDED ROUND SPEED (mps)', zh = '制导弹速度（米每秒）',
          d_en = 'Speed of the guided round itself. 0 leaves the game value (90) '
              .. 'alone, which is why guided rounds crawl. The APW round flies at '
              .. '880 - try 600 to 900 first, too fast and it cannot turn.',
          d_zh = '制导弹本身的速度。0 表示不改（原厂 90，所以制导弹飞得慢）。'
              .. 'APW 原弹是 880，建议先试 600 到 900，太快会转不过弯。' },
        { k = 'seek_accel', min = 0, max = 2000, step = 50,
          en = 'SEEKER ACCELERATION', zh = '制导弹加速度',
          d_en = 'How hard the seeker accelerates towards its speed. The game '
              .. 'value is 200. 0 leaves it alone.',
          d_zh = '制导弹向目标速度加速的强度。游戏原值是 200。0 表示不改。' },
        -- P13: SIGHT TEST PROFILE used to be a row here.  It is the kind of
        -- "only raise it if something is missed" knob that belongs in the cfg,
        -- and the page is exactly 32 rows - the scope multiplier below is worth
        -- more to a player than it is.  los_desc still works from the cfg.
        { k = 'scope_scale', min = 0.05, max = 1, step = 0.05,
          en = 'SCOPE LOCK SCALE', zh = '开镜锁定系数',
          d_en = 'Only used with FOLLOW THE SCOPE ZOOM below. The lock range '
              .. 'through a scope becomes the ORIGINAL range times this decimal, '
              .. 'so it grows with the magnification: a 4x scope locks roughly '
              .. 'four times the area a 1x scope does at the same setting. 0.3 is '
              .. 'shipped. 1.0 is the original behaviour, where a strong scope '
              .. 'can push the ring off the screen; small values keep the ring '
              .. 'small at every zoom. Hipfire is never scaled.',
          d_zh = '只在下面那个「开镜锁定范围跟随倍镜」打开时生效。开镜时的锁定范围 = '
              .. '原版范围 × 这个小数值，因此会随倍镜放大系数走：同一数值下，4 倍镜锁'
              .. '的范围大约是 1 倍镜的 4 倍。出厂值 0.3。填 1.0 就是原版行为（高倍镜'
              .. '下圆环会涨到屏幕外），填小则任何倍率下环都小。腰射不受影响。' },

        { k = 'target_interval', min = 1, max = 60, step = 1,
          en = 'TARGET REFRESH (frames)', zh = '目标刷新间隔（帧）',
          d_en = 'How often the enemy list is rebuilt, in frames. 20 is about '
              .. 'three times a second. Lower costs frames, higher feels laggy.',
          d_zh = '每隔多少帧重建一次敌人列表。20 大约是一秒三次。调低更费帧数，'
              .. '调高会觉得迟钝。' },
        { k = 'round_speed', min = 0, max = 2000, step = 25,
          en = 'BALLISTICS ROW SPEED (mps)', zh = '弹道行速度（米每秒）',
          d_en = 'Rewrites the speed in the weapon own ballistics row. 0 leaves '
              .. 'it alone. NOTE the guided round does not move at this speed - '
              .. 'that one is GUIDED ROUND SPEED above.',
          d_zh = '改写武器自己那行弹道的速度。0 表示不改。注意制导弹并不按这个速度'
              .. '飞，真正管速度的是上面的「制导弹速度」。' },
        { k = 'round_gravity', min = -1, max = 3, step = 0.1,
          en = 'BALLISTICS ROW GRAVITY', zh = '弹道行重力',
          d_en = 'Gravity multiplier in the weapon own ballistics row. -1 means '
              .. 'leave the game value alone, 0 makes the round fly flat.',
          d_zh = '武器自己那行弹道的重力倍数。-1 表示不改，0 让弹丸完全平直飞行。' },
        { k = 'cluster_life', min = 0.1, max = 8, step = 0.1,
          en = 'CLUSTER BOMBLET LIFE (s)', zh = '子弹药寿命（秒）',
          d_en = 'How long an RL-77 cluster bomblet may live once it has the '
              .. 'seeker. The factory value is 0.0 (it never expires), which is '
              .. 'fine for a dumb bomblet but not for a homing one. 3 is shipped.',
          d_zh = 'RL-77 集束子弹药装上制导后能活多久。原厂值是 0.0（永不超时），'
              .. '对无制导的子弹药没问题，对会追人的就不行。出厂值 3 秒。' },
        { k = 'cluster_delay', min = 0, max = 1, step = 0.05,
          en = 'BOMBLET ARM TIME (s)', zh = '子弹药锁定生效时间（秒）',
          d_en = 'How long after the burst a bomblet may be given a target. The '
              .. 'cluster rocket bursts after 0.25 s, so this has to stay small - '
              .. '0.05 is the shipped value.',
          d_zh = '子弹药炸开后多久才允许被指定目标。集束火箭 0.25 秒就炸开，'
              .. '所以这个值必须小，出厂值 0.05 秒。' },
        { k = 'cluster_seeker', min = 0, max = 7, step = 1,
          en = 'BOMBLET SEEKER (0 - 7)', zh = '子弹药追踪弹实体（0 - 7）',
          d_en = 'Which seeker entity the bomblet borrows. 0 is the P-92 warrant, '
              .. 'the same one the main round uses - it needs a weapon lock and a '
              .. 'bomblet is spawned by an explosion, not by a weapon, so 0 is the '
              .. 'one combination that never homed. 1 is the MLS-4X commando '
              .. 'missile and 2 the Patriot exosuit rocket: both are Guidance '
              .. 'seekers that steer a projectile, which is what a bomblet is. '
              .. '3 is the Mini Missile Silo missile, 4 a plain Guidance seeker, '
              .. '5 the enemy homing rocket, 6 a fast Behaviour seeker, 7 the Vox '
              .. 'Engine External one that waits for the target we publish.',
          d_zh = '子弹药借用哪个追踪弹丸实体。0 是 P-92 法令，和主弹一样，它需要有武器'
              .. '提供锁定，而子弹药是爆炸炸出来的、不是武器打出来的，所以 0 是唯一'
              .. '确认打不中的组合。1 是 MLS-4X 突击兵导弹、2 是爱国者外骨骼火箭，'
              .. '两者都是自己找目标、并且直接驱动弹丸的 Guidance 追踪弹，正合子弹药。'
              .. '3 是单兵导弹井的导弹，4 是普通 Guidance，5 是敌人的追踪火箭，'
              .. '6 是快速 Behaviour 追踪弹，7 是等我们发布目标的 Vox Engine。' },
        { k = 'launcher_seeker', min = 0, max = 9, step = 1,
          en = 'ROCKET SEEKER (0 - 9)', zh = '火箭本体追踪弹实体（0 - 9）',
          d_en = 'Which seeker entity the rocket that carries the burst borrows. '
              .. 'The rocket is fired by a weapon, so it has a source id and a '
              .. 'TargetLock seeker works - 0, the P-92 warrant, is shipped. '
              .. 'With 1 the burst went off far too early, like the commando '
              .. "missile's own fuse. 8 is the P-33 round, 9 the FAF-14 Spear "
              .. 'rocket.',
          d_zh = '携带集束的那枚火箭本体借用哪个追踪弹实体。火箭是武器打出去的，有'
              .. '发射源 id，所以 TargetLock 类追踪弹能用，出厂值 0 是 P-92 法令。'
              .. '用 1 时集束提前炸开，像是突击兵导弹自带的引信。8 是 P-33 制导手枪弹，'
              .. '9 是 FAF-14 飞矛弹。' },
        { k = 'rocket_life', min = 0, max = 5, step = 0.05,
          en = 'CLUSTER AIRBURST DELAY (s)', zh = '集束空中起爆延时（秒）',
          d_en = 'How long the cluster round may fly before it bursts. The '
              .. 'factory value is 0.25 s and it is a plain timer with no '
              .. 'proximity fuse, so the round always burst about 20 m out no '
              .. 'matter how good its guidance was - that is why it looked like '
              .. 'it went off too early. 1.5 is what the flak round ships. 0 '
              .. 'means leave the factory value alone.',
          d_zh = '集束弹出膛后多久起爆。出厂值是 0.25 秒，而且是纯定时、没有近炸引信，'
              .. '所以不管制导多准，它都会在大约 20 米处炸开，这就是"太提前爆炸"的来源。'
              .. '1.5 是同一把枪那个「高爆」模式出厂用的值。0 表示不改。' },
        { k = 'rocket_prox', min = 0, max = 20, step = 0.5,
          en = 'CLUSTER PROXIMITY FUSE (m)', zh = '集束近炸引信（米）',
          d_en = 'Give the cluster round the proximity fuse it does not ship '
              .. 'with, so it bursts when it ARRIVES at whatever it chased '
              .. 'instead of on a timer. The flak round uses 2.0. 0 means off.',
          d_zh = '给集束弹补一个它出厂没有的近炸引信，让它追到东西身上再炸，而不是'
              .. '按定时器炸。同一把枪「高爆」模式用的是 2.0。0 表示关闭。' },
        { k = 'swarm_count', min = 0, max = 64, step = 1,
          en = 'GUIDED DARTS PER SHOT', zh = '每发打出的制导弹数',
          d_en = '2 or more turns the CLUSTER mode into a guided swarm: the '
              .. 'weapon itself fires that many guided darts per shot instead of '
              .. 'one rocket that bursts, and each dart is bound to its own '
              .. 'target. 25 is shipped - exactly as many as the factory burst '
              .. 'scattered - and each dart takes the bomblet damage, so a burst '
              .. 'still hits for the same total. 0 or 1 keeps the airburst. The '
              .. 'flak mode is never touched.',
          d_zh = '设为 2 以上时，「集束」模式变成一发打出这么多颗制导弹：由武器自己打出，'
              .. '不再是一枚火箭飞过去炸开，而且每颗各自绑一个目标。出厂 25 颗，正好等于'
              .. '原厂一次空爆撒出的子弹药数，并且每颗用子弹药的伤害，所以一次齐射的总伤害'
              .. '和原来一样。0 或 1 保留上面的空爆行为。「高爆」模式不受影响。' },
    }
    local TOGGLES = {
        { k = 'range_ring', en = 'RANGE RING', zh = '范围圆环',
          d_en = 'Draw the ring around the crosshair that shows the aim cone: its '
              .. 'radius follows LOCK ANGLE below and the camera zoom, so it is the '
              .. 'area the addon can actually acquire inside. A hairline, one pixel '
              .. 'wide. Set LOCK ANGLE to 0 for no ring.',
          d_zh = '画屏幕中央那圈显示索敌范围的圆环：半径跟着下面的「锁定角度」和相机缩放走，'
              .. '圈内就是 mod 能索敌到的范围。一像素宽的细线。把锁定角度设为 0 就没有圆环。' },
        { k = 'lock_reticle', en = 'LOCK MARKERS', zh = '锁定标记',
          d_en = 'Draw the stock lock markers on the target: three of them spin in '
              .. 'and close onto it when the lock completes.',
          d_zh = '在目标身上画原版锁定标记：三个标记在锁定完成时旋转收拢过去。' },
        { k = 'target_box', en = 'TARGET BOX', zh = '目标方框',
          d_en = 'Draw a wire box around the locked target. This is the only element '
              .. 'drawn in world space rather than on the screen.',
          d_zh = '在被锁定的目标外面画一个线框。这是唯一画在世界空间（而不是屏幕上）的元素。' },
        { k = 'lock_helldivers', en = 'LOCK HELLDIVERS ONLY', zh = '只锁潜兵',
          d_en = 'Lock friendly Helldivers instead of enemies: the aim cone picks a '
              .. 'teammate and the round flies at them. No enemy is locked while '
              .. 'this is on. Works in any mode, including solo (where nothing '
              .. 'can be locked and the addon simply does not bind).',
          d_zh = '改成只锁友方潜兵、不锁敌人：瞄准锥里挑一个队友，弹丸朝他飞。'
              .. '开启期间敌人完全不锁。单人局也能开，只是没人可锁、不会绑定。' },
        { k = 'swarm_split', en = 'EACH DART ITS OWN TARGET', zh = '每颗各追各的目标',
          d_en = 'Hand the darts different targets, round robin over what is in '
              .. 'the aim cone, so they fan out instead of stacking on one enemy.',
          d_zh = '给每颗弹分配不同的目标（在瞄准锥里轮流挑），让它们散开而不是全堆在一个敌人身上。' },
        { k = 'flak_only', en = 'ONLY GUIDE THE FLAK ROUND', zh = '只制导高射弹',
          d_en = 'Shipped ON. The cluster mode keeps its factory round, its factory '
              .. 'burst and its 25 bomblets, and gets no seeker at all - only the '
              .. 'flak round is guided. Turn it off to give the cluster mode the '
              .. 'guided swarm as well.',
          d_zh = '默认开启。集束模式完全保持原厂：原厂引信、原厂爆炸、原厂 25 颗子弹药，'
              .. '也不给它制导；只有高射弹享受制导。关掉才会给集束模式上追踪霰弹。' },
        { k = 'lua_bind', en = 'BIND TARGET OURSELVES', zh = '自己绑定目标',
          d_en = 'If the engine has not locked anything by itself, pick a target '
              .. 'in the aim cone and bind it. Leave this on.',
          d_zh = '引擎自己没锁到目标时，在瞄准锥里挑一个绑上去。建议保持开启。' },
        { k = 'los_check', en = 'REQUIRES LINE OF SIGHT', zh = '掩体后不锁',
          d_en = 'Refuse a target with something solid between you and it. '
              .. 'The engine\'s own lock already works this way - this puts the '
              .. 'same test on the fallback above, which would otherwise bind '
              .. 'straight through cover.',
          d_zh = '你和目标之间有实体挡住时不锁定。引擎自己的锁定本来就是这么判的；'
              .. '这一项是给上面那个兜底补上同一道判断，否则它会隔着掩体硬绑。' },
        -- P12: the sight-test log was a row here. It is a diagnostic, kept in
        -- the cfg (los_debug=1) and documented in the README.
        { k = 'los_foliage', en = 'SHOOT THROUGH FOLIAGE', zh = '忽略植物遮挡',
          d_en = 'Tree leaves block the view but not the bullet. The engine marks '
              .. 'those hits in the record it returns, and this skips them, so a '
              .. 'target behind leaves still locks.',
          d_zh = '树叶挡视线但挡不住子弹。引擎在返回的命中记录里把这类命中标了出来，'
              .. '这一项会跳过它们，所以躲在树叶后的目标仍然可以锁定。' },
        { k = 'cone_fallback', en = 'NEAREST ENEMY FALLBACK', zh = '退化为最近敌人',
          d_en = 'When the aim cone is empty, take the nearest enemy instead. Off '
              .. 'means an empty cone simply does not bind, which is what makes '
              .. 'LOCK ANGLE mean anything.',
          d_zh = '瞄准锥里没有目标时改用最近的敌人。关闭则锥里没人就不绑，'
              .. '这样「锁定角度」才有意义。' },
        { k = 'cluster_guide', en = 'GUIDE RL-77 CLUSTER BOMBLETS', zh = '制导 RL-77 集束子弹药',
          d_en = 'Give the 25 bomblets of the RL-77 Airburst cluster burst the '
              .. 'same seeker, and send them at the target the launcher itself is '
              .. 'locked onto. Only runs while the launcher is in the weapon list '
              .. 'and in your hands.',
          d_zh = '给 RL-77 空爆火箭「集束」模式炸出的 25 颗子弹药装上同一套制导，'
              .. '并让它们追火箭筒自己锁到的目标。只在火箭筒在武器列表里且在手上时生效。' },
        { k = 'cluster_autofix', en = 'AVOID THE BROKEN SEEKER', zh = '跳过打不中的追踪弹',
          d_en = 'Seeker 0 is a TargetLock seeker and a bomblet has no weapon to '
              .. 'lock with, so while this is on a cfg that still says 0 is '
              .. 'upgraded to 1. Turn it off only if you want to see 0 for '
              .. 'yourself.',
          d_zh = '0 号追踪弹是 TargetLock，而子弹药没有武器能给它锁定，所以开启时 cfg '
              .. '里仍然写着 0 会被自动升到 1。只有想亲眼确认 0 的表现时才关掉。' },
        { k = 'apw_damage', en = 'KEEP THE WEAPON OWN DAMAGE', zh = '保留武器本来的伤害',
          d_en = 'Rewrite the leased round damage back to the weapon own value. '
              .. 'Off means every weapon hits with the P-92 Warrant damage.',
          d_zh = '把租来的弹的伤害改回武器自己的数值。关闭则所有武器都用 P-92 法令'
              .. '的伤害。' },
        { k = 'require_assets', en = 'LOAD PROJECTILE MATERIALS', zh = '加载弹丸材质',
          d_en = 'Ask the shared HD2Runtime to keep the leased projectile loaded, '
              .. 'so it does not show the missing-material icon. Needs HD2Runtime.',
          d_zh = '请共用的 HD2Runtime 让租来的弹丸保持加载，避免出现缺材质的紫问号。'
              .. '需要安装 HD2Runtime。' },
        { k = 'scope_fix', en = 'FOLLOW THE SCOPE ZOOM',
          zh = '开镜锁定范围跟随倍镜',
          d_en = 'OFF (shipped): the lock cone is compensated by the camera zoom, '
              .. 'so the range ring keeps the SAME size on screen and hipfire and '
              .. 'a scope lock exactly the same area - what the ring shows is what '
              .. 'is locked, at any magnification. ON: while a scope is in use the '
              .. 'lock range becomes the ORIGINAL range times SCOPE LOCK SCALE '
              .. 'above, so it follows the magnification: a 4x scope locks further '
              .. 'than a 1x scope at the same setting. Hipfire is never scaled.',
          d_zh = '关闭（默认）：锁定锥按相机缩放做补偿，范围圆环在任何倍率下都保持'
              .. '同样的屏幕大小，腰射和开镜锁的范围完全一致——圆环画多大，就锁多大。'
              .. '打开：使用瞄准镜时，锁定范围 = 原版范围 × 上面的「开镜锁定系数」，'
              .. '于是会随倍镜放大系数走：同一数值下 4 倍镜比 1 倍镜锁得更远。'
              .. '腰射始终不受影响。' },
        -- P12/P13: ship_scan, debug and los_debug were never rows; ship_scan and
        -- debug were dropped from the menu, and scan_ms / los_desc joined them,
        -- so that these scope rows fit inside the 32 option cap.
    }
    -- One toggle per weapon.  The hash is the "(Model)" entry from Hash.csv -
    -- that is the resource the live weapon table matches on, and it is the same
    -- number the shipped cfg line uses for the APW-1.
    -- One toggle per weapon.  Every hash is a weapon resource hash
    -- straight out of the community list, verified against Hash.csv.  141 of
    -- them, spread over five category buttons because the megapack allows 32
    -- rows per button.
    local WEAPONS_MENU = {
        { h = '0x84354339522C932D', en = 'AR-2 Coyote', zh = 'AR-2 野狼' },
        { h = '0x968211C0033DCE64', en = 'AR-23 Liberator', zh = 'AR-23 解放者' },
        { h = '0xA7EE1EBF58FCDF1F', en = 'AR-23A Liberator Carbine', zh = 'AR-23A 卡宾"解放者"' },
        { h = '0xCF5F176E0E322BE1', en = 'AR-23C Liberator Concussive', zh = 'AR-23C 震荡"解放者"' },
        { h = '0x43CB1033961A2276', en = 'AR-23P Liberator Penetrator', zh = 'AR-23P 穿甲"解放者"' },
        { h = '0xBC29613666DF696B', en = 'AR-32 Pacifier', zh = 'AR-32 安抚者' },
        { h = '0x708EA298C82093D0', en = 'AR-59 Suppressor', zh = 'AR-59 消音器' },
        { h = '0xCE063AA33D95A812', en = 'AR-61 Tenderizer', zh = 'AR-61 肉锤' },
        { h = '0xA955C4EA6F6D4203', en = 'AR/GL-21 One-Two', zh = 'AR/GL-21 幺二' },
        { h = '0x5FECAB819F96A3E8', en = 'BR-14 Adjudicator', zh = 'BR-14 审判者' },
        { h = '0xCDF28BE026BB7D84', en = 'StA-52 Assault Rifle', zh = 'StA-52 突击步枪' },
        { h = '0x4DBD74F49C8FFC13', en = 'MA5C Assault Rifle', zh = 'MA5C 突击步枪' },
        { h = '0x0F83639AB8C86165', en = 'R-2 Amendment', zh = 'R-2 修正' },
        { h = '0xE6D932BE83729076', en = 'R-6 Deadeye', zh = 'R-6 鹰眼' },
        { h = '0x03E67A19B07C6523', en = 'R-63 Diligence', zh = 'R-63 勤勉' },
        { h = '0x4C786785C79D44E7', en = 'R-63CS Diligence Counter Sniper', zh = 'R-63CS 反狙击"勤勉"' },
        { h = '0xF0338468DCDB6A6C', en = 'R-72 Censor', zh = 'R-72 审查官' },
        { h = '0x7B75E5132FFD4CA6', en = 'R-2124 Constitution', zh = 'R-2124 宪法' },
        { h = '0x9571CA51F0DAF35B', en = 'MP-98 Knight', zh = 'MP-98 骑士' },
        { h = '0x94BD931B5FB4EE95', en = 'SMG-32 Reprimand', zh = 'SMG-32 训斥' },
        { h = '0x4E4A613EB9BF5C24', en = 'SMG-37 Defender', zh = 'SMG-37 防卫者' },
        { h = '0x0807AEA5217E4767', en = 'SMG-72 Pummeler', zh = 'SMG-72 暴击斗士' },
        { h = '0x8A307BD1811A5FE9', en = 'SMG/FLAM-34 Stoker', zh = 'SMG/FLAM-34 司炉者' },
        { h = '0x4BA41B6F9F405CC2', en = 'StA-11 SMG', zh = 'StA-11 冲锋枪' },
        { h = '0xBE70EE0D8D44028E', en = 'M7S SMG', zh = 'M7S 冲锋枪' },
        { h = '0x72170A55A1F37FF1', en = 'DBS-2 Double Freedom', zh = 'DBS-2 双重自由' },
        { h = '0x41EAC4A03987FAA0', en = 'SG-8 Punisher', zh = 'SG-8 制裁者' },
        { h = '0x4F749E2EE26F532D', en = 'SG-8S Slugger', zh = 'SG-8S 重炮手' },
        { h = '0x4E310B1FE4C52B52', en = 'SG-20 Halt', zh = 'SG-20 止息' },
        { h = '0xDCD1C835407EF7BA', en = 'SG-97 Sweeper', zh = 'SG-97 扫荡者' },
        { h = '0xD323DE60855898AC', en = 'SG-451 Cookout', zh = 'SG-451 野炊' },
        { h = '0x46183B50961D1328', en = 'SG-225 Breaker', zh = 'SG-225 破裂者' },
        { h = '0xC12A34F375BD5A87', en = 'SG-225IE Breaker Incendiary', zh = 'SG-225IE 高燃"破裂者"' },
        { h = '0x5EBAEA70C0D060B9', en = 'SG-225SP Breaker Spray&Pray', zh = 'SG-225SP 千发百中"破裂者"' },
        { h = '0x90DDC374F4E3D756', en = 'M90A Shotgun', zh = 'M90A 霰弹枪' },
        { h = '0xF49227A0630A3F7F', en = 'CB-9 Exploding Crossbow', zh = 'CB-9 爆燃弩' },
        { h = '0xB6AFF2195568767F', en = 'R-36 Eruptor', zh = 'R-36 爆裂铳' },
        { h = '0x076DD5D4F4360204', en = 'ARC-12 Blitzer', zh = 'ARC-12 雷霆' },
        { h = '0x27EE1ED8F6FB6356', en = 'LAS-5 Scythe', zh = 'LAS-5 长柄镰' },
        { h = '0x8645F167B3C813A2', en = 'LAS-16 Sickle', zh = 'LAS-16 镰刀' },
        { h = '0x295BEB26DC4F8FF1', en = 'LAS-17 Double-Edge Sickle', zh = 'LAS-17 双刃镰刀' },
        { h = '0x3C86E871923F3970', en = 'LAS-13 Trident', zh = 'LAS-13 三叉戟' },
        { h = '0xEEA5E3CEF1E12C14', en = 'PLAS-1 Scorcher', zh = 'PLAS-1 焦土' },
        { h = '0xFB3A19078694708A', en = 'PLAS-101 Purifier', zh = 'PLAS-101 净化者' },
        { h = '0x05D8D8C073B9D502', en = 'SG-8P Punisher Plasma', zh = 'SG-8P 等离子"制裁者"' },
        { h = '0x30061F91AF477F5E', en = 'PLAS-39 Accelerator Rifle', zh = 'PLAS-39 加速步枪' },
        { h = '0x4FB0F8C02F55C82B', en = 'FLAM-66 Torcher', zh = 'FLAM-66 火炬手' },
        { h = '0x80F1A156D9FA1E36', en = 'JAR-5 Dominator', zh = 'JAR-5 主宰' },
        { h = '0xF992CE97577C8A7F', en = 'VG-70 Variable', zh = 'VG-70 变数' },
        { h = '0x186EA95DE7306B1A', en = 'SMG-203 Gallant', zh = 'SMG-203 英勇无畏' },
        { h = '0x7E3145A5BAA4B948', en = 'LAS-22 Shear', zh = 'LAS-22 切变' },
        { h = '0xE5796355A8FD67E0', en = 'R-4 Hyena', zh = 'R-4 鬣狗' },
        { h = '0x1ABBFF60D26BA391', en = 'R/40-K', zh = 'R/40-K 高能精确射手步枪' },
        { h = '0x05E4E5C2DB6E44A2', en = 'P-2 Peacemaker', zh = 'P-2 和平制造者' },
        { h = '0x8D3D52A3B2F19402', en = 'P-4 Senator', zh = 'P-4 参议员' },
        { h = '0x3575AABC5F1F9326', en = 'P-19 Redeemer', zh = 'P-19 救世主' },
        { h = '0xC780BCD79547DA0F', en = 'P-69 Veto', zh = 'P-69 否决者' },
        { h = '0xCF8934FF6567A42D', en = 'P-92 Warrant', zh = 'P-92 法令' },
        { h = '0x1A437158E1B8D2A1', en = 'P-113 Verdict', zh = 'P-113 裁决' },
        { h = '0x4D58C77087B774C5', en = 'M6C/SOCOM Pistol', zh = 'M6C 特种作战手枪' },
        { h = '0x9EB160830321BFD6', en = 'GP-20 Ultimatum', zh = 'GP-20 最后通牒' },
        { h = '0x52E4334E6A128CAF', en = 'GP-31 Grenade Pistol', zh = 'GP-31 榴弹手枪' },
        { h = '0x7B06196E90154C88', en = 'LAS-7 Dagger', zh = 'LAS-7 匕首' },
        { h = '0x416D053372C4E433', en = 'PLAS-45 Epoch', zh = 'LAS-58 猛爪' },
        { h = '0xD6B1FB05B9109353', en = 'P-11 Stim Pistol', zh = 'P-11 治疗剂手枪' },
        { h = '0x0B882808C6F498E8', en = 'P-35 Re-Educator', zh = 'P-35 思想改造' },
        { h = '0x3F92BA65EF65CCA9', en = 'P-72 Crisper', zh = 'P-72 迅击' },
        { h = '0xAA69A60D74A3EC54', en = 'PLAS-15 Loyalist', zh = 'PLAS-15 忠诚者' },
        { h = '0x2B28E17FFED05F7C', en = 'SG-22 Bushwhacker', zh = 'SG-22 游击兵' },
        { h = '0xFCD8A6E67EAC635A', en = 'CQC-2 Saber', zh = 'CQC-2 军刀' },
        { h = '0x75816077C139C850', en = 'CQC-5 Combat Hatchet', zh = 'CQC-5 战斗短柄斧' },
        { h = '0xE3B6AEDD07FCB464', en = 'CQC-19 Stun Lance', zh = 'CQC-19 眩晕长矛' },
        { h = '0x52CDBFBACA3CB397', en = 'CQC-30 Stun Baton', zh = 'CQC-30 眩晕短棍' },
        { h = '0x792D5D2A340FD6E6', en = 'CQC-42 Machete', zh = 'CQC-42 砍刀' },
        { h = '0x7E1F76163C667E4B', en = 'CQC-72 Entrenchment Tool', zh = 'CQC-72 堑壕工具' },
        { h = '0x14D5D4506056C7A4', en = 'P-33 Missile Pistol', zh = 'P-33 制导手枪' },
        { h = '0xBDE1F2534280300D', en = 'P-41 Ombudsman', zh = 'P-41 巡查者' },
        { h = '0xDBB6C961C59FADC1', en = 'P/40K', zh = 'P/40K 爆弹手枪' },
        { h = '0x4CE9EAB785A79B7B', en = 'G-6 Frag', zh = 'G-6 破片弹' },
        { h = '0x04653AB33F3FFB44', en = 'G-10 Incendiary', zh = 'G-10 燃烧弹' },
        { h = '0x6B11FC757618C57E', en = 'G-12 High Explosive', zh = 'G-12 高爆弹' },
        { h = '0x075B19B068FB1045', en = 'G-7 Pineapple', zh = 'G-7 菠萝' },
        { h = '0x14368DC8784220B0', en = 'TED-63 Dynamite', zh = 'TED-63 炸药' },
        { h = '0x5DE8FD02A05B4B0A', en = 'G-3 Smole', zh = 'G-3 烟雾弹' },
        { h = '0x0416984F4922757B', en = 'G-4 Gas', zh = 'G-4 毒气榴弹' },
        { h = '0xEB725C39FC38B87C', en = 'G-13 Incendiary Impact', zh = 'G-13 燃烧冲击弹' },
        { h = '0x7686544F539BB9B7', en = 'G-16 Impact', zh = 'G-16 冲击弹' },
        { h = '0x0080869506299773', en = 'G-23 Stun', zh = 'G-23 眩晕弹' },
        { h = '0xDB922A7AFC42894B', en = 'G-31 Arc', zh = 'G-31 电弧' },
        { h = '0x46333FC9E3D4BD34', en = 'G-48 Giga Grenade', zh = 'G-48 千兆级榴弹' },
        { h = '0x2D398D1EC35E0838', en = 'G-50 Seeker', zh = 'G-50寻踪者' },
        { h = '0xDAB81B0D80B511C7', en = 'G-89 Smokescreen', zh = 'G-89 烟幕' },
        { h = '0x3FA94F58F596BC0B', en = 'G-109 Urchin', zh = 'G-109 海胆' },
        { h = '0xC5C05FCB5747C799', en = 'G-123 Thermite', zh = 'G-123 铝热弹' },
        { h = '0x03F31CAF3A7D8F4E', en = 'G-142 Pyrotech', zh = 'G-142 烟花术' },
        { h = '0x1B9AC59697006337', en = 'G/SH-39 Shield', zh = 'G/SH-39 盾雷' },
        { h = '0xF7B35A9C5AE340B6', en = 'K-2 Throwing Knife', zh = 'K-2 飞刀' },
        { h = '0xA20683199DFC19E8', en = 'TM-1 Lure Mine', zh = 'TM-1 诱饵地雷' },
        { h = '0x6002622114037024', en = 'Shrapnel Grenade', zh = '破片手榴弹' },
        { h = '0x1FF81C46CC79FD34', en = 'EMS Grenade', zh = '电磁冲击波手榴弹' },
        { h = '0x6290E1DEBC0D884B', en = 'Cyborg\'s Grenade', zh = '生化人的手榴弹' },
        { h = '0x2968DEBA6D6C2F09', en = 'G-11 Caltrops', zh = 'G-11 铁蒺藜' },
        { h = '0x5C14F27759DD3BE0', en = 'G-8 Immolation', zh = 'G-8 焚身' },
        { h = '0xEE4C107B941AB7F4', en = 'G/40K', zh = 'G/40K 热熔地雷' },
        { h = '0xA6A735ACCB4A327F', en = 'M-105 Stalwart', zh = 'M-105 盟友' },
        { h = '0x11C27D3BABB38956', en = 'MG-43 Machine Gun', zh = 'MG-43 机枪' },
        { h = '0x2152D5147B0AC418', en = 'MG-206 Heavy Machine Gun', zh = 'MG-206 重机枪' },
        { h = '0x43A58CB89CFA197C', en = 'M-1000 Maxigun', zh = 'M-1000 重装机枪' },
        { h = '0x02EECD0B1FA49630', en = 'GL-21 Grenade Launcher', zh = 'GL-21 榴弹发射器' },
        { h = '0x88C2D09AD85A7C9F', en = 'GL-28 Belt-Fed Grenade Launcher', zh = 'GL-28 弹链式榴弹发射器' },
        { h = '0xFE3B29B2CFA63F9B', en = 'GL-52 De-Escalator', zh = 'GL-52 缓和使者' },
        { h = '0x9F80D67A12A7E40F', en = 'GR-8 Recoilless Rifle', zh = 'GR-8 无后座力炮' },
        { h = '0x25AA2FD4643CF4EE', en = 'FAF-14 Spear', zh = 'FAF-14 飞矛' },
        { h = '0x26E40437EA275296', en = 'RL-77 Airburst Rocket Launcher', zh = 'RL-77 空爆火箭弹发射器' },
        { h = '0x5990123D142B16CB', en = 'MLS-4X Commando', zh = 'MLS-4X 突击兵' },
        { h = '0xFC13460592CA79AA', en = 'Mini Missile Silo Target Designator', zh = 'MS-11 单兵导弹发射井' },
        { h = '0x80932FA0ED6901D3', en = 'EAT-17 Expendable Anti-Tank', zh = 'EAT-17 消耗性反坦克武器' },
        { h = '0xB2B5E0D185605F9E', en = 'EAT-700 Expendable Napalm', zh = 'EAT-700 消耗性凝固汽油弹' },
        { h = '0x7617642765AC38C7', en = 'EAT-411 Leveller', zh = 'EAT-411 荡平者' },
        { h = '0xD54B9505C0F72873', en = 'LAS-98 Laser Cannon', zh = 'LAS-98 激光大炮' },
        { h = '0x35A61296619CC47E', en = 'LAS-99 Quasar Cannon', zh = 'LAS-99 类星体加农炮' },
        { h = '0xE8D5F49AD7780E54', en = 'PLAS-45 Epoch', zh = 'PLAS-45 纪元' },
        { h = '0xA8CFFB316F0B5C5F', en = 'AC-8 Autocannon', zh = 'AC-8 机炮' },
        { h = '0x89C5493E08CA4207', en = 'APW-1 Anti-Materiel Rifle', zh = 'APW-1 反器材步枪' },
        { h = '0x96DE9CD50F7306E6', en = 'ARC-3 Arc Thrower', zh = 'ARC-3 电弧发射器' },
        { h = '0x2E9D0BDC48B09E60', en = 'RS-422 Railgun', zh = 'RS-422 磁轨炮' },
        { h = '0x3828E2051AA9E897', en = 'S-11 Speargun', zh = 'S-11 矛枪' },
        { h = '0xCC786F6491FE7E65', en = 'StA-X3 W.A.S.P. Launcher', zh = 'StA-X3 W.A.S.P.发射器' },
        { h = '0x39AB99895147A3BF', en = 'FLAM-40 Flame Thrower', zh = 'FLAM-40 火焰喷射器' },
        { h = '0x78A8185F63A70795', en = 'B/FLAM-80 Cremator', zh = 'B/FLAM-80 焚燃者' },
        { h = '0x88F61AFFF48AC8A4', en = 'TX-41 Sterilizer', zh = 'TX-41 灭菌器' },
        { h = '0xB0F1B354BA1D38D8', en = 'CQC-1 One True Flag', zh = 'CQC-1 唯一真旗' },
        { h = '0xBF4CFD2AEABFB5A4', en = 'CQC-9 Defoliation Tool', zh = 'CQC-9 除叶工具' },
        { h = '0x5F3EC9BDA2BD8553', en = 'CQC-20 Breaching Hammer', zh = 'CQC-20 破门锤' },
        { h = '0x4F8A477E577AABA9', en = 'Physical Gun', zh = '开发者工具 物理枪' },
        { h = '0x52071F49263415E4', en = 'SG-88 Break-Action Shotgun', zh = 'SG-88 中折式霰弹枪' },
        { h = '0xB16C9D490AA59B77', en = 'MGX-42 Bullet Storm', zh = 'MGX-42 子弹风暴' },
        { h = '0xE85E623F93F96FB3', en = 'Entrenchment Tool', zh = 'CQC-72 堑壕工具' },
        { h = '0x6CFCC7F8801A0266', en = '40-K', zh = '40-K 热熔枪' },
        { h = '0x006E44327BB953FE', en = 'GL-15', zh = 'GL-15 驱逐者' },
        { h = '0xC85F576D5E086147', en = 'LAS-12', zh = 'LAS-12 钗' },
    }

    local ID_ENABLE = 'apw_guided_enable'
    local done = false

    -- Compare by the 8 bytes the game stores, so a hash written in decimal in
    -- the cfg still counts as the same weapon.
    local function has_weapon(h)
        local b = hash8(h)
        if not b then return false end
        for _, v in ipairs(WEAPONS_TXT) do if hash8(v) == b then return true end end
        return false
    end
    -- Rebuild the cfg line from the toggles and hand it to the addon.  The
    -- leases have to be let go and taken again, and doing both in one frame is
    -- what crashed an earlier build, so it is spread over two: this frame puts
    -- everything back, the next one re-arms with the new list.
    -- P10: same shape as has_weapon/set_weapon, but the priority list changes
    -- nothing about which weapons are guided, so no lease re-arm is needed.
    local function has_prio(h)
        local b = hash8(h)
        if not b or not ctx.prio then return false end
        return ctx.prio[b] == true
    end
    local function has_prio_small(h)
        local b = hash8(h)
        if not b or not ctx.small then return false end
        return ctx.small[b] == true
    end
    local function set_prio(h, big, small)
        local b = hash8(h)
        if not b then return end
        local out_big, out_small = {}, {}
        for _, v in ipairs(WEAPONS_TXT) do
            local vh = hash8(v)
            if vh then
                local keep_big = ctx.prio ~= nil and ctx.prio[vh] == true
                local keep_small = ctx.small ~= nil and ctx.small[vh] == true
                if vh == b then keep_big, keep_small = big, small end
                if keep_big then out_big[#out_big + 1] = v end
                if keep_small then out_small[#out_small + 1] = v end
            end
        end
        ctx.prio, ctx.small = {}, {}
        for _, v in ipairs(out_big) do local vh = hash8(v); if vh then ctx.prio[vh] = true end end
        for _, v in ipairs(out_small) do local vh = hash8(v); if vh then ctx.small[vh] = true end end
        local text_big, text_small = table.concat(out_big, ','), table.concat(out_small, ',')
        -- keep the text refresh_targets parses in step with what was just built,
        -- or the next scan would rebuild the sets from the previous contents
        state.prio_txt, state.prio_small_txt = text_big, text_small
        state.save_cfg_key('prio_targets', text_big)
        state.save_cfg_key('prio_small', text_small)
        log('menu: prio_targets = ' .. (text_big == '' and '(none)' or text_big))
        log('menu: prio_small = ' .. (text_small == '' and '(none)' or text_small))
    end
    local function set_weapon(h, on)
        local out = {}
        for _, v in ipairs(WEAPONS_TXT) do
            if not (hash8(v) == hash8(h)) then out[#out + 1] = v end
        end
        if on then out[#out + 1] = h end
        local text = table.concat(out, ',')
        parse_weapons(text)
        state.save_cfg_key('weapons', text)
        state.menu_rearm = 1
        log(('menu: weapons = %s'):format(text == '' and '(none)' or text))
    end
    -- Two weapons can share a first token (there are two PLAS-45 entries), and
    -- a duplicate id makes the megapack refuse the second row outright, so the
    -- generator keeps a set and only falls back to a numeric suffix on a clash.
    local used_id = {}
    local function wid(i, en)
        local code = en:match('^(%S+)') or ('w' .. tostring(i))
        local base = 'apw_w_' .. code:lower():gsub('[^%w]', '')
        if not used_id[base] then used_id[base] = true; return base end
        local k = 2
        while used_id[base .. tostring(k)] do k = k + 1 end
        used_id[base .. tostring(k)] = true
        return base .. tostring(k)
    end
    local function clamp(value, lo, hi, fallback)
        value = tonumber(value)
        if not value then return fallback end
        if value < lo then return lo end
        if value > hi then return hi end
        return value
    end
    local function num(v)
        if type(v) ~= 'number' then return nil end
        return string.format('%.6g', v)
    end

    return function()
        if done then return end
        local MOM = rawget(_G, 'ModOptionsMenu')
        if type(MOM) ~= 'table' or type(MOM.register_option) ~= 'function' then return end
        done = true
        -- v1.1 and later resolve function texts again whenever the escape menu
        -- opens; v1.0 needs plain strings, so the language is fixed there
        menu_version = tonumber(MOM.version) or 1
        local ok, err = pcall(function()
            -- Cut a byte budget without cutting a character in half: the pack
            -- counts BYTES, but half a Chinese character is not valid text and
            -- the row can come out as garbage.  Step back while the byte at the
            -- cut is a UTF-8 continuation byte (0x80..0xBF).
            local function fit(text, limit)
                if #text <= limit then return text end
                local cut = limit
                while cut > 0 do
                    local b = text:byte(cut)
                    if not b or b < 0x80 or b >= 0xC0 then break end
                    cut = cut - 1
                end
                -- cut == 0 only for text that is not valid UTF-8 to begin with;
                -- sub(1, -1) would return the WHOLE string, so say so instead
                if cut <= 0 then return '' end
                return text:sub(1, cut - 1)
            end
            local function row(id, spec)
                -- text() already clipped function texts by CHARACTER, which is
                -- what v1.1+ counts.  Only a plain string needs the old byte
                -- limits - that path is a menu older than v1.1.
                if type(spec.label) == 'string' then spec.label = fit(spec.label, 64) end
                if type(spec.description) == 'string' and #spec.description > 400 then
                    spec.description = nil
                end
                local good, why = MOM.register_option(id, spec)
                if not good then
                    log(('menu: %s refused - %s'):format(id, tostring(why)))
                end
                return good
            end
            row(ID_ENABLE, {
                type = 'toggle', mod = MOD_CTRL,
                label = text('ENABLE', '启用', 64),
                default = cfg.enable == 1,
                description = text('Turns the whole addon on and off. Off puts every '
                    .. 'value it wrote back the way the game shipped it. Same '
                    .. 'switch as the enable line in the cfg, and F7 in game.',
                    '整个 mod 的总开关。关闭会把所有改过的数值还原成出厂值。'
                    .. '与 cfg 里的 enable 是同一个开关，游戏里按 F7 也一样。', 400),
            })
            for _, s in ipairs(SLIDERS) do
                local id = 'apw_' .. s.k
                local val = clamp(cfg[s.k], s.min, s.max, s.min)
                row(id, {
                    type = 'slider', mod = MOD_CTRL, label = text(s.en, s.zh, 64),
                    min = s.min, max = s.max, step = s.step, default = val,
                    description = text(s.d_en, s.d_zh, 400),
                })
                MOM.set(id, val)
                local kept = MOM.get(id)
                if type(kept) == 'number' and kept ~= cfg[s.k] then
                    cfg[s.k] = kept
                    state.save_cfg_key(s.k, num(kept))
                end
                if type(MOM.on_change) == 'function' then
                    MOM.on_change(id, function(value)
                        cfg[s.k] = value
                        state.save_cfg_key(s.k, num(value))
                        log(('menu: %s = %s'):format(s.k, num(value)))
                    end)
                end
            end
            for _, t in ipairs(TOGGLES) do
                local id = 'apw_' .. t.k
                local val = cfg[t.k] == 1
                row(id, {
                    type = 'toggle', mod = MOD_CTRL, label = text(t.en, t.zh, 64),
                    default = val, description = text(t.d_en, t.d_zh, 400),
                })
                MOM.set(id, val)
                local kept = MOM.get(id)
                local as01 = kept and 1 or 0
                if as01 ~= cfg[t.k] then
                    cfg[t.k] = as01
                    state.save_cfg_key(t.k, tostring(as01))
                end
                if type(MOM.on_change) == 'function' then
                    MOM.on_change(id, function(value)
                        cfg[t.k] = value and 1 or 0
                        state.save_cfg_key(t.k, tostring(cfg[t.k]))
                        log(('menu: %s = %d'):format(t.k, cfg[t.k]))
                    end)
                end
            end
            MOM.set(ID_ENABLE, cfg.enable == 1)
            if type(MOM.on_change) == 'function' then
                MOM.on_change(ID_ENABLE, function(value)
                    local on = value and 1 or 0
                    cfg.enable = on
                    state.save_cfg_key('enable', tostring(on))
                    if on == 1 then
                        state.armed = true
                    elseif state.armed then
                        state.armed = false
                        pcall(sync_leases, false)
                        pcall(damage, false)
                        pcall(ballistics, false)
                        pcall(seeker, false)
                    end
                    log('menu: enable = ' .. tostring(on))
                end)
            end
            -- P14: which rows the menu does not offer. Classified by the shipped
            -- name, which is what the row is drawn with, so a hash that appears
            -- twice (the Entrenchment Tool does) cannot slip through one of them.
            -- Careful with the grenade rule: GL-, GP- and GR- are grenade
            -- LAUNCHERS and the recoilless rifle, so it matches G- and G/ only.
            local function MENU_DROP(en)
                if en:sub(1, 4) == 'CQC-' or en == 'Entrenchment Tool' then
                    return true                                   -- melee
                end
                if en:match('^G[-/]') or en == 'TED-63 Dynamite'
                    or en == 'K-2 Throwing Knife' or en == 'TM-1 Lure Mine'
                    or en == 'Shrapnel Grenade' or en == 'EMS Grenade'
                    or en == 'Cyborg\'s Grenade' then
                    return true                                   -- throwable
                end
                return en == 'Physical Gun'                       -- not a weapon
            end
            local page, on_page = 1, 0
            state.menu_kept = 0
            for i, w in ipairs(WEAPONS_MENU) do
                -- P14: melee, throwables and the non-player rows are not offered
                -- in the menu any more. They are still guidable - the cfg weapons=
                -- line takes any hash - they simply no longer take a row, and the
                -- rows are what cost a whole category button.
                if not MENU_DROP(w.en) then
                    state.menu_kept = state.menu_kept + 1
                    on_page = on_page + 1
                    if on_page > 32 then on_page, page = 1, page + 1 end
                    local id = wid(i, w.en)
                    local label = text(w.en, w.zh, 64)
                    local guided, big = has_weapon(w.h), has_prio(w.h)
                    local small = has_prio_small(w.h)
                    local val = guided and (big and 3 or (small and 4 or 2)) or 1
                    row(id, {
                        type = 'choice', mod = MOD_WEAP .. ' ' .. tostring(page),
                        label = label, default = val,
                        choices = { 'OFF', text('AIM FIRST', '准心优先', 48),
                                    text('BIG FIRST', '最大血量大优先', 48),
                                    text('SMALL FIRST', '最大血量小优先', 48) },
                        description = text('OFF: plain rounds. AIM FIRST: guided, locks the '
                            .. 'enemy nearest the crosshair. BIG FIRST: guided, locks the '
                            .. 'enemy with the MOST maximum health. SMALL FIRST: guided, '
                            .. 'locks the one with the LEAST. Both order by maximum '
                            .. 'health, so the choice does not drift as a target is '
                            .. 'damaged, and inside one tier the crosshair still decides.',
                            '关：打普通弹。准心优先：打制导弹，锁离准心最近的敌人。'
                            .. '最大血量大优先：打制导弹，锁最大血量的敌人。'
                            .. '最大血量小优先：打制导弹，锁最小血量的敌人。'
                            .. '两者都按最大血量排序，不会因为目标受伤而中途改选；'
                            .. '同一档内仍由准心决定。', 400),
                    })
                    MOM.set(id, val)
                    if type(MOM.on_change) == 'function' then
                        MOM.on_change(id, function(value)
                            local v = tonumber(value) or 1
                            -- P15: only rewrite the weapons line when ON/OFF really
                            -- changed. set_weapon releases every lease for a frame and
                            -- takes them again on the next, which tears the lock UI
                            -- down and rebuilds it; moving a row from AIM FIRST to BIG
                            -- FIRST keeps exactly the same weapons guided, so it needs
                            -- none of that - set_prio carries the whole change.
                            local on = v >= 2
                            if on ~= has_weapon(w.h) then set_weapon(w.h, on) end
                            set_prio(w.h, v == 3, v == 4)
                        end)
                    end
                    end
            end
        end)
        if not ok then
            log('options menu: could not publish the options - ' .. tostring(err))
        else
            log(('options menu: %s + %s 1..%d on the MODS tab - %d weapons '
                .. 'offered, %d dropped from the menu as melee / throwable / '
                .. 'non-player (still usable through the cfg weapons= line)')
                :format(MOD_CTRL, MOD_WEAP,
                    math.ceil((state.menu_kept or #WEAPONS_MENU) / 32),
                    state.menu_kept or #WEAPONS_MENU,
                    #WEAPONS_MENU - (state.menu_kept or #WEAPONS_MENU)))
            log(('options menu: texts in %s (client language %s)')
                :format(chinese() and 'Chinese' or 'English',
                    tostring(language_code() or 'unknown')))
        end
    end
end)()

-- ===================================================================
-- P3: lock reticle - range ring + lock markers
-- ===================================================================
-- THREE elements, TWO screen GUIs, and the split is load bearing:
--
--   GUI A - the RANGE RING (hand-built triangles). Triangles cannot be updated
--           in place: rebuilding them at a colour change is what makes a ring
--           vanish. So the ring lives on its own GUI and that GUI is rebuilt
--           only when its quantised radius, colour or the resolution changes.
--           Its screen radius is the aim cone half angle projected through the
--           camera's vertical FOV, so it follows LOCK ANGLE and the camera zoom.
--
--   GUI B - the LOCK MARKERS (stock Warrant bitmap quads) and, in world space,
--           the TARGET BOX. This GUI is created once and never rebuilt: the
--           quads are updated in place, which is the whole point of separating
--           it. Sharing one GUI with the ring was a bug: zooming a scope moves
--           the FOV, the ring rebuilt every frame, and the markers were
--           destroyed and recreated with it often enough to look absent.
--
-- Engine queries and GUI calls only: nothing here reads or writes process
-- memory. The ring needs no game assets, so it works before the leased Warrant
-- package is resident; the markers simply skip until it is.
local reticle_step = (function()
    local UI = { status = 'idle', error = nil, last_status = nil,
                frames = 0, locked = false, marks = 0, projected = false,
                -- GUI B: lock markers
                gui = nil, world = nil, ids = {}, quads = {}, started = nil,
                markers = false, markers_reason = nil,
                -- GUI A: range ring
                ringu = nil, ringw = nil, ring_key = nil, ring_radius = nil, ring_fov = nil,
                -- world space: the target box
                line = nil, line_dirty = false, marker_reason = nil,
                lock_seen = nil, diag_at = -1, diag_tx = nil, diag_ty = nil }
    -- sr.Color takes (a, r, g, b)
    local RING_UNLOCKED, RING_LOCKED = { 255, 255, 180, 32 }, { 255, 64, 255, 64 }
    local RING_HALF = 0.5              -- half of a one-pixel-wide line
    local RING_SEGMENTS = 96           -- enough that the polygon reads as a circle
    local RING_LEVEL = 100             -- same band the reference reticles draw in
    local LOCK_SECONDS = 0.05
    local BOX_HALF = 0.7
    -- The addon re-picks ctx.target EVERY frame while it is tracking something,
    -- so a target stamp older than this means it stopped: the box then has to go
    -- instead of hanging in the air at the last position anybody knew about.
    local BOX_STALE = 60                      -- frames, 1 s at 60 Hz
    local FALLBACK_FOV = 1.0471975511965976   -- 60 degrees, when the camera is unknown
    -- The lock flickers by design: the aim cone is deliberately tight, so
    -- pick_target loses and regains the target from one frame to the next. The
    -- ring colour follows a short memory of it rather than the instantaneous
    -- state, because every colour change rebuilds the ring's GUI.
    local LOCK_MEMORY = 18                    -- frames, 0.3 s at 60 Hz
    local RING_QUANTISE = 4                   -- rebuild the ring in 4 px steps
    -- Stock image widgets bind this texture slot explicitly; Gui.material alone
    -- does not reproduce their texture initialization.
    local TEXTURE_SLOT = '3aa8b87e00000000'
    -- The marker sprite only. The outline circle in the same atlas is deliberately
    -- not used: it cannot be sized to the cone or thinned to a hairline.
    local MARKER = { material = '5af18dfb697cfef2', texture = 'f9a3f22a93eedcbd',
                     uv = { 0.5712890625, 0.0078125, 0.03125, 0.0625 } }

    local function engine()
        local s = rawget(_G, 'stingray')
        if type(s) ~= 'table' or type(s.Application) ~= 'table'
            or type(s.World) ~= 'table' or type(s.Gui) ~= 'table'
            or type(s.Script) ~= 'table' then return nil end
        -- Vector3 and Color are callables; the engine may expose either as a
        -- function or as a callable table, so accept both and never assume.
        if type(s.Vector3) ~= 'function' and type(s.Vector3) ~= 'table' then return nil end
        if type(s.Color) ~= 'function' and type(s.Color) ~= 'table' then return nil end
        if type(s.World.create_screen_gui) ~= 'function'
            or type(s.World.destroy_gui) ~= 'function'
            or type(s.Gui.resolution) ~= 'function'
            or type(s.Gui.triangle) ~= 'function' then return nil end
        return s
    end

    -- The engine's namespaces are not all the same shape: some are tables, some
    -- are callable tables, some are userdata. Ask for the field rather than
    -- assuming a type, which is exactly what makes a type check here a trap.
    local function has(ns, field)
        if ns == nil then return false end
        local ok, f = pcall(function() return ns[field] end)
        return ok and type(f) == 'function'
    end

    local function listed(s, w)
        if w == nil then return false end
        for _, x in pairs(s.Application.worlds() or {}) do if x == w then return true end end
        return false
    end

    -- GUI B: the markers
    local function drop_markers(s)
        if UI.gui and UI.world and s and listed(s, UI.world) then
            pcall(s.World.destroy_gui, UI.world, UI.gui)
        end
        UI.gui, UI.world, UI.markers = nil, nil, false
        UI.ids, UI.quads, UI.started = {}, {}, nil
    end

    -- GUI A: the ring
    local function drop_ring(s)
        if UI.ringu and UI.ringw and s and listed(s, UI.ringw) then
            pcall(s.World.destroy_gui, UI.ringw, UI.ringu)
        end
        UI.ringu, UI.ringw, UI.ring_key = nil, nil, nil
    end

    -- Make the box invisible again.  This is the path that is KNOWN to work on
    -- this build - reset the object, push one fully transparent degenerate line
    -- and dispatch it - and it is what marker() has always done when the TARGET
    -- is lost.  Handing the object back with World.destroy_line_object alone
    -- does not always take it out of the frame, and a box that is still being
    -- rendered can never be reached again once its handle is gone.
    local function clear_line(s, w)
        if not (UI.line and UI.line_dirty and w) then return false end
        if not (has(s.LineObject, 'reset') and has(s.LineObject, 'add_line')
            and has(s.LineObject, 'dispatch')) then return false end
        local z = s.Vector3(0, 0, 0)
        local ok = pcall(function()
            s.LineObject.reset(UI.line)
            s.LineObject.add_line(UI.line, s.Color(0, 0, 0, 0), z, z)
            s.LineObject.dispatch(w, UI.line)
        end)
        if ok then UI.line_dirty = false end
        return ok
    end

    local function drop_lines(s)
        if not UI.line then return end
        local w = s.Application.main_world and s.Application.main_world() or nil
        -- 1. hide it first, so a destroy that silently does nothing cannot leave
        --    a visible box behind
        clear_line(s, w)
        -- 2. then hand the object back, and only forget the handle when the
        --    engine really took it.  Keeping it costs nothing (the next target
        --    reuses the object) and it is the only way to clear a box that is
        --    still being drawn.
        local gone = false
        if w and has(s.World, 'destroy_line_object') then
            gone = pcall(s.World.destroy_line_object, w, UI.line)
        end
        if gone then
            UI.line, UI.line_dirty, UI.line_fails = nil, false, 0
            return
        end
        UI.line_fails = (UI.line_fails or 0) + 1
        -- by now the object is invisible, so letting go cannot strand a box; this
        -- only stops a broken destroy call from being retried for ever
        if not UI.line_dirty and UI.line_fails > 120 then
            UI.line, UI.line_dirty, UI.line_fails = nil, false, 0
        end
    end

    -- HD2 draws screen overlays in the UI world, never in the mission world.
    local function ui_world(s)
        local main = s.Application.main_world and s.Application.main_world() or nil
        for _, w in pairs(s.Application.worlds() or {}) do if w ~= main then return w end end
        return nil
    end

    -- ---------------------------------------------------------------- project
    -- The render camera is not handed to a mod, so it is found the way the game's
    -- own HUD addons do it: the camera unit closest to the mission camera pose,
    -- cached and re-checked once a second.
    local CAM = { camera = nil, unit = nil, next_scan = 0, reason = nil }

    local function render_camera(s, world, now)
        if CAM.unit then
            local ok, alive = false, nil
            if has(s.Unit, 'alive') then ok, alive = pcall(s.Unit.alive, CAM.unit) end
            if not ok or alive ~= true then CAM.camera, CAM.unit = nil, nil end
        end
        if CAM.camera then return CAM.camera end
        if now < CAM.next_scan then return nil end
        CAM.next_scan = now + 1
        if not (has(s.World, 'units') and has(s.World, 'debug_camera_pose')
            and has(s.Unit, 'num_cameras') and has(s.Unit, 'camera')
            and has(s.Camera, 'world_position') and has(s.Matrix4x4, 'translation')
            and has(s.Vector3, 'x')) then
            CAM.reason = 'camera_api_missing'
            return nil
        end
        local okp, pose = pcall(s.World.debug_camera_pose, world)
        if not okp or pose == nil then CAM.reason = 'no_camera_pose' return nil end
        local oko, origin = pcall(s.Matrix4x4.translation, pose)
        if not oko or origin == nil then CAM.reason = 'no_camera_origin' return nil end
        local ox, oy, oz = s.Vector3.x(origin), s.Vector3.y(origin), s.Vector3.z(origin)
        local okw, units = pcall(s.World.units, world)
        if not okw or type(units) ~= 'table' then CAM.reason = 'no_units' return nil end
        local best, best_unit, best_cam = 0.25, nil, nil
        for _, u in pairs(units) do
            local okn, n = pcall(s.Unit.num_cameras, u)
            if okn and type(n) == 'number' and n > 0 then
                local okc, cam = pcall(s.Unit.camera, u, 1)
                if okc and cam then
                    local okpos, p = pcall(s.Camera.world_position, cam)
                    if okpos and p then
                        local dx = s.Vector3.x(p) - ox
                        local dy = s.Vector3.y(p) - oy
                        local dz = s.Vector3.z(p) - oz
                        local d = dx * dx + dy * dy + dz * dz
                        if d < best then best, best_unit, best_cam = d, u, cam end
                    end
                end
            end
        end
        CAM.unit, CAM.camera = best_unit, best_cam
        CAM.reason = best_cam and nil or 'camera_not_found'
        return CAM.camera
    end

    local function camera_fov(s, camera)
        if camera and has(s.Camera, 'vertical_fov') then
            local ok, v = pcall(s.Camera.vertical_fov, camera)
            if ok and type(v) == 'number' and v > 0.05 and v < 3 then return v end
        end
        return nil
    end

    -- Screen radius of the aim cone's half angle. A cone projects to a fixed
    -- screen radius, so this is (h/2)/tan(fov/2) * tan(cone) - independent of how
    -- far away the target is.
    local function ring_radius(s, h, world, now)
        local fov = camera_fov(s, render_camera(s, world, now))
        local k = (h / 2) / math.tan((fov or FALLBACK_FOV) / 2)
        -- the SAME tangent best_for acquires with (ctx.cone_tan, published by
        -- update_cone), so the ring cannot disagree with what is locked
        local cone_tan = tonumber(ctx.cone_tan)
        if not cone_tan or cone_tan ~= cone_tan then
            local cone = cfg.cone_deg or 12
            if type(cone) ~= 'number' or cone <= 0 then return nil end
            cone_tan = math.tan(math.rad(cone))
        end
        if cone_tan <= 0 then return nil end
        local r = cone_tan * k
        if type(r) ~= 'number' or r ~= r or r < 2 then return nil end
        return math.min(r, h * 4), fov
    end

    -- world position -> screen pixels, or nil when the camera or the binding is
    -- not available. The caller falls back to the screen centre on nil.
    local function raw_project(s, world, pos, w, h, now)
        if not has(s.Camera, 'world_to_screen') then return nil end
        local camera = render_camera(s, world, now)
        if not camera then return nil end
        local ok, p = pcall(s.Camera.world_to_screen, camera,
            s.Vector3(pos[1], pos[2], pos[3]), nil, s.Vector2(w, h))
        if not ok or p == nil then return nil end
        local okx, x = pcall(s.Vector3.x, p)
        local oky, y = pcall(s.Vector3.y, p)
        if not okx or not oky or type(x) ~= 'number' or type(y) ~= 'number'
            or x ~= x or y ~= y then return nil end
        -- a point behind the camera projects to nonsense; reject it rather than
        -- dragging the markers across the screen
        if math.abs(x) > w * 4 or math.abs(y) > h * 4 then return nil end
        return x, y
    end

    -- THE PROJECTION SLIP, measured and corrected (P15c).
    --
    -- The lock markers are PROJECTED; the range ring is DRAWN at the screen centre.
    -- The camera axis - the direction the player looks down - has to land on the
    -- crosshair, which is the screen centre, so the projection of that axis is the
    -- error term of the whole projection. Measured live it is ZERO in most
    -- sessions (then nothing here changes anything) and was 130 px right and
    -- 154 px above the centre in one, where the markers sat that far off the enemy
    -- while the ring stayed on the crosshair - the "sometimes good, sometimes bad"
    -- report, and the reason no targeting change ever fixed it.
    --
    -- So the offset is measured from the axis every frame and subtracted. A slip
    -- larger than a quarter of the screen is not a slip but a broken camera pose,
    -- and is ignored rather than dragging the markers across the screen.
    local OFF = { frame = -1, x = 0, y = 0 }

    local function axis_offset(s, world, w, h, now)
        if OFF.frame == state.frame then return OFF.x, OFF.y end
        OFF.frame, OFF.x, OFF.y = state.frame, 0, 0
        if world and ctx.cam_origin and ctx.cam_forward then
            local ax, ay = raw_project(s, world,
                { ctx.cam_origin[1] + ctx.cam_forward[1] * 50,
                  ctx.cam_origin[2] + ctx.cam_forward[2] * 50,
                  ctx.cam_origin[3] + ctx.cam_forward[3] * 50 }, w, h, now)
            if ax and ay then
                local dx, dy = ax - w / 2, ay - h / 2
                if math.abs(dx) <= w * 0.25 and math.abs(dy) <= h * 0.25 then
                    OFF.x, OFF.y = dx, dy
                end
            end
        end
        return OFF.x, OFF.y
    end

    -- what the reticle draws with: the raw projection with that slip removed
    local function project(s, world, pos, w, h, now)
        local x, y = raw_project(s, world, pos, w, h, now)
        if not x then return nil end
        local ox, oy = axis_offset(s, world, w, h, now)
        return x - ox, y - oy
    end

    -- ------------------------------------------------------------------- ring
    -- one hairline quad, drawn as the two triangles Gui.triangle wants
    local function seg(s, gui, ax, ay, bx, by, half, colour)
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1e-6 then return end
        local nx, ny = -dy / len * half, dx / len * half
        local V = s.Vector3
        s.Gui.triangle(gui, V(ax + nx, 0, ay + ny), V(bx + nx, 0, by + ny),
            V(bx - nx, 0, by - ny), RING_LEVEL, colour)
        s.Gui.triangle(gui, V(ax + nx, 0, ay + ny), V(bx - nx, 0, by - ny),
            V(ax - nx, 0, ay - ny), RING_LEVEL, colour)
    end

    local function ring_draw(s, w, h, radius, rgba)
        local gui = UI.ringu
        if not gui then return false, 'no_gui' end
        local colour = s.Color(rgba[1], rgba[2], rgba[3], rgba[4])
        local cx, cy = w / 2, h / 2
        local px, py = cx + radius, cy
        for i = 1, RING_SEGMENTS do
            local a = i * 2 * math.pi / RING_SEGMENTS
            local qx, qy = cx + radius * math.cos(a), cy + radius * math.sin(a)
            seg(s, gui, px, py, qx, qy, RING_HALF, colour)
            px, py = qx, qy
        end
        return true
    end

    -- ---------------------------------------------------------------- markers
    local function markers_setup(s, gui)
        if s.Vector2 == nil then return false, 'marker_api_missing' end
        if not (has(s.IdString64, 'from_hex') and has(s.Material, 'set_texture')
            and has(s.Gui, 'material') and has(s.Gui, 'bitmap_3d_uv')
            and has(s.Gui, 'update_bitmap_3d_uv') and has(s.Quaternion, 'axis_angle')
            and has(s.Matrix4x4, 'from_quaternion_position')) then
            return false, 'marker_api_missing'
        end
        -- the leased Warrant package has to be resident for this sprite; when it
        -- is not, the markers simply skip and the ring is unaffected
        if has(s.Application, 'can_get') then
            local ok, got = pcall(s.Application.can_get, 'material',
                s.IdString64.from_hex(MARKER.material))
            if not ok or got ~= true then return false, 'material_not_loaded' end
            ok, got = pcall(s.Application.can_get, 'texture',
                s.IdString64.from_hex(MARKER.texture))
            if not ok or got ~= true then return false, 'texture_not_loaded' end
        end
        local ok, material = pcall(s.Gui.material, gui, s.IdString64.from_hex(MARKER.material))
        if not ok or material == nil then return false, 'material_unavailable' end
        ok = pcall(s.Material.set_texture, material, s.IdString64.from_hex(TEXTURE_SLOT),
            s.IdString64.from_hex(MARKER.texture))
        if not ok then return false, 'texture_bind_failed' end
        return true
    end

    -- One atlas quad. `angle` is in degrees; the transform centres the quad in
    -- its own frame, because Gui.bitmap_3d_uv's origin differs from
    -- Gui.triangle's (a negative Z origin left it half a quad above centre).
    local function quad(s, index, x, y, size, angle, alpha, lock_state, tint)
        local old = UI.quads[index]
        if old and ((alpha == 0 and old.alpha == 0)
            or (old.x == x and old.y == y and old.size == size
                and old.angle == angle and old.alpha == alpha
                and old.state == lock_state)) then
            return
        end
        local material = s.IdString64.from_hex(MARKER.material)
        local uv = MARKER.uv
        local uv0, uv1 = s.Vector2(uv[1], uv[2]), s.Vector2(uv[1] + uv[3], uv[2] + uv[4])
        local radians = math.rad(angle)
        local rotation = s.Quaternion.axis_angle(s.Vector3(0, 1, 0), radians)
        local half = size / 2
        local sine, cosine = math.sin(radians), math.cos(radians)
        local pose = s.Matrix4x4.from_quaternion_position(rotation,
            s.Vector3(x - half * (cosine + sine), 0, y - half * (cosine - sine)))
        local pos = s.Vector3(0, 0, 0)
        local use = (alpha == 0) and s.Color(0, 0, 0, 0) or tint
        if UI.ids[index] then
            s.Gui.update_bitmap_3d_uv(UI.gui, UI.ids[index], material, uv0, uv1, pose, pos,
                RING_LEVEL, s.Vector2(size, size), use)
        else
            UI.ids[index] = s.Gui.bitmap_3d_uv(UI.gui, material, uv0, uv1, pose, pos,
                RING_LEVEL, s.Vector2(size, size), use)
        end
        old = old or {}
        UI.quads[index] = old
        old.x, old.y, old.size, old.angle, old.alpha, old.state = x, y, size, angle, alpha,
            lock_state
    end

    local function markers_draw(s, w, h, locked, now, world)
        local progress = 0
        if locked then
            if UI.started == nil then UI.started = now end
            progress = math.min(1, math.max(0, (now - UI.started) / LOCK_SECONDS))
        else
            UI.started = nil
        end
        local confirmed = locked and progress >= 1
        local state = confirmed and 'locked' or (locked and 'acquiring' or 'idle')
        -- sr.Color takes (a, r, g, b); these are the stock Warrant colours.
        local colour = confirmed and s.Color(255, 0, 255, 0)
            or (locked and s.Color(255, 255, 193.8, 7.65)
                or s.Color(255, 255, 233.07, 0))
        -- The markers orbit the LOCKED TARGET on screen, which is what makes the
        -- reticle read as "that one". Centre only when there is no target or the
        -- projection is unavailable.
        local tx, ty
        if locked then
            local p = ctx.target and ctx.target.position
            if type(p) == 'table' and type(p[1]) == 'number' and world then
                tx, ty = project(s, world, p, w, h, now)
                UI.projected = (tx ~= nil)
            end
        else
            UI.projected = false
        end
        local bx, by = tx or w / 2, ty or h / 2
        UI.diag_tx, UI.diag_ty = tx, ty
        -- three markers 120 degrees apart, spinning once and contracting from
        -- radius 24 to 10 over the lock; hidden until there is a target
        local scale = h / 1080
        local radius = (24 * (1 - progress) + 10 * progress) * scale
        local alpha = locked and 1 or 0
        for i = 0, 2 do
            local angle = progress * 360 + i * 120
            local radians = math.rad(angle)
            quad(s, i + 1, bx + math.sin(radians) * radius,
                by + math.cos(radians) * radius, 48 * scale, angle, alpha, state, colour)
        end
        UI.status = confirmed and 'drawn_locked' or (locked and 'drawn_acquiring' or 'drawn')
    end

    -- ------------------------------------------------------------ world marker
    local EDGES = { {1,2},{3,4},{5,6},{7,8},{1,3},{2,4},{5,7},{6,8},{1,5},{2,6},{3,7},{4,8} }
    local function marker(s)
        local world = s.Application.main_world and s.Application.main_world() or nil
        if not world or not (has(s.World, 'create_line_object')
            and has(s.World, 'destroy_line_object') and has(s.LineObject, 'reset')
            and has(s.LineObject, 'add_line')
            and has(s.LineObject, 'dispatch')) then
            UI.marker_reason = 'line_api_missing'
            return
        end
        local t = ctx.target
        local p = t and t.position
        local fresh = (state.frame - (ctx.target_at or -1e9)) <= BOX_STALE
        if type(p) ~= 'table' or type(p[1]) ~= 'number' or not fresh then
            clear_line(s, world)
            return
        end
        if not UI.line then
            UI.line = s.World.create_line_object(world, true)
            if not UI.line then UI.marker_reason = 'line_create_failed' return end
        end
        local c = {}
        for i = 0, 7 do
            c[i + 1] = { p[1] + ((i % 2 == 0) and -BOX_HALF or BOX_HALF),
                         p[2] + ((math.floor(i / 2) % 2 == 0) and -BOX_HALF or BOX_HALF),
                         p[3] + ((math.floor(i / 4) % 2 == 0) and -BOX_HALF or BOX_HALF) }
        end
        local colour, V = s.Color(255, 64, 255, 64), s.Vector3
        s.LineObject.reset(UI.line)
        for i = 1, #EDGES do
            local a, b = c[EDGES[i][1]], c[EDGES[i][2]]
            s.LineObject.add_line(UI.line, colour, V(a[1], a[2], a[3]), V(b[1], b[2], b[3]))
        end
        s.LineObject.dispatch(world, UI.line)
        UI.line_dirty = true
        UI.marks = UI.marks + 1
    end

    -- One line a second while a target is held. This is what turns "the position
    -- is wrong" into numbers: the camera, the FOV, the target's world position and
    -- where it projected to, next to the screen centre.
    local function diag(s, w, h, locked, now)
        if not locked then return end
        local sec = math.floor(now)
        if UI.diag_at == sec then return end
        UI.diag_at = sec
        local p = ctx.target and ctx.target.position
        -- P15: where the camera axis itself lands on screen. The ring is drawn
        -- about the screen centre; if the game's projection is off centre (a lens
        -- shift, which third person cameras often use) the axis lands somewhere
        -- else, and then it is the RING that is drawn in the wrong place while the
        -- marker - which is projected - is right.
        local ax, ay, mx, my
        local mw = s.Application.main_world and s.Application.main_world() or nil
        if mw and ctx.cam_origin and ctx.cam_forward then
            -- raw on purpose: this is the measurement of the slip itself
            ax, ay = raw_project(s, mw, { ctx.cam_origin[1] + ctx.cam_forward[1] * 50,
                ctx.cam_origin[2] + ctx.cam_forward[2] * 50,
                ctx.cam_origin[3] + ctx.cam_forward[3] * 50 }, w, h, now)
        end
        -- P15b: and the MUZZLE axis, for the same reason. Three things can be the
        -- aim direction here - the debug camera pose (what the cone is built on),
        -- the render camera the points are projected with, and the weapon in hand -
        -- and the crosshair is wherever the game puts it. If the muzzle axis lands
        -- on the screen centre while the camera axis does not, the camera pose is
        -- the odd one out and the cone is aimed 6 degrees off the crosshair.
        if mw and ctx.origin and ctx.forward then
            mx, my = raw_project(s, mw, { ctx.origin[1] + ctx.forward[1] * 50,
                ctx.origin[2] + ctx.forward[2] * 50,
                ctx.origin[3] + ctx.forward[3] * 50 }, w, h, now)
        end
        log(('RETICLE DIAG cam=%s fov=%s screen=%dx%d centre=%.0f,%.0f world=%s,%s,%s '
            .. 'screenpos=%s,%s axis=%s,%s muz=%s,%s ring=%s r=%s box=%s')
            :format(tostring(CAM.camera ~= nil),
                UI.ring_fov and string.format('%.1fdeg', math.deg(UI.ring_fov)) or 'fallback',
                w, h, w / 2, h / 2,
                p and string.format('%.1f', p[1]) or '-',
                p and string.format('%.1f', p[2]) or '-',
                p and string.format('%.1f', p[3]) or '-',
                UI.diag_tx and string.format('%.0f', UI.diag_tx) or '-',
                UI.diag_ty and string.format('%.0f', UI.diag_ty) or '-',
                ax and string.format('%.0f', ax) or '-',
                ay and string.format('%.0f', ay) or '-',
                mx and string.format('%.0f', mx) or '-',
                my and string.format('%.0f', my) or '-',
                tostring(UI.ring_radius), tostring(cfg.range_ring == 1),
                tostring(UI.line ~= nil)))
    end

    -- ------------------------------------------------ which weapon is aiming
    -- P4. APW drives its aim cone from held[1], which is usually the primary
    -- slung on the player's back. Whenever the weapon in hand is the second one -
    -- a support weapon - the cone started behind the player, so the target it
    -- picked was wrong and everything drawn from it (the markers, the box) did
    -- not appear. The weapon in hand points where the player looks and the slung
    -- one does not, so the pose best aligned with the camera forward is the one
    -- in hand. The choice is published as ctx.aim_pose and APW's weapon_pose()
    -- prefers it on the next frame, which fixes the cone and the display together.
    local AIM = { id = nil, score = nil }

    -- The camera's own pose. It is published so the ACQUISITION cone can be built
    -- on it: a cone whose apex is the camera projects to exactly a circle about
    -- the screen centre, radius tan(half angle) * (h/2)/tan(fov/2), at every depth
    -- - which is precisely the ring drawn below. Building the cone on the muzzle
    -- instead makes the two disagree by several degrees in third person, more than
    -- the whole cone at a tight LOCK ANGLE, and enemies outside the ring were
    -- acquired because of it.
    local function camera_pose(s, world)
        if not world or not has(s.Matrix4x4, 'forward') or not has(s.Matrix4x4, 'translation')
            or not has(s.World, 'debug_camera_pose') or not has(s.Vector3, 'x') then
            return nil
        end
        local ok, pose = pcall(s.World.debug_camera_pose, world)
        if not ok or pose == nil then return nil end
        local okf, f = pcall(s.Matrix4x4.forward, pose)
        local okt, o = pcall(s.Matrix4x4.translation, pose)
        if not okf or f == nil or not okt or o == nil then return nil end
        local okx, fx = pcall(s.Vector3.x, f)
        local _, fy = pcall(s.Vector3.y, f)
        local _, fz = pcall(s.Vector3.z, f)
        local _, ox = pcall(s.Vector3.x, o)
        local _, oy = pcall(s.Vector3.y, o)
        local _, oz = pcall(s.Vector3.z, o)
        if not okx or type(fx) ~= 'number' or type(fy) ~= 'number' or type(fz) ~= 'number'
            or type(ox) ~= 'number' or type(oy) ~= 'number' or type(oz) ~= 'number' then
            return nil
        end
        return { ox, oy, oz }, { fx, fy, fz }
    end

    -- The LOCK ANGLE is calibrated against this vertical FOV, and the cone is
    -- compensated with the current one so the lock range is the same SIZE ON
    -- SCREEN at every zoom (see the P12 note above).
    local SCOPE_REF_FOV = 60
    -- "a scope is in use" = the FOV is at least this much narrower than the
    -- reference (54 degrees with the shipped 60).  Without a margin the small
    -- FOV wobble of walking and sprinting would switch the scope model on and off.
    local SCOPE_MARGIN = 0.9

    -- Publish tan(effective half angle) for best_for and the ring alike.
    local function update_cone(s, world)
        local cone = num_or(cfg.cone_deg, 12)
        if cone <= 0 then ctx.cone_tan = 0 return end     -- cone 0 = no ring
        local tan_cone = math.tan(math.rad(cone))
        local fov = camera_fov(s, render_camera(s, world, state.frame / 60))
        if not fov then ctx.cone_tan = tan_cone return end  -- no camera: as set
        if cfg.scope_fix == 1 and fov < math.rad(SCOPE_REF_FOV) * SCOPE_MARGIN then
            -- Follow the magnification: the ring is the ORIGINAL ring (the
            -- uncompensated one, which grows as the FOV narrows) times the
            -- user's decimal.  A 4x scope therefore locks proportionally
            -- further than a 1x scope, and the decimal still caps the whole
            -- thing - 1.0 is exactly the original behaviour.
            local scale = num_or(cfg.scope_scale, 0.3)
            if scale ~= scale or scale < 0.02 then scale = 0.02
            elseif scale > 1 then scale = 1 end
            ctx.cone_tan = tan_cone * scale
            return
        end
        -- Screen consistent: compensate with the camera FOV so the ring keeps
        -- the same pixel radius at every zoom.
        local zoom = math.tan(fov / 2) / math.tan(math.rad(SCOPE_REF_FOV) / 2)
        -- a nonsense FOV must not produce a nonsense cone
        if zoom ~= zoom or zoom < 0.05 then zoom = 0.05
        elseif zoom > 2 then zoom = 2 end
        ctx.cone_tan = tan_cone * zoom
    end

    local function update_aim_pose(s, world)
        -- published first and unconditionally: the acquisition cone depends on it
        local cam_o, cam_f = camera_pose(s, world)
        ctx.cam_origin, ctx.cam_forward = cam_o, cam_f
        update_cone(s, world)
        local held = ctx.held
        if not cam_f or not held or #held < 2 or not ctx.pose then
            ctx.aim_pose, ctx.aim_txt, AIM.id, AIM.score = nil, nil, nil, nil
            return
        end
        local cx, cy, cz = cam_f[1], cam_f[2], cam_f[3]
        local best_id, best_score
        for i = 1, #held do
            local p = ctx.pose[held[i].id]
            if p then
                local f = p.forward
                local score = f[1] * cx + f[2] * cy + f[3] * cz
                if not best_score or score > best_score then
                    best_id, best_score = held[i].id, score
                end
            end
        end
        -- the two poses can be almost equally aligned; require a clear win before
        -- switching so the choice cannot flicker from one frame to the next
        if AIM.id and AIM.id ~= best_id and ctx.pose[AIM.id]
            and best_score and best_score <= (AIM.score or -2) + 0.08 then
            best_id, best_score = AIM.id, AIM.score
        end
        if not best_id then ctx.aim_pose, ctx.aim_txt = nil, nil return end
        if AIM.id ~= best_id then
            AIM.id, AIM.score = best_id, best_score
            log(('AIM the aim cone now starts at the weapon in hand (id=%s, '
                .. 'camera-aligned score %.2f), not at the first one carried')
                :format(tostring(best_id), best_score))
        else
            AIM.score = best_score
        end
        ctx.aim_pose = ctx.pose[best_id]
        -- P10: the hash of the weapon in hand, so the targeting order can follow
        -- it. This is the same weapon pick the aim cone uses, which is what makes
        -- the reticle agree with whatever the round does.
        for i = 1, #held do
            if held[i].id == best_id then ctx.aim_txt = held[i].txt break end
        end
    end

    -- ------------------------------------------- is the weapon in hand guided?
    -- P11. The lock UI belongs to a GUIDED weapon. The runtime reports the entity
    -- in hand and its type (docs/player-equipment.md), and the addon publishes the
    -- set of guided types as ctx.guided. Whatever is off the list - a weapon whose
    -- guidance is switched off in the MODS tab, a stratagem ball, anything that is
    -- not the list's weapon resource at all - drops the marker, the ring and the
    -- box instead of drawing a lock that can never bind. The test is the list, not
    -- a category: throwables and melee weapons are on it and are guidable when
    -- they are switched on, so they keep the UI.
    --
    -- It fails OPEN on purpose. When the runtime cannot be asked at all (no
    -- runtime module, no player, a runtime without the call) the UI is drawn
    -- exactly as it was before this existed, rather than silently disappearing.
    local HAND = { at = -1e9, type = nil, ok = true, reason = nil, logged = nil,
                   rt = nil, next_try = -1e9 }
    local HAND_EVERY = 6                  -- frames between queries, 0.1 s at 60 Hz

    -- The shared runtime is NOT a global. This addon already asks for it by name
    -- for its asset leases, and that is the only path that is known to work:
    -- rawget(_G, 'hd2') is nil in a Bingus addon, which is exactly what the first
    -- build of this gate hit - it saw "no_hd2" on every query and therefore drew
    -- the UI everywhere. A global is still accepted first, in case a runtime ever
    -- publishes one. A miss is retried once a second, not once a frame.
    local function hand_runtime()
        if HAND.rt then return HAND.rt end
        -- the global costs nothing to re-check, so it is checked every time
        local g = rawget(_G, 'hd2')
        if type(g) == 'table' and type(g.local_player) == 'function' then
            HAND.rt = g
            return g
        end
        -- require is the expensive one, miss or not, so a miss waits a second
        if state.frame < HAND.next_try then return nil end
        HAND.next_try = state.frame + 60
        local ok, mod = pcall(require, 'mods/skyeshade/hd2runtime')
        if ok and type(mod) == 'table' then HAND.rt = mod end
        return HAND.rt
    end

    local function hand_guided()
        if (state.frame - HAND.at) < HAND_EVERY then return HAND.ok end
        HAND.at = state.frame
        local hd2 = hand_runtime()
        local pok, text, why, via = pcall(function()
            if type(hd2) ~= 'table' then return nil, 'no_runtime' end
            if type(hd2.local_player) ~= 'function' then
                return nil, 'no_local_player'
            end
            local p = hd2.local_player()
            if p == nil then return nil, 'no_player' end
            -- equipped_weapon re-reads the wielder slot on every call and is the
            -- newest name for this; held_weapon and loadout().held are older ones
            local w, wwhy, how
            if type(p.equipped_weapon) == 'function' then
                w, wwhy, how = p:equipped_weapon(), nil, 'equipped_weapon'
            elseif type(p.held_weapon) == 'function' then
                w, wwhy, how = p:held_weapon(), nil, 'held_weapon'
            elseif type(p.loadout) == 'function' then
                local lo = p:loadout()
                w, how = (type(lo) == 'table') and lo.held or nil, 'loadout'
            else
                return nil, 'no_hand_api'
            end
            if w == nil then return nil, tostring(wwhy or 'nothing_in_hand') end
            if type(w.type) ~= 'string' then return nil, 'no_type' end
            -- the runtime prints the weapon resource as hex digits, with or
            -- without the 0x the cfg and the SDK catalogs use
            local t = w.type:upper():gsub('^0X', '')
            return t, nil, how .. (w.slot and ('/' .. tostring(w.slot)) or '')
        end)
        if not pok then
            HAND.ok, HAND.type = true, nil
            HAND.reason = 'call failed: ' .. tostring(text)
        elseif text == nil then
            HAND.ok, HAND.type, HAND.reason, via = true, nil, tostring(why), nil
        else
            HAND.type = text
            if ctx.guided == nil then
                -- the addon has not published the list yet: fail open, exactly as
                -- for a runtime that cannot be asked
                HAND.ok, HAND.reason = true, 'no_list'
            else
                HAND.ok, HAND.reason = ctx.guided[text] == true, nil
            end
        end
        -- one line per change, so "the ring never came back" is answerable: the
        -- reason word says which piece of the query failed, and `via` which call
        -- answered when it did
        local key = (HAND.ok and 'guided:' or 'not:')
            .. tostring(HAND.type or HAND.reason)
        if key ~= HAND.logged then
            HAND.logged = key
            -- the one failure that is worth spelling out: with no runtime there is
            -- no way to know what is in hand, the gate fails OPEN, and the lock UI
            -- comes back for every weapon - which reads as "the feature broke
            -- again" unless the log says why
            local note = (HAND.reason == 'no_runtime')
                and ('  <-- HD2Runtime is not installed or not enabled: the lock UI '
                     .. 'cannot tell which weapon is in hand, so it is drawn for all '
                     .. 'of them. Install/enable HD2Runtime and restart.') or ''
            log(('RETICLE hand weapon: type=%s in the guided list=%s -> lock UI %s%s%s')
                :format(tostring(HAND.type or HAND.reason),
                    tostring(ctx.guided ~= nil
                        and ctx.guided[HAND.type or ''] == true),
                    HAND.ok and 'ON' or 'OFF',
                    via and (' (via ' .. via .. ')') or '', note))
        end
        return HAND.ok
    end

    -- -------------------------------------------------------------------- draw
    local function draw()
        local s = engine()
        if not s then UI.status = 'no_stingray' return end
        local mworld = s.Application.main_world and s.Application.main_world() or nil
        -- published before the toggle checks: the aim cone must start from the
        -- weapon in hand whether or not anything is being drawn
        if cfg.enable == 1 and state.armed then update_aim_pose(s, mworld) end
        local want_ring = cfg.range_ring == 1
        local want_markers = cfg.lock_reticle == 1
        if cfg.enable ~= 1 or not state.armed or not (want_ring or want_markers
            or cfg.target_box == 1) then
            drop_markers(s) drop_ring(s) drop_lines(s)
            UI.locked = false UI.status = 'off' return
        end
        -- the reticle belongs to the weapon in hand
        if (state.frame - (ctx.weapon_at or -99999)) > 2 then
            drop_markers(s) drop_ring(s) drop_lines(s)
            UI.locked = false UI.status = 'idle' return
        end
        -- P11: and only while that weapon is one of the guided ones. Holding a
        -- weapon whose guidance is off, or one that cannot be guided at all,
        -- shows no lock UI at all.
        if not hand_guided() then
            drop_markers(s) drop_ring(s) drop_lines(s)
            UI.locked = false UI.status = 'hand_not_guided' return
        end
        local ok, w, h = pcall(s.Gui.resolution)
        if not ok or type(w) ~= 'number' or type(h) ~= 'number'
            or w < 320 or h < 200 or w > 16384 or h > 16384 then
            UI.status = 'no_resolution' return
        end
        local locked = ctx.target ~= nil
        UI.locked = locked
        if locked then UI.lock_seen = state.frame end
        -- what the RING shows: the lock with a short memory, so a flickering
        -- acquisition cannot rebuild the ring on every frame
        local ring_locked = UI.lock_seen ~= nil and (state.frame - UI.lock_seen) <= LOCK_MEMORY
        local now = state.frame / 60

        -- ---- GUI A: the range ring, on its own, rebuilt only when it changes.
        -- The radius depends on the camera FOV, so a scoped rifle zooming in and
        -- out changes it continuously; it is quantised and, critically, isolated
        -- from the markers so a rebuild can never disturb them.
        local ring_key
        if want_ring and mworld then
            local r, fov = ring_radius(s, h, mworld, now)
            if r then
                UI.ring_radius = math.floor(r / RING_QUANTISE + 0.5) * RING_QUANTISE
                UI.ring_fov = fov
                ring_key = (ring_locked and 'L' or 'U') .. '|' .. w .. '|' .. h
                    .. '|' .. UI.ring_radius
            end
        end
        if UI.ringu and not listed(s, UI.ringw) then drop_ring(s) end
        if UI.ringu and ring_key ~= UI.ring_key then drop_ring(s) end
        if not UI.ringu and ring_key then
            local world = ui_world(s)
            if not world then UI.status = 'no_ui_world' return end
            local gui = s.World.create_screen_gui(world, 'scale', 1, 1)
            if not gui then UI.status = 'ring_gui_failed' return end
            UI.ringu, UI.ringw = gui, world
            ring_draw(s, w, h, UI.ring_radius, ring_locked and RING_LOCKED or RING_UNLOCKED)
        end
        UI.ring_key = ring_key

        -- ---- GUI B: the lock markers. Created once, never rebuilt.
        if want_markers then
            if UI.gui and not listed(s, UI.world) then drop_markers(s) end
            if not UI.gui then
                local world = ui_world(s)
                if not world then UI.status = 'no_ui_world' return end
                local gui = s.World.create_screen_gui(world, 'scale', 1, 1)
                if not gui then UI.status = 'marker_gui_failed' return end
                UI.gui, UI.world = gui, world
                UI.ids, UI.quads = {}, {}
                local ready, why = markers_setup(s, gui)
                UI.markers = ready
                UI.markers_reason = ready and nil or why
            end
            if UI.markers then
                markers_draw(s, w, h, locked, now, mworld)
            end
        else
            if UI.gui then drop_markers(s) end
            UI.projected = false
        end

        -- ---- the box is its own switch: it is the only thing in world space
        if cfg.target_box == 1 then
            marker(s)
        else
            drop_lines(s)
        end
        UI.frames = UI.frames + 1
        diag(s, w, h, locked, now)
    end

    return function(stop)
        local s = engine()
        if not s then return end
        if stop then
            -- hand the aim cone back to the file's own choice before going away
            ctx.aim_pose, ctx.cam_origin, ctx.cam_forward = nil, nil, nil
            pcall(drop_markers, s) pcall(drop_ring, s) pcall(drop_lines, s)
            UI.status = 'stopped' return
        end
        if type(s.Script.temp_byte_count) ~= 'function'
            or type(s.Script.set_temp_byte_count) ~= 'function' then return end
        -- every call must run inside the engine's temporaries ring
        local counted, saved = pcall(s.Script.temp_byte_count)
        if not counted then return end
        local ok, err = pcall(draw)
        if not ok then
            UI.error = tostring(err)
            UI.status = 'error'
            pcall(drop_markers, s) pcall(drop_ring, s)
        end
        pcall(s.Script.set_temp_byte_count, saved)
        -- one line per change, so a reticle that never appears says why in the log
        if UI.last_status ~= UI.status then
            UI.last_status = UI.status
            if UI.status ~= 'idle' and UI.status ~= 'off' then
                log(('RETICLE %s (ring=%s r=%s markers=%s proj=%s box=%s frames=%d marks=%d)%s%s%s')
                    :format(UI.status, tostring(cfg.range_ring == 1),
                        tostring(UI.ring_radius), tostring(UI.markers), tostring(UI.projected),
                        tostring(UI.line ~= nil), UI.frames, UI.marks,
                        UI.markers_reason and (' marker=' .. UI.markers_reason) or '',
                        UI.marker_reason and (' box=' .. UI.marker_reason) or '',
                        UI.error and (' error=' .. UI.error) or ''))
            end
        end
    end
end)()
local previous_update, previous_shutdown = update, shutdown
if type(previous_update) ~= 'function' then log('no global update - abort'); return end
local key_down = false
local started = false
local last_status = nil

local my_update = function(...)
    state.frame = state.frame + 1
    menu_step()
    -- The menu added or dropped a weapon: let every lease go this frame and take
    -- them again the next one.  Doing both in the same frame is exactly what
    -- crashed the live entity cycling in an earlier build.
    if state.menu_rearm == 1 then
        state.menu_rearm = 2
        if state.armed then
            state.armed = false
            pcall(sync_leases, false)
            pcall(damage, false)
            pcall(ballistics, false)
            pcall(seeker, false)
        end
    elseif state.menu_rearm == 2 then
        state.menu_rearm = 0
        if cfg.enable == 1 then state.armed = true end
    end
    if cfg.enable == 1 and cfg.autostart == 1 and not started then
        started = true
        state.armed = true
    end
    if KS and (state.frame % 10) == 0 then
        local d = KS(cfg.key) < 0
        if d and not key_down then
            key_down = true
            if cfg.enable == 1 then
                -- F7 RESTARTS. The addon occasionally ends up in a state where it
                -- stops locking, and releasing every lease and taking them again
                -- clears it - the same thing as switching it off and on in the
                -- MODS tab. state.menu_rearm is the addon's own two-frame
                -- release/re-take path (the weapon menu uses it when the list
                -- changes) and it is the one known not to crash the live entity
                -- cycling: doing both in the same frame is what crashed it.
                -- To switch the addon OFF, use the MODS tab or enable=0 in the cfg.
                state.menu_rearm = 1
                log('RESTART (F7) - every lease released this frame and taken '
                    .. 'again on the next one. This does NOT switch the addon off.')
            end
        end
        key_down = d
        if cfg.seek_cycle == 1 then
            local c = KS(cfg.seek_key or 121) < 0
            if c and not state.cycle_down then
                state.cycle_down = true
                set_seek(((state.seek_idx or 1) % #SEEK_LIST) + 1)
            end
            state.cycle_down = c
        end
    end
    if state.asset_watch and state.asset_watch.tick then
        local aw = state.asset_watch
        pcall(aw.tick, aw, 0.016)
        if aw.status == 'complete' then
            state.asset_watch = nil
            log('ASSET resident - the leased projectile has its material now')
        elseif aw.status == 'rejected' then
            state.asset_watch = nil
            log('ASSET rejected: ' .. tostring(aw.error))
        elseif aw.status == 'cancelled' then
            state.asset_watch = nil
        end
    end
    if cfg.enable == 1 and state.armed then
        local ok, err = pcall(step)
        if not ok then
            state.failures = state.failures + 1
            if state.failures < 5 then log('step error: ' .. tostring(err)) end
        end
    end
    -- P3: the lock reticle. Outside the guard above on purpose: it has to be able
    -- to clear itself while the weapon is holstered or the option is off.
    pcall(reticle_step)
    if (state.frame % 60) == 0 then
        local t = ctx.target
        local st = ('STATUS armed=%s leased=%s binds=%d enemies=%d target=%s '
            .. 'seek=%d writes=%d bombs=%d dmg=%s %s')
            :format(tostring(state.armed), tostring(state.leased), state.binds,
                #ctx.targets, t and (t.name .. '/' .. tostring(t.net) .. '/' ..
                    string.format('%.0fm', ctx.last_dist or -1)) or 'none',
                ctx.seek_active, state.writes, ctx.bomb_seen or 0,
                ctx.dl and ((dl_rows and #dl_rows > 0) and 'patched' or 'pending') or 'searching',
                ctx.mission and 'mission' or 'ship')
        if st ~= last_status then last_status = st; log(st) end
    end
    if (state.frame % 600) == 0 then
        log(('heartbeat f=%d armed=%s leased=%s binds=%d writes=%d failures=%d')
            :format(state.frame, tostring(state.armed), tostring(state.leased),
                state.binds, state.writes, state.failures))
    end
    return previous_update(...)
end
update = my_update

shutdown = function(...)
    pcall(reticle_step, true)
    pcall(sync_leases, false)
    pcall(damage, false)
    pcall(ballistics, false)
    pcall(cluster, false)
    pcall(launcher, false)
    pcall(PL.phase, false)
    pcall(seeker, false)
    if update == my_update then update = previous_update end
    if previous_shutdown then return previous_shutdown(...) end
end

log('================ ' .. REVISION .. ' ================')
log('Guided Rounds v1.8.5 by cancan2333 & SoS2430')
log('APW-1 guided rounds: warrant seeker + APW-1 damage.')
log('RL-77: the rocket that carries the burst is guided (cluster_guide='
    .. tostring(cfg.cluster_guide) .. '), and its airburst timer is extended so '
    .. 'the 25 bomblets land where it arrives. The bomblets themselves cannot '
    .. 'home - no projectile spawned by an explosion carries a seeker.')
do
    local _, sname, smode = cluster_seeker()
    log('bomblet seeker entity cluster_seeker='
        .. tostring(cfg.cluster_seeker) .. ' -> ' .. tostring(smode) .. ' '
        .. tostring(sname))
    local _, lname, lmode = launcher_seeker()
    log('rocket seeker entity launcher_seeker='
        .. tostring(cfg.launcher_seeker) .. ' -> ' .. tostring(lmode) .. ' '
        .. tostring(lname))
    if cfg.flak_only == 1 then
        log('cluster mode: FACTORY - the round keeps its own fuse, its own burst '
            .. 'and its own bomblets, and gets no seeker. Only the flak round '
            .. 'is guided (flak_only=1).')
    else
        log(('cluster mode: %s (fuse %s s, proximity %s m - the factory fuse is '
             .. 'a plain 0.25 s timer, which is why it always burst about 20 m '
             .. 'out)')
            :format(((tonumber(cfg.swarm_count) or 0) > 1)
                    and ('swarm of ' .. tostring(cfg.swarm_count)
                         .. ' guided darts')
                    or 'airburst',
                    tostring(cfg.rocket_life), tostring(cfg.rocket_prox)))
    end
end
log('cfg: ' .. tostring(CFG_PATH))
log('log: ' .. tostring(LOG_PATH))
if CFG_PATH then
    local chk = io.open(CFG_PATH, 'r')
    if chk then
        chk:close()
        log('folder and cfg ready: ' .. tostring(OUT_DIR))
    else
        log('WARNING: could not create the cfg at ' .. tostring(CFG_PATH))
    end
end
log('weapons in the list: ' .. table.concat(WEAPONS_TXT, ', '))
do
    local t = {}
    for i, e in ipairs(SEEK_LIST) do t[#t + 1] = string.format('#%d %s %s', i, e.h, e.note) end
    log('seek entities (cycle with key ' .. tostring(cfg.seek_key or 121) .. '):')
    for _, l in ipairs(t) do log('   ' .. l) end
    log('seek entity now: #' .. (state.seek_idx or 1) .. ' ' .. SEEK_LIST[state.seek_idx or 1].h)
end
log(('start-up: enable=%d autostart=%d -> arms itself; F7 releases every '
    .. 'lease and takes it again (it does NOT switch the addon off)')
    :format(cfg.enable, cfg.autostart))
asset_start()
return { revision = REVISION, state = state }
