# Guided Rounds v1.8.5 —— 优化说明 / Optimization notes

本版**只做代码质量优化**：内存偏移、数值常量、相位顺序、cfg 键名、菜单文案与全部游戏行为
与 v1.8.0 完全一致。唯一的例外是下面第 1 节：三处原本会**抛错**（进而在游戏里表现为
"这一步卡住/日志里刷 error"）的隐患被修好了。

验证方式见第 4 节：新旧两份源码做了**逐 token 对比**，每一个语义改动都能在报告里对上号；
另外还用**游戏自带的 LuaJIT 真正加载并跑了一遍**（菜单行数、F10 换弹、shutdown 三条路径）。

> **版本关系**：v1.8.5 = v1.8.4 + 选项文字跟随游戏语言（第 1.7 节）。v1.8.3 = v1.8.2 + 开镜/腰射锁定范围一致；v1.8.4 把「开镜跟随倍镜」这一档
> 从固定倍率改成「原版范围 × 用户系数」（第 1.6 节）。
> v1.8.1 是健壮性/可读性优化（含 4 处会报错的隐患修复，其中 `ptr_ok` 的
> 声明顺序问题曾导致第一版加载失败，见 4.2 节）；**v1.8.2 = v1.8.1 + 锁定目标方框残留的修复**
> （见第 1.5 节）。若你装的是 v1.8.1，请用本包覆盖后 purge & redeploy。

---

## 1. 修复的真实隐患（3 处）

| # | 位置 | 问题 | 后果 | 修法 |
| --- | --- | --- | --- | --- |
| 1 | `set_seek()`（F10 换追踪弹） | 它调用 `set_lease()` 和 `sync_leases()`，但这两个 `local` 都声明在它**后面**。Lua 的 local 只从声明那一行起可见，所以这两处读到的是**全局变量 = nil** | `seek_cycle=1` 时按 F10 → `attempt to call a nil value ('set_lease')`；该调用点**没有 pcall**，异常会直接打断这一帧的 `update` | 把 `set_lease` 移到 `set_seek` 之前，并给 `sync_leases` 加前置声明（`local sync_leases` + 后面改成赋值） |
| 2 | `refresh_targets()` | `cfg.debug == 1 and state.watch_open(e.resource)`：`entity()` 可能返回 nil，而 `and` 只短路了左半边 | `debug=1` 时只要有一个实体读不出来，这一帧的索敌就整个报错（被 `step` 的 pcall 兜住，但本帧不再刷新目标） | 改成 `(cfg.debug == 1 and e ~= nil) and …` |
| 3 | `update_aim_pose()`（准心轴选择） | 条件里 `best_score <= …`，而 `best_score` 在"这一帧一个姿态都没找到"时是 nil | 一旦走到就是 `attempt to compare nil with number` | 加上 `best_score and …` |

另外两处"不会崩但会说谎"的问题也一并修了：

- `state.save_cfg_key()` 以前**文件打不开也返回 true**，于是 `DLIB remembered the projectile table address…` 会在没写成功时照样打出来。现在返回真实的写入结果。
- `parse_weapons()` 以前遇到"`weapons=` 行里没有一个能用的哈希"会**默默保留旧列表**。现在会写一行日志说明。

## 1.5 v1.8.2：锁定目标方框（绿色世界方框）残留

**现象**（用户报告）：目标在锁定范围内时切换武器，绿色方框**一直留在屏幕上**；
而如果目标自己走出锁定范围，方框会正常消失。

**原因**：方框是一个 world-space line object（`World.create_line_object`），有两条移除路径：

