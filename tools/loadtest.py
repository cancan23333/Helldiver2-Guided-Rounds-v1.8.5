"""Load a built guided_rounds resource with the game's own LuaJIT.

This is the same compile+run path Bingus Shared Loader uses (luaL_loadbuffer +
lua_pcall against <game>/bin/lua51.dll), with the minimum game environment faked
so the chunk gets all the way to its own startup logging:

  * update / shutdown exist, so the addon installs its hook instead of aborting;
  * require('ffi') returns the real ffi with GetModuleHandleA patched, so
    'game.dll' resolves to a dummy base and the Win32 calls are real
    (ReadProcessMemory on that dummy base simply fails, as it must);
  * LOCALAPPDATA is redirected, so the cfg and the log are written to a scratch
    folder and the player's own files are never touched.

    python loadtest.py <lua-file> [--resource-archive <patch_0>]
"""
import argparse
import ctypes
import os
import pathlib
import struct
import sys

GAME = pathlib.Path(r'G:\SteamLibrary\steamapps\common\Helldivers 2')
DLL = GAME / 'bin' / 'lua51.dll'
WORKSPACE = pathlib.Path(r'D:\HD2自瞄')
SCRATCH = WORKSPACE / '.loadtest'
RESOURCE = 'mods/cancan2333/guided_rounds'
MIX = 0xC6A4A7935BD1E995
MASK = (1 << 64) - 1

PRELUDE = r'''
update = function(...) end
shutdown = function(...) end
local real = require('ffi')
real.cdef('void *GetModuleHandleA(const char *name); void *GetProcAddress(void *module, const char *name);')
local dummy = real.cast('void *', 0x140000000)
local kernel = real.C.GetModuleHandleA('kernel32')
local getproc = real.C.GetProcAddress
local C = setmetatable({}, { __index = function(_, key)
    if key == 'GetModuleHandleA' then
        return function(name)
            if name == nil or name == 'kernel32' or name == 'user32' then
                return real.C.GetModuleHandleA(name)
            end
            return dummy
        end
    end
    if key == 'GetProcAddress' then
        return function(_, name) return getproc(kernel, name) end
    end
    return real.C[key]
end })
local proxy = setmetatable({}, { __index = function(_, key)
    if key == 'C' then return C end
    return real[key]
end })
package.preload['ffi'] = function() return proxy end
'''

# A stand-in for CowboyBingus Mod Options Menu (api version 3 / v1.2), close
# enough to trust: label, description and each choice may be a FUNCTION that is
# resolved now and again on refresh - exactly what the pack does when the escape
# menu opens - and the limits count CHARACTERS, as v1.1 and later do.
MENU_STUB = r'''
local function mom_length(text)
    local n = 0
    for _ in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do n = n + 1 end
    return n
end
local mom_last_error
mom_first_error = mom_first_error
local function mom_resolve(value, limit)
    if type(value) == 'function' then
        local ok, result = pcall(value)
        if not ok then mom_last_error = tostring(result)
            if not mom_first_error then mom_first_error = tostring(result) end
            return nil end
        value = result
    end
    if type(value) ~= 'string' then mom_last_error = 'not a string: ' .. type(value); return nil end
    if mom_length(value) > limit then
        mom_last_error = 'over ' .. limit .. ' characters (' .. mom_length(value) .. ')'
        if not mom_first_error then mom_first_error = mom_last_error end
        return nil
    end
    return value
end
ModOptionsMenu = (function()
    local M = { version = 3, api = 1, options = {}, order = {}, sources = {},
                labels = {}, descriptions = {}, choices = {}, refused = {} }
    function M.register_option(id, spec)
        if type(id) ~= 'string' or id == '' then return false, 'bad id' end
        if type(spec) ~= 'table' then return false, 'bad spec' end
        if M.options[id] then return false, 'duplicate id' end
        local label = mom_resolve(spec.label, 64)
        if not label then return false, 'invalid label' end
        local description
        if spec.description ~= nil then
            description = mom_resolve(spec.description, 400)
            if not description then return false, 'invalid description' end
        end
        local choices
        if spec.type == 'choice' then
            choices = {}
            for i, choice in ipairs(spec.choices or {}) do
                local text = mom_resolve(choice, 48)
                if not text then return false, 'invalid choice name' end
                choices[i] = text
            end
            if #choices < 2 then return false, 'too few choices' end
        end
        M.sources[id] = spec
        M.labels[id], M.descriptions[id], M.choices[id] = label, description, choices
        M.options[id] = spec
        M.order[#M.order + 1] = id
        return true
    end
    -- what the pack does whenever the escape menu opens, right after it observed
    -- the game's Text Language
    function M.refresh()
        for id, spec in pairs(M.sources) do
            local label = mom_resolve(spec.label, 64)
            if label then M.labels[id] = label end
            if spec.description ~= nil then
                local description = mom_resolve(spec.description, 400)
                if description then M.descriptions[id] = description end
            end
            if spec.type == 'choice' then
                for i, choice in ipairs(spec.choices or {}) do
                    local text = mom_resolve(choice, 48)
                    if text then M.choices[id][i] = text end
                end
            end
        end
    end
    function M.set(id, value) M.options[id] = M.options[id] or {}; M.options[id].value = value end
    function M.get(id) return M.options[id] and M.options[id].value end
    function M.on_change(id, fn) M.changes = M.changes or {}; M.changes[id] = fn end
    return M
end)()
'''


