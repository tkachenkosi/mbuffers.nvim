local M = {}

vim.g.mm_windows = nil

local main_buf, main_win
local filter_buf, filter_win
local original_lines = {}
local max_len_buffer = 0   -- ВАЖНО самая длинная строка в списке путей.
local current_win
local search_number_string = ""

-- для плавного фильтра
local filter_debounce_timer = nil
local is_filtering = false

local main_ns
local filter_ns

local config = {
	home_dir = tostring(os.getenv("HOME")),		-- домашняя директория
	width_win = 0,												-- ширина окна, если = 0 вычисляется
	color_light_path = "#ada085",					-- цвет выделения пути из имени файла
	color_light_filter = "#224466",				-- цвет строки ввода фильтра
	color_light_curr = "#f1b841",					-- цвет цвет номера для текущего буфера
}

-- local ns

local function select_first_line()
	search_number_string = ""
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function select_last_line()
	search_number_string = ""
	vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
end

local function n_number_pressed_find_line(key)
	search_number_string = search_number_string .. key

	if #search_number_string > 3 then
		search_number_string = key
	end

  local num_line = vim.fn.search(search_number_string, 'n')

  if num_line > 0 then
    vim.api.nvim_win_set_cursor(0, { num_line, 0 })
  end
end


local function safe_close()
	vim.g.mm_windows = nil

	if filter_buf and vim.api.nvim_buf_is_valid(filter_buf) then
			pcall(vim.api.nvim_buf_detach, filter_buf)
	end

	if filter_win and vim.api.nvim_win_is_valid(filter_win) then
		vim.api.nvim_win_close(filter_win, true)
	end
	if main_win and vim.api.nvim_win_is_valid(main_win) then
		vim.api.nvim_win_close(main_win, true)
	end

	-- vim.cmd("stopi")
	vim.cmd.stopinsert()
end

local function close()
		safe_close()
		if current_win and vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_set_current_win(current_win)
		end
end

local function highlight_path_in_filename(line, line_number)
	local row = line_number - 1

	if line:find("%", 1, true) then
		vim.api.nvim_buf_set_extmark(main_buf, main_ns, row, 5, {
			end_line = row,
			end_col = 7,
			hl_group = "MyHlPathCurr",
			priority = 100,
		})
	end

	local last_slash_pos = line:find("/[^/]*$")
	if last_slash_pos then
		vim.api.nvim_buf_set_extmark(main_buf, main_ns, row, 8, {
			end_line = row,
			end_col = last_slash_pos,
			hl_group = "MyHlPath",
			priority = 50,
		})
	end
end

local function select_buffer()
		local buf_number = tonumber(string.sub(vim.api.nvim_get_current_line(), 2, 4))
		if not buf_number then return end		-- ? рекомендация
		safe_close()
		vim.api.nvim_win_set_buf(current_win, vim.fn.bufnr(buf_number))
		if current_win and vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_set_current_win(current_win)
		end
end

local function select_main_window()
    vim.api.nvim_set_current_win(main_win)
    vim.wo[main_win].cursorline = true
		vim.bo[main_buf].readonly = true
		vim.bo[main_buf].modifiable = false

		-- vim.cmd("stopi")
		vim.cmd.stopinsert()
end

local function select_filter_window()
		vim.bo[main_buf].readonly = false
		vim.bo[main_buf].modifiable = true

		if table.concat(vim.api.nvim_buf_get_lines(filter_buf, 0, -1, false), ""):find("*", 1, true) then
			vim.api.nvim_buf_set_lines(filter_buf, 0, -1, false, {})
		end

    vim.wo[main_win].cursorline = false
    vim.api.nvim_set_current_win(filter_win)
		-- vim.cmd("star")
		vim.cmd.startinsert()
end

