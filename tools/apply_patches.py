"""Deterministic refactor of guided_rounds.lua v1.8.0 -> v1.8.2.

Every edit is an exact-match replacement that must hit the expected number of
times, so the script either applies the whole set or fails loudly without
writing anything.  Nothing here changes an engine offset, a magic value or an
order of operations; the changes are bug fixes, missing guards, named constants
and readability work (see OPTIMIZATION.md)."""
import pathlib
import re

ROOT = pathlib.Path(r'D:\HD2自瞄')
SRC = ROOT / 'Guided-Rounds-v1.8.0' / 'docs' / 'guided_rounds.lua'
DST = ROOT / 'Guided-Rounds-v1.8.5' / 'docs' / 'guided_rounds.lua'
VERSION = '1.8.5'

text = SRC.read_text(encoding='utf-8')
applied = []


def sub(name, old, new, count=1):
    global text
    got = text.count(old)
    if got != count:
        raise SystemExit(f'PATCH "{name}": expected {count} match(es), found {got}\n---\n{old[:400]}')
    text = text.replace(old, new)
    applied.append(name)


# --------------------------------------------------------------- hash notation
def hash8(hexstr):
    h = hexstr[2:].upper().rjust(16, '0')
    return bytes(int(h[i - 1:i + 1], 16) for i in range(15, 0, -2))


def to_hash(bs):
    return '0x' + ''.join('%02X' % b for b in reversed(bs))


def convert_hash_table(match):
    indent, arg, rest = match.group(1), match.group(2), match.group(3)
    bs = bytes(int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})', arg))
    if len(bs) != 8:
        raise SystemExit(f'hash entry is not 8 bytes: {arg}')
    hexs = to_hash(bs)
    if hash8(hexs) != bs:
        raise SystemExit(f'hash8 round-trip failed for {hexs}')
    return f"{indent}[hash8('{hexs}')] = {rest}"


def convert_indexed_hash(match):
    """[7] = string.char(0x.., ...)  ->  [7] = hash8('0x...')"""
    indent, index, arg, comma = match.group(1), match.group(2), match.group(3), match.group(4)
    bs = bytes(int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})', arg))
    if len(bs) != 8:
        raise SystemExit(f'indexed hash entry {index} is not 8 bytes: {arg}')
    hexs = to_hash(bs)
    if hash8(hexs) != bs:
        raise SystemExit(f'hash8 round-trip failed for {hexs}')
    return f"{indent}[{index}] = hash8('{hexs}'){comma}"


# =====================================================================  P1  map
sub('P1 module map + revision', """local KEY = 'Hd2ApwGuidance3'
local REVISION = 'guided-rounds-v1.8.0'""", """-- ===================================================================
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
local REVISION = 'guided-rounds-v{VERSION}'""".format(VERSION=VERSION))

sub('P1 version header', '-- Mod: Guided Rounds v1.8.0',
    '-- Mod: Guided Rounds v' + VERSION)

# ============================================================  P2  log + paths
sub('P2 log cap constant', """    local lines = 0
local log_dir_ok = nil""", """-- The log is opened, appended to and closed for every single line, so a
-- condition that fires every frame can grow it without bound.  The cap keeps
-- one bad mission from filling the disk; the counter counts lines offered.
local LOG_MAX_LINES = 20000
local lines = 0
local log_dir_ok = nil""")

sub('P2 log cap use', '    if lines > 20000 then return end',
    '    if lines > LOG_MAX_LINES then return end')

# ===============================================================  P3  helpers
sub('P3 u32 short-read guard', """local function u32(s, o)
    if type(s) ~= 'string' then return nil end
    local a, b, c, d = s:byte(o + 1, o + 4)
    if not a then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end""", """local function u32(s, o)
    if type(s) ~= 'string' then return nil end
    local a, b, c, d = s:byte(o + 1, o + 4)
    -- string.byte returns fewer values than asked for when the string ends
    -- early, so "a is there but d is not" is possible.  Every byte has to be
    -- present, or the missing one turns the arithmetic below into a Lua error.
    if not a or not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end""")

sub('P3 ptr_ok + num_or + rd', """local mbi = ffi.new('uint8_t[48]')

local function rd(a, n)
    if type(a) ~= 'number' or a < 65536 or a >= 0x800000000000 then return nil end""", """local mbi = ffi.new('uint8_t[48]')

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
    if not ptr_ok(a) then return nil end""")

sub('P3 ptr8 uses ptr_ok', """    local v = u64(s, 0)
    if not v or v < 65536 or v >= 0x800000000000 then return nil end""", """    local v = u64(s, 0)
    if not ptr_ok(v) then return nil end""")

sub('P3 write_bytes address guard', """local function write_bytes(a, bytes)
    if type(a) ~= 'number' or type(bytes) ~= 'string' or #bytes < 1 then return false end""", """local function write_bytes(a, bytes)
    -- a value that cannot be an address never reaches VirtualProtect: the call
    -- would only fail, and logging it would flood the file on a hot path
    if type(bytes) ~= 'string' or #bytes < 1 or not ptr_ok(a) then return false end""")

sub('P3 slot uses ptr_ok',
    "    if not b or b < 65536 or b >= 0x800000000000 then return nil, nil, nil, 'map_base' end",
    "    if not ptr_ok(b) then return nil, nil, nil, 'map_base' end")