# A stand-in for the engine's world-space line API plus the few stingray calls
# reticle_step touches, so the green target box can be driven and inspected
# without the game.  A line object counts as VISIBLE when its last dispatch
# carried at least one non-transparent line - which is what the player sees.
RENDER_STUB = r'''
__lines = {}
__destroy_works = false          -- flip to true to model an engine whose
                                 -- destroy_line_object really removes the object
__screen_w, __screen_h = 1920, 1080
__fov_rad = nil                  -- vertical FOV the mocked camera reports
__ring_max = 0                   -- farthest ring vertex drawn this frame
local MAIN, UIW = { name = 'mission' }, { name = 'ui' }
local CAM_UNIT, CAM_OBJ = { name = 'camera unit' }, { name = 'camera' }
World = {}
function World.create_line_object(w) local o = { lines = {}, visible = false }
    __lines[#__lines + 1] = o; return o end
function World.destroy_line_object(w, o)
    if __destroy_works then o.destroyed, o.visible = true, false end
end
function World.create_screen_gui(w) return { kind = 'gui' } end
function World.destroy_gui(w, g) end
function World.units(w) return { CAM_UNIT } end
function World.debug_camera_pose(w) return { pose = true } end
Unit = { alive = function() return true end,
         num_cameras = function(u) return 1 end,
         camera = function(u, i) return CAM_OBJ end }
Camera = { world_position = function(c) return { x = 0, y = 0, z = 0 } end,
           vertical_fov = function(c) return __fov_rad end }
Matrix4x4 = { translation = function(m) return { x = 0, y = 0, z = 0 } end }
LineObject = {}
function LineObject.reset(o) o.lines, o.visible = {}, false end
function LineObject.add_line(o, colour) o.lines[#o.lines + 1] = colour end
function LineObject.dispatch(w, o)
    o.visible = false
    for _, c in ipairs(o.lines) do
        if type(c) == 'table' and (c.a or 0) > 0 then o.visible = true end
    end
end
Application = { main_world = function() return MAIN end,
                worlds = function() return { MAIN, UIW } end }
Script = { temp_byte_count = function() return 1 end,
           set_temp_byte_count = function() end }
Gui = { resolution = function() return __screen_w, __screen_h end }
function Gui.triangle(gui, a, b, c)
    local function far(v)
        local dx, dy = v.x - __screen_w / 2, v.z - __screen_h / 2
        return math.sqrt(dx * dx + dy * dy)
    end
    local m = math.max(far(a), far(b), far(c))
    if m > __ring_max then __ring_max = m end
end
Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end
Vector2 = function(x, y) return { x = x, y = y } end
Vector3 = setmetatable({}, { __call = function(_, x, y, z) return { x = x, y = y, z = z } end })
Vector3.x = function(v) return v.x end
Vector3.y = function(v) return v.y end
Vector3.z = function(v) return v.z end
stingray = { Application = Application, World = World, LineObject = LineObject,
             Gui = Gui, Script = Script, Color = Color, Vector2 = Vector2,
             Vector3 = Vector3, Unit = Unit, Camera = Camera, Matrix4x4 = Matrix4x4 }
'''

