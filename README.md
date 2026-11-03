# 星河输入法 · Stellar River IME

星河输入法是面向 Windows 的中日文输入法，目标是逐步打磨接近主流商业输入法的使用体验。源码项目名和 GitHub 仓库仍为 `pyIME`。

## 当前基线

项目以成熟的开源组件为起点，而不是从零实现 Windows 文本服务：

- [`vendor/weasel`](https://github.com/rime/weasel)：小狼毫 Windows TSF 前端，负责系统集成、候选窗和部署工具。
- [`vendor/weasel/librime`](https://github.com/rime/librime)：Rime 输入法引擎，作为 Weasel 的上游子模块固定版本。
- [`config/rime-ice`](https://github.com/iDvel/rime-ice)：雾凇拼音方案与词库，作为独立子模块固定版本。
- [`config/rime-jaroomaji`](https://github.com/lazyfoxchan/rime-jaroomaji)：日语罗马字方案与词库，以子模块固定版本，不依赖 Lua。

各上游组件保留各自的代码与许可证。当前使用上游 TSF 实现，已加入简繁拼音、日语、Shift 英文切换和候选窗配置，不是搜狗输入法的完整复刻。

## 当前输入体验

- 首次安装默认勾选并排序为 **简体拼音 → 繁体拼音 → 日语**，首次启动默认使用简体拼音。对应方案为 `luna_pinyin_simp`、`luna_pinyin` 和 `jaroomaji`，不默认勾选注音、仓颉等其他方案。
- 简体拼音中 `zhongguo` 输出“中国”；选择繁体拼音后输出“中國”。切换方案时分别恢复对应字形，避免简体状态带入繁体方案。
- 英文沿用 Shift 直输模式，简体、繁体和日语方案都可以切换；不额外添加独立英文方案或修改 Windows 英语键盘。可用 F4 打开方案菜单，选择所需方案。
- 轻按左或右 Shift 在当前文字模式与英文之间切换；正在输入时，先把原始字母上屏，再切换到英文。例如输入 `nihao` 后按 Shift，上屏 `nihao`，而不是“你好”。
- Shift 与字母组合使用不触发中英文切换；长按 Shift 不作为轻按切换处理。
- 候选窗采用已确认的经典桌面样式：白底、横向每页 5 个候选、蓝色选中、白色选中文字、圆角、上方显示拼音。使用自有配置，不复制搜狗商标或皮肤资源，不宣称像素级一致。
- 有候选时，**逗号键 `,` 选择上一项、句号键 `.` 选择下一项**，不是上一页/下一页，也不会直接上屏；适用于简体、繁体和日语。未出现候选时保留各方案的标点，英文模式仍直输 ASCII 标点。要输入标点，请先确认或结束当前候选。
- Page Up / Page Down 继续翻页；中文的 `-` / `=` 翻页保持不变，日语的 `-` 仍用于长音。候选逐项移动使用 Tab / Shift+Tab 对应动作，在横向及竖向布局都不依赖箭头方向。
- 用户已有的 `default.custom.yaml`、`weasel.custom.yaml` 仍在默认配置之后应用，不覆盖个人设置。升级后如保留旧方案或旧主题，请通过星河输入法设置选择简化字方案和 `Stellar River Light` 主题，并执行“重新部署”；旧的用户自定义按键和布局优先级仍更高。

配置保存在 [`config/pyime/`](./config/pyime/)，随安装包分发。构建时使用 librime 的 YAML 配置接口将默认值合入数据文件，让首次安装设置向导和运行时保持一致，同时保留用户补丁入口。

## 日语输入

按 **F4 → 日语** 启用罗马字输入。这是星河内部的 Rime 方案，不增加独立 Windows 日语键盘或改变系统语言。选择日语方案后默认进入日语，而不是英文模式：

- 小写罗马字输入假名，**Enter** 直接确认假名，例如 `hiragana` → `ひらがな`、`gakkou` → `がっこう`。
- 大写罗马字输入片假名，例如按住 Shift 输入 `KATAKANA`，再按 Enter → `カタカナ`；Shift+字母不会切走输入模式。
- 罗马字输入读音后，从候选中选择汉字词，例如 `nihongo` 的候选包含 `日本語`；使用方向键选择、空格或数字确认。
- **Shift+Enter** 确认当前罗马字母；轻按左右 Shift 切换日语和英文，行为与中文方案一致。
- 逗号、句号分别输出日文标点 `、`、`。`。候选窗沿用白底、横向每页 5 个候选和蓝色选中，日语单独使用 Yu Gothic UI / Meiryo 等字体回退。

此功能基于 Rime 词典式转换，复用 Mozc、JMdict、KANJIDIC2 等数据，**并未集成 Mozc 的转换引擎，也不宣称具备同等整句预测或文节编辑能力**。首次部署会编译新增的大词库，耗时及磁盘占用较原来增加。已有用户自定义方案列表不会被覆盖；升级后如看不到“日语”，请在输入法设置中勾选“日语”并重新部署。

## 产品名称和兼容性

品牌定义位于 [`config/branding.json`](./config/branding.json)。中文名为“星河输入法”，英文品牌为 **Stellar River**，完整产品名为 **Stellar River IME**，无空格的代码标识使用 `StellarRiver`；GitHub 仓库仍为 `pyIME`。安装器、卸载列表、开始菜单、系统输入法显示名、托盘提示、设置窗口和文件属性使用对应的中英文产品名。安装包名为 `星河输入法-0.17.4.0-setup.exe`。

为了兼容此前安装及用户词库，暂时保留上游 TSF GUID、注册表路径、进程文件名以及 `%APPDATA%\Rime` 用户目录。因此这是原有 Weasel 安装的品牌定制升级，不是可与小狼毫并行注册的独立输入法；内部文件出现 `WeaselServer.exe`、`weasel.dll` 属于兼容实现，不是显示品牌。覆盖安装后如 Windows 缓存旧显示名，按安装器提示重启或注销再登录。

新安装默认父目录为 `Program Files\stellariver`（按用户指定的拼写），32 位安装使用对应的 Program Files 目录。内部版本子目录继续保留，例如 64 位机器上的程序目录为 `C:\Program Files\stellariver\weasel-0.17.4`。升级会复用注册表中记录的原安装父目录，不自动搬移既有安装；用户词库目录不变。

上游许可证、版权和来源说明继续保留，不将上游成果声明为完全自研。自动更新不再连接 Weasel 上游下载源，防止被上游安装包覆盖回旧品牌；“检查新版本”打开本项目的 GitHub Releases 页面，目前需要手动获取新版。

## 获取源码

```powershell
git clone --recurse-submodules git@github.com:cnwuzhh/pyIME.git
cd pyIME
git submodule update --init --recursive
```

仓库使用 Git 子模块固定上游版本。更新某个上游时，请在对应子模块目录中更新，再在 pyIME 仓库中提交新的子模块引用。

## 构建星河输入法

当前构建入口为 [`scripts/build.ps1`](./scripts/build.ps1)，使用 Visual Studio 2022 的 v143 工具链，构建 x64 与 Win32，不构建 ARM。脚本不安装输入法，也不修改系统输入设置。

首次构建前，初始化所有子模块并准备以下工具：

- Visual Studio Build Tools 2022：C++ 桌面构建工具、ATL/MFC、Windows 10 SDK `10.0.19041.0`。
- CMake `3.31.8`：解压到 `.tools\cmake-3.31.8-windows-x86_64`，避免旧依赖遇到 CMake 4 的兼容性变化。
- Boost `1.84.0`：解压到 `.tools\boost_1_84_0`，首次构建会编译静态库。
- Git for Windows（含 Git Bash）和 NSIS，安装在默认位置。
- Python 3 与 clang-format `18.1.8`：本地隔离环境位于 `.tools\python`，格式工具不是编译步骤的前置要求。

系统工具的安装命令如下；Visual Studio 和 NSIS 安装可能需要管理员授权：

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --accept-package-agreements --accept-source-agreements --override "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.ATL --add Microsoft.VisualStudio.Component.VC.ATLMFC --add Microsoft.VisualStudio.Component.Windows10SDK.19041"
winget install --id NSIS.NSIS --exact --source winget --accept-package-agreements --accept-source-agreements
```

从 [CMake 官方发布](https://github.com/Kitware/CMake/releases/tag/v3.31.8)和 [Boost 官方归档](https://archives.boost.io/release/1.84.0/source/)下载对应压缩包，核对发布方提供的 SHA-256 后解压到上述目录。可用 `python -m venv .tools\python` 创建 Python 环境，再执行 `.tools\python\Scripts\python.exe -m pip install clang-format==18.1.8` 安装格式工具。

在 pyIME 根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

这里的执行策略仅用于这次脚本进程，不改变系统执行策略。脚本在同一 `cmd.exe` 进程中配置 MSVC，并从 Weasel 根目录分别调用上游各个构建阶段，以免丢失编译器环境或沿用 librime 构建留下的工作目录。首次构建包括 Boost 和 librime 源码编译、默认数据准备、Weasel 编译和安装包生成；上游完整流程会重新生成 librime 的本地构建缓存。只修改 Weasel 后可追加 `-SkipDependencies` 复用已经生成的 Boost/librime，仍准备数据并生成新安装包；自定义 Boost/CMake 位置可通过 `-BoostRoot` 和 `-CMakeBin` 指定。

候选快捷键还使用 [`patches/rime-candidate-keys.patch`](./patches/rime-candidate-keys.patch) 中的小型兼容补丁，在本项目的配置关闭 `key_binder/reinterpret_paging_key` 时，不再把用于候选移动的句号回填到后续字母输入。未设置此选项时保持上游行为。构建入口临时应用并恢复该源码补丁；`-SkipDependencies` 会核对补丁和两个运行时 DLL 的缓存哈希，不匹配时显式重编译 x64/Win32 librime，避免旧运行时忽略新配置。

Boost 使用 [`scripts/boost-config.jam`](./scripts/boost-config.jam) 中的官方配置：由构建入口明确传入已验证的 `vcvarsall.bat` 路径，并设置 `rewrite-setup-scripts=off`。这避免 Boost 1.84 的自动路径识别和环境缓存失败导致架构错误或编译目标被跳过。

原始构建日志输出到 `.build\build-*.log`，安装包统一放在仓库根目录的 [`output/`](./output/) 中。上游构建在 `vendor\weasel\output\archives` 中生成星河安装包，构建入口随后复制到根目录 `output`，核对 SHA-256，并显示最终路径。同名文件会被最新成功构建覆盖。工具缓存和安装包二进制不提交到 Git，`output` 中的说明文件保留在版本控制中。安装包已加入星河品牌和上述默认输入配置，尚未集成雾凇拼音；输入法安装与配置部署另行执行。安装后，可通过开始菜单中的星河输入法工具打开用户文件夹。更多上游细节见 [Weasel 构建说明](https://github.com/rime/weasel/blob/master/INSTALL.md)。

上游脚本会临时改写 OpenCC 的 CMake 文件并删除 librime 的占位文件；构建入口在运行前保存其原始字节，结束时恢复，避免源码变脏。Weasel 子模块设置 `ignore = untracked`，只忽略未跟踪的构建输出，已跟踪源码改动和子模块版本变化仍会显示。

[`scripts/apply-branding.ps1`](./scripts/apply-branding.ps1) 在构建时对已知显示名称和资源应用品牌替换，构建入口在成功或失败后恢复这些上游文件的原始字节，包括 UTF-16 资源文件；不需要修改或提交上游子模块。

## 验证输入配置与候选窗

完成构建后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-profile.ps1
```

测试从根目录 `output` 的星河安装包解压实际配置和 Rime DLL，检查安装器品牌、所有程序各语言版本信息、对话框及字符串资源和上游许可证；通过安装向导使用的选中方案 API 验证默认勾选简体、繁体、日语及其顺序。验证中文繁简输出、日语平假名/片假名/汉字/标点、三个方案内的 Shift 英文切换，以及日语词库及许可的打包完整性。另用空用户补丁、已有字体补丁和已有用户的逆序方案列表分别验证部署行为，确认保留个人选择且不改写自定义文件；不读写真实用户词库或系统输入设置。

候选导航测试检查逗号/句号的逐项位置、不会误翻页或提交、随后继续输入不插入句号，以及四种布局、普通标点和原有翻页键。构建还调用 NSIS 预处理检查，验证全部架构分支默认使用 `stellariver` 并保留旧安装目录复用；预处理结果保存在 `.build/installer-defaults-preprocessed.nsi`，不运行安装器或修改系统注册表。

测试会短暂显示原生候选窗，用实际编译的 Weasel UI 检查横向布局、白底与蓝色选中，生成 [`output/candidate-preview.png`](./output/candidate-preview.png)。需要可用的 Windows 桌面；这不是网页模拟，也不替代安装后的真实应用 TSF 兼容性测试。测试成功后清理其解压目录，图片和安装包留在 `output`，不提交 Git。

## 使用雾凇拼音配置

本次源码构建的 librime 尚未集成 `librime-lua`；雾凇拼音方案依赖 Lua 处理器、翻译器和过滤器，因此不能直接将配置部署到本次安装包并认为已经支持雾凇拼音。当前运行验证使用上游朙月拼音·简化字（`luna_pinyin_simp`）；后续须集成 Lua 插件，再验证雾凇拼音部署和输入。

雾凇拼音配置位于 `config\rime-ice`。完成 Lua 集成后，首次替换 Rime 用户配置前，先从星河输入法工具打开用户文件夹并备份现有 `%APPDATA%\Rime` 内容；然后按[雾凇拼音说明](https://github.com/iDvel/rime-ice#安装)部署配置，并执行“重新部署”。不要直接删除未备份的用户配置或词库。

## 许可证

上游组件各自适用其仓库中的许可证：Weasel 为 GPL-3.0，雾凇拼音为 GPL-3.0，librime 为 BSD-3-Clause。分发包含这些组件的构建时，必须遵守各自许可证及其依赖项的要求。pyIME 自有代码的许可证将在添加自有实现时另行确定。

日语方案 rime-jaroomaji 的自有文件采用 Apache-2.0，数据文件各自保留来源许可：Mozc 数据含 Google 的 BSD 条款以及 IPAdic/NAIST/ICOT 声明；JMdict 和 KANJIDIC2 数据由 James William BREEN 及 Electronic Dictionary Research and Development Group（EDRDG）持有版权，采用 CC BY-SA 4.0。词库内容保持上游原样，不将这些数据声明为自有版权。详见[日语来源声明](./config/japanese-NOTICES.txt)、[EDRDG 许可](./licenses/japanese/EDRDG-LICENCE.html)和 [CC BY-SA 4.0 全文](./licenses/japanese/CC-BY-SA-4.0.txt)。对应许可和原始说明会随安装包分发。

## 进展日志

每次任务结束时，在 [`log/`](./log/) 中追加进展记录，包含完成事项、验证结果、阻塞项和下一步。按北京时间每日一个文件，具体约定见 [日志说明](./log/README.md)。

每次任务或阶段完成后，更新日志、验证相关改动，并主动提交和推送到当前分支的远端。同步失败须如实记录和报告，不强制推送或提交无关改动。