| 路径 | 触发条件 | 做法 | 是否有效 |
| --- | --- | --- | --- |
| A「清空」 | 目标丢失（`ctx.target` 为 nil） | `LineObject.reset` + 加一条**全透明**的退化线 + `dispatch` | **有效**（所以目标走出范围时方框正常消失） |
| B「丢弃」 | 收不到绘制条件时（切武器、停用、mod 不再驱动 UI） | `World.destroy_line_object`，然后**无条件**把 `UI.line` 置空 | **不可靠**：这个调用不一定真的把对象从画面里拿掉；而且那一刻 `main_world()` 可能是 nil（连调用都跳过）——**句柄却被丢掉了**，于是方框留在屏幕上，此后**任何代码都无法再碰到它**，只能等下一次切场景 |

也就是说：报告里"目标出圈正常消失、锁着切武器就一直显示"的差异，正是这两条路径的差异。

**修法**（三处，都在 `reticle_step` 与 `step` 里）：

1. 新增 `clear_line()`，把路径 A 抽出来；**丢弃方框时先调用它**——不管引擎那边成不成功，
   方框先变成不可见。
2. `drop_lines()` 只在**真的交还成功**时才放掉句柄；失败就保留句柄、下一帧再试
   （对象还在世界里的情况下，句柄是唯一能再清掉它的东西）。只有当方框已经确认不可见、
   且连续 120 帧都交还失败时，才彻底放手——这样既不会残留可见方框，也不会永远重试一个坏调用。
3. 新增 `ctx.target_at` 帧戳（`step()` 里每帧 `pick_target()` 之后刷新）。方框只在帧戳
   **不超过 60 帧**时才绘制，于是"addon 已不再跟踪、方框却钉在最后位置"不会再发生。

**验证**（`tools/loadtest.py --probe-render`，用游戏自带 LuaJIT + 一个 stingray 桩：
线对象只有在最后一次 `dispatch` 含有非透明线时才算"可见"）：

| 场景 | v1.8.0 / v1.8.1（修前） | v1.8.2（修后） |
| --- | --- | --- |
| 目标被锁定 | `drawn=1` | `drawn=1` |
| reticle 停止绘制（≈切武器）后 | **`afterDrop=1`（残留）** | **`afterDrop=0`** |
| mod 在跑但已不再刷新目标 | **`afterStaleTarget=2`（还多出一个）** | **`afterStaleTarget=0`** |
| 重新有目标 | `redrawn=2`（旧的还在） | `redrawn=1` |

两种引擎模型都测了：`destroy_line_object` **真的生效**、以及**静默不生效**（复现报告的那种引擎），
修后结果都是上面右列。

## 1.6 v1.8.3：开镜与腰射的锁定范围不一致

**现象**（用户报告）：用放大瞄准镜和腰射时，锁定范围不一样。

**原因**：锁定锥是**世界角度固定**的（`cfg.cone_deg`），而范围圆环是这个锥经**当前相机**
投影到屏幕上的圆：`r = tan(锥半角) × (h/2) / tan(fov/2)`。所以倍率越高、`fov` 越小、环越大。
用户自己的日志（2560×1440）实测：

| 相机垂直 FOV | 圆环半径 |
| --- | --- |
| 60°（腰射） | 264 px |
| 8°（高倍镜） | **1816 px**（屏幕半高只有 720 px —— 整圈跑出屏幕，屏幕上几乎什么都能锁） |

于是"屏幕上能锁的范围"在腰射和开镜之间差了 7 倍。

**修法**：把锁定锥按**当前相机 FOV 补偿**，使圆环在任意倍率下保持同样的像素半径：

```
tan(有效半角) = tan(cone_deg) × tan(fov/2) / tan(60°/2)        （基准 60°）
```

- 补偿后的正切值每帧发布一次为 **`ctx.cone_tan`**，`best_for()`（决定锁谁）与
  `ring_radius()`（决定画多大）**共用同一个值**，所以"环"和"实际锁定范围"不可能不一致。
