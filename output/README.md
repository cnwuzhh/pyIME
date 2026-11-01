# 安装包输出目录

以后产出的安装包统一放在本目录。

运行 [`scripts/build.ps1`](../scripts/build.ps1) 后，脚本会将上游生成的安装包复制到这里，核对 SHA-256，并输出最终路径。同名安装包会被最新成功构建覆盖。

当前文件名为 `weasel-0.17.4.0-installer.exe`。此阶段仍使用 Weasel 品牌，已加入默认简体拼音、左右 Shift 中英文切换、白底横向 5 候选及蓝色选中圆角样式，尚未集成雾凇拼音所需的 Lua 插件。

运行 [`scripts/test-profile.ps1`](../scripts/test-profile.ps1) 可验证安装包中的配置及输入行为，并生成 `candidate-preview.png`；预览来自实际的原生 Weasel 候选窗，不是模拟图片。

安装包二进制仅保存在本地，不提交到 Git；本说明文件用于保留目录及其用途。