# The lock cone is FOV compensated, so the ring must keep the same pixel radius
# at every zoom (scope_fix off) and be multiplied by scope_mult while a scope is
# in use (scope_fix on).  The screen width is nudged per phase ONLY to force the
# reticle to rebuild the ring, which it otherwise does only when its key changes.
SCOPE_PROBE = r'''
local P = __probe
P.cfg.enable, P.cfg.target_box, P.cfg.lock_reticle = 1, 0, 0
P.cfg.range_ring = 1
P.cfg.cone_deg, P.cfg.scope_fix, P.cfg.scope_scale = 12, 0, 0.3
P.state.armed = true
P.ctx.target = { position = { 10, 20, 30 }, net = 7, name = 'probe target' }
P.ctx.target_at = P.state.frame
P.ctx.weapon_at = P.state.frame
local width = 1920
local function phase(fov_deg)
    width = width + 2
    __screen_w, __fov_rad = width, math.rad(fov_deg)
    P.state.frame = P.state.frame + 1
    P.ctx.target_at, P.ctx.weapon_at = P.state.frame, P.state.frame
    __ring_max = 0
    P.reticle()
    return math.floor(__ring_max + 0.5), P.ctx.cone_tan
end
local out = {}
local function note(tag, fov)
    local r, t = phase(fov)
    out[#out + 1] = tag .. ' ring=' .. r .. ' tan=' .. string.format('%.4f', t or -1)
end
note('hipfire60', 60)
note('scope8_off', 8)
P.cfg.scope_fix = 1
note('scope1x_45_on0.3', 45)
note('scope8x_on0.3', 8)
P.cfg.scope_scale = 0.1
note('scope8x_on0.1', 8)
P.cfg.scope_fix, P.cfg.scope_scale = 0, 0.3
note('wide75', 75.6)
__probe_scope = table.concat(out, ' | ')
'''

# Scenario: the box is drawn while locked, the reticle is then told to stop
# drawing (which is what a weapon switch does), and finally the addon stops
# refreshing the target while the reticle is still running.
RENDER_PROBE = r'''
local P = __probe
P.cfg.enable, P.cfg.target_box = 1, 1
P.cfg.range_ring, P.cfg.lock_reticle = 0, 0
P.state.armed = true
local function visible()
    local n = 0
    for _, o in ipairs(__lines) do if o.visible then n = n + 1 end end
    return n
end
local function frames(n)
    for _ = 1, n do
        P.state.frame = P.state.frame + 1
        P.reticle()
    end
end
P.ctx.target = { position = { 10, 20, 30 }, net = 7, name = 'probe target' }
P.ctx.target_at = P.state.frame
P.ctx.weapon_at = P.state.frame
frames(1)
local drawn = visible()
P.ctx.weapon_at = P.state.frame - 10          -- the mod stops driving the reticle
frames(3)
local after_drop = visible()
P.ctx.weapon_at = P.state.frame               -- running again ...
P.ctx.target_at = P.state.frame - 1000        -- ... but the target is never refreshed
frames(2)
local after_stale = visible()
P.ctx.target_at = P.state.frame               -- a fresh target must draw again
P.ctx.weapon_at = P.state.frame
frames(1)
local redrawn = visible()
__probe_render = 'box drawn=' .. drawn .. ' afterDrop=' .. after_drop ..
    ' afterStaleTarget=' .. after_stale .. ' redrawn=' .. redrawn
'''



# The client language comes from the shared Bingus Text registry, which the pack
# fills right before it refreshes these texts.  This walks the same sequence for
# several languages and reports what the menu would show.
LANGUAGE_PROBE = r'''
local P = __probe
P.cfg.enable = 1
P.state.armed = true
update()
update()
local M = ModOptionsMenu
local function ascii(text)
    for i = 1, #(text or '') do if text:byte(i) > 127 then return false end end
    return true
end
local out = {}
for _, tag in ipairs({ 'zh-Hans', 'zh-Hant', 'en', 'de', 'us', 'cn', 'tw' }) do
    BingusTranslations = { game_language = tag, game_code = tag }
    M.refresh()                      -- what the pack does when the menu opens
    local enable = M.labels['apw_guided_enable']
    local cone = M.labels['apw_cone_deg']
    local weapon = M.labels['apw_w_ar23']
    local choice = M.choices['apw_w_ar23'] and M.choices['apw_w_ar23'][3] or '-'
    out[#out + 1] = tag .. ': enable=' .. tostring(enable) ..
        ' (ascii=' .. tostring(ascii(enable)) .. ') cone=' .. tostring(cone) ..
        ' weapon=' .. tostring(weapon) .. ' (ascii=' .. tostring(ascii(weapon)) .. ')' ..
        ' choice3=' .. choice .. ' (ascii=' .. tostring(ascii(choice)) .. ')'
end
BingusTranslations = nil              -- no registry and no runtime installed
M.refresh()
out[#out + 1] = 'unknown: enable=' .. tostring(M.labels['apw_guided_enable'])
__probe_language = table.concat(out, '  ||  ') .. '  || firstError=' .. tostring(mom_first_error)
'''