- 关闭时（默认）：开镜与腰射锁定的屏幕范围完全相同。
- `scope_fix=1`（**菜单里「开镜锁定范围跟随倍镜」**）：在使用瞄准镜时（FOV 窄于基准的
  90%，即 < 54°）改为**原版（未补偿）圆环 × `scope_scale`**，`scope_scale` 是 MODS 页里
  配置的小数（0.05–1，默认 0.3）。原版圆环本身 ∝ 1/tan(FOV/2)，所以这一档**自动跟随倍镜
  放大系数**：一倍镜与高倍镜不再得到同样的缩放。填 1.0 = 完全原版行为（高倍镜下环会跑出
  屏幕）；填小则任何倍率下环都小。腰射状态不受影响。
  > v1.8.3 这一档用的是"固定倍率"（不管倍镜多少倍都乘同一个数），所以 1 倍镜和 8 倍镜的
  > 缩放完全一样——v1.8.4 按用户要求改成上面的乘法系数模型。
- 没有相机 / 读不到 FOV 时退回未补偿的 `cone_deg`（与旧行为一致）。

**验证**（`tools/loadtest.py --probe-scope`，相机桩给出指定 FOV，量取圆环三角形离屏幕
中心的最远距离；1920×1080，cone=12°）：

| 场景 | 圆环半径 | `ctx.cone_tan` |
| --- | --- | --- |
| 腰射 60° | 200 px | 0.2126 |
| 高倍镜 8°（开关关） | **200 px（与腰射一致）** | 0.0257 |
| 约 1 倍镜 45°（开关开，系数 0.3） | **84 px**（原版 277 px × 0.3） | 0.0638 |
| 高倍镜 8°（开关开，系数 0.3） | **492 px**（原版 1641 px × 0.3） | 0.0638 |
| 高倍镜 8°（开关开，系数 0.1） | **164 px** | 0.0213 |
| 广角 75.6° | **200 px（与腰射一致）** | 0.2856 |

注意后两行同系数时 `ctx.cone_tan` 相同（世界角度一致），但**屏幕半径差了近 6 倍**——
这正是"跟随倍镜放大系数"：同一系数下，8 倍镜锁的范围约是一倍镜的 6 倍。

**菜单**：GUIDED ROUNDS 页仍是**正好 32 行**（126 行武器页不变），新增两行，为此把
`los_desc`（视线检测配置）与 `scan_ms`（扫描预算）改为 cfg-only —— 两者都是"只有出问题时
才调"的旋钮，和 `ship_scan` / `debug` / `los_debug` 同类，功能一字未减。
`--probe-menu` 复核：`rows=136`、`scope_fix=true scope_mult=true los_desc_removed=true scan_ms_removed=true`。

## 1.7 v1.8.5：菜单选项跟随游戏语言

**需求**：客户端语言不是简体/繁体中文时显示英文，是中文时保持原样。

**做法**（用 Mod Options Menu 自己的机制，不猜、不额外读内存）：

- v1.1+（API 2）允许 `label` / `description` / 每个 `choice` 是**函数**；菜单在**每次打开
  逃生菜单**时重新调用它们（`translation.refresh`）。
- 而菜单在同一时刻（`mod_options_menu.lua` 里 `translation.observe()` → `translation.refresh()`）
  刚把游戏 Text Language 写进共享注册表 `_G.BingusTranslations`（`game_language` 标签 /
  `game_code` 代码），所以我们的文字函数**读那里**即可，且天然跟随语言变化。
- 读取顺序：`BingusTranslations.override` → `.game_language` → `.game_code`；
  没有注册表时退一步问 HD2Runtime（`hd2.text.language()` 0.31.2+ / `hd2.ui.language()` 0.31.1+），
  都没有就按英文（与菜单自身"读不到就用英文"的兜底一致）。
- 判定：`cn` / `tw` / `chs` / `cht` / 任何 `zh*` → 中文；其余（含读不到）→ 英文。
- 菜单是 v1.0（只接受字符串）时，`menu_version < 2`，语言在注册那一刻定一次，行为与旧版一致。
- 文字长度：v1.1+ 的 64 / 400 / 48 上限按**字符**计（不是字节），所以新的 `clip()` 按 UTF-8
  字符边界裁剪，避免半个汉字导致整行被拒。