text, n_range = re.subn(r"if (obj|ep) and \1 >= 65536 and \1 < 0x800000000000 then",
                        r"if ptr_ok(\1) then", text)
if n_range != 3:
    raise SystemExit(f'P3 pointer-range: expected 3, found {n_range}')
applied.append(f'P3 pointer-range -> ptr_ok ({n_range}x)')

sub('P3 dl_validate uses ptr_ok',
    '    if ptr < 65536 or ptr >= 0x800000000000 then return nil end',
    '    if not ptr_ok(ptr) then return nil end', count=2)

sub('P3 dl.cached uses ptr_ok',
    '    if p < 65536 or p >= 0x800000000000 then return end',
    '    if not ptr_ok(p) then return end')

sub('P3 seek_find uses ptr_ok',
    '                    if at >= 65536 and seek_header(at) then',
    '                    if ptr_ok(at) and seek_header(at) then')

sub('P3 seek_ptr uses ptr_ok', '    if p > 65536 then', '    if ptr_ok(p) then')

# =======================================================  P4  named constants
sub('P4 settings row cap', """local SET_ENTRIES = 542""", """local SET_ENTRIES = 542
-- Highest row index the settings table can hold.  The per-weapon override copy
-- lands in this range and the launcher sweep walks exactly these rows; 272 is
-- the row count, not the 616 byte stride above.
local SET_ROW_MAX = 272""")

sub('P4 override row bound', '                    if idx and idx < 272 then',
    '                    if idx and idx < SET_ROW_MAX then')

sub('P4 launcher row bound', """                    local row = idx and idx < 272
                                and rd(tb + SET_ROW_OFF + ROW_SIZE * idx, ROW_SIZE)""",
    """                    local row = idx and idx < SET_ROW_MAX
                                and rd(tb + SET_ROW_OFF + ROW_SIZE * idx, ROW_SIZE)""")

sub('P4 launcher sweep bound', '    for idx = 0, 271 do', '    for idx = 0, SET_ROW_MAX - 1 do')

sub('P4 publish cap', """local pub_buffers = {}
local function publish(net, field, value)
    if not PUBLISH_OK then return false end
    if type(net) ~= 'number' or net == UNBOUND then return false end
    if #pub_buffers >= 8192 then return false end""", """-- The engine is handed a pointer to the value, so every published buffer has
-- to stay alive for the rest of the session and none of them are ever freed.
-- That is why this is capped: past the cap the native notification is skipped,
-- while the binding itself (the write_bytes call below) keeps working.
local PUB_MAX = 8192
local pub_buffers = {}
local function publish(net, field, value)
    if not PUBLISH_OK then return false end
    if type(net) ~= 'number' or net == UNBOUND then return false end
    if #pub_buffers >= PUB_MAX then return false end""")

sub('P4 cluster max seeker index', """    row = nil,""", """    row = nil,
    max_unit = 9,          -- highest index in units[] / names[] below""")

sub('P4 cluster unit gate', """                for u = 0, 9 do
                    if cur == CLUSTER.units[u] then known = true break end
                end""", """                for u = 0, CLUSTER.max_unit do
                    if cur == CLUSTER.units[u] then known = true break end
                end""")

sub('P4 cluster restore gate', """        for u = 0, 9 do
            if cur == CLUSTER.units[u] then known = true break end
        end""", """        for u = 0, CLUSTER.max_unit do
            if cur == CLUSTER.units[u] then known = true break end
        end""")

sub('P4 launcher unit gate',
    '            for u = 0, 9 do if cur == CLUSTER.units[u] then known = true break end end',
    '            for u = 0, CLUSTER.max_unit do\n'
    '                if cur == CLUSTER.units[u] then known = true break end\n'
    '            end')

sub('P4 cfg version string', "        'cfgver=16',", "        ('cfgver=%d'):format(CFGVER),")

# ============================================================  P5  real bugs
# set_seek is declared before set_lease and sync_leases, so both of those reads
# resolved to globals and F10 (seek_cycle=1) raised "attempt to call a nil value".
sub('P5 set_lease before set_seek', """local function set_seek(i)
    local e = SEEK_LIST[i]
    if not e or not e.bytes then return end
    state.seek_idx = i
    set_lease(e.bytes)""", """-- forward: set_seek (the F10 seeker cycle) must be able to re-lease, and
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
    set_lease(e.bytes)""")

sub('P5 drop the old set_lease definition', """local function set_lease(h)
    if not h then return end
    local t = {}
    for i = #h, 1, -1 do t[#t + 1] = string.format('%02X', h:byte(i)) end
    LEASE.bytes, LEASE.txt = h, '0x' .. table.concat(t)
end

-- P17: one counter row per watched resource""", """-- P17: one counter row per watched resource""")

sub('P5 sync_leases is the forward local',
    'local function sync_leases(on)\n    ctx.wset = ctx.wset or {}',
    'sync_leases = function(on)\n    ctx.wset = ctx.wset or {}')

# refresh_targets indexed e.resource while entity() may well have returned nil,
# so debug=1 turned every unreadable entity into a Lua error.
sub('P5 debug watch nil entity',
    '            local w = cfg.debug == 1 and state.watch_open(e.resource) or nil',
    '            local w = (cfg.debug == 1 and e ~= nil) and state.watch_open(e.resource) or nil')

