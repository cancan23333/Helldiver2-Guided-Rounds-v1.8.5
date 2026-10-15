# Guided Rounds v1.8.5 — 制导弹丸 / Guided projectiles for every weapon

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Mod page](https://img.shields.io/badge/AyakaMods-mod%20page-blue)](https://ayakamods.com/mods/guided-rounds-%E5%AD%90%E5%BC%B9%E8%BF%BD%E8%B8%AA%E4%B8%8E%E8%87%AA%E7%9E%84%E6%89%A9%E5%B1%95.5059/)

A Helldivers 2 addon for Bingus Shared Loader: the P-92 Warrant's own guidance, ported to every weapon on the list.
Rounds track the enemy after they leave the barrel, while **damage, muzzle velocity and ballistics stay the weapon's own**.

**中文** | [English](#english)

> ### ★ NEW IN v1.8.5 — FULL ENGLISH SUPPORT ★
> Every in-game option now follows your game language: Simplified or Traditional Chinese shows Chinese, **every other
> language shows English**. English-speaking players get a fully English menu for the first time (earlier versions were
> Chinese-only). Nothing to configure — change Text Language in the game's options and open the escape menu again.

---

## 目录（中文）

- [简介](#简介)
- [来源声明（基于他人作品二次修改）](#来源声明基于他人作品二次修改)
- [依赖](#依赖)
- [安装](#安装)
- [使用方法](#使用方法)
- [亮点](#亮点)
- [已知问题](#已知问题)
- [多人游戏建议](#多人游戏建议)
- [源码与构建](#源码与构建)
- [开源许可](#开源许可)
- [致谢](#致谢)

### 简介

把 **P-92 法令手枪**的原版制导机制移植到武器清单里的每一把枪上。弹丸出膛后自动追踪敌人，而
**伤害、初速、弹道仍然使用武器自己的数值**（不会统一变成法令手枪的 90 伤害）。带索敌范围圆环、锁定标记与
目标方框，全部参数可在游戏内 **MODS** 页签实时调整。

### 来源声明（基于他人作品二次修改）

本 mod 是 [DIY your weapon to shoot like Donk（APW-1 反器材锁头 DIY-able）](https://ayakamods.com/mods/diy-your-weapon-to-shoot-like-donk-apw-1-%E5%8F%8D%E5%99%A8%E6%9D%90%E9%94%81%E5%A4%B4mod-diy-able.4226/)
的**二次修改产物**：制导机制、内存偏移与大部分实现都来自那个 addon，本仓库是在它基础上的独立开发与修复。
如果你更偏好原作的做法，请直接使用原作；两个包修改同一批武器字段，**不要同时启用**。

### 依赖

必需：

- [Bingus Shared Loader](https://ayakamods.com/mods/bingus-shared-loader.3861/) —— v18+ / API 1
- [HD2Runtime](https://ayakamods.com/mods/hd2runtime.4260/) —— v0.40.0+

强烈推荐：

- [WeakPoint Lock-On v2](https://ayakamods.com/mods/weakpoint-lock-on-v2.3981/) —— v3.0
- [Vanilla Plus Megapack](https://ayakamods.com/mods/vanilla-plus-megapack.3913/) —— 提供游戏内 MODS 页签；不装只能用 cfg 改参数

缺少 HD2Runtime 时弹丸材质不会加载，弹丸会显示成缺材质的问号图标。

### 安装

1. 用管理器导入 `Guided-Rounds-v1.8.5.zip`（或在本仓库运行 `python build.py` 自行构建）
2. 启用本 mod 与上面的依赖
3. purge & redeploy
4. 重启游戏

⚠️ 如果你装过原作「DIY-able / APW-1 反器材锁头」，请先卸载：两者修改同一批武器字段，同时启用会互相冲突。

### 使用方法

逃生菜单的 **MODS** 页签里有两个分类：

- **GUIDED ROUNDS** —— 总开关与全部参数（正好 32 项）
- **GUIDED WEAPONS 1..4** —— **104** 把枪/支援武器，每把一个四选一：
  - **OFF**：打普通弹
  - **准心优先**：打制导弹，锁离准心最近的敌人
  - **最大血量大优先**：制导，锁最大血量最大的
  - **最大血量小优先**：制导，锁最大血量最小的

  两个血量档都按**最大**血量排序（不会因为目标受伤而中途改选），同一档内仍由准心决定。

**常用参数**

| 参数 | 说明 |
| --- | --- |
| 开启 | 总开关。关闭会把所有改过的内存按字节还原 |
| 锁定角度 | 索敌锥半角，**同时决定屏幕上范围圆环的大小**；设 0 就没有圆环 |
| 锁定距离 | 索敌距离上限（米），出厂 250 |
| 制导弹速度 / 加速度 | 直接写追踪组件的速度与加速度。原厂只有 90 m/s，所以制导弹看起来慢；建议先试 600–900 |
| 出膛锁定生效时间 | 弹丸出膛后多久才允许被指定目标，出厂 0.25 秒 |
| 自己绑定目标 | 引擎没锁上时由 mod 在瞄准锥里挑一个绑上去，**建议保持开启** |
| 掩体后不锁 | 默认开。用引擎自己的碰撞射线判遮挡，而且**从手上的枪口发出**——判的就是子弹这条路 |
| 忽略植物遮挡 | 默认开。树叶挡视线但挡不住子弹，跳过引擎标记的这类命中 |
| 范围圆环 / 锁定标记 / 目标方框 | 三个锁定视觉元素，各自独立开关 |
| 加载弹丸材质 | **必须保持开启**。关掉后弹丸会显示成缺失材质的问号图标 |
| 开镜锁定系数 / 开镜锁定范围跟随倍镜 | 默认关。关闭时圆环在任何倍率下都是同样的屏幕大小，腰射与开镜能锁的范围完全一致；打开后开镜锁定范围 = 原版范围 × 系数，随倍镜放大系数自适应 |

**快捷键**

| 键 | 作用 |
| --- | --- |
| **F7** | 重启本 mod：把所有写过的值还原后重新武装。它**不会关闭** mod，用于清掉偶发「锁不上」的状态 |
| **F10** | 循环切换追踪弹类型（需要先在 cfg 里把 `seek_cycle` 设为 1） |

**配置文件**（`ship_scan` / `debug` / `los_debug` / `los_desc` / `scan_ms` 这几个开发者/排查开关只写在 cfg 里，不占菜单行）

```
%LOCALAPPDATA%\Hd2ApwGuidance\apw_guidance.cfg
```

**语言**：菜单选项文字自动跟随游戏语言——简体/繁体中文显示中文，其它语言显示英文；改了 Text Language 之后重开一次逃生菜单即可生效。

### 亮点

- 把 P-92 法令的原版制导机制移植到 **104** 把枪与支援武器，弹丸出膛后自动追踪敌人
- **伤害、初速、弹道仍然使用武器自己的数值**，不会统一变成法令手枪的数据
- 索敌范围圆环（1 像素细线）+ 原版锁定标记 + 目标方框，三者各自独立开关；**圆环画多大就锁多大**
- **掩体后不锁**：视线检测用引擎自己的碰撞射线，而且从**手上的枪口**发出（不是相机），判的就是子弹这条路
- 每把枪可选四种模式：**OFF / 准心优先 / 最大血量大优先 / 最大血量小优先**
- **开镜与腰射的锁定范围不再打架**：默认屏幕一致；想要「开镜锁得更远」可打开「跟随倍镜」，并按系数自适应
- **F7 一键重启**，清掉偶发的锁不上状态
- **（v1.8.5 新增）菜单选项文字跟随游戏语言**自动切换中/英
- RL-77 空爆火箭：可让携带集束的那枚火箭本体制导（出厂 `flak_only=1`，集束模式保持原厂行为，只制导高射弹）
- 菜单遵守 MODS 页的硬上限（每分类 32 行、页签最多 8 个分类），**不会挤掉别的 mod 的分类**

### 已知问题

- **刚进入战局时会有一小段卡顿——这是正常现象，将来也不会修复。**
  mod 必须先在本机内存里找到游戏的数据表才能工作，这一小段卡顿就是那次查找。它是**一次性**的：数据表找到之后
  就不再扫描，之后的战斗不受影响。想减轻可以把 cfg 里的 `scan_ms` 调小（出厂 4 毫秒/帧；调小则卡顿更轻，
  代价是找到数据表更慢）。
- **作为主机时，没装本 mod 的队友会看到粉色问号弹丸。**
  本 mod 会把弹丸换成 P-92 法令的**弹丸实体**（追踪组件在那个实体里），而资源包是**按机器加载**的：只有装 mod 的机器申请过这个包，
  别人的游戏里这个实体解析不出来，于是渲染成缺材质的问号。这是引擎的资源加载机制，**主机侧无法绕开**。
- **作为客机加入别人的战局时，通常不会出现这个问题**：你自己那台机器加载了自己需要的包，射击效果对你完全正常，
  队友也不需要装任何东西。所以**推荐以客机身份加入其他队伍**。
- 想让队友也看到正常模型：让队友把 HD2Runtime 升到 **0.31 以上**（新版运行时会自动加载队友 mod 需要的材质，队友不需要装本 mod）；
  或者让队里任意一人把 **P-92 法令**当副武器带着（该资源包会被全队加载）。
- **激光、电弧、火焰、喷射类等非弹丸武器无法使用，且未来也不会支持。** 例如 LAS-98 激光大炮、ARC-3 电弧发射器、
  FLAM-40 火焰喷射器、TX-41 灭菌器等：它们**没有可追踪的弹丸**，本 mod 的制导机制对它们无效。
- 近战武器、手雷/投掷物，以及非玩家武器的行不列在菜单里（受 MODS 页 32 行/分类限制）；把这些武器写进 cfg 的
  `weapons=` 行仍可制导。
- 与其它修改同一批武器/弹丸字段的 mod 可能冲突。

### 多人游戏建议

- **推荐以客机身份加入别人的战局。** 你的制导效果只由你自己的机器计算，队友不会看到问号弹丸，你也不需要队友装任何东西。
- 如果你是主机：请提前告知队友可能看到问号弹丸，并按上面「已知问题」里的办法缓解。
- 建议使用 Friends Only / 邀请制房间。

### 源码与构建

mod 源码是单个 Lua 文件：`docs/guided_rounds.lua`（构建脚本的唯一输入），另外还有：

```
Guided-Rounds-v1.8.5/
├─ manifest.json            管理器清单（GUID、名称、Include）
├─ build.py                 打包脚本：重建 Addon/ 与安装包 zip
├─ Addon/                   部署目录：9ba626afa44a3aa3.patch_0 (+ .stream / .gpu_resources)
├─ docs/
│  ├─ guided_rounds.lua     mod 源码
│  ├─ README.md             随包说明书
│  └─ OPTIMIZATION.md       各版本改动与验证记录
└─ tools/                   离线自检脚本（不进安装包）
```

构建（只需要 Python 3，不需要游戏或 SDK）：

```powershell
cd Guided-Rounds-v1.8.5
python build.py                                  # 写 Addon/ 与 Guided-Rounds-v1.8.5.zip
python build.py --check-against ..\BingusSharedLoader-source-v19   # 与官方构建器逐字节对拍
```

归档写入器的输出与 Bingus Shared Loader 官方 `scripts/archive.py` + `build_addon.py` **逐字节一致**。

`tools/` 里的自检脚本（改完源码建议跑一遍）：

| 脚本 | 作用 |
| --- | --- |
| `guardglobals.py` | 抓「在自己被声明之前就被引用」的 local——这类名字会被编译成全局读取，永远是 nil |
| `loadtest.py` | **用游戏自带的 `bin/lua51.dll` 真正加载并执行这份 Lua**：`--probe-menu`（数 MODS 菜单行数）、`--probe-seek`（F10）、`--probe-scope`（开镜/腰射圆环）、`--probe-render`（目标方框）、`--probe-language`（语言自适应）、`--probe-shutdown`（还原路径） |
| `check_package.py` | 只用标准库解析构建出来的 zip：清单结构、归档头、资源哈希，并把 Lua 从归档里解回来与 `docs/` 逐字节比对 |
| `hunks.py` / `verify.py` / `numcheck.py` / `names.py` | 与旧版本做 token 级差异、数值/标识符清单对比，确认改动没有意外波及内存偏移与常量 |

### 开源许可

本仓库以 **MIT 许可证**开源，见 [LICENSE](LICENSE)。你可以自由使用、修改、再分发，只需保留版权与许可声明。

源码仓库：<https://github.com/cancan23333/Helldiver2-Guided-Rounds-v1.8.5>

欢迎在 Issues 里报告问题（附上 `%LOCALAPPDATA%\Hd2ApwGuidance\ApwGuidance.log` 与
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\BingusSharedLoader.log` 更有效），也欢迎 Pull Request。

本仓库不含游戏本体资源；制导组件与场景资源的版权属于 Arrowhead Game Studios。

### 致谢

本包是 [DIY your weapon to shoot like Donk（APW-1 反器材锁头 DIY-able）](https://ayakamods.com/mods/diy-your-weapon-to-shoot-like-donk-apw-1-%E5%8F%8D%E5%99%A8%E6%9D%90%E9%94%81%E5%A4%B4mod-diy-able.4226/)
的二次修改产物：制导机制、内存偏移与大部分实现来自那个 addon。也感谢 Bingus Shared Loader、HD2Runtime、
Mod Options Menu / Vanilla Plus Megapack 的作者们。作者：cancan2333 & SoS2430。

---

<a id="english"></a>

## English

A Helldivers 2 addon for Bingus Shared Loader: the **P-92 Warrant's own guidance**, ported to every weapon on the list.
Rounds track the enemy after they leave the barrel, while **damage, muzzle velocity and ballistics stay the weapon's
own** (they do not become the Warrant's 90 damage). It adds an aim-cone range ring, a lock marker and a target box, all
tunable live from the in-game **MODS** tab.

> ### ★ NEW IN v1.8.5 — FULL ENGLISH SUPPORT ★
> Every in-game option now follows your game language: Simplified or Traditional Chinese shows Chinese, **every other
> language shows English** — a fully English menu for the first time (earlier versions were Chinese-only). Nothing to
> configure: change Text Language in the game's options and open the escape menu again.

### Derivation notice (built on someone else's work)

This project is a **modified derivative** of
[DIY your weapon to shoot like Donk (APW-1 Anti-Materiel lock-on, DIY-able)](https://ayakamods.com/mods/diy-your-weapon-to-shoot-like-donk-apw-1-%E5%8F%8D%E5%99%A8%E6%9D%90%E9%94%81%E5%A4%B4mod-diy-able.4226/):
the guidance mechanism, the memory offsets and most of the implementation come from that addon. If you prefer the
original approach, use that mod instead — both edit the same weapon fields, so **do not enable the two together**.

### Requirements

Required:

- [Bingus Shared Loader](https://ayakamods.com/mods/bingus-shared-loader.3861/) — v18+ / API 1
- [HD2Runtime](https://ayakamods.com/mods/hd2runtime.4260/) — v0.40.0+

Highly recommended:

- [WeakPoint Lock-On v2](https://ayakamods.com/mods/weakpoint-lock-on-v2.3981/) — v3.0
- [Vanilla Plus Megapack](https://ayakamods.com/mods/vanilla-plus-megapack.3913/) — provides the in-game MODS tab; without it only the cfg file can change settings

Without HD2Runtime the projectile materials are never loaded and rounds show as missing-material question marks.

### Installation

1. Import `Guided-Rounds-v1.8.5.zip` with your mod manager (or run `python build.py` here to build it yourself)
2. Enable this mod and the requirements above
3. Purge & redeploy
4. Restart the game

⚠️ If the original "DIY-able / APW-1 Anti-Materiel lock-on" addon is installed, remove it first — both edit the same
weapon fields and conflict when enabled together.

### How to use

The escape menu's **MODS** tab carries two categories:

- **GUIDED ROUNDS** — master switch and every parameter (exactly 32 rows)
- **GUIDED WEAPONS 1..4** — **104** weapons and support weapons, one four-way choice each:
  - **OFF**: plain rounds
  - **AIM FIRST**: guided, locks the enemy nearest the crosshair
  - **BIG FIRST**: guided, locks the enemy with the most maximum health
  - **SMALL FIRST**: guided, locks the enemy with the least maximum health

  Both health tiers order by **maximum** health, so the choice does not drift as a target is damaged; inside one tier the crosshair still decides.

**Common settings**

| Setting | Meaning |
| --- | --- |
| ENABLE | Master switch. Turning it off restores every byte it wrote |
| LOCK ANGLE | Acquisition cone half angle, and **it also sets the on-screen radius of the range ring**; 0 removes the ring |
| LOCK RANGE | Furthest target accepted, in metres (250 shipped) |
| GUIDED ROUND SPEED / SEEKER ACCELERATION | Written straight into the seeker component. The game value is only 90 m/s, which is why guided rounds look slow; try 600–900 first |
| ARM TIME AFTER MUZZLE | How long after leaving the barrel a round may be given a target (0.25 s shipped) |
| BIND TARGET OURSELVES | When the engine has not locked anything, pick one in the aim cone and bind it. **Leave this on** |
| REQUIRES LINE OF SIGHT | On by default. Uses the engine's own collision ray, cast **from the muzzle in your hands** — the bullet's own path is tested |
| SHOOT THROUGH FOLIAGE | On by default. Leaves block the view but not the bullet, so the engine's foliage hits are skipped |
| RANGE RING / LOCK MARKERS / TARGET BOX | The three lock visuals, each with its own switch |
| LOAD PROJECTILE MATERIALS | **Keep this ON.** With it off, rounds show as missing-material question marks |
| SCOPE LOCK SCALE / FOLLOW THE SCOPE ZOOM | Off by default. Off: the ring keeps the same on-screen size at every zoom. On: the scoped range is the original range × the scale, so it follows the magnification |

**Hotkeys**

| Key | Action |
| --- | --- |
| **F7** | Restarts the mod: every value it wrote is restored, then taken again. It does **not** switch the mod off |
| **F10** | Cycles the seeker entity (set `seek_cycle=1` in the cfg first) |

**Config file** (the developer/troubleshooting switches live here only, so they cost no menu row:
`ship_scan` / `debug` / `los_debug` / `los_desc` / `scan_ms`)

```
%LOCALAPPDATA%\Hd2ApwGuidance\apw_guidance.cfg
```

**Language**: option texts follow the game language — Simplified/Traditional Chinese shows Chinese, every other
language shows English. After changing Text Language in the game, open the escape menu again.

### Highlights

- The P-92 Warrant's own guidance, ported to **104** weapons and support weapons
- **Damage, muzzle velocity and ballistics stay the weapon's own** — nothing is normalised to the Warrant's numbers
- Range ring (one-pixel hairline), stock lock markers and a target box, each with its own switch; **what the ring shows is what is locked**
- **Cover is respected**: the sight test casts the engine's own collision ray **from the muzzle in your hands**, so it judges the bullet's actual path
- Four modes per weapon: **OFF / AIM FIRST / BIG FIRST / SMALL FIRST**
- **Hipfire and scope no longer disagree**; switch on FOLLOW THE SCOPE ZOOM to lock further the more you zoom
- **F7 restarts in one keypress** instead of toggling the mod off and on
- **(new in v1.8.5) option texts follow the game language** (Chinese / English)
- RL-77 Airburst: the rocket that carries the burst can be guided (`flak_only=1` shipped, so the cluster mode stays factory)
- The menu respects the MODS tab's hard limits, so it **never pushes another mod's category out**

### Known issues

- **A short stutter when a mission starts — this is normal and will not be fixed.** The mod has to locate the game's
  data tables in this machine's memory before it can do anything, and that search is the stutter. It is a **one-off**
  cost: once the tables are found nothing is scanned again. To soften it, lower `scan_ms` in the cfg (4 ms per frame
  shipped: less stutter, but the tables are found later).
- **As the host, squadmates who do not have this mod see pink question-mark rounds.** The mod swaps a weapon's round for
  the P-92 Warrant **projectile entity** (that is where the seeker lives), and resource packages are loaded **per
  machine**: only a machine that asked for the package has it. This is the engine's asset loading and **cannot be worked
  around from the host side**.
- **Joining someone else's game as a client does not normally show this** — your own machine loads what it needs, and the
  host needs nothing installed. That is why **joining other squads as a client is the recommended way to play**.
- To make squadmates see the correct model: have them update HD2Runtime to **0.31 or newer** (a current runtime loads
  what a lobby peer's mods need by itself), or have anyone in the squad carry the **P-92 Warrant** as their sidearm.
- **Non-projectile weapons cannot be guided and will never be supported.** LAS-98 Laser Cannon, ARC-3 Arc Thrower,
  FLAM-40 Flame Thrower, TX-41 Sterilizer and other beam/arc/flame/spray weapons fire **no projectile to steer**.
- Melee weapons, grenades/throwables and non-player weapon rows are not listed in the menu (32 rows per category);
  writing them into the cfg's `weapons=` line still guides them.
- May conflict with other mods that edit the same weapon or projectile fields.

### Multiplayer advice

- **Join other squads as a client.** Your guidance is computed on your own machine, squadmates never see question-mark
  rounds, and nobody needs anything installed for you.
- If you are the host: tell your squadmates they may see question-mark rounds, and use the mitigations above.
- Friends Only / invite-only lobbies are recommended.

### Source and build

The addon is a single Lua file, `docs/guided_rounds.lua` (the only input the build script needs):

```
Guided-Rounds-v1.8.5/
├─ manifest.json            mod manager manifest (GUID, name, Include)
├─ build.py                 packaging: rewrites Addon/ and the release zip
├─ Addon/                   deployment folder: 9ba626afa44a3aa3.patch_0 (+ sidecars)
├─ docs/
│  ├─ guided_rounds.lua     the addon source
│  ├─ README.md             the README shipped inside the package
│  └─ OPTIMIZATION.md       per-version change log and verification notes
└─ tools/                   offline self-check scripts (not packaged)
```

Build (Python 3 only; no game or SDK needed):

```powershell
cd Guided-Rounds-v1.8.5
python build.py                                  # writes Addon/ and Guided-Rounds-v1.8.5.zip
python build.py --check-against ..\BingusSharedLoader-source-v19   # byte-compare with the official builder
```

The archive writer produces output **byte-identical** to Bingus Shared Loader's own
`scripts/archive.py` + `build_addon.py`.

Self-checks in `tools/` (worth running after a change):

| Script | Purpose |
| --- | --- |
| `guardglobals.py` | finds a local read before its declaration — such a name compiles to a global read and is nil forever |
| `loadtest.py` | **loads and runs the addon with the game's own `bin/lua51.dll`**: `--probe-menu` (MENU rows), `--probe-seek` (F10), `--probe-scope` (ring vs zoom), `--probe-render` (target box), `--probe-language` (language adaptation), `--probe-shutdown` (teardown) |
| `check_package.py` | parses the built zip with the standard library: manifest, archive header, resource hash, and the Lua payload byte-compared with `docs/` |
| `hunks.py` / `verify.py` / `numcheck.py` / `names.py` | token-level diff against older revisions plus numeric/identifier inventories, to prove no offset or constant moved by accident |

### License

Released under the **MIT license**, see [LICENSE](LICENSE). Use, modify and redistribute freely, keeping the copyright
and license notice.

Source repository: <https://github.com/cancan23333/Helldiver2-Guided-Rounds-v1.8.5>

Issues and pull requests are welcome — attaching `%LOCALAPPDATA%\Hd2ApwGuidance\ApwGuidance.log` and
`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\BingusSharedLoader.log` makes a report much easier to act on.

This repository contains no game assets; guidance components and scene assets are copyright Arrowhead Game Studios.

### Credits

This package is a modified derivative of
[DIY your weapon to shoot like Donk (APW-1 Anti-Materiel lock-on, DIY-able)](https://ayakamods.com/mods/diy-your-weapon-to-shoot-like-donk-apw-1-%E5%8F%8D%E5%99%A8%E6%9D%90%E9%94%81%E5%A4%B4mod-diy-able.4226/);
the guidance mechanism, the memory offsets and most of the implementation come from that addon. Thanks also to the
authors of Bingus Shared Loader, HD2Runtime and Mod Options Menu / Vanilla Plus Megapack. Authors: cancan2333 & SoS2430.