local function get_open_buffers()
    original_lines = {}
		max_len_buffer = 0   -- ВАЖНО самая длинная строка в списке путей.
    local current_buf = vim.api.nvim_get_current_buf()
    local previous_buf = vim.fn.bufnr("#")
		local root_dir = vim.fn.getcwd() .. "/"

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.fn.buflisted(buf) == 1 and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
            local file_name = string.gsub(string.gsub(vim.api.nvim_buf_get_name(buf), root_dir, "", 1), config.home_dir, "", 1)

            local buf_number = vim.api.nvim_buf_get_number(buf) -- Номер буфера
						-- local is_modified = vim.api.nvim_buf_get_option(buf, "modified")
						local is_modified = vim.bo[buf].modified
						max_len_buffer = math.max(max_len_buffer, string.len(file_name))

            local attributes = {}
            if buf == current_buf then
                table.insert(attributes, "%")
            end
            if buf == previous_buf then
                table.insert(attributes, "#")
            end
            if #attributes == 0 then
                table.insert(attributes, " ")
						end
						if is_modified then
                table.insert(attributes, "+")
						else
                table.insert(attributes, " ")
						end

            table.insert(original_lines, string.format(" %3d %s %s", buf_number, table.concat(attributes, ""), file_name))
        end
    end
end

local function create_main_window()
    main_buf = vim.api.nvim_create_buf(false, true)

		vim.bo[main_buf].buftype = "nofile"
		vim.bo[main_buf].bufhidden = "wipe"
		vim.bo[main_buf].swapfile = false
		vim.bo[main_buf].buflisted = false
		vim.bo[main_buf].modifiable = true
		vim.bo[main_buf].textwidth = 0
		vim.bo[main_buf].filetype = "text"
		vim.bo[main_buf].undolevels = -1

    vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, original_lines)

		vim.api.nvim_set_hl(0, "MyHlPath", {
			fg = config.color_light_path,
			ctermfg = 180,
			default = true,
		})

		vim.api.nvim_set_hl(0, "MyHlPathCurr", {
			fg = config.color_light_curr,      -- цвет
			ctermfg = 180,       -- Терминальный цвет
			default = true,   -- наследовать отсутствующие атрибуты
		})

		-- ns = vim.api.nvim_create_namespace("file_paths_highlights")
		main_ns = vim.api.nvim_create_namespace("main_highlights")

		for i, line in ipairs(original_lines) do
			highlight_path_in_filename(line, i)
		end

    local width = 0
		if config.width_win > 0 then
			width = math.min(vim.o.columns - 10, config.width_win )
		else
			width = math.min(vim.o.columns - 10,  max_len_buffer + 10)
		end

    local height = math.min(vim.o.lines - 4, vim.api.nvim_buf_line_count(main_buf) + 1)
    local col = math.floor((vim.o.columns - width))

    local wopts = {
        relative = "editor",
        width = width,
        height = height,
        row = 1,
        col = col,
        style = "minimal",
				focusable = true,
        zindex = 100,
        border = "none",
    }

    main_win = vim.api.nvim_open_win(main_buf, true, wopts)

    vim.wo[main_win].cursorline = true
    vim.wo[main_win].winblend = 0
    vim.wo[main_win].winhighlight = "Normal:NormalFloat,CursorLine:Visual"
    vim.wo[main_win].wrap = false
    vim.wo[main_win].number = false
    vim.wo[main_win].relativenumber = false
    vim.wo[main_win].signcolumn = "no"
    vim.wo[main_win].colorcolumn = ""

		-- vim.cmd("stopi")
		vim.cmd.stopinsert()

		local opts = { noremap = true, silent = true, buffer = main_buf }
		vim.bo[main_buf].readonly = true
		vim.bo[main_buf].modifiable = false

		for _, key in ipairs({ ':','/','?','*','#','<F1>','<F2>','<F3>','<F4>','<F5>','<F6>','<F7>','<F8>','<F9>','<F10>','<F12>','<Leader>' }) do
				vim.keymap.set('n', key, '<Nop>', opts)
		end

		vim.keymap.set("n", "<Esc>", function() close() end, opts)
		vim.keymap.set("n", "q", function() close() end, opts)
		vim.keymap.set("n", "f", function() select_filter_window() end, opts)
		vim.keymap.set("n", "<c-Up>", function() select_filter_window() end, opts)
		vim.keymap.set("n", "<Home>", function() select_first_line() end, opts)
		vim.keymap.set("n", "<End>", function() select_last_line() end, opts)
		vim.keymap.set("n", "<CR>", function() select_buffer() end, opts)


		for i = 0, 9 do
			vim.keymap.set("n", tostring(i), function() n_number_pressed_find_line(i) end, opts)
		end
end