sub('P5 best_for cfg guards', """    local cos_limit = math.cos(math.rad(cfg.cone_deg))""", """    -- the cfg file is hand editable, so a nonsense value falls back to the
    -- shipped one instead of raising inside math.rad or comparing with nil
    local cone_deg = num_or(cfg.cone_deg, 12)
    local max_dist = num_or(cfg.max_dist, 250)
    local cos_limit = math.cos(math.rad(cone_deg))""")

sub('P5 best_for max_dist', '        if dist >= 0.01 and dist <= cfg.max_dist then',
    '        if dist >= 0.01 and dist <= max_dist then')

sub('P5 aim pose nil compare',
    '            and best_score <= (AIM.score or -2) + 0.08 then',
    '            and best_score and best_score <= (AIM.score or -2) + 0.08 then')

sub('P5 scan budget num_or', '        local ms = cfg.scan_ms or 4',
    '        local ms = num_or(cfg.scan_ms, 4)')

sub('P5 target interval num_or', '    local iv = cfg.target_interval or 20',
    '    local iv = num_or(cfg.target_interval, 20)')

sub('P5 bind delay num_or', '                    local aim, delay = ctx.target, cfg.bind_delay',
    '                    local aim, delay = ctx.target, num_or(cfg.bind_delay, 0.25)')

sub('P5 cluster delay num_or (bomb)',
    '                        aim, delay = bomb_aim(), cfg.cluster_delay',
    '                        aim, delay = bomb_aim(), num_or(cfg.cluster_delay, 0.05)')

sub('P5 cluster delay num_or (rocket)',
    '                        if rocket then delay = cfg.cluster_delay end',
    '                        if rocket then delay = num_or(cfg.cluster_delay, 0.05) end')

sub('P5 cluster life num_or', '        local want = cfg.cluster_life',
    '        local want = num_or(cfg.cluster_life, 0)')

sub('P5 seek speed num_or', '    local w = cfg.seek_speed or 0',
    '    local w = num_or(cfg.seek_speed, 0)')

sub('P5 seek accel num_or', '    if (cfg.seek_accel or 0) > 0 then',
    '    if num_or(cfg.seek_accel, 0) > 0 then')

# the saved-addon cfg key was reported as written even when the file could not
# be opened at all, so the log claimed a remembered address that was never saved
sub('P5 save_cfg_key reports the write', """    if not CFG_PATH then return false end
    local ok = pcall(function()
        local f = io.open(CFG_PATH, 'r')
        if not f then return end""", """    if not CFG_PATH then return false end
    local wrote = false
    local ok = pcall(function()
        local f = io.open(CFG_PATH, 'r')
        if not f then return end""")

sub('P5 save_cfg_key result', """        w:write(table.concat(lines, '\\n') .. '\\n')
        w:close()
    end)
    return ok
end""", """        w:write(table.concat(lines, '\\n') .. '\\n')
        w:close()
        wrote = true
    end)
    return ok and wrote
end""")

sub('P5 parse_weapons reports junk', """    if #list > 0 then WEAPONS, WEAPONS_TXT = list, txt end
end""", """    if #list > 0 then
        WEAPONS, WEAPONS_TXT = list, txt
    else
        -- the line was there but held nothing usable: saying so beats silently
        -- keeping the previous list while the user stares at the cfg
        log('WEAPONS the weapons= line held no usable hash - the previous list '
            .. 'is kept')
    end
end""")

# ==============================================  P6  reticle: no more shadowing
# R is the engine offset table at the top of the file; the reticle closure
# declared its own R for UI state, which makes both harder to follow.
start_anchor = 'local reticle_step = (function()\n'
end_anchor = 'end)()\nlocal previous_update, previous_shutdown = update, shutdown'
i0 = text.index(start_anchor)
i1 = text.index(end_anchor)
head = text[:i0] + start_anchor
body = text[i0 + len(start_anchor):i1]
tail = text[i1:]
if re.search(r'\bR\.(entity|weapon|attach|health|faction|player|pose|mission|seeking|publish)\b', body):
    raise SystemExit('P6: the reticle closure uses the engine offset table - do not rename R')
body, n_decl = re.subn(r'^    local R = \{', '    local UI = {', body, flags=re.M)
body, n_use = re.subn(r'\bR\.', 'UI.', body)
if n_decl != 1 or n_use < 80 or re.search(r'\bR\.', body):
    raise SystemExit(f'P6: unexpected rename counts decl={n_decl} use={n_use}')
applied.append(f'P6 reticle R -> UI ({n_use} uses)')
text = head + body + tail

# =================================================================  P7  polish
# quad()'s parameter named `state` shadowed the addon-wide state table
sub('P7 quad state parameter', """    local function quad(s, index, x, y, size, angle, alpha, state, tint)
        local old = UI.quads[index]
        if old and ((alpha == 0 and old.alpha == 0)
            or (old.x == x and old.y == y and old.size == size
                and old.angle == angle and old.alpha == alpha and old.state == state)) then""",
    """    local function quad(s, index, x, y, size, angle, alpha, lock_state, tint)
        local old = UI.quads[index]
        if old and ((alpha == 0 and old.alpha == 0)
            or (old.x == x and old.y == y and old.size == size
                and old.angle == angle and old.alpha == alpha
                and old.state == lock_state)) then""")

