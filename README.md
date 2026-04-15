# feature-nav.nvim

基于 GitNexus 的代码功能特性导航 - Neovim 插件

## 安装

### lazy.nvim

```lua
-- 本地开发
{ dir = "~/source/feature-nav.nvim" }

-- 或从 GitHub
{ "skilldag/feature-nav.nvim" }
```

### 复制文件

```bash
cp -r . ~/.config/nvim/lua/feature-nav/
```

然后在 `init.lua` 中：

```lua
require("feature-nav").setup()
```

## 使用

命令：

- `:FeatureNav` - 打开导航
- `:FeatureNavSearch [query]` - 搜索
- `:FeatureNavRefresh` - 刷新
- `:FeatureNavClose` - 关闭

快捷键：

- `<Leader>nl` - 打开 Label 导航
- `<Leader>nq` - 语义搜索

## 依赖

- Neovim 0.9+
- Node.js 18+ (用于 `feature-tool.js` CLI)

## CLI 配套

配套 [feature-nav](https://github.com/skilldag/feature-nav) 使用：

```bash
npm install -g feature-nav
```
