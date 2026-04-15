-- fzfnav.lua - GitNexus Label 导航（label_annotations；Community/Process 行在表 gitnexus_entity）
-- 左 Label 列表 ｜ 右上: Label 详情 + Process ｜ 右下: 代码预览（入口 + 执行链）
-- 嵌入「代码预览」默认只列链条路径；**P** 浮窗内可看代码；[ ] / Ctrl+p,n、1-9 换段；Enter 打开源码。

local M = {}

local function get_project_name()
	local cwd = vim.fn.getcwd()
	local real_path = vim.fn.resolve(cwd)
	local project_name = real_path:match("([^/]+)$")
	return project_name or "default"
end

local config = {
	tool_path = os.getenv("HOME") .. "/.agents/skills/feature-nav/scripts/feature-tool.js",
    left_width_ratio = 0.32,
    --- 右侧上半部分高度占整列高度的比例（余下为代码区）
    preview_top_ratio = 0.44,
    --- 上半行内「详情」宽度占右侧总宽的比例
    detail_in_right_ratio = 0.52,
    --- 代码预览：目标行上下各显示行数
    code_context_lines = 14,
    --- 浮窗预览：更大上下文
    popout_context_lines = 28,
    --- 嵌入的「代码预览」窗：false 时只列链条（入口/步 + 路径），不 read_file；看代码用 P 浮窗
    embed_show_code_snippet = false,
    --- 仅列链条时 tag 列宽（字符）
    embed_chain_tag_width = 32,
}

--- JSON null → vim.NIL；vim.NIL 在 Lua 中为 truthy，`a or b` 无法从 null 回退到 b
---@param v any
---@param default string|nil
---@return string
local function json_txt(v, default)
    if v == nil or v == vim.NIL then
        return default or ""
    end
    if type(v) == "string" then
        return v ~= "" and v or (default or "")
    end
    return tostring(v)
end

--- 左侧列表展示：优先 LLM 名称，否则 GitNexus 的 label 键（如 Clustering）
---@param row table
---@return string
local function label_row_title(row)
    local s = json_txt(row.llm_feature_name, "")
    if s ~= "" then
        return s
    end
    return json_txt(row.label, "?")
end

--- 调 feature-tool 用的 label 主键（GitNexus 类名）
---@param row table
---@return string|nil
local function label_gitnexus_key(row)
    local k = json_txt(row.label, "")
    return k ~= "" and k or nil
end

--- JSON 数组：null → 空表；vim.NIL 在 `x or {}` 里会阻断回退，不能用 `#(x or {})` 偷懒
---@param v any
---@return table
local function json_array(v)
    if v == nil or v == vim.NIL or type(v) ~= "table" then
        return {}
    end
    return v
end

--- Process 行展示：有 LLM 名则前置；否则 gitnexus_id / label
---@param p table
---@return string
local function process_row_title(p)
    local llm = json_txt(p.llm_feature_name, "")
    local gid = json_txt(p.gitnexus_id, "")
    local theme = json_txt(p.gitnexus_label, "")
    local core = nil
    if gid ~= "" then
        local show = gid
        if #show > 24 then
            show = show:sub(1, 21) .. "…"
        end
        --- 流程名与 id 不同则附上，避免只重复 Clustering
        if theme ~= "" and theme ~= gid then
            local t = theme
            if #t > 14 then
                t = t:sub(1, 11) .. "…"
            end
            core = show .. " · " .. t
        else
            core = show
        end
    elseif theme ~= "" then
        core = theme
    else
        core = json_txt(p.id, "?")
    end
    if llm ~= "" then
        local short = llm
        if #short > 22 then
            short = short:sub(1, 19) .. "…"
        end
        return short .. " ← " .. core
    end
    if core then
        return core
    end
    return json_txt(p.id, "?")
end

--- symbol_id 取最后一段作简短名（Function:path:Name → Name）
---@param symbol_id string
---@return string
local function symbol_id_tail(symbol_id)
    local s = json_txt(symbol_id, "")
    if s == "" then
        return "?"
    end
    local tail = s:match("([^:]+)$")
    return tail or s
end

--- 入口 + process_steps 全量列表（含无路径步，便于对照 DB）；仅 jumpable 可预览/Enter
---@param p table
---@return table[]
local function build_process_chain_locations(p)
    local locs = {}
    local jlist = json_array(p.jump_targets)
    local jt = jlist[1]
    if jt and json_txt(jt.file_path, "") ~= "" then
        table.insert(locs, {
            tag = "入口",
            file_path = json_txt(jt.file_path, ""),
            line_number = tonumber(jt.line_number) or 1,
            jumpable = true,
        })
    end
    local steps = json_array(p.steps)
    for i, st in ipairs(steps) do
        local sym = symbol_id_tail(json_txt(st.symbol_id, ""))
        local fp = json_txt(st.file_path, "")
        local ln = tonumber(st.line_number)
        if ln == nil then
            ln = 1
        end
        local tag = string.format("步%d · %s", i, sym)
        if fp ~= "" then
            table.insert(locs, {
                tag = tag,
                file_path = fp,
                line_number = ln,
                jumpable = true,
            })
        else
            table.insert(locs, {
                tag = tag .. " (无路径)",
                file_path = "",
                line_number = ln,
                jumpable = false,
                symbol_id = json_txt(st.symbol_id, ""),
            })
        end
    end
    return locs
end

--- 标签条用的短文案（避免一行过长）
---@param L table
---@param i integer
---@return string
local function chain_tab_short_label(L, i)
    local tag = json_txt(L.tag, "")
    if tag == "入口" then
        return "入"
    end
    local stepn = tag:match("^步(%d+)")
    if stepn then
        return stepn
    end
    if #tag <= 6 then
        return tag
    end
    return tag:sub(1, 5) .. "…"
end

--- 单行「页面标签」：当前项用 [·] 包起来
---@param locs table[]
---@param current integer
---@param max_cols integer|nil
---@return string
local function format_chain_tab_bar(locs, current, max_cols)
    max_cols = max_cols or 64
    if #locs == 0 then
        return ""
    end
    local function build(compact)
        local chunks = {}
        for i, L in ipairs(locs) do
            local lab = compact and tostring(i) or chain_tab_short_label(L, i)
            if i == current then
                table.insert(chunks, "[" .. lab .. "]")
            else
                table.insert(chunks, lab)
            end
        end
        return " « " .. table.concat(chunks, " ") .. " » "
    end
    local s = build(false)
    if #s > max_cols then
        s = build(true)
    end
    return s
end