sub('P7 quad state parameter body',
    '        old.x, old.y, old.size, old.angle, old.alpha, old.state = x, y, size, angle, alpha, state',
    '        old.x, old.y, old.size, old.angle, old.alpha, old.state = x, y, size, angle, alpha,\n'
    '            lock_state')

# the LOS closure declared its own finite() with a different limit, hiding the
# file-wide one and reading as if they were the same rule
sub('P7 LOS finite rename', """    local LIMIT = 1e7
    local function finite(n)
        return type(n) == 'number' and n == n and n <= LIMIT and n >= -LIMIT
    end""", """    local LIMIT = 1e7
    -- deliberately not the file-wide finite(): this one is the world-space
    -- bound a physics query accepts, and it is named differently so the two
    -- rules cannot be confused at a call site
    local function in_bounds(n)
        return type(n) == 'number' and n == n and n <= LIMIT and n >= -LIMIT
    end""")

los_start = text.index('local LOS = (function()')
los_end = text.index('local function best_for(')
los = text[los_start:los_end]
los_new, n_los = re.subn(r'(?<![\w.])finite\(', 'in_bounds(', los)
if 'finite(' in los_new:
    raise SystemExit('P7: a finite() call survived the LOS rename')
text = text[:los_start] + los_new + text[los_end:]
applied.append(f'P7 LOS finite -> in_bounds ({n_los} calls)')

# seek_speeds(addr) shadowed the module-wide `base` (game.dll base address)
sub('P7 seek_speeds parameter', """local function seek_speeds(base)
    local b = rd(base, SEEK_REC)""", """local function seek_speeds(addr)
    local b = rd(addr, SEEK_REC)""")

sub('P7 seek_rows_at local base', """    local base = rows + math.floor((j - 1) / SEEK_REC) * SEEK_REC
    local off, val, orig = seek_speeds(base)
    if not off then
        log(('SEEKER row @%s found but the speed triple is not where it should be '
            .. '- no write'):format(hexa(base)))
        return nil
    end
    sk_rows = { addr = base, off = off, orig = orig, accel_off = off + 12 }
    log(('SEEKER P-92 Warrant component row @%s, speeds at +0x%X = %.1f m/s')
        :format(hexa(base), off, val))""", """    local row_base = rows + math.floor((j - 1) / SEEK_REC) * SEEK_REC
    local off, val, orig = seek_speeds(row_base)
    if not off then
        log(('SEEKER row @%s found but the speed triple is not where it should be '
            .. '- no write'):format(hexa(row_base)))
        return nil
    end
    sk_rows = { addr = row_base, off = off, orig = orig, accel_off = off + 12 }
    log(('SEEKER P-92 Warrant component row @%s, speeds at +0x%X = %.1f m/s')
        :format(hexa(row_base), off, val))""")

# render_camera called s.Unit.alive without checking the call exists; a missing
# call cleared the cached camera once a second and did it through an exception
sub('P7 render_camera alive guard', """        if CAM.unit then
            local ok, alive = pcall(s.Unit.alive, CAM.unit)
            if not ok or alive ~= true then CAM.camera, CAM.unit = nil, nil end
        end""", """        if CAM.unit then
            local ok, alive = false, nil
            if has(s.Unit, 'alive') then ok, alive = pcall(s.Unit.alive, CAM.unit) end
            if not ok or alive ~= true then CAM.camera, CAM.unit = nil, nil end
        end""")

# a 64 byte label budget cut with sub(1,63) can slice a UTF-8 character in half
sub('P7 UTF-8 safe label trim', """            local function row(id, spec)
                -- the megapack counts these limits in bytes; drop the
                -- description rather than lose the row
                if #spec.label > 64 then spec.label = spec.label:sub(1, 63) end""", """            -- Cut a byte budget without cutting a character in half: the pack
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
                -- the megapack counts these limits in bytes; drop the
                -- description rather than lose the row
                spec.label = fit(spec.label, 64)""")

sub('P7 start-up log text',
    "log(('start-up: enable=%d autostart=%d -> arms itself, F7 only switches it off')",
    "log(('start-up: enable=%d autostart=%d -> arms itself; F7 releases every '\n"
    "    .. 'lease and takes it again (it does NOT switch the addon off)')")

sub('P7 version banner', "log('Guided Rounds v1.8.0 by cancan2333 & SoS2430')",
    "log('Guided Rounds v{VERSION} by cancan2333 & SoS2430')".format(VERSION=VERSION))

# ---------------------------------------------------------------- indentation
# the cfg template mixed 4 and 8 space indentation inside one table
cfg_start = text.index("    w:write(table.concat({\n") + len("    w:write(table.concat({\n")
cfg_end = text.index("    }, '\\n') .. '\\n')", cfg_start)
block = text[cfg_start:cfg_end].split('\n')
fixed = []
for line in block:
    if re.match(r'^\s*\.\.\s', line):
        fixed.append(re.sub(r'^\s*', ' ' * 12, line))
    elif re.match(r"^\s*'", line):
        fixed.append(re.sub(r'^\s*', ' ' * 8, line))
    else:
        fixed.append(line)
text = text[:cfg_start] + '\n'.join(fixed) + text[cfg_end:]
applied.append('P8 cfg template indentation')

# the MENU_DROP guard body was not indented at all, hiding where it ends
lines = text.split('\n')
guard = '                if not MENU_DROP(w.en) then'
gi = lines.index(guard)
li = gi + 1
while lines[li] != '            end':
    li += 1
