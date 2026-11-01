# pyIME

一个面向 Windows 的中文输入法项目，目标是逐步打磨接近主流商业输入法的使用体验。

## 当前基线

项目以成熟的开源组件为起点，而不是从零实现 Windows 文本服务：

- [`vendor/weasel`](https://github.com/rime/weasel)：小狼毫 Windows TSF 前端，负责系统集成、候选窗和部署工具。
- [`vendor/weasel/librime`](https://github.com/rime/librime)：Rime 输入法引擎，作为 Weasel 的上游子模块固定版本。
- [`config/rime-ice`](https://github.com/iDvel/rime-ice)：雾凇拼音方案与词库，作为独立子模块固定版本。

Weasel 和雾凇拼音保留各自的上游代码与许可证。当前仓库只是可复现的上游基线，尚未包含 pyIME 自有的 TSF 代码或搜狗兼容功能。

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

原始构建日志输出到 `.build\build-*.log`，安装包输出到 `vendor\weasel\output\archives`。工具缓存和编译产物不提交到 Git。此阶段构建的是上游 Weasel 安装包，尚未改为 pyIME 品牌或集成雾凇拼音；输入法安装与配置部署另行执行。安装后，可通过开始菜单中的小狼毫工具打开用户文件夹。更多上游细节见 [Weasel 构建说明](https://github.com/rime/weasel/blob/master/INSTALL.md)。

上游脚本会临时改写 OpenCC 的 CMake 文件并删除 librime 的占位文件；构建入口在运行前保存其原始字节，结束时恢复，避免源码变脏。Weasel 子模块设置 `ignore = untracked`，只忽略未跟踪的构建输出，已跟踪源码改动和子模块版本变化仍会显示。

## 使用雾凇拼音配置

雾凇拼音配置位于 `config\rime-ice`。首次替换 Rime 用户配置前，先从小狼毫工具打开用户文件夹并备份现有 `%APPDATA%\Rime` 内容；然后按[雾凇拼音说明](https://github.com/iDvel/rime-ice#安装)部署配置，并在小狼毫中执行“重新部署”。不要直接删除未备份的用户配置或词库。

## 许可证

上游组件各自适用其仓库中的许可证：Weasel 为 GPL-3.0，雾凇拼音为 GPL-3.0，librime 为 BSD-3-Clause。分发包含这些组件的构建时，必须遵守各自许可证及其依赖项的要求。pyIME 自有代码的许可证将在添加自有实现时另行确定。

## 进展日志

每次任务结束时，在 [`log/`](./log/) 中追加进展记录，包含完成事项、验证结果、阻塞项和下一步。按北京时间每日一个文件，具体约定见 [日志说明](./log/README.md)。

每次任务或阶段完成后，更新日志、验证相关改动，并主动提交和推送到当前分支的远端。同步失败须如实记录和报告，不强制推送或提交无关改动。