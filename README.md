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

请先按 [Weasel 构建说明](https://github.com/rime/weasel/blob/master/INSTALL.md)安装 Windows C++ 桌面构建环境、CMake、clang-format 和 Boost，并配置 `BOOST_ROOT`。首次构建前，先初始化所有上游子模块。

```powershell
cd vendor\weasel
Copy-Item env.bat.template env.bat
# 编辑 env.bat，设置 BOOST_ROOT 为本机 Boost 目录
.\build.bat all
```

安装包由上游构建流程输出到 `vendor\weasel\output\archives`。安装输入法后，可通过开始菜单中的小狼毫工具打开用户文件夹。

## 使用雾凇拼音配置

雾凇拼音配置位于 `config\rime-ice`。首次替换 Rime 用户配置前，先从小狼毫工具打开用户文件夹并备份现有 `%APPDATA%\Rime` 内容；然后按[雾凇拼音说明](https://github.com/iDvel/rime-ice#安装)部署配置，并在小狼毫中执行“重新部署”。不要直接删除未备份的用户配置或词库。

## 许可证

上游组件各自适用其仓库中的许可证：Weasel 为 GPL-3.0，雾凇拼音为 GPL-3.0，librime 为 BSD-3-Clause。分发包含这些组件的构建时，必须遵守各自许可证及其依赖项的要求。pyIME 自有代码的许可证将在添加自有实现时另行确定。

## 进展日志

每次任务结束时，在 [`log/`](./log/) 中追加进展记录，包含完成事项、验证结果、阻塞项和下一步。按北京时间每日一个文件，具体约定见 [日志说明](./log/README.md)。

每次任务或阶段完成后，更新日志、验证相关改动，并主动提交和推送到当前分支的远端。同步失败须如实记录和报告，不强制推送或提交无关改动。