ci = li - 1
while lines[ci].strip() != 'end':
    ci -= 1
for k in range(gi + 1, ci + 1):
    if lines[k].strip():
        lines[k] = '    ' + lines[k]
text = '\n'.join(lines)
applied.append(f'P8 menu weapon loop indentation ({ci - gi} lines)')

# =======================================================  P9  hash literals
divmod_block = """-- decimal string -> divided by 256, exact (Lua numbers cap out at 2^53)
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

"""
hash_comment = "-- '0x89C5493E08CA4207' or '9927421484392399367' -> the 8 bytes the game stores\n"
hash_block = """local function hash8(tok)
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

"""
sub('P9 remove divmod256 from its old place', divmod_block, '')
sub('P9 remove the hash8 comment from its old place', hash_comment, '')
sub('P9 remove hash8 from its old place', hash_block, '')
sub('P9 insert both above the constants', """-- ---------------------------------------------------------------- constants""",
    """-- Every 8 byte resource hash in this file is written the way the cfg file and
-- the community hash tables write it, and turned into the bytes the game
-- actually stores by hash8():
--   hash8('0x89C5493E08CA4207') -> 07 42 CA 08 3E 49 C5 89
""" + divmod_block + hash_comment + hash_block + """
-- ---------------------------------------------------------------- constants""")

const_pairs = [
    ("""local APW_B = string.char(0x07, 0x42, 0xCA, 0x08, 0x3E, 0x49, 0xC5, 0x89)
local P92_ENTITY_B = string.char(0x92, 0x13, 0x97, 0x58, 0x43, 0xDA, 0x53, 0x80)""",
     """local APW_B = hash8('0x89C5493E08CA4207')          -- APW-1 Anti-Materiel Rifle
local P92_ENTITY_B = hash8('0x8053DA4358971392')    -- P-92 Warrant projectile"""),
    ("""    weapon = string.char(0x96, 0x52, 0x27, 0xEA, 0x37, 0x04, 0xE4, 0x26),""",
     """    weapon = hash8('0x26E40437EA275296'),   -- RL-77 Airburst Rocket Launcher"""),
]
for old, new in const_pairs:
    sub('P9 constant hash', old, new)

# CLUSTER.units
u_start = text.index('    units = {\n') + len('    units = {\n')
u_end = text.index('    },\n    names = {', u_start)
u_block, n_units = re.subn(
    r"^(\s*)\[(\d+)\] = string\.char\(((?:0x[0-9A-Fa-f]{2})(?:, 0x[0-9A-Fa-f]{2})*)\)(,?)\s*$",
    convert_indexed_hash, text[u_start:u_end], flags=re.M)
if n_units != 10:
    raise SystemExit(f'P9: expected 10 CLUSTER.units rows, converted {n_units}')
text = text[:u_start] + u_block + text[u_end:]
applied.append(f'P9 CLUSTER.units -> hash8 ({n_units}x)')

# TARGETS + WATCH
text, n_tab = re.subn(
    r"^(\s*)\[string\.char\(((?:0x[0-9A-Fa-f]{2})(?:, 0x[0-9A-Fa-f]{2})*)\)\] = (.*)$",
    convert_hash_table, text, flags=re.M)
if n_tab < 200:
    raise SystemExit(f'P9: only {n_tab} hash table rows converted, expected 200+')
applied.append(f'P9 TARGETS/WATCH -> hash8 ({n_tab}x)')

# ==================================================  P10  navigation comments
# bind_projectiles() and refresh_targets() are the two longest functions in the
# file; four signposts each make them skimmable without touching a line of logic.
sub('P10 bind walk banner', """    local bound, natively_bound, not_ready, too_young = 0, 0, 0, 0
    for i = 0, limit - 1 do""", """    local bound, natively_bound, not_ready, too_young = 0, 0, 0, 0
    -- ---- walk every live entry of the seeking manager ------------------
    for i = 0, limit - 1 do""")

sub('P10 bind census banner', """        if payload and payload ~= 0 then
            local seen = ctx.seen_payload""", """        -- ---- census: every distinct payload seen this session ----------
        if payload and payload ~= 0 then
            local seen = ctx.seen_payload""")

sub('P10 bind mine banner', """        local bomb = ctx.bomb_type ~= nil and ctx.rl77_id ~= nil""",
    """        -- ---- is this entry one of ours? ---------------------------------
        local bomb = ctx.bomb_type ~= nil and ctx.rl77_id ~= nil""")

sub('P10 bind arm banner', """            local nb = rd(net + 56 * i, 56)
            if nb then""", """            -- ---- arm and bind an entry that has no target yet ----------
            local nb = rd(net + 56 * i, 56)
            if nb then""")

sub('P10 bind diag banner', """    -- v4.5 diagnosis: is the bomblet even IN the seeking manager, and if it is,""",
    """    -- ---- diagnostics (debug=1 only) ---------------------------------
    -- v4.5 diagnosis: is the bomblet even IN the seeking manager, and if it is,""")

sub('P10 targets collect banner', """    local list = {}
    for n = 0, hcount - 1 do""", """    -- ---- collect the candidates -----------------------------------------
    local list = {}
    for n = 0, hcount - 1 do""")

