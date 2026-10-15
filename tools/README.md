# tools/ —— v1.8.1 这次优化是怎么做、怎么验的

这些脚本**不参与 mod 运行，也不进安装包**（`build.py` 只打包 `manifest.json`、`Addon/`
和 `docs/`）。留着是为了让这次改动**可复现、可复查**：源码怎么被改的、改完怎么证明没改坏，
都在这里。

除了 `apply_patches.py`（一次性转换，已经跑过），其它都是**只读检查**，不会修改任何文件。
路径都写死指向 `..\..\Guided-Rounds-v1.8.0` 与 `..\docs`，所以从任何目录运行都行。

| 脚本 | 作用 | 依赖 |
| --- | --- | --- |
| `apply_patches.py` | **唯一的改动来源**：把 v1.8.0 的源码逐条改写成 v1.8.1 并写入 `docs/guided_rounds.lua`。每条替换都声明了命中次数，任何一条对不上就整体失败、不写文件 | 无 |
| `luatokens.py` | 自写的 Lua 5.1 词法器（注释/空白丢掉，长字符串、两种引号、十六进制都处理） | 无 |
| `hunks.py` | 先把两版里两种哈希写法归一化，再做 token 级 diff，每个语义改动一行 | luatokens |
| `verify.py` | 完整校验：语法树解析 + token diff + 数值字面量清单对比 | luaparser（可选） |
| `numcheck.py` | 数值字面量 / 字符串字面量清单对比（注释已剔除） | luatokens |
| `names.py` | 标识符清单对比：只在一版里出现的名字（抓拼写错误和误改名） | luatokens |
| `locals.py` | 主 chunk 的 local 槽位统计（LuaJIT 上限 200，这段代码一向贴着上限） | luaparser |
| `check_package.py` | 只用 `zipfile`/`struct` 独立解析构建出来的安装包：清单结构、归档头、资源哈希、把 Lua 从归档里解回来和 `docs/` 对比 | 无 |
| `guardglobals.py` | 抓「在自己被声明之前就被引用」的 chunk 级 local —— 这类名字会被编译成全局读取，永远是 nil（第一版 v1.8.1 就是栽在这里） | luatokens |
| `loadtest.py` | **用游戏自带的 `bin/lua51.dll` 真正加载并执行这份 Lua**：`--probe-menu`（数 MODS 菜单行数）、`--probe-seek`（F10 的 `set_seek(2)`）、`--probe-render`（用 stingray 桩驱动世界方框，可复现"切武器后方框残留"）、`--probe-shutdown`（还原路径）。`LOCALAPPDATA` 指向临时目录，不碰玩家真实 cfg/日志 | 无（需要游戏在 `G:\SteamLibrary\...`，改 `loadtest.py` 顶部 `GAME` 可换路径） |

用法：

```powershell
python tools\verify.py            # 语法 + token diff + 数值清单
python tools\hunks.py             # 只看改动清单（推荐先看这个）
python tools\names.py             # 标识符增删
python tools\guardglobals.py docs\guided_rounds.lua
python tools\loadtest.py docs\guided_rounds.lua --probe-menu --probe-seek --probe-shutdown
python tools\loadtest.py docs\guided_rounds.lua --probe-render            # 世界方框（期望 afterDrop=0）
python tools\check_package.py     # 校验 ..\Guided-Rounds-v1.8.2.zip
```

`verify.py` 与 `locals.py` 需要 `python -m pip install luaparser`；没装的话
`verify.py` 会跳过语法树那一项，token diff 照常跑。

`check_package.py` 里写死了 v1.8.1 的包名与资源名；换成别的版本要顺手改一下常量。