def resource_hash(name):
    data = name.encode('utf-8')
    value = len(data) * MIX & MASK
    end = len(data) // 8 * 8
    for (word,) in struct.iter_unpack('<Q', data[:end]):
        word = word * MIX & MASK
        word ^= word >> 47
        value = (value ^ (word * MIX & MASK)) * MIX & MASK
    if data[end:]:
        value = (value ^ int.from_bytes(data[end:], 'little')) * MIX & MASK
    value ^= value >> 47
    value = value * MIX & MASK
    return value ^ (value >> 47)


def from_archive(path):
    blob = pathlib.Path(path).read_bytes()
    magic, types, files = struct.unpack_from('<III', blob, 0)
    if magic != 0xF0000011:
        raise SystemExit('not a patch archive: ' + str(path))
    want = resource_hash(RESOURCE)
    for i in range(files):
        row = struct.unpack_from('<7Q6I', blob, 72 + 32 * types + 80 * i)
        if row[0] == want:
            payload = blob[row[2]:row[2] + row[7]]
            return payload[8:]                     # strip the length+version head
    raise SystemExit('resource %s not found in %s' % (RESOURCE, path))


def run(script, probe=None):
    library = ctypes.CDLL(str(DLL))
    library.luaL_newstate.restype = ctypes.c_void_p
    library.luaL_openlibs.argtypes = [ctypes.c_void_p]
    library.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p,
                                        ctypes.c_size_t, ctypes.c_char_p]
    library.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    library.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int,
                                      ctypes.POINTER(ctypes.c_size_t)]
    library.lua_tolstring.restype = ctypes.c_void_p
    library.lua_close.argtypes = [ctypes.c_void_p]
    state = library.luaL_newstate()
    if not state:
        raise SystemExit('luaL_newstate failed')
    try:
        library.luaL_openlibs(state)
        status = library.luaL_loadbuffer(state, script, len(script), b'@guided_rounds')
        if status == 0:
            status = library.lua_pcall(state, 0, 1, 0)
        message = ''
        if status == 0 and probe:
            # a second chunk in the same state: it can reach the addon's own
            # upvalues only through the probe the source was patched to publish
            code = probe.encode('utf-8')
            status = library.luaL_loadbuffer(state, code, len(code), b'@probe')
            if status == 0:
                status = library.lua_pcall(state, 0, 1, 0)
        length = ctypes.c_size_t()
        pointer = library.lua_tolstring(state, -1, ctypes.byref(length))
        message = ctypes.string_at(pointer, length.value).decode('utf-8', 'replace') if pointer else ''
        return status, message
    finally:
        library.lua_close(state)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('lua', nargs='?', help='a Lua file to run')
    parser.add_argument('--resource-archive', help='a patch_0 to pull the resource out of')
    parser.add_argument('--keep-scratch', action='store_true')
    parser.add_argument('--probe-seek', action='store_true',
                        help='also call the addon\'s own set_seek(2) (the F10 path)')
    parser.add_argument('--probe-menu', action='store_true',
                        help='call update() with a Mod Options Menu stub and count the rows')
    parser.add_argument('--probe-shutdown', action='store_true',
                        help='also call shutdown() (the teardown path F7 and exit use)')
    parser.add_argument('--probe-render', action='store_true',
                        help='drive the world-space target box through a stingray mock')
    parser.add_argument('--probe-language', action='store_true',
                        help='re-resolve the option texts for several client languages')
    parser.add_argument('--probe-scope', action='store_true',
                        help='measure the range ring at several FOVs (scope compensation)')
    parser.add_argument('--destroy-works', action='store_true',
                        help='model an engine whose destroy_line_object really works')
    args = parser.parse_args()

    if args.resource_archive:
        source = from_archive(args.resource_archive)
        label = args.resource_archive
    elif args.lua:
        source = pathlib.Path(args.lua).read_bytes()
        label = args.lua
    else:
        parser.error('give a lua file or --resource-archive')

    prelude = PRELUDE
    probes = []
    summary = []
    if args.probe_menu:
        prelude += MENU_STUB
        probes.append('''for i = 1, 3 do update() end
local n = 0
for id in pairs(ModOptionsMenu.options) do n = n + 1 end
local categories = {}
for _, id in ipairs(ModOptionsMenu.order) do
    local m = ModOptionsMenu.options[id].mod
    categories[m] = (categories[m] or 0) + 1
end
local names = {}
for m, c in pairs(categories) do names[#names + 1] = m .. '=' .. c end
table.sort(names)
__probe_menu = 'menu rows=' .. n .. ' categories: ' .. table.concat(names, ' ') ..
    ' | rows: scope_fix=' .. tostring(ModOptionsMenu.options['apw_scope_fix'] ~= nil) ..
    ' scope_scale=' .. tostring(ModOptionsMenu.options['apw_scope_scale'] ~= nil) ..
    ' los_desc_removed=' .. tostring(ModOptionsMenu.options['apw_los_desc'] == nil) ..
    ' scan_ms_removed=' .. tostring(ModOptionsMenu.options['apw_scan_ms'] == nil) ..
    ' lock_shuttle=' .. tostring(ModOptionsMenu.options['apw_lock_shuttle'] ~= nil) ..
    ' lock_dropship=' .. tostring(ModOptionsMenu.options['apw_lock_dropship'] ~= nil) ..
    ' swarm_split_removed=' .. tostring(ModOptionsMenu.options['apw_swarm_split'] == nil) ..
    ' cluster_autofix_removed=' .. tostring(ModOptionsMenu.options['apw_cluster_autofix'] == nil)''')
        summary.append('__probe_menu')

    # anything that needs to reach the addon's private state gets a probe table
    # injected just before its final return
    if args.probe_language:
        prelude += MENU_STUB
    if args.probe_seek or args.probe_render or args.probe_scope or args.probe_language:
        tail = b'return { revision = REVISION, state = state }'
        if tail not in source:
            raise SystemExit('cannot find the final return to patch for the probe')
        source = source.replace(
            tail,
            b'__probe = { ctx = ctx, state = state, cfg = cfg, reticle = reticle_step,'
            b' set_seek = set_seek }\n' + tail)

    if args.probe_seek:
        probes.append('__probe_seek_result = (function() __probe.set_seek(2) '
                      'return "seek ok" end)()')
        summary.append('__probe_seek_result')
    if args.probe_render or args.probe_scope:
        prelude += RENDER_STUB
        if args.destroy_works:
            prelude = prelude.replace('__destroy_works = false', '__destroy_works = true')
    if args.probe_render:
        probes.append(RENDER_PROBE)
        summary.append('__probe_render')
    if args.probe_scope:
        probes.append(SCOPE_PROBE)
        summary.append('__probe_scope')
    if args.probe_language:
        probes.append(LANGUAGE_PROBE)
        summary.append('__probe_language')
    if args.probe_shutdown:
        probes.append('''shutdown()
__probe_shutdown = 'shutdown ok' ''')
        summary.append('__probe_shutdown')

    probe = None
    if probes:
        probe = '\n'.join(probes) + '\nreturn ' + (
            ' .. " | " .. '.join(summary) if len(summary) > 1 else summary[0])

    SCRATCH.mkdir(parents=True, exist_ok=True)
    log_dir = SCRATCH / 'Hd2ApwGuidance'
    if log_dir.is_dir():
        for stale in log_dir.iterdir():
            stale.unlink()                          # keep each run's log its own
    os.environ['LOCALAPPDATA'] = str(SCRATCH)
    print(f'resource: {label}  ({len(source)} bytes)')
    print(f'DLL:      {DLL}')
    print(f'LOCALAPPDATA -> {SCRATCH}')
    if args.probe_menu:
        print('probe:    update() x3 with a Mod Options Menu stub, then count rows')
    if args.probe_seek:
        print('probe:    set_seek(2) called (the F10 seeker cycle)')
    if args.probe_render:
        print('probe:    world box through a stingray mock '
              f'(destroy_line_object actually works: {args.destroy_works})')
    if args.probe_scope:
        print('probe:    range ring at 60 / 8 / 1x+scale / 8x+scale / 8x+scale0.1 / 75.6')
    if args.probe_language:
        print('probe:    option texts re-resolved for zh-Hans/zh-Hant/en/de/us/cn/tw/unknown')
    if args.probe_shutdown:
        print('probe:    shutdown() called')
    status, message = run(prelude.encode('utf-8') + b'\n' + source, probe)
    print('status:', 'OK' if status == 0 else f'ERROR ({status})')
    print('result:', message.strip()[:2000])
    log = SCRATCH / 'Hd2ApwGuidance' / 'ApwGuidance.log'
    if log.is_file():
        lines = log.read_text(encoding='utf-8', errors='replace').splitlines()
        print(f'addon log: {log}  ({len(lines)} lines)')
        for line in lines[:6] + (['   ...'] if len(lines) > 12 else []) + lines[-6:]:
            print('   ', line)
    else:
        print('addon log: (none written)')
    return 1 if status else 0


if __name__ == '__main__':
    sys.exit(main())
