# 安装包输出目录

以后产出的安装包统一放在本目录。

运行 [`scripts/build.ps1`](../scripts/build.ps1) 后，脚本会将上游生成的安装包复制到这里，核对 SHA-256，并输出最终路径。同名安装包会被最新成功构建覆盖。

当前安装包为 `星河输入法-0.17.4.0-setup.exe`。中文名为“星河输入法”，英文品牌为 `Stellar River`，完整英文产品名为 `Stellar River IME`。安装界面、Windows 输入法显示名、开始菜单和设置窗口均使用此品牌；已加入默认简体拼音、左右 Shift 中英文切换、白底横向 5 候选及蓝色选中圆角样式，尚未集成雾凇拼音所需的 Lua 插件。

旧名 `weasel-0.17.4.0-installer.exe` 是此前的测试构建，已移至本地 `legacy` 子目录，不是本次星河品牌安装包。请使用上述新文件。内部程序文件名及 TSF 标识保留上游兼容性，不影响显示名称。

运行 [`scripts/test-profile.ps1`](../scripts/test-profile.ps1) 可验证安装包中的配置及输入行为，并生成 `candidate-preview.png`；预览来自实际的原生 Weasel 候选窗，不是模拟图片。

安装包二进制仅保存在本地，不提交到 Git；本说明文件用于保留目录及其用途。