local function get_dir_project()
	local dir_progect = string.gsub(vim.fn.getcwd(), config.home_dir, "~", 1)
	max_len_buffer = math.max(max_len_buffer, string.len(dir_progect) - 6)
	return " " .. dir_progect .. "/* "
end

-- установка фильтра
local function update_buffer_list_filtered(filter_text)
	if is_filtering then return end
  is_filtering = true

	vim.schedule(function()
		local filtered_lines = {}
		for _, line in ipairs(original_lines) do
			if line:find(filter_text, 1, true) then
				table.insert(filtered_lines, line)
			end
		end

		-- обновляем текст
		vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, filtered_lines)

		-- чистим highlight
		vim.api.nvim_buf_clear_namespace(main_buf, main_ns, 0, -1)

		-- заново ставим highlight
		for i, line in ipairs(filtered_lines) do
			highlight_path_in_filename(line, i)
		end

		is_filtering = false
	end)
end

local function create_filter_window()
	filter_buf = vim.api.nvim_create_buf(false, true)

	vim.bo[filter_buf].buftype = "nofile"
	vim.bo[filter_buf].bufhidden = "wipe"
	vim.bo[filter_buf].swapfile = false
	vim.bo[filter_buf].buflisted = false
	vim.bo[filter_buf].modifiable = true
	vim.bo[filter_buf].textwidth = 0
	vim.bo[filter_buf].filetype = "text"
	vim.bo[filter_buf].undolevels = -1

	local dir_project = get_dir_project()
	vim.api.nvim_buf_set_lines(filter_buf, 0, -1, false, {dir_project})

	local width = 0
	if config.width_win > 0 then
		width = math.min(vim.o.columns - 10, config.width_win )
	else
		width = math.min(vim.o.columns - 10,  max_len_buffer + 10)
	end
	local height = 1
	local col = math.floor((vim.o.columns - width) )

	local wopts = {
			relative = "editor",
			width = width,
			height = height,
			row = 0,
			col = col,
			style = "minimal",
			focusable = true,
			zindex = 101,
			border = "none",
	}

	filter_win = vim.api.nvim_open_win(filter_buf, true, wopts)

	vim.wo[filter_win].cursorline = false
	vim.wo[filter_win].winblend = 0

	vim.api.nvim_set_hl(0, "MyRedText", {
		bg = config.color_light_filter,      -- GUI цвет
		ctermfg = 180,       -- Терминальный цвет
		default = true,   -- наследовать отсутствующие атрибуты
	})

	-- ns = vim.api.nvim_create_namespace("file_paths_highlights")
	filter_ns = vim.api.nvim_create_namespace("filter_highlights")

	vim.api.nvim_buf_set_extmark(filter_buf, filter_ns, 0, 0, {
			end_line = 0,
			end_col = #dir_project,
			hl_group = "MyRedText",
			priority = 50,
	})

	-- vim.cmd("star")
	vim.cmd.startinsert()

	local opts = { noremap = true, silent = true, buffer = filter_buf }
	for _, key in ipairs({ '<F1>','<F2>','<F3>','<F4>','<F5>','<F6>','<F7>','<F8>','<F9>','<F10>','<F12>' }) do
			vim.keymap.set('i', key, '<Nop>', opts)
	end
	vim.keymap.set("i", "<Esc>", function() close() end, opts)
	vim.keymap.set("i", "<CR>", function() select_main_window() end, opts)
	vim.keymap.set("i", "<Down>", function() select_main_window() end, opts)

	vim.api.nvim_buf_attach(filter_buf, false, {
		on_lines = function()
			if filter_debounce_timer then
				filter_debounce_timer:stop()
			end

			filter_debounce_timer = vim.defer_fn(function()
				local filter_text = table.concat(vim.api.nvim_buf_get_lines(filter_buf, 0, -1, false), "")
				update_buffer_list_filtered(filter_text)
				filter_debounce_timer = nil
			end, 150)

		end,})
end



function M.setup(options)
	config = vim.tbl_deep_extend("force", config, options or {})
end

function M.start()
	if vim.g.mm_windows ~= nil or #vim.api.nvim_list_bufs() < 2 then
		return
	end
	vim.g.mm_windows = 1
	search_number_string = ""
	current_win = vim.api.nvim_get_current_win()
	get_open_buffers()
  create_filter_window()
  create_main_window()
end

return M