**验证**（`tools/loadtest.py --probe-language`，用一个会像真菜单那样**重新解析函数文字**的桩，
并把 `BingusTranslations` 换成不同语言）：

| 客户端语言 | 结果 |
| --- | --- |
| `zh-Hans` / `zh-Hant` / `cn` / `tw` | 中文（`ascii=false`） |
| `en` / `de` / `us` | 英文（`ascii=true`：`ENABLE` / `LOCK ANGLE (deg)` / `FOLLOW THE SCOPE ZOOM` / 武器与四选一同样英文） |
| 读不到（无注册表且无 HD2Runtime） | 英文 |

136 行全部注册成功（`refused=0`），分类与行数不变。

## 2. 健壮性加固（不影响正常路径）

- **`ptr_ok()`**：全文只有一个"这个数能不能当进程地址用"的判断（`>= 65536 且 < 0x800000000000`），
  替换了 10 处散落的字面量比较，并且给 `write_bytes()` 也补上了 —— 不可能成为地址的值不再送进
  `VirtualProtect`/`WriteProcessMemory`。
- **`u32()` 短读保护**：`string.byte` 在字符串提前结束时**返回的值比要的少**，
  原写法在"有 a 没有 d"时会直接算 `nil * 16777216` 报错。现在四字节不全就返回 nil。
- **`num_or()`**：cfg 是手改文件，`inf`/`NaN` 以前会一路流进比较式。例如
  `target_interval` 被写成 `1e400` 会得到 `inf`，`scan_age >= inf` 永远为假 → **敌人列表再也不刷新**。
  现在这类值统一回落到出厂默认。用在 `target_interval`、`scan_ms`、`bind_delay`、
  `cluster_delay`、`cluster_life`、`seek_speed`、`seek_accel`、`cone_deg`、`max_dist` 上。
- **菜单标签裁剪按 UTF-8 字符边界**：原来 `sub(1, 63)` 会把一个中文字符**劈成两半**，
  截出非法 UTF-8 文本。新的 `fit()` 遇到续字节（0x80–0xBF）就往回退一格。
- **`render_camera()`**：调用 `s.Unit.alive` 之前先用 `has()` 确认这个函数存在，
  不再靠 pcall 抛异常来发现"引擎里没有这个调用"。

## 3. 可读性

| 改动 | 说明 |
| --- | --- |
| 文件头 **MODULE MAP** | 一张"什么在哪儿"的目录，按名字而不是行号索引 |
| **哈希统一写法** | 全部 **245 个** 8 字节资源哈希由 `string.char(0x.., …)` 改成 `hash8('0x…')`（`TARGETS` 224 条 + `WATCH` 8 条 + `CLUSTER.units` 10 条 + 3 个命名常量），也就是 cfg 行、`SEEK_LIST`、社区哈希表用的**同一种写法**。`hash8`/`divmod256` 因此上移到常量区之前，脚本对每个条目做了**字节级往返校验**（`hash8(hex) == 原字节`）才写入 |
| `CLUSTER.units` | 同样改成 `hash8('0x…')`，其中 0/8/9 号现在能一眼看出就是 `SEEK_LIST` 里的法令 / P-33 / FAF-14 |
| 命名常量 | `LOG_MAX_LINES`（日志上限）、`SET_ROW_MAX`（设置表行数上限，原来散着 `272`/`271`）、`PUB_MAX`（发布缓冲上限）、`CLUSTER.max_unit`（原来三处 `for u = 0, 9`） |
| 消除同名遮蔽 | 准心 UI 的 `R` → **`UI`**（`R` 是全文的引擎偏移表）；`quad(..., state, ...)` → `lock_state`（`state` 是全局状态表）；LOS 内部的 `finite()` → `in_bounds()`（与外层 `finite()` 规则不同）；`seek_speeds(base)` / `local base = …` → `addr` / `row_base`（`base` 是 game.dll 基址） |
| 常量不再手抄 | cfg 模板里的 `'cfgver=16'` 改成 `('cfgver=%d'):format(CFGVER)`，不会再和 `CFGVER` 走散 |
| 缩进 | cfg 模板里 4/8 空格混排的 30 行、以及菜单 `MENU_DROP` 分支里**完全没有缩进**的 42 行，都对齐了 |
| 日志文案 | 启动行 `F7 only switches it off` 与实际行为（F7 是重启，不是关闭）矛盾，已改正 |