sub('P10 targets diag banner', """    if cfg.lock_helldivers == 1 then
        -- one line per change of (avatar type, count), enough to tell "no teammate""",
    """    -- ---- diagnostics ----------------------------------------------------
    if cfg.lock_helldivers == 1 then
        -- one line per change of (avatar type, count), enough to tell "no teammate""")

sub('P10 targets publish banner', """    ctx.targets = list
    -- P10: the weapon in hand decides the order.""", """    -- ---- publish, and rebuild the per-weapon ordering sets --------------
    ctx.targets = list
    -- P10: the weapon in hand decides the order.""")

# ================================================  P11  the stuck world box
# The green target box is a world-space line object.  v1.8.0/v1.8.1 dropped it
# with World.destroy_line_object only, and forgot the handle unconditionally -
# so when that call did not actually take the object out of the frame (or when
# main_world() was nil at that moment) the box stayed on screen for the rest of
# the mission and nothing could reach it any more.  The clear path used when the
# TARGET is lost (reset + one transparent line + dispatch) always worked, so the
# drop now hides the box that way first and only releases the handle once the
# engine really took it - or once the box is provably invisible.
sub('P11 box staleness constant', """    local LOCK_SECONDS = 0.05
    local BOX_HALF = 0.7""", """    local LOCK_SECONDS = 0.05
    local BOX_HALF = 0.7
    -- The addon re-picks ctx.target EVERY frame while it is tracking something,
    -- so a target stamp older than this means it stopped: the box then has to go
    -- instead of hanging in the air at the last position anybody knew about.
    local BOX_STALE = 60                      -- frames, 1 s at 60 Hz""")

sub('P11 clear_line + drop_lines', """    local function drop_lines(s)
        if UI.line then
            local w = s.Application.main_world and s.Application.main_world() or nil
            if w and has(s.World, 'destroy_line_object') then
                pcall(s.World.destroy_line_object, w, UI.line)
            end
            UI.line, UI.line_dirty = nil, false
        end
    end""", """    -- Make the box invisible again.  This is the path that is KNOWN to work on
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
    end""")

sub('P11 marker uses clear_line + staleness', """        local t = ctx.target
        local p = t and t.position
        if type(p) ~= 'table' or type(p[1]) ~= 'number' then
            if UI.line and UI.line_dirty then
                s.LineObject.reset(UI.line)
                local z = s.Vector3(0, 0, 0)
                s.LineObject.add_line(UI.line, s.Color(0, 0, 0, 0), z, z)
                s.LineObject.dispatch(world, UI.line)
                UI.line_dirty = false
            end
            return
        end""", """        local t = ctx.target
        local p = t and t.position
        local fresh = (state.frame - (ctx.target_at or -1e9)) <= BOX_STALE
        if type(p) ~= 'table' or type(p[1]) ~= 'number' or not fresh then
            clear_line(s, world)
            return
        end""")

sub('P11 step stamps the target', """    refresh_poses()
    local t = pick_target()""", """    refresh_poses()
    local t = pick_target()
    -- P11: the reticle reads this stamp to tell "the addon is still tracking
    -- this target" from "this is the last position it ever saw"
    ctx.target_at = state.frame""")

# ===========================================  P12  the lock range and the scope
# The lock cone used to be a fixed WORLD angle, while the ring is the projection
# of that cone through the camera.  A ring drawn that way grows with the zoom:
# measured on the player's own session it was 264 px at a 60 degree FOV and
# 1816 px through an 8 degree scope (the screen is 2560x1440, so the ring left
# the screen entirely and everything visible could be locked).  Hipfire and
# scope therefore did NOT lock the same area on screen.
#
# Now the cone is compensated by the camera FOV, so the ring keeps the SAME
# pixel radius at every zoom and what can be locked on screen is the same when
# scoped as when hipfiring.  scope_fix=1 switches to the OTHER model while a
# scope is in use: the ring becomes the ORIGINAL (uncompensated) ring times the
# user's decimal scope_scale, so it follows the magnification - a 4x scope locks
# proportionally further than a 1x one - while the decimal keeps it from growing
# over the whole screen.  The effective tangent is published once per frame as
# ctx.cone_tan and used by BOTH best_for (what gets locked) and ring_radius (what
# is drawn), so the two can never disagree.
sub('P12 cfg keys', """local cfg = { enable = 1, autostart = 1, key = 118, cone_deg = 12, max_dist = 250,""",
    """local cfg = { enable = 1, autostart = 1, key = 118, cone_deg = 12, max_dist = 250,
              -- scope: the lock cone is FOV compensated so the ring keeps the
              -- same on-screen size at every zoom.  scope_fix=1 uses the other
              -- model while a scope is in use: ring = original ring x
              -- scope_scale, which follows the magnification.  See update_cone().
              scope_fix = 0, scope_scale = 0.3,""")

sub('P12 cfg template', """        'cone_deg=12',
        'max_dist=250',""", """        'cone_deg=12',
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
        'scope_scale=0.3',""")

sub('P12 ring uses the shared tangent', """    local function ring_radius(s, h, world, now)
        local fov = camera_fov(s, render_camera(s, world, now))
        local k = (h / 2) / math.tan((fov or FALLBACK_FOV) / 2)
        local cone = cfg.cone_deg or 12
        if type(cone) ~= 'number' or cone <= 0 then return nil end
        local r = math.tan(math.rad(cone)) * k""", """    local function ring_radius(s, h, world, now)
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
        local r = cone_tan * k""")