local state = {
    win_left = nil,
    win_detail = nil,
    win_process = nil,
    win_code = nil,
    buf_left = nil,
    buf_detail = nil,
    buf_process = nil,
    buf_code = nil,
    --- 代码预览浮窗（独立居中窗口，P 打开）
    buf_popout = nil,
    win_popout = nil,
    current_view = "labels",
    labels = {},
    selected_idx = 1,
    repo_root = nil,
    detail_cache = {},
    search_items = {},
    search_selected_idx = 1,
    ---@type table[] 当前 Label 下 processes 命令结果
    processes_for_label = {},
    process_selected_idx = 1,
    ---@type { file_path: string, line_number: integer }|nil
    code_jump_ref = nil,
    --- 当前 Process 预览：链条上选中的位置 1..n
    chain_loc_idx = 1,
    --- 用于切换 Process 时重置 chain_loc_idx
    last_chain_process_id = nil,
    --- 预览标签浏览历史（chain_loc_idx 序列），配合 H / L
    ---@type integer[]
    preview_hist = {},
    preview_hist_pos = 1,
    --- fill_code_buffer 时若为 true，不向 preview_hist 写入
    preview_hist_silent = false,
}

local function close_code_popout()
    if state.win_popout and vim.api.nvim_win_is_valid(state.win_popout) then
        vim.api.nvim_win_close(state.win_popout, true)
    end
    state.win_popout = nil
    if state.buf_popout and vim.api.nvim_buf_is_valid(state.buf_popout) then
        vim.api.nvim_buf_delete(state.buf_popout, { force = true })
    end
    state.buf_popout = nil
end

local function close_all_wins()
    close_code_popout()
    for _, w in ipairs({ state.win_left, state.win_detail, state.win_process, state.win_code }) do
        if w and vim.api.nvim_win_is_valid(w) then
            vim.api.nvim_win_close(w, true)
        end
    end
    state.win_left = nil
    state.win_detail = nil
    state.win_process = nil
    state.win_code = nil
    state.buf_left = nil
    state.buf_detail = nil
    state.buf_process = nil
    state.buf_code = nil
    state.code_jump_ref = nil
    state.chain_loc_idx = 1
    state.last_chain_process_id = nil
    state.preview_hist = {}
    state.preview_hist_pos = 1
    state.preview_hist_silent = false
end

--- 前向声明：open_code_popout 早于本文件后部定义，其内 vim.schedule 闭包须捕获此局部，否则会当成全局 chain_nav → nil
local chain_nav, chain_goto

---@param argv string[]
local function run_tool(argv)
	local parts = { "node", config.tool_path, "--repo", get_project_name() }
	vim.list_extend(parts, argv)
    local shell = {}
    for _, p in ipairs(parts) do
        table.insert(shell, vim.fn.shellescape(p))
    end
    local output = vim.fn.system(table.concat(shell, " "))
    local ok, result = pcall(vim.fn.json_decode, output)
    if ok then
        return result
    end
    return { status = "error", message = output }
end

local function resolve_workspace_path(p)
    if not p or p == "" then
        return nil
    end
    if vim.fn.filereadable(p) == 1 then
        return vim.fn.fnamemodify(p, ":p")
    end
    local root = state.repo_root or vim.fn.getcwd()
    local joined = vim.fs.joinpath(root, p)
    if vim.fn.filereadable(joined) == 1 then
        return vim.fn.fnamemodify(joined, ":p")
    end
    local trimmed = p:gsub("^%./", "")
    joined = vim.fs.joinpath(root, trimmed)
    if vim.fn.filereadable(joined) == 1 then
        return vim.fn.fnamemodify(joined, ":p")
    end
    return nil
end

