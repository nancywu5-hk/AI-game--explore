# AI 游戏资产版本管理存档

这个仓库存放「游戏资产版本管理工作台」和它套用的开源游戏源码。

## 开源游戏

[EliasSteffen/Wool](https://github.com/EliasSteffen/Wool)

- 引擎：Godot 4.7，主场景 `res://scenes/levels/level_1.tscn`
- 许可：MIT
- 版权：Copyright (c) 2025 E. Steffen, Mischa
- 本地路径：`games/Wool`
- 放进来的是脚本、场景、角色、地图、UI 和音效
- 没有放营销片、安装包和 IDE 配置

## 工作台

用浏览器打开 `outputs/游戏资产版本管理工作台.html`。

角色、关卡、按钮和音效都指向 `games/Wool` 里的真实文件。Sprint 卡是工作台盖在这棵树上的验收合同，不是上游仓库自己的迭代记录。

多人多 Agent 的规则不变：可以并行看图和读关卡，签认和提交串行。版本 Agent 在真人签认前不写入本仓库。