sub('P12 scope constants + update_cone', """    local function update_aim_pose(s, world)
        -- published first and unconditionally: the acquisition cone depends on it
        local cam_o, cam_f = camera_pose(s, world)
        ctx.cam_origin, ctx.cam_forward = cam_o, cam_f""", """    -- The LOCK ANGLE is calibrated against this vertical FOV, and the cone is
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
        update_cone(s, world)""")

sub('P12 best_for uses the shared tangent', """    -- the cfg file is hand editable, so a nonsense value falls back to the
    -- shipped one instead of raising inside math.rad or comparing with nil
    local cone_deg = num_or(cfg.cone_deg, 12)
    local max_dist = num_or(cfg.max_dist, 250)
    local cos_limit = math.cos(math.rad(cone_deg))""", """    local max_dist = num_or(cfg.max_dist, 250)
    -- ctx.cone_tan (published by the reticle's update_cone) is tan(effective
    -- half angle): already compensated for the camera FOV, and for the scope
    -- multiplier when that is switched on.  cos(atan(t)) = 1/sqrt(1+t^2), so
    -- the angle itself never has to be rebuilt here.  The ring uses the same
    -- number, which is what keeps "what is drawn" and "what is locked" equal.
    local cone_tan = tonumber(ctx.cone_tan)
    if not cone_tan or cone_tan ~= cone_tan or cone_tan < 0 then
        cone_tan = math.tan(math.rad(num_or(cfg.cone_deg, 12)))
    end
    local cos_limit = 1 / math.sqrt(1 + cone_tan * cone_tan)""")

# =================================================  P13  menu rows for the scope
# The MODS page holds exactly 32 rows per category and GUIDED ROUNDS is full, so
# the two scope rows take the place of two knobs that only matter in edge cases -
# SIGHT TEST PROFILE (raise it only if the sight test misses something) and SCAN
# BUDGET (a performance knob).  Both keep working from the cfg, exactly like
# ship_scan / debug / los_debug before them.
sub('P13 los_desc row -> scope multiplier', """        { k = 'los_desc', min = 0, max = 34, step = 1,
          en = 'SIGHT TEST PROFILE', zh = '视线检测配置',
          d_en = 'Which of the engine\\'s 35 collision profiles the sight '
              .. 'test uses. 0 already sees ground and solid cover; raise it '
              .. 'only if something is missed.',
          d_zh = '视线检测用引擎 35 个碰撞配置里的哪一个。0 已经能识别地面和实体掩体，'
              .. '只有漏判时才需要往上调。' },""", """        -- P13: SIGHT TEST PROFILE used to be a row here.  It is the kind of
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
""")

# P13: SCAN BUDGET was a row here too; it is a performance knob and stays in the
# cfg (scan_ms=4).  Removing it (and SIGHT TEST PROFILE) is what pays for the two
# scope rows, so GUIDED ROUNDS stays at exactly 32 rows.
sub('P13 scan_ms row -> scope switch', """        { k = 'scan_ms', min = 1, max = 16, step = 1,
          en = 'SCAN BUDGET (ms per frame)', zh = '扫描预算（每帧毫秒）',
          d_en = 'Milliseconds per frame spent looking for the data tables. 4 is '
              .. 'the shipped value. Raise it to find the tables sooner, lower it '
              .. 'if the first mission stutters.',
          d_zh = '每帧用来查找数据表的毫秒数。出厂值 4。调大能更快找到表，'
              .. '第一局卡顿时就调小。' },
""", "")

sub('P13 scope toggle', """        -- P12: ship_scan and debug were rows here. Both are developer
        -- switches that live in the cfg either way; they were dropped so that
        -- LOAD PROJECTILE MATERIALS keeps its row inside the 32 option cap.
    }""", """        { k = 'scope_fix', en = 'FOLLOW THE SCOPE ZOOM',
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
    }""")

# ==============================================  P14  the options follow the语言
# The MODS page shows Chinese to every client, because the language was a
# constant ('zh') in the source.  Mod Options Menu v1.1+ (api version 2) accepts
# label / description / choice as FUNCTIONS and calls them again every time the
# escape menu opens - right after it has read the game's Text Language into the
# shared Bingus Text registry (_G.BingusTranslations).  So the language is read
# from there, at the moment the menu asks for the text: Simplified and
# Traditional Chinese keep the Chinese texts, every other language gets English
# (which is also the pack's own fallback when the language cannot be read).
# Menu v1.0 takes strings only: there the choice is made once, at registration.
sub('P14 language detection', """    local LANG = 'zh'
    local ZH = LANG == 'zh'
    local function L(en, zh) return ZH and zh or en end""",
    """    -- The language the options are shown in.  Read when the menu asks for a
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
        if type(text) ~= 'string' or #text <= limit then return text end
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
    end""")

sub('P14 enable row text', """                label = L('ENABLE', '启用'),""",
    """                label = text('ENABLE', '启用', 64),""")

