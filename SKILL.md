# Feature Navigation Skill

基于 GitNexus + LLM 的代码功能特性导航系统。

## 核心理念

**结构分析 (GitNexus) + 语义理解 (LLM) = 智能代码导航**

- GitNexus 提供精确的代码位置和调用关系
- LLM 提供语义化的功能理解和业务场景
- 两者结合实现从功能描述到代码实现的智能跳转

## 架构（单一真源）

- **库表与业务逻辑**只在 **`feature-tool.js`**（Node + `better-sqlite3`）里维护；**Neovim**（`fzfnav.lua`）也只调这个脚本。
- 仓库里的 **`.sh` / `feature_tool.py`** 是历史或**独立工作流**（例如 `llm-analyze.sh` 批处理、`parse-gitnexus.sh` 旧解析），**不是**插件依赖；新功能请加在 Node，避免再复制一份 SQL。
- **`init-db.sh`** 已与 Node 对齐：`init` 等价于 `node feature-tool.js init`（删库文件后按 `initDatabase()` 建表）；`verify` / `backup` 仍用 `sqlite3` 做运维。

## 命令 (通过 `fn` CLI)

```bash
fn [-r <repo>] <command> [args...]
```

**全局选项**:
- `-r, --repo <name>`: 指定仓库名，可从任意目录运行

**命令别名**:
- `label` → `ls`
- `sync` → `s`
- `search` → `sr`
- `status` → `st`
- `processes` → `p`
- `modules` → `m`
- `process-next` → `n`

**核心命令**:

| 命令 | 说明 |
|------|------|
| `sync [repo]` | 同步数据 (默认当前目录) |
| `sync --clean` | 清空后全量同步 |
| `ls [name]` | 列出/查看 labels |
| `ls --init` | 初始化 label 表 |
| `ls --next` | 获取下一个待标注 label |
| `save-label <label> <json>` | 保存 Label 级标注 |
| `sr <query>` | 语义搜索 |
| `st` | 查看状态 |
| `p <label>` | 查看 label 下的流程 |
| `m <label>` | 查看 label 下的跳转目标 |
| `n [label]` | 下一条待标注 process |
| `enrich` | 导出 JSON 供 LLM 分析 |
| `import-enrich <json>` | 导入 LLM 分析结果 |

## Process 级 LLM（每个流程单独标）

- **Label** 的 `save-label` 只写 `label_annotations`，**不会**自动填各 Process。
- 标完 Label 后应对该 Label 下每条 Process：`label <Name>` 的 JSON 里会有 **`unannotated_processes`**（`id` 列表）；或循环执行 **`process-next`** / **`process-next <Label键>`** 取 `entity` + `steps` + `jump_targets`，再 **`save-process <id> '{"feature_name":"…","feature_description":"…","core_logic_summary":"…","complexity":3}'`**。
- `processes <label>` 返回的每条 Process 现含 **`llm_feature_name`** 等，便于看哪些已标。

## 数据层级

| 层级 | 数量 | 说明 |
|------|------|------|
| **Label** | 24 | 功能分类(Clustering, Skill, Api...) |
| **Community** | 161 | Label 下的代码模块 |
| **Process** | 50 | 调用关系 |

## 使用示例

```bash
# 同步数据
fn sync ~/source/skilldag
fn s                 # 当前目录

# 查看标注进度
fn st

# 语义搜索
fn sr 聚类

# 查看 Label 详情
fn ls Skill

# LLM Enrichment 流程
fn enrich > /tmp/c.json       # 导出 JSON
fn import-enrich '[...]'      # 导入 LLM 结果
fn ls --init                 # 重新初始化
fn ls                        # 查看优化后的 features

# 从任意目录调用
fn -r ts-opencode ls
fn -r ts-opencode st
```

## 标注结果 (24 Labels)

| Label | 名称 | 功能 |
|------|------|------|
| Clustering | 聚类算法 | 实现数据聚类功能 |
| Skill | Skill实现 | Skill定义和执行引擎 |
| Api | API接口 | REST API接口定义 |
| Installer | 安装器 | 应用和依赖安装 |
| Infrastructure | 基础设施 | 底层技术组件 |
| Loader | 加载器 | 配置和资源加载 |
| Domain | 领域模型 | 业务领域实体 |
| Commands | CLI命令 | 命令行接口 |
| App | 应用程序 | 应用主程序 |
| Client | 客户端集成 | 外部服务客户端 |
| Application | 业务应用 | 业务场景应用层 |
| Task | 任务调度 | 异步任务执行 |
| Skillhub | Skill中心 | Skill注册分发 |
| Server | HTTP服务器 | HTTP服务端 |
| Config | 配置管理 | 应用配置管理 |
| Integration | 集成 | 第三方系统集成 |
| Cli | CLI框架 | 命令行框架 |
| Provider | 提供者 | 服务提供者抽象 |
| Parser | 解析器 | 文本和DSL解析 |
| Llmclient | LLM客户端 | 大语言模型客户端 |
| Cluster | 微聚类 | 细粒度代码聚类 |
| Storage | 存储 | 数据持久化 |
| Event | 事件系统 | 事件驱动机制 |
| Batch-upload | 批量上传 | 批量数据上传 |

## 搜索示例

```bash
# 搜索"聚类"
$ node feature-tool.js search 聚类

{
  "results": [
    {
      "type": "label",
      "label": "Clustering",
      "feature_name": "聚类算法",
      "feature_description": "实现数据聚类功能",
      "core_logic": "K-Means等聚类算法",
      "use_cases": "数据分类",
      "community_count": 31
    }
  ],
  "count": 1
}
```

## 数据库

- **位置**: `~/.feature_nav/db/*.db`
- **工具**: `feature-tool.js` 或通过 `fn` CLI

## 安装

```bash
cd ~/.agents/skills/feature-nav/scripts && npm link
```

安装后可在任何位置使用 `fn` 命令。

## LLM Enrichment 工作流

当 GitNexus 返回的 `heuristicLabel` 与 `label` 相同时，使用 LLM 进行语义标注：

```bash
# 1. 导出 communities
fn enrich > /tmp/communities.json

# 2. 使用 OpenCode/LLM 分析后，更新 heuristic_label
# 例如: [{"id":"community_comm_76","new_label":"Auth"}, ...]

# 3. 导入更新
fn import-enrich '[...]'

# 4. 重新初始化 label 表
fn ls --init

# 5. 查看优化后的 features
fn ls
```