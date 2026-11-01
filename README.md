# pyIME

一个面向 Windows 的中文输入法项目，目标是逐步打磨接近主流商业输入法的使用体验。

## 当前基线

项目以成熟的开源组件为起点，而不是从零实现 Windows 文本服务：

- [`vendor/weasel`](https://github.com/rime/weasel)：小狼毫 Windows TSF 前端，负责系统集成、候选窗和部署工具。
- [`vendor/weasel/librime`](https://github.com/rime/librime)：Rime 输入法引擎，作为 Weasel 的上游子模块固定版本。
- [`config/rime-ice`](https://github.com/iDvel/rime-ice)：雾凇拼音方案与词库，作为独立子模块固定版本。

Weasel 和雾凇拼音保留各自的上游代码与许可证。当前使用上游 TSF 实现，已加入 pyIME 的简体中文、Shift 切换和候选窗配置，不是搜狗输入法的完整复刻。

## 当前输入体验

- 默认使用朙月拼音·简化字（`luna_pinyin_simp`），默认中文输入，例如 `zhongguo` 输出“中国”。
- 轻按左或右 Shift 切换中英文；正在输入拼音时，先把原始拼音字母上屏，再切换到英文。例如输入 `nihao` 后按 Shift，上屏 `nihao`，而不是“你好”。
- Shift 与字母组合使用不触发中英文切换；长按 Shift 不作为轻按切换处理。
- 候选窗采用已确认的经典桌面样式：白底、横向每页 5 个候选、蓝色选中、白色选中文字、圆角、上方显示拼音。使用自有配置，不复制搜狗商标或皮肤资源，不宣称像素级一致。
- 用户已有的 `default.custom.yaml`、`weasel.custom.yaml` 仍在默认配置之后应用，不覆盖个人设置。升级后如保留旧方案或旧主题，请通过小狼毫设置选择简化字方案和 `pyIME Light` 主题，并执行“重新部署”；旧的用户自定义按键和布局优先级仍更高。

配置保存在 [`config/pyime/`](./config/pyime/)，随安装包分发。构建时使用 librime 的 YAML 配置接口将默认值合入数据文件，让首次安装设置向导和运行时保持一致，同时保留用户补丁入口。

## 获取源码

```powershell
git clone --recurse-submodules git@github.com:cnwuzhh/pyIME.git
cd pyIME
git submodule update --init --recursive
```

仓库使用 Git 子模块固定上游版本。更新某个上游时，请在对应子模块目录中更新，再在 pyIME 仓库中提交新的子模块引用。

## 构建 Weasel

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

Boost 使用 [`scripts/boost-config.jam`](./scripts/boost-config.jam) 中的官方配置：由构建入口明确传入已验证的 `vcvarsall.bat` 路径，并设置 `rewrite-setup-scripts=off`。这避免 Boost 1.84 的自动路径识别和环境缓存失败导致架构错误或编译目标被跳过。

原始构建日志输出到 `.build\build-*.log`，安装包统一放在仓库根目录的 [`output/`](./output/) 中。上游仍在 `vendor\weasel\output\archives` 中生成安装包，构建入口随后复制到根目录 `output`，核对 SHA-256，并显示最终路径。安装包沿用上游文件名，同名文件会被最新成功构建覆盖。工具缓存和安装包二进制不提交到 Git，`output` 中的说明文件保留在版本控制中。此阶段仍使用 Weasel 品牌，已加入上述 pyIME 默认输入配置，尚未集成雾凇拼音；输入法安装与配置部署另行执行。安装后，可通过开始菜单中的小狼毫工具打开用户文件夹。更多上游细节见 [Weasel 构建说明](https://github.com/rime/weasel/blob/master/INSTALL.md)。

上游脚本会临时改写 OpenCC 的 CMake 文件并删除 librime 的占位文件；构建入口在运行前保存其原始字节，结束时恢复，避免源码变脏。Weasel 子模块设置 `ignore = untracked`，只忽略未跟踪的构建输出，已跟踪源码改动和子模块版本变化仍会显示。

## 验证输入配置与候选窗

完成构建后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-profile.ps1
```

测试从根目录 `output` 的安装包解压实际配置和 Rime DLL，在独立测试目录验证首次安装默认值、简体候选与上屏、左右 Shift 切换、拼音字母上屏和 Shift+字母不误切换。另用空用户补丁和已有字体补丁分别验证部署行为，不读写真实用户词库或系统输入设置。

测试会短暂显示原生候选窗，用实际编译的 Weasel UI 检查横向布局、白底与蓝色选中，生成 [`output/candidate-preview.png`](./output/candidate-preview.png)。需要可用的 Windows 桌面；这不是网页模拟，也不替代安装后的真实应用 TSF 兼容性测试。测试成功后清理其解压目录，图片和安装包留在 `output`，不提交 Git。

## 使用雾凇拼音配置

本次源码构建的 librime 尚未集成 `librime-lua`；雾凇拼音方案依赖 Lua 处理器、翻译器和过滤器，因此不能直接将配置部署到本次安装包并认为已经支持雾凇拼音。当前运行验证使用上游朙月拼音·简化字（`luna_pinyin_simp`）；后续须集成 Lua 插件，再验证雾凇拼音部署和输入。

雾凇拼音配置位于 `config\rime-ice`。首次替换 Rime 用户配置前，先从小狼毫工具打开用户文件夹并备份现有 `%APPDATA%\Rime` 内容；然后按[雾凇拼音说明](https://github.com/iDvel/rime-ice#安装)部署配置，并在小狼毫中执行“重新部署”。不要直接删除未备份的用户配置或词库。

## 许可证

上游组件各自适用其仓库中的许可证：Weasel 为 GPL-3.0，雾凇拼音为 GPL-3.0，librime 为 BSD-3-Clause。分发包含这些组件的构建时，必须遵守各自许可证及其依赖项的要求。pyIME 自有代码的许可证将在添加自有实现时另行确定。

## 进展日志

每次任务结束时，在 [`log/`](./log/) 中追加进展记录，包含完成事项、验证结果、阻塞项和下一步。按北京时间每日一个文件，具体约定见 [日志说明](./log/README.md)。

每次任务或阶段完成后，更新日志、验证相关改动，并主动提交和推送到当前分支的远端。同步失败须如实记录和报告，不强制推送或提交无关改动。