sub('P14 enable description', """                description = L('Turns the whole addon on and off. Off puts every '
                    .. 'value it wrote back the way the game shipped it. Same '
                    .. 'switch as the enable line in the cfg, and F7 in game.',
                    '整个 mod 的总开关。关闭会把所有改过的数值还原成出厂值。'
                    .. '与 cfg 里的 enable 是同一个开关，游戏里按 F7 也一样。'),""",
    """                description = text('Turns the whole addon on and off. Off puts every '
                    .. 'value it wrote back the way the game shipped it. Same '
                    .. 'switch as the enable line in the cfg, and F7 in game.',
                    '整个 mod 的总开关。关闭会把所有改过的数值还原成出厂值。'
                    .. '与 cfg 里的 enable 是同一个开关，游戏里按 F7 也一样。', 400),""")

sub('P14 slider texts', """                    type = 'slider', mod = MOD_CTRL, label = L(s.en, s.zh),""",
    """                    type = 'slider', mod = MOD_CTRL, label = text(s.en, s.zh, 64),""")

sub('P14 slider description', """                    description = L(s.d_en, s.d_zh),""",
    """                    description = text(s.d_en, s.d_zh, 400),""")

sub('P14 toggle texts', """                    type = 'toggle', mod = MOD_CTRL, label = L(t.en, t.zh),
                    default = val, description = L(t.d_en, t.d_zh),""",
    """                    type = 'toggle', mod = MOD_CTRL, label = text(t.en, t.zh, 64),
                    default = val, description = text(t.d_en, t.d_zh, 400),""")

sub('P14 weapon label', """                    local label = ZH and w.zh or w.en""",
    """                    local label = text(w.en, w.zh, 64)""")

sub('P14 weapon choices', """                        choices = { 'OFF', L('AIM FIRST', '准心优先'),
                                    L('BIG FIRST', '最大血量大优先'),
                                    L('SMALL FIRST', '最大血量小优先') },""",
    """                        choices = { 'OFF', text('AIM FIRST', '准心优先', 48),
                                    text('BIG FIRST', '最大血量大优先', 48),
                                    text('SMALL FIRST', '最大血量小优先', 48) },""")

sub('P14 weapon description', """                        description = L('OFF: plain rounds. AIM FIRST: guided, locks the '""",
    """                        description = text('OFF: plain rounds. AIM FIRST: guided, locks the '""")

# the two multi-line description calls need their limit on the CLOSING line
sub('P14 weapon description limit', """                            .. '同一档内仍由准心决定。'),
                    })""", """                            .. '同一档内仍由准心决定。', 400),
                    })""")

sub('P14 clip tolerates no limit', """    local function clip(text, limit)
        if type(text) ~= 'string' or #text <= limit then return text end""",
    """    local function clip(text, limit)
        if type(text) ~= 'string' then return text end
        if not limit or #text <= limit then return text end""")

sub('P14 row takes functions', """            local function row(id, spec)
                -- the megapack counts these limits in bytes; drop the
                -- description rather than lose the row
                spec.label = fit(spec.label, 64)
                if spec.description and #spec.description > 400 then
                    spec.description = nil
                end""", """            local function row(id, spec)
                -- text() already clipped function texts by CHARACTER, which is
                -- what v1.1+ counts.  Only a plain string needs the old byte
                -- limits - that path is a menu older than v1.1.
                if type(spec.label) == 'string' then spec.label = fit(spec.label, 64) end
                if type(spec.description) == 'string' and #spec.description > 400 then
                    spec.description = nil
                end""")

sub('P14 read the menu version', """        local MOM = rawget(_G, 'ModOptionsMenu')
        if type(MOM) ~= 'table' or type(MOM.register_option) ~= 'function' then return end
        done = true""", """        local MOM = rawget(_G, 'ModOptionsMenu')
        if type(MOM) ~= 'table' or type(MOM.register_option) ~= 'function' then return end
        done = true
        -- v1.1 and later resolve function texts again whenever the escape menu
        -- opens; v1.0 needs plain strings, so the language is fixed there
        menu_version = tonumber(MOM.version) or 1""")

sub('P14 menu log line', """            log(('options menu: %s + %s 1..%d on the MODS tab (%s) - %d weapons '
                .. 'offered, %d dropped from the menu as melee / throwable / '
                .. 'non-player (still usable through the cfg weapons= line)')
                :format(MOD_CTRL, MOD_WEAP,
                    math.ceil((state.menu_kept or #WEAPONS_MENU) / 32), LANG,
                    state.menu_kept or #WEAPONS_MENU,
                    #WEAPONS_MENU - (state.menu_kept or #WEAPONS_MENU)))""",
    """            log(('options menu: %s + %s 1..%d on the MODS tab - %d weapons '
                .. 'offered, %d dropped from the menu as melee / throwable / '
                .. 'non-player (still usable through the cfg weapons= line)')
                :format(MOD_CTRL, MOD_WEAP,
                    math.ceil((state.menu_kept or #WEAPONS_MENU) / 32),
                    state.menu_kept or #WEAPONS_MENU,
                    #WEAPONS_MENU - (state.menu_kept or #WEAPONS_MENU)))
            log(('options menu: texts in %s (client language %s)')
                :format(chinese() and 'Chinese' or 'English',
                    tostring(language_code() or 'unknown')))""")

# ---------------------------------------------------------------- write it out
# newline='\n' on purpose: the source that ships is LF, exactly like v1.8.0.
# Without it Python would translate to CRLF on Windows and the packaged resource
# would no longer be byte identical to docs/guided_rounds.lua.
DST.write_text(text, encoding='utf-8', newline='\n')
print('applied %d patches:' % len(applied))
for a in applied:
    print('  -', a)
print('wrote', DST)