---@param path string
---@param center_line integer
---@param ctx integer
---@return string[]|nil lines
---@return string|nil resolved_path
---@return integer|nil mark_buf_line 预览缓冲区内「目标行」的 1-based 行号（供 zz 居中）
local function read_code_snippet(path, center_line, ctx)
    local full = resolve_workspace_path(path)
    if not full or vim.fn.filereadable(full) ~= 1 then
        return nil, nil, nil
    end
    local lines = vim.fn.readfile(full)
    if not lines or #lines == 0 then
        return { " (空文件) " }, full, 1
    end
    local n = #lines
    center_line = math.max(1, math.min(tonumber(center_line) or 1, n))
    local lo = math.max(1, center_line - ctx)
    local hi = math.min(n, center_line + ctx)
    local out = {
        string.format(" %s (行 %d) ", vim.fn.fnamemodify(full, ":t"), center_line),
        string.rep("─", math.min(60, #lines[1] + 20)),
    }
    for i = lo, hi do
        local mark = (i == center_line) and "▶" or " "
        table.insert(out, string.format("%s %4d │ %s", mark, i, lines[i]))
    end
    --- 前两行是标题/分隔线，代码从第 3 行起；▶ 所在行 = 3 + (center_line - lo)
    local mark_buf_line = 3 + (center_line - lo)
    return out, full, mark_buf_line
end

---@param t { file_path: string, line_number?: integer }
local function open_jump_target(t)
    local path = resolve_workspace_path(t.file_path)
    if not path or vim.fn.filereadable(path) ~= 1 then
        vim.notify("无法打开文件: " .. tostring(t.file_path), vim.log.levels.WARN)
        return
    end
    local line = tonumber(t.line_number) or 1
    close_all_wins()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    if line > 1 then
        vim.fn.cursor(line, 1)
    end
    vim.cmd("normal! zz")
end

local function jump_to_label_modules(label_name)
    if not label_name or label_name == "" then
        return
    end
    local result = run_tool({ "modules", label_name })
    if result.status ~= "success" then
        vim.notify("feature-nav: " .. tostring(result.message or "modules 失败"), vim.log.levels.WARN)
        return
    end
    local targets = result.targets or {}
    if #targets == 0 then
        local comm = result.communities or {}
        if #comm > 0 then
            local np = #(result.processes or {})
            vim.notify(
                string.format(
                    "该 Label 含 %d 个 Community、%d 个 Process，但尚无 jump_targets。",
                    #comm,
                    np
                ),
                vim.log.levels.INFO
            )
        else
            vim.notify("未找到该 Label 下的跳转目标", vim.log.levels.WARN)
        end
        return
    end
    if #targets == 1 then
        open_jump_target(targets[1])
        return
    end
    vim.ui.select(targets, {
        prompt = "打开位置 (C=Community P=Process)",
        format_item = function(it)
            local ft = it.feature_type or "community"
            local tag = (ft == "process") and "P" or "C"
            return string.format("[%s] %s:%s", tag, it.file_path or "?", tostring(it.line_number or 1))
        end,
    }, function(choice)
        if choice then
            open_jump_target(choice)
        end
    end)
end

local function fill_detail_buffer(label_name)
    if not state.buf_detail or not vim.api.nvim_buf_is_valid(state.buf_detail) then
        return
    end
    if not label_name or label_name == "" then
        vim.api.nvim_buf_set_option(state.buf_detail, "modifiable", true)
        vim.api.nvim_buf_set_lines(state.buf_detail, 0, -1, false, {
            " Label 详情 ",
            " ─── ",
            "",
            " ← 左侧选一项 Label",
        })
        vim.api.nvim_buf_set_option(state.buf_detail, "modifiable", false)
        return
    end

    local cached = state.detail_cache[label_name]
    if not cached then
        local result = run_tool({ "label", label_name })
        if result.status ~= "success" or result.label == nil or result.label == vim.NIL then
            vim.api.nvim_buf_set_option(state.buf_detail, "modifiable", true)
            vim.api.nvim_buf_set_lines(state.buf_detail, 0, -1, false, {
                " Label 详情 ",
                " ─── ",
                "",
                " ⚠ " .. tostring(label_name),
            })
            vim.api.nvim_buf_set_option(state.buf_detail, "modifiable", false)
            return
        end
        cached = result.label
        state.detail_cache[label_name] = cached
    end

    local label = cached
    --- 与左侧列表一致：无 LLM 名称时用 GitNexus label（如 Clustering）
    local title = label_row_title({
        llm_feature_name = label.llm_feature_name,
        label = label.label,
    })
    local display_name = json_txt(label.llm_feature_name, "")
    local desc = json_txt(label.llm_feature_description, "")
    local core = json_txt(label.llm_core_logic_summary, "")
    local uses = json_txt(label.llm_use_cases, "")
    local has_llm_body = display_name ~= "" or desc ~= "" or core ~= "" or uses ~= ""

    local lines = {
        string.format(" %s ", title),
        string.rep("─", 28),
    }
    if has_llm_body then
        table.insert(lines, string.format("Label 键: %s", json_txt(label.label, "?")))
        table.insert(lines, string.format("展示名: %s", display_name ~= "" and display_name or "—"))
        table.insert(lines, string.format("描述: %s", desc ~= "" and desc or "—"))
        table.insert(lines, string.format("核心: %s", core ~= "" and core or "—"))
        table.insert(lines, string.format("场景: %s", uses ~= "" and uses or "—"))
    else
        table.insert(lines, string.format(" Label 键: %s", json_txt(label.label, "?")))
        table.insert(lines, " （label_annotations 中 LLM 字段为空，可 save-label 写入）")
        table.insert(lines, " save-label 可补展示名/描述/核心/场景")
    end
    table.insert(lines, string.format("复杂度: %s/5", json_txt(label.llm_complexity, "3")))
    table.insert(lines, string.format("C×%d  P×%d", label.n_communities or 0, label.n_processes or 0))

    vim.api.nvim_buf_set_option(state.buf_detail, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_detail, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(state.buf_detail, "modifiable", false)
    if state.win_detail and vim.api.nvim_win_is_valid(state.win_detail) then
        vim.api.nvim_win_call(state.win_detail, function()
            vim.cmd("normal! gg")
        end)
    end
end

--- 预览「标签」访问历史：与 [/] 循环配合，H/L 在记录中后退/前进
---@param idx integer
local function preview_hist_reset(idx)
    state.preview_hist = { idx }
    state.preview_hist_pos = 1
end

---@param new_idx integer
local function preview_hist_record_from_cycle(new_idx)
    if state.preview_hist_silent then
        return
    end
    local hist = state.preview_hist
    local pos = state.preview_hist_pos or 1
    if not hist or #hist == 0 then
        preview_hist_reset(new_idx)
        return
    end
    if pos < #hist and hist[pos + 1] == new_idx then
        state.preview_hist_pos = pos + 1
        return
    end
    if pos > 1 and hist[pos - 1] == new_idx then
        state.preview_hist_pos = pos - 1
        return
    end
    while #hist > pos do
        table.remove(hist)
    end
    if hist[pos] ~= new_idx then
        table.insert(hist, new_idx)
        state.preview_hist_pos = #hist
    end
end

local function preview_hist_back()
    if state.preview_hist_pos <= 1 then
        return
    end
    state.preview_hist_pos = state.preview_hist_pos - 1
    state.chain_loc_idx = state.preview_hist[state.preview_hist_pos]
    state.preview_hist_silent = true
    fill_code_buffer()
    state.preview_hist_silent = false
end

local function preview_hist_forward()
    local hist = state.preview_hist
    if not hist or state.preview_hist_pos >= #hist then
        return
    end
    state.preview_hist_pos = state.preview_hist_pos + 1
    state.chain_loc_idx = hist[state.preview_hist_pos]
    state.preview_hist_silent = true
    fill_code_buffer()
    state.preview_hist_silent = false
end

local function fill_code_empty(msg)
    if not state.buf_code or not vim.api.nvim_buf_is_valid(state.buf_code) then
        return
    end
    state.code_jump_ref = nil
    state.preview_hist = {}
    state.preview_hist_pos = 1
    vim.api.nvim_buf_set_option(state.buf_code, "filetype", "fzfnav")
    vim.api.nvim_buf_set_option(state.buf_code, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_code, 0, -1, false, {
        " 代码预览 ",
        " ─── ",
        "",
        " " .. (msg or "（无）"),
    })
    vim.api.nvim_buf_set_option(state.buf_code, "modifiable", false)
    close_code_popout()
end

--- 链条列表行（嵌入 / 浮窗头部共用）
---@param locs table[]
---@param idx integer 当前段
---@param tag_w integer
---@return string[]
local function build_chain_list_lines(locs, idx, tag_w)
    local out = {}
    for i, L in ipairs(locs) do
        local mark = (i == idx) and "▶" or " "
        local fp = L.file_path
        if fp ~= "" and #fp > 56 then
            fp = fp:sub(1, 53) .. "…"
        end
        if fp ~= "" then
            table.insert(
                out,
                string.format("%s %2d. %-" .. tag_w .. "s  %s:%d", mark, i, L.tag, fp, L.line_number)
            )
        else
            table.insert(out, string.format("%s %2d. %s", mark, i, L.tag))
        end
    end
    return out
end

--- 组装嵌入区/浮窗共用的预览文本
---@param p table|nil
---@param display_chain_idx integer
---@param tab_w integer
---@param code_ctx_lines integer
---@param footer_kind string "embed" | "popout"
---@return string[]|nil merged, integer|nil mark_buf_line, table|nil jump_ref
local function compose_code_preview_lines(p, display_chain_idx, tab_w, code_ctx_lines, footer_kind)
    if not p then
        return nil
    end
    local locs = build_process_chain_locations(p)
    if #locs == 0 then
        return nil
    end
    local idx = math.max(1, math.min(display_chain_idx, #locs))
    local loc = locs[idx]

    local sep_w = math.min(50, math.max(28, math.floor((vim.o.columns or 80) * 0.25)))
    local sep = string.rep("─", sep_w)

    local list_only_embed = footer_kind == "embed" and not config.embed_show_code_snippet

    if list_only_embed then
        local tag_w = math.max(18, tonumber(config.embed_chain_tag_width) or 32)
        local merged = {
            string.format(
                " 链 %d/%d · [ ] Ctrl+p n · 1-9 · P 浮窗看代码 · Enter 打开 · H/L 历史 ",
                idx,
                #locs
            ),
            sep,
        }
        vim.list_extend(merged, build_chain_list_lines(locs, idx, tag_w))
        table.insert(merged, sep)
        table.insert(merged, "")
        table.insert(
            merged,
            " 本窗仅列表；按 P 弹出可读代码的浮窗 · Tab 切窗 · q 关全部 "
        )
        local mark_buf_line = 2 + idx
        local jump_ref = nil
        if loc.jumpable then
            jump_ref = { file_path = loc.file_path, line_number = loc.line_number }
        end
        return merged, mark_buf_line, jump_ref
    end

    local tab_line = format_chain_tab_bar(locs, idx, tab_w)
    local header = {
        tab_line ~= "" and tab_line or " （无标签）",
        string.format(
            " 第 %d/%d 段 · [ 或 Ctrl+p 上一段 · ] 或 Ctrl+n 下一段 · 1-9 跳到第 n 段 · H/L 预览浏览历史 ",
            idx,
            #locs
        ),
        sep,
    }
    vim.list_extend(header, build_chain_list_lines(locs, idx, 18))
    table.insert(header, string.rep("─", math.min(50, math.max(28, #(header[2] or "")))))

    local snippet
    local mark_buf_line
    local jump_ref
    if loc.jumpable then
        snippet, _, mark_buf_line = read_code_snippet(loc.file_path, loc.line_number, code_ctx_lines)
        if not snippet then
            snippet = {
                " (无法读文件) ",
                " " .. loc.file_path,
            }
            mark_buf_line = 1
        end
        jump_ref = { file_path = loc.file_path, line_number = loc.line_number }
    else
        snippet = {
            " (此步无 file_path，无法预览) ",
            " symbol_id: " .. json_txt(loc.symbol_id, "—"),
            "",
            " 可 sync 仓库以补全 process_steps ",
        }
        mark_buf_line = 1
        jump_ref = nil
    end

    local merged = {}
    for _, L in ipairs(header) do
        table.insert(merged, L)
    end
    local header_len = #merged
    for _, L in ipairs(snippet) do
        table.insert(merged, L)
    end
    if mark_buf_line then
        mark_buf_line = header_len + mark_buf_line
    end
    table.insert(merged, "")
    if footer_kind == "popout" then
        table.insert(
            merged,
            " 浮窗 · Ctrl+p/n 或 Alt+p/n 换段 · [/] · 1-9 · H/L · Enter 打开 · Esc/q 关浮窗 · P 刷新 "
        )
    else
        table.insert(
            merged,
            " P 放大浮窗 · [/] Ctrl+p n · 1-9 · Enter 打开 · Tab 切窗 · H/L 历史 · q 关全部 "
        )
    end
    return merged, mark_buf_line, jump_ref
end

local function sync_code_popout_buffer()
    if not state.win_popout or not vim.api.nvim_win_is_valid(state.win_popout) then
        return
    end
    if not state.buf_popout or not vim.api.nvim_buf_is_valid(state.buf_popout) then
        return
    end
    local procs = state.processes_for_label
    local p = procs[state.process_selected_idx]
    local w = vim.api.nvim_win_get_width(state.win_popout)
    local merged, mark_buf_line, jump_ref = compose_code_preview_lines(
        p,
        state.chain_loc_idx,
        w,
        config.popout_context_lines,
        "popout"
    )
    if not merged then
        return
    end
    state.code_jump_ref = jump_ref
    vim.api.nvim_buf_set_option(state.buf_popout, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_popout, 0, -1, false, merged)
    vim.api.nvim_buf_set_option(state.buf_popout, "modifiable", false)
    vim.api.nvim_buf_set_option(state.buf_popout, "filetype", "fzfnav")
    pcall(vim.api.nvim_win_set_config, state.win_popout, {
        title = string.format(" 预览浮窗 %d ", state.chain_loc_idx),
        title_pos = "center",
    })
    vim.api.nvim_win_call(state.win_popout, function()
        if mark_buf_line and mark_buf_line >= 1 then
            local last = vim.api.nvim_buf_line_count(state.buf_popout)
            local row = math.min(mark_buf_line, last)
            vim.api.nvim_win_set_cursor(0, { row, 0 })
            vim.cmd("normal! zz")
        else
            vim.cmd("normal! gg")
        end
    end)
end

--- 居中浮窗：更大上下文，链操作与嵌入预览同步
local function open_code_popout()
    local procs = state.processes_for_label
    local p = procs[state.process_selected_idx]
    local locs = p and build_process_chain_locations(p) or {}
    if #locs == 0 then
        vim.notify("当前无代码可预览", vim.log.levels.INFO)
        return
    end
    close_code_popout()

    local cols = vim.o.columns or 80
    local lines = vim.o.lines or 24
    local w = math.min(110, math.max(56, cols - 8))
    local merged, mark_buf_line, jump_ref = compose_code_preview_lines(
        p,
        state.chain_loc_idx,
        w,
        config.popout_context_lines,
        "popout"
    )
    if not merged then
        return
    end
    state.code_jump_ref = jump_ref

    state.buf_popout = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(state.buf_popout, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(state.buf_popout, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_popout, 0, -1, false, merged)
    vim.api.nvim_buf_set_option(state.buf_popout, "modifiable", false)
    vim.api.nvim_buf_set_option(state.buf_popout, "filetype", "fzfnav")

    local h = math.min(lines - 4, math.max(14, #merged + 1))
    h = math.min(h, lines - 2)
    local row = math.max(0, math.floor((lines - h) / 2))
    local col = math.max(0, math.floor((cols - w) / 2))

    state.win_popout = vim.api.nvim_open_win(state.buf_popout, true, {
        relative = "editor",
        width = w,
        height = h,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " 代码预览（浮窗） ",
        title_pos = "center",
    })
    vim.api.nvim_win_set_option(state.win_popout, "wrap", false)
    vim.api.nvim_win_set_option(state.win_popout, "number", false)

    local b = state.buf_popout
    --- 浮窗内避免与全局 Ctrl 映射冲突：schedule + buffer 局部 + nowait；终端若占 Ctrl 可用 Alt+p/n
    local map_pop = { buffer = b, silent = true, nowait = true, noremap = true }
    local function pop_chain(d)
        return function()
            vim.schedule(function()
                chain_nav(d)
            end)
        end
    end
    vim.keymap.set("n", "q", close_code_popout, map_pop)
    vim.keymap.set("n", "<Esc>", close_code_popout, map_pop)
    vim.keymap.set("n", "<CR>", function()
        if state.code_jump_ref then
            open_jump_target(state.code_jump_ref)
        end
    end, map_pop)
    vim.keymap.set("n", "[", pop_chain(-1), map_pop)
    vim.keymap.set("n", "]", pop_chain(1), map_pop)
    vim.keymap.set("n", "<C-p>", pop_chain(-1), map_pop)
    vim.keymap.set("n", "<C-n>", pop_chain(1), map_pop)
    vim.keymap.set("n", "<M-p>", pop_chain(-1), map_pop)
    vim.keymap.set("n", "<M-n>", pop_chain(1), map_pop)
    for d = 1, 9 do
        local k = d
        vim.keymap.set("n", tostring(d), function()
            vim.schedule(function()
                chain_goto(k)
            end)
        end, map_pop)
    end
    vim.keymap.set("n", "H", function()
        vim.schedule(preview_hist_back)
    end, map_pop)
    vim.keymap.set("n", "L", function()
        vim.schedule(preview_hist_forward)
    end, map_pop)
    vim.keymap.set("n", "j", function()
        vim.cmd("normal! j")
    end, map_pop)
    vim.keymap.set("n", "k", function()
        vim.cmd("normal! k")
    end, map_pop)
    vim.keymap.set("n", "P", function()
        close_code_popout()
        open_code_popout()
    end, map_pop)

    vim.api.nvim_win_call(state.win_popout, function()
        if mark_buf_line and mark_buf_line >= 1 then
            local last = vim.api.nvim_buf_line_count(state.buf_popout)
            local row0 = math.min(mark_buf_line, last)
            vim.api.nvim_win_set_cursor(0, { row0, 0 })
            vim.cmd("normal! zz")
        end
    end)
end

local function fill_code_buffer()
    if not state.buf_code or not vim.api.nvim_buf_is_valid(state.buf_code) then
        return
    end
    local procs = state.processes_for_label
    local idx = state.process_selected_idx
    local p = procs[idx]
    if not p then
        state.last_chain_process_id = nil
        fill_code_empty("无 Process")
        return
    end

    local pid = json_txt(p.id, "")
    if pid ~= state.last_chain_process_id then
        state.last_chain_process_id = pid
        state.chain_loc_idx = 1
        preview_hist_reset(1)
    end

    local locs = build_process_chain_locations(p)
    if #locs == 0 then
        local ns = tonumber(p.gitnexus_step_count) or 0
        local nst = #json_array(p.steps)
        state.code_jump_ref = nil
        state.preview_hist = {}
        state.preview_hist_pos = 1
        fill_code_empty(
            string.format(
                "无可用位置（需 jump_targets 入口或 process_steps 含 file_path）。DB: step_count=%s steps行=%d",
                tostring(ns),
                nst
            )
        )
        return
    end

    state.chain_loc_idx = math.max(1, math.min(state.chain_loc_idx, #locs))

    if not state.preview_hist_silent and (#state.preview_hist == 0) then
        preview_hist_reset(state.chain_loc_idx)
    end

    local tab_w = 64
    if state.win_code and vim.api.nvim_win_is_valid(state.win_code) then
        tab_w = math.max(36, vim.api.nvim_win_get_width(state.win_code) - 2)
    end

    local merged, mark_buf_line, jump_ref =
        compose_code_preview_lines(p, state.chain_loc_idx, tab_w, config.code_context_lines, "embed")
    if not merged then
        return
    end
    state.code_jump_ref = jump_ref

    vim.api.nvim_buf_set_option(state.buf_code, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_code, 0, -1, false, merged)
    vim.api.nvim_buf_set_option(state.buf_code, "modifiable", false)
    vim.api.nvim_buf_set_option(state.buf_code, "filetype", "fzfnav")

    if state.win_code and vim.api.nvim_win_is_valid(state.win_code) then
        local title = string.format(" 链 %d/%d ", state.chain_loc_idx, #locs)
        pcall(vim.api.nvim_win_set_config, state.win_code, { title = title, title_pos = "center" })
        vim.api.nvim_win_call(state.win_code, function()
            if mark_buf_line and mark_buf_line >= 1 then
                local last = vim.api.nvim_buf_line_count(state.buf_code)
                local row = math.min(mark_buf_line, last)
                vim.api.nvim_win_set_cursor(0, { row, 0 })
                vim.cmd("normal! zz")
            else
                vim.cmd("normal! gg")
            end
        end)
    end

    sync_code_popout_buffer()
end

local function redraw_process_list()
    if not state.buf_process or not vim.api.nvim_buf_is_valid(state.buf_process) then
        return
    end
    local lines = {
        " j/k 选流程 · 预览 P 浮窗 · [ ]/Ctrl+p n 换段 · Enter 打开 ",
        string.rep("─", 22),
    }
    local procs = state.processes_for_label
    if #procs == 0 then
        table.insert(lines, " (无 Process) ")
    else
        state.process_selected_idx = math.max(1, math.min(state.process_selected_idx, #procs))
        local any_j = false
        for i, proc in ipairs(procs) do
            local gl = process_row_title(proc)
            if #gl > 32 then
                gl = gl:sub(1, 29) .. "…"
            end
            local nj = #json_array(proc.jump_targets)
            local nsteps = #json_array(proc.steps)
            if nsteps == 0 and (proc.gitnexus_step_count or 0) > 0 then
                nsteps = proc.gitnexus_step_count
            end
            if nj > 0 then
                any_j = true
            end
            local prefix = (i == state.process_selected_idx) and "▶" or " "
            local mark = (proc.association == "shared_file") and "~" or " "
            table.insert(lines, string.format(" %s%s %s  s:%s j:%d", prefix, mark, gl, tostring(nsteps), nj))
        end
        if not any_j then
            table.insert(lines, "")
            table.insert(lines, " j:0 = DB 无 jump_targets")
            table.insert(lines, " 需写入跳转索引后才有代码预览")
        end
    end
    vim.api.nvim_buf_set_option(state.buf_process, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_process, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(state.buf_process, "modifiable", false)
    if #procs > 0 then
        vim.api.nvim_win_set_cursor(state.win_process, { state.process_selected_idx + 2, 0 })
    end
    fill_code_buffer()
end

local function load_processes_for_label(label_name)
    state.processes_for_label = {}
    state.process_selected_idx = 1
    if not label_name or label_name == "" then
        redraw_process_list()
        return
    end
    local r = run_tool({ "processes", label_name })
    if r.status ~= "success" then
        state.processes_for_label = {}
        redraw_process_list()
        return
    end
    local plist = r.processes
    if plist == nil or plist == vim.NIL or type(plist) ~= "table" then
        plist = {}
    end
    state.processes_for_label = plist
    redraw_process_list()
end

--- 选中 Label 后刷新：详情 + Process 列表 + 代码
local function load_preview_for_label(label_name)
    fill_detail_buffer(label_name)
    load_processes_for_label(label_name)
end

local function refresh_detail_preview()
    if state.current_view ~= "labels" then
        return
    end
    if #state.labels == 0 then
        fill_detail_buffer(nil)
        load_processes_for_label(nil)
        return
    end
    local row = state.labels[state.selected_idx]
    if not row then
        fill_detail_buffer(nil)
        load_processes_for_label(nil)
        return
    end
    load_preview_for_label(label_gitnexus_key(row))
end

local function refresh_search_detail_preview()
    if state.current_view ~= "search" or #state.search_items == 0 then
        return
    end
    local idx = state.search_selected_idx or 1
    if idx < 1 or idx > #state.search_items then
        fill_detail_buffer(nil)
        load_processes_for_label(nil)
        return
    end
    local item = state.search_items[idx]
    local pk = item and label_gitnexus_key(item)
    if pk then
        load_preview_for_label(pk)
    end
end

local function open_split_layout()
    close_all_wins()
    state.detail_cache = {}
    state.processes_for_label = {}
    state.process_selected_idx = 1
    state.code_jump_ref = nil
    state.chain_loc_idx = 1
    state.last_chain_process_id = nil
    state.preview_hist = {}
    state.preview_hist_pos = 1
    state.preview_hist_silent = false

    local total_w = math.floor(vim.o.columns * 0.88)
    local height = math.floor(vim.o.lines * 0.74)
    local row0 = math.floor((vim.o.lines - height) / 2)
    local base_col = math.floor((vim.o.columns - total_w) / 2)

    local left_w = math.max(26, math.floor(total_w * config.left_width_ratio))
    local right_w = total_w - left_w - 1
    local col_right = base_col + left_w + 1

    local top_h = math.max(8, math.floor(height * config.preview_top_ratio))
    local code_h = height - top_h - 1

    local detail_w = math.max(20, math.floor(right_w * config.detail_in_right_ratio))
    local proc_w = right_w - detail_w - 1
    local col_detail = col_right
    local col_proc = col_right + detail_w + 1
    local row_code = row0 + top_h + 1

    state.buf_left = vim.api.nvim_create_buf(false, true)
    state.buf_detail = vim.api.nvim_create_buf(false, true)
    state.buf_process = vim.api.nvim_create_buf(false, true)
    state.buf_code = vim.api.nvim_create_buf(false, true)

    for _, b in ipairs({ state.buf_left, state.buf_detail, state.buf_process, state.buf_code }) do
        vim.api.nvim_buf_set_option(b, "bufhidden", "wipe")
        vim.api.nvim_buf_set_option(b, "filetype", "fzfnav")
    end

    state.win_left = vim.api.nvim_open_win(state.buf_left, true, {
        relative = "editor",
        width = left_w,
        height = height,
        row = row0,
        col = base_col,
        style = "minimal",
        border = "rounded",
        title = " Label ",
        title_pos = "center",
    })

    state.win_detail = vim.api.nvim_open_win(state.buf_detail, false, {
        relative = "editor",
        width = detail_w,
        height = top_h,
        row = row0,
        col = col_detail,
        style = "minimal",
        border = "rounded",
        title = " Label 详情 ",
        title_pos = "center",
    })

    state.win_process = vim.api.nvim_open_win(state.buf_process, false, {
        relative = "editor",
        width = proc_w,
        height = top_h,
        row = row0,
        col = col_proc,
        style = "minimal",
        border = "rounded",
        title = " Process ",
        title_pos = "center",
    })

    state.win_code = vim.api.nvim_open_win(state.buf_code, false, {
        relative = "editor",
        width = right_w,
        height = code_h,
        row = row_code,
        col = col_right,
        style = "minimal",
        border = "rounded",
        title = " 代码预览 ",
        title_pos = "center",
    })

    for _, w in ipairs({ state.win_left, state.win_detail, state.win_process, state.win_code }) do
        vim.api.nvim_win_set_option(w, "number", false)
    end
    vim.api.nvim_win_set_option(state.win_left, "cursorline", true)
    vim.api.nvim_win_set_option(state.win_process, "cursorline", true)
    vim.api.nvim_win_set_option(state.win_detail, "wrap", true)
    vim.api.nvim_win_set_option(state.win_process, "wrap", false)
    vim.api.nvim_win_set_option(state.win_code, "wrap", false)
end

local function redraw_labels_arrows()
    if state.current_view ~= "labels" or #state.labels == 0 then
        return
    end
    state.selected_idx = math.max(1, math.min(state.selected_idx, #state.labels))
    local lines = {
        " j/k · Tab 切窗 ",
        string.rep("─", math.min(34, vim.api.nvim_win_get_width(state.win_left) - 2)),
    }
for i, label in ipairs(state.labels) do
		local name = label.label or label.llm_feature_name or "?"
		local nc = label.community_count or 0
		local np = label.process_count or 0
		local prefix = (i == state.selected_idx) and "▶" or " "
		table.insert(lines, string.format(" %s %s %d/%d", prefix, name, nc, np))
	end
    vim.api.nvim_buf_set_option(state.buf_left, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_left, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(state.buf_left, "modifiable", false)
    vim.api.nvim_win_set_cursor(state.win_left, { state.selected_idx + 2, 0 })
    refresh_detail_preview()
end

local function render_labels()
	local result = run_tool({ "label" })
	local lines = {
        " j/k · Tab 切窗 ",
        string.rep("─", math.min(34, vim.api.nvim_win_get_width(state.win_left) - 2)),
    }

    if result.status ~= "success" then
        table.insert(lines, "")
        table.insert(lines, " ⚠ " .. tostring(result.message or ""):sub(1, 100))
        vim.notify("feature-nav: label 失败", vim.log.levels.WARN)
        state.labels = {}
        state.current_view = "labels"
    else
        state.labels = result.results or {}
        state.current_view = "labels"
        if #state.labels == 0 then
            table.insert(lines, " (暂无) ")
        else
            state.selected_idx = math.max(1, math.min(state.selected_idx or 1, #state.labels))
            for i, label in ipairs(state.labels) do
                local name = label_row_title(label)
                local nc = label.community_count or 0
                local np = label.process_count or 0
                local prefix = (i == state.selected_idx) and "▶" or " "
                table.insert(lines, string.format(" %s %s  %d/%d", prefix, name, nc, np))
            end
        end
    end

    vim.api.nvim_buf_set_option(state.buf_left, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_left, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(state.buf_left, "modifiable", false)
    if #state.labels > 0 then
        vim.api.nvim_win_set_cursor(state.win_left, { state.selected_idx + 2, 0 })
    end
    refresh_detail_preview()
end

local function render_search(query)
    local result = run_tool({ "search", query })
    state.current_view = "search"
    state.search_items = {}
    state.search_selected_idx = 1

    local lines = {
        " j/k · Tab ",
        string.rep("─", math.min(34, vim.api.nvim_win_get_width(state.win_left) - 2)),
    }

    if result.status ~= "success" then
        table.insert(lines, " 搜索失败 ")
        vim.api.nvim_buf_set_option(state.buf_left, "modifiable", true)
        vim.api.nvim_buf_set_lines(state.buf_left, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(state.buf_left, "modifiable", false)
        load_preview_for_label(nil)
        return
    end

    for _, item in ipairs(result.results or {}) do
        if item.type == "label" then
            table.insert(state.search_items, item)
            --- item.feature_name = search API 的 llm_feature_name，即 Label 展示名
            table.insert(
                lines,
                string.format(" Label %s → %s", json_txt(item.label, "?"), json_txt(item.feature_name, ""))
            )
        end
    end

    if #state.search_items == 0 then
        table.insert(lines, " (无结果) ")
    end

    vim.api.nvim_buf_set_option(state.buf_left, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buf_left, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(state.buf_left, "modifiable", false)

    if #state.search_items > 0 then
        state.search_selected_idx = 1
        vim.api.nvim_win_set_cursor(state.win_left, { 3, 0 })
        refresh_search_detail_preview()
    else
        load_preview_for_label(nil)
    end
end

--- 在预览窗内沿「入口 + 各步」循环移动（与 fill_code_buffer 共用同一套 locs）
---@param delta integer
chain_nav = function(delta)
    local procs = state.processes_for_label
    local p = procs[state.process_selected_idx]
    if not p then
        return
    end
    local locs = build_process_chain_locations(p)
    local n = #locs
    if n == 0 then
        return
    end
    local new_idx = ((state.chain_loc_idx - 1 + delta) % n + n) % n + 1
    state.chain_loc_idx = new_idx
    preview_hist_record_from_cycle(new_idx)
    fill_code_buffer()
end

--- 跳到链条上第 n 段（与上方「▶ n. …」序号一致，1–9 键）
---@param n integer
chain_goto = function(n)
    local procs = state.processes_for_label
    local p = procs[state.process_selected_idx]
    if not p then
        return
    end
    local locs = build_process_chain_locations(p)
    local m = #locs
    if m == 0 or n < 1 or n > m then
        return
    end
    state.chain_loc_idx = n
    preview_hist_record_from_cycle(n)
    fill_code_buffer()
end

local function map_keys()
    local function do_quit()
        close_all_wins()
    end

    local function focus_cycle()
        local order = { state.win_left, state.win_detail, state.win_process, state.win_code }
        local cur = vim.api.nvim_get_current_win()
        local ix = 1
        for i, w in ipairs(order) do
            if w and vim.api.nvim_win_is_valid(w) and cur == w then
                ix = i
                break
            end
        end
        local next_ix = (ix % #order) + 1
        local nw = order[next_ix]
        if nw and vim.api.nvim_win_is_valid(nw) then
            vim.api.nvim_set_current_win(nw)
        end
    end

    local function label_name_for_jump()
        if state.current_view == "labels" and #state.labels > 0 then
            local r = state.labels[state.selected_idx]
            return r and label_gitnexus_key(r)
        end
        if state.current_view == "search" and #state.search_items > 0 then
            local idx = state.search_selected_idx or 1
            local it = state.search_items[idx]
            return it and label_gitnexus_key(it)
        end
        return nil
    end

    local function enter_action()
        local cw = vim.api.nvim_get_current_win()

        if cw == state.win_code then
            if state.code_jump_ref then
                open_jump_target(state.code_jump_ref)
            else
                vim.notify("当前段无路径：在预览窗按 [ ] 或 Ctrl+p/n 换到其它代码段", vim.log.levels.INFO)
            end
            return
        end

        if cw == state.win_process then
            if state.code_jump_ref then
                open_jump_target(state.code_jump_ref)
                return
            end
            local procs = state.processes_for_label
            local p = procs[state.process_selected_idx]
            local jlist = p and json_array(p.jump_targets) or {}
            local jt = jlist[1]
            if jt and json_txt(jt.file_path, "") ~= "" then
                open_jump_target(jt)
            else
                vim.notify("当前段无路径：焦点切到右侧预览窗，用 [ ] 或 1-9 换段", vim.log.levels.INFO)
            end
            return
        end

        if cw == state.win_detail then
            local ln = label_name_for_jump()
            if ln then
                jump_to_label_modules(ln)
            end
            return
        end

        if cw == state.win_left then
            if state.current_view == "labels" and #state.labels > 0 then
                local idx = vim.fn.line(".") - 2
                if idx >= 1 and idx <= #state.labels then
                    state.selected_idx = idx
                    local label = state.labels[idx]
                    local lk = label_gitnexus_key(label)
                    if lk then
                        jump_to_label_modules(lk)
                    end
                end
            elseif state.current_view == "search" and #state.search_items > 0 then
                local idx = vim.fn.line(".") - 2
                if idx >= 1 and idx <= #state.search_items then
                    state.search_selected_idx = idx
                    local item = state.search_items[idx]
                    local sk = label_gitnexus_key(item)
                    if sk then
                        jump_to_label_modules(sk)
                    end
                end
            end
        end
    end

    local function labels_j()
        if state.current_view ~= "labels" or #state.labels == 0 then
            return
        end
        local max_line = 2 + #state.labels
        if vim.fn.line(".") < max_line then
            vim.cmd("normal! j")
            state.selected_idx = math.max(1, math.min(vim.fn.line(".") - 2, #state.labels))
            redraw_labels_arrows()
        end
    end

    local function labels_k()
        if state.current_view ~= "labels" or #state.labels == 0 then
            return
        end
        if vim.fn.line(".") > 3 then
            vim.cmd("normal! k")
            state.selected_idx = math.max(1, math.min(vim.fn.line(".") - 2, #state.labels))
            redraw_labels_arrows()
        end
    end

    local function search_j()
        if state.current_view ~= "search" or #state.search_items == 0 then
            return
        end
        if vim.fn.line(".") < 2 + #state.search_items then
            vim.cmd("normal! j")
            state.search_selected_idx = math.max(1, math.min(vim.fn.line(".") - 2, #state.search_items))
            refresh_search_detail_preview()
        end
    end

    local function search_k()
        if state.current_view ~= "search" or #state.search_items == 0 then
            return
        end
        if vim.fn.line(".") > 3 then
            vim.cmd("normal! k")
            state.search_selected_idx = math.max(1, math.min(vim.fn.line(".") - 2, #state.search_items))
            refresh_search_detail_preview()
        end
    end

    local function process_j()
        if #state.processes_for_label == 0 then
            return
        end
        local max_line = 2 + #state.processes_for_label
        if vim.fn.line(".") < max_line then
            vim.cmd("normal! j")
            state.process_selected_idx = math.max(1, math.min(vim.fn.line(".") - 2, #state.processes_for_label))
            redraw_process_list()
        end
    end

    local function process_k()
        if #state.processes_for_label == 0 then
            return
        end
        if vim.fn.line(".") > 3 then
            vim.cmd("normal! k")
            state.process_selected_idx = math.max(1, math.min(vim.fn.line(".") - 2, #state.processes_for_label))
            redraw_process_list()
        end
    end

    local all_bufs = { state.buf_left, state.buf_detail, state.buf_process, state.buf_code }
    for _, b in ipairs(all_bufs) do
        vim.keymap.set("n", "q", do_quit, { buffer = b })
        vim.keymap.set("n", "<Tab>", focus_cycle, { buffer = b })
        vim.keymap.set("n", "<CR>", enter_action, { buffer = b })
    end

    vim.keymap.set("n", "j", function()
        if state.current_view == "labels" then
            labels_j()
        elseif state.current_view == "search" then
            search_j()
        else
            vim.cmd("normal! j")
        end
    end, { buffer = state.buf_left })

    vim.keymap.set("n", "k", function()
        if state.current_view == "labels" then
            labels_k()
        elseif state.current_view == "search" then
            search_k()
        else
            vim.cmd("normal! k")
        end
    end, { buffer = state.buf_left })

    vim.keymap.set("n", "j", process_j, { buffer = state.buf_process })
    vim.keymap.set("n", "k", process_k, { buffer = state.buf_process })
    vim.keymap.set("n", "P", function()
        open_code_popout()
    end, { buffer = state.buf_process })

    vim.keymap.set("n", "j", function()
        vim.cmd("normal! j")
    end, { buffer = state.buf_detail })
    vim.keymap.set("n", "k", function()
        vim.cmd("normal! k")
    end, { buffer = state.buf_detail })

    vim.keymap.set("n", "j", function()
        vim.cmd("normal! j")
    end, { buffer = state.buf_code })
    vim.keymap.set("n", "k", function()
        vim.cmd("normal! k")
    end, { buffer = state.buf_code })
    vim.keymap.set("n", "[", function()
        chain_nav(-1)
    end, { buffer = state.buf_code })
    vim.keymap.set("n", "]", function()
        chain_nav(1)
    end, { buffer = state.buf_code })
    vim.keymap.set("n", "<C-p>", function()
        chain_nav(-1)
    end, { buffer = state.buf_code })
    vim.keymap.set("n", "<C-n>", function()
        chain_nav(1)
    end, { buffer = state.buf_code })
    for d = 1, 9 do
        vim.keymap.set("n", tostring(d), function()
            chain_goto(d)
        end, { buffer = state.buf_code })
    end
    vim.keymap.set("n", "H", function()
        preview_hist_back()
    end, { buffer = state.buf_code })
    vim.keymap.set("n", "L", function()
        preview_hist_forward()
    end, { buffer = state.buf_code })
    vim.keymap.set("n", "P", function()
        open_code_popout()
    end, { buffer = state.buf_code })

    vim.keymap.set("n", "l", function()
        if state.win_detail and vim.api.nvim_win_is_valid(state.win_detail) then
            vim.api.nvim_set_current_win(state.win_detail)
        end
    end, { buffer = state.buf_left })

    vim.keymap.set("n", "h", function()
        if state.win_left and vim.api.nvim_win_is_valid(state.win_left) then
            vim.api.nvim_set_current_win(state.win_left)
        end
    end, { buffer = state.buf_detail })

    vim.keymap.set("n", "h", function()
        if state.win_left and vim.api.nvim_win_is_valid(state.win_left) then
            vim.api.nvim_set_current_win(state.win_left)
        end
    end, { buffer = state.buf_process })

    vim.keymap.set("n", "h", function()
        if state.win_left and vim.api.nvim_win_is_valid(state.win_left) then
            vim.api.nvim_set_current_win(state.win_left)
        end
    end, { buffer = state.buf_code })
end

local function show(query)
    state.selected_idx = 1
    local root = vim.env.FEATURE_NAV_REPO
    state.repo_root = (root and root ~= "") and root or vim.fn.getcwd()
    open_split_layout()

    if query and query ~= "" then
        render_search(query)
    else
        render_labels()
    end

    local ns = vim.api.nvim_create_namespace("fzfnav")
    for _, b in ipairs({ state.buf_left, state.buf_detail, state.buf_process, state.buf_code }) do
        vim.api.nvim_buf_add_highlight(b, ns, "Title", 0, 0, -1)
    end

    map_keys()
    if state.win_left and vim.api.nvim_win_is_valid(state.win_left) then
        vim.api.nvim_set_current_win(state.win_left)
    end
end

M.show = show
M.search = function(query)
    show(query)
end
return M
