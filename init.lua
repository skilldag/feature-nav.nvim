-- feature-nav.nvim 插件入口
local M = require("feature-nav")

-- 默认配置
local default_config = {
    cache_enabled = true,
    cache_ttl = 3600,
    max_clusters = 50,
    window_width = 0.7,
    window_height = 0.6,
}

-- 设置函数
function M.setup(user_config)
    local config = vim.tbl_deep_extend("force", default_config, user_config or {})
    
    -- 设置用户命令
    vim.api.nvim_create_user_command("FeatureNav", function()
        require("feature-nav").open()
    end, {
        desc = "打开 GitNexus Label 导航"
    })
    
    vim.api.nvim_create_user_command("FeatureNavRefresh", function()
        require("feature-nav").refresh()
    end, {
        desc = "刷新 Label 缓存/数据"
    })

    vim.api.nvim_create_user_command("FeatureNavLabels", function()
        require("feature-nav.fzfnav").show()
    end, {
        desc = "多级悬浮查看 Labels"
    })

    vim.api.nvim_create_user_command("FeatureNavSearch", function(opts)
        local query = opts.args or ""
        require("feature-nav.fzfnav").search(query)
    end, {
        desc = "语义搜索 Labels（label_annotations）",
        nargs = "?",
        complete = function()
            return {}
        end
    })

    -- Key maps（与 core/keymaps 一致：nl / nq；勿用 f 前缀，<Leader>f 已被 LSP format 占用）
    vim.keymap.set("n", "<leader>nl", function()
        require("feature-nav.fzfnav").show()
    end, { desc = "Label 导航: 打开列表" })

    vim.keymap.set("n", "<leader>nq", function()
        vim.ui.input({ prompt = "搜索: " }, function(query)
            if query and query ~= "" then
                require("feature-nav.fzfnav").search(query)
            end
        end)
    end, { desc = "Label 导航: 语义搜索" })
    
    vim.api.nvim_create_user_command("FeatureNavClose", function()
        require("feature-nav").close()
    end, {
        desc = "关闭 Label 导航"
    })
    
    -- 可选：设置自动命令
    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            -- 可以在这里添加初始化逻辑
        end,
        once = true
    })
    
    print("✅ feature-nav.nvim 已加载")
    return M
end

return M