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
require("feature-nav").setup({
    tool_path = "/path/to/feature-tool.js",
})
```

## 配置

| 选项        | 说明         | 默认值                                                 |
| ----------- | ------------ | ------------------------------------------------------ |
| `tool_path` | CLI 工具路径 | `~/.agents/skills/feature-nav/scripts/feature-tool.js` |

或通过环境变量配置：

```bash
export FEATURE_NAV_TOOL=/custom/path/feature-tool.js
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

需要配合 [feature-nav](https://github.com/skilldag/feature-nav) CLI 使用：

```bash
# 克隆 CLI 工具
git clone https://github.com/skilldag/feature-nav.git ~/feature-nav

# 安装依赖并链接
cd ~/feature-nav
npm install
npm link

# 验证安装
fn --help
```

或使用环境变量指定路径：

```bash
export FEATURE_NAV_TOOL=~/feature-nav/feature-tool.js
```