## 4. 怎么验证的

本包 `tools/` 下的脚本（不参与 mod 运行、也不进安装包，只为让改动可复现可复查）：

| 脚本 | 作用 |
| --- | --- |
| `apply_patches.py` | 全部改动都在这里，**逐条精确匹配 + 声明命中次数**；任何一条对不上就整体失败、不写文件。所以这次改动是**可复现**的 |
| `luatokens.py` + `hunks.py` | 自写 Lua 5.1 词法器，去掉注释与空白后做 token 级 diff。共 **250 处差异**，逐条核对全部对应上面的改动（纯改名占多数） |
| `numcheck.py` | 数值/字符串字面量清单对比（注释已剔除）：**所有**数字变化都能对上号（例：`0x80` 8→2 是哈希字节进了字符串；`65536` 20→10 是收敛进 `ptr_ok`；`272` 变成 `SET_ROW_MAX`）。没有任何偏移或魔数被意外改动 |
| `names.py` | 标识符清单对比：新增的名字恰好是 `LOG_MAX_LINES`、`PUB_MAX`、`SET_ROW_MAX`、`UI`、`cut`、`fit`、`in_bounds`、`lock_state`、`max_unit`、`num_or`、`ptr_ok`、`row_base`、`wrote`、`math.huge`，没有其它增删 |
| `locals.py` | 主 chunk 的 local 数量 162 → 168（LuaJIT 上限 200）——这段代码一向贴着上限，所以新增 local 控制在 6 个 |
| `verify.py` | 上面几项的合集；语法树检查需要 `pip install luaparser`，没装就自动跳过 |
| `check_package.py` | 只用 `zipfile`/`struct` 独立解析构建出来的 ZIP：清单结构、归档头、资源哈希，并把 Lua 从归档里解回来与 `docs/guided_rounds.lua` **逐字节**比对 |
| `guardglobals.py` | 专门抓**「在自己被声明之前就被引用」**的 chunk 级 local。这类名字会被编译成**全局读取**，永远是 nil —— 本次第一版就是在 `rd()` 里提前用了 `ptr_ok()`，导致整个 addon 加载失败（见第 4.2 节） |
| `loadtest.py` | **用游戏自带的 `bin/lua51.dll` 真正加载并运行这份 Lua**：`--probe-menu`（数 MODS 菜单行数）、`--probe-seek`（F10）、`--probe-render`（用 stingray 桩驱动世界方框，复现/验证第 1.5 节那个 bug）、`--probe-shutdown`。见第 4 节 |

结果：语法树解析通过；数值与标识符清单的差异全部可解释；打包出来的 Lua 资源与
`docs/guided_rounds.lua` 完全相同。

构建产物也做了校验：`build.py` 的归档写入器与 BingusSharedLoader 官方
`scripts/archive.py` + `build_addon.py` 的输出**逐字节一致**（用 v1.8.0 的源码验证过：
重建结果与仓库里现成的 `9ba626afa44a3aa3.patch_0` 完全相同）。

### 4.1 用游戏自带的 LuaJIT 实机跑一遍

`bin/lua51.dll` 就在游戏目录里，所以这份 Lua 可以**离线加载并执行**（Bingus Shared Loader
用的就是同一条 `luaL_loadbuffer` + `lua_pcall` 路径）。`tools/loadtest.py` 会：

- 把 `LOCALAPPDATA` 指到临时目录，**不碰玩家真实的 cfg 与日志**；
- 给 `update`/`shutdown` 打桩，并替换 `require('ffi')`，让 `GetModuleHandleA('game.dll')`
  返回一个假基址（其余 Win32 调用都是真的，对着假地址读写只会失败、不会出事）；
- 跑完整段 chunk，然后**再调用 `update()` 三次、`set_seek(2)`（F10）、`shutdown()`**，
  并给 `ModOptionsMenu` 打一个**会像真 pack 一样拒绝超长行**的桩来数菜单行。

| 检查 | v1.8.0 | v1.8.1 |
| --- | --- | --- |
| 加载整段 chunk | OK | **OK** |
| MODS 菜单行数 | `rows=136`：`GUIDED ROUNDS=32`、`GUIDED WEAPONS 1..4 = 32/32/32/8` | **完全相同** |
| `set_seek(2)`（F10 换追踪弹） | **ERROR：`attempt to call global 'set_lease'`** | **OK** |
| `shutdown()`（退出/停用时的还原路径） | OK | **OK** |

也就是说：菜单与 F7/F10 相关路径都真的跑过一遍，而且 v1.8.0 的 F10 崩溃在离线环境里
就能复现、修好后不再复现。

### 4.2 第一版曾经加载失败（已修）

第一版 v1.8.1 把 `rd()` 里的内联地址判断换成了新助手 `ptr_ok()`，但 `ptr_ok` 的
`local function` 写在 `rd` **后面**。Lua 的 local 只从声明那一行起可见，所以 `rd` 里的
`ptr_ok` 被编译成**全局读取**——永远是 nil：

```
mods/cancan2333/guided_rounds: load failed:
  guided_rounds.lua:389: attempt to call global 'ptr_ok' (a nil value)
```

整段 chunk 在第一次 `rd()` 调用时就中断，于是**菜单选项一并消失**（`menu_step` 与
`update` 钩子都在它后面才注册）。

- 修法：`ptr_ok` / `num_or` 移到 `rd` 之前，并在这两个函数上写明"为什么必须在前"。
- 防复发：`guardglobals.py` 现在专门扫这一类错误（它同时把 v1.8.0 里 `set_seek`
  那两处 `set_lease` / `sync_leases` 报出来，等于顺带验证了第 1 节的修复）。
- 现在的结果：`guardglobals.py` 对 v1.8.1 报"没有提前引用"，`loadtest.py` 三项探针全绿。

## 5. 怎么重新构建

```powershell
cd Guided-Rounds-v1.8.5
python build.py                                  # 写 Addon/ 与 Guided-Rounds-v1.8.5.zip
python build.py --check-against ..\BingusSharedLoader-source-v19   # 顺便和官方构建器对拍
```

脚本只读 `docs/guided_rounds.lua` 和 `manifest.json`，产出的 ZIP 结构就是管理器要的形态：

```
Guided-Rounds-v1.8.5.zip
  manifest.json
  Addon/9ba626afa44a3aa3.patch_0
  Addon/9ba626afa44a3aa3.patch_0.stream
  Addon/9ba626afa44a3aa3.patch_0.gpu_resources
  docs/…                      （参考用，不参与部署）
```

## 6. 没有改动的东西

内存偏移、`ROW_SIZE`/`PROJ_REC`/`SEEK_REC`、`DL_*`/`SEEK_DL` 类型哈希、
`TARGETS` 内容、`CLUSTER` 的判定浮点、damage id、相位调用顺序、
所有 cfg 键与默认值、菜单分类名与行数、全部日志行的前缀与格式（第 3 节列出的两行除外）、
F7 的两帧释放/重取路径、以及 `lease`/`damage`/`ballistics`/`cluster`/`launcher`/
`PL.phase`/`seeker` 各自的读改写逻辑。
