local M = {}

vim.g.mm_windows = nil

-- Основной буфер и окно
local main_buf, main_win
-- Буфер и окно для ввода фильтра
local filter_buf, filter_win
-- Исходные строки (для фильтрации)
local original_lines = {}
-- для вычисления ширины окна
local max_len_buffer = 0
-- окно откуда был запуск и в котором нужно поменять содержимое
local current_win
-- поиск строки по номеру буфера 
local search_number_string = ""
-- домашняя директория
local home_dir = ""

local config = {
	-- #112233
	width_win = 0,												-- ширина окна, если = 0 вычисляется
	-- color_cursor_line = "#2b2b2b",				-- цвет подсветки строки с курсором
	-- color_cursor_mane_line = "",		-- цвет подсветки строки в основном редакторе
	color_light_path = "#ada085",					-- цвет выделения пути из имени файла
	color_light_filter = "#224466",				-- цвет строки ввода фильтра
	color_light_curr = "#f1b841",					-- цвет цвет номера для текущего буфера
}

-- Создаем namespace для хайлайтов
local ns

-- переход на первую строку
local function select_first_line()
	search_number_string = ""
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

-- переход  на последнию строку
local function select_last_line()
	-- Получаем количество строк в текущем буфере
	-- Перемещаем курсор на последнюю строку
	search_number_string = ""
	vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
end

-- поиск строки по номеру буфера
-- обрабатывает цифровые клавиши
local function n_number_pressed_find_line(key)
	search_number_string = search_number_string .. key

	if #search_number_string > 3 then
		search_number_string = key
	end

	-- Ищем строку в буфере
  local num_line = vim.fn.search(search_number_string, 'n')

  -- Если строка найдена, перемещаем курсор на неё
  if num_line > 0 then
		-- Перемещаем курсор
    vim.api.nvim_win_set_cursor(0, { num_line, 0 })
  end
end

-- перехват движения вверх
-- local function select_up()
	-- vim.cmd('norm! k')
-- end

	-- if vim.api.nvim__buf_stats(0).current_lnum == 1 then
		-- переходим в окно фильта когда достигнута первая строчка списка
		-- M.select_filter_window()

		-- Получаем количество строк в текущем буфере
		-- Перемещаем курсор на последнюю строку
		-- vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
	-- end
-- end

local function close()
		vim.g.mm_windows = nil
    -- Закрываем окна для фильтра и буфероф
    vim.api.nvim_win_close(filter_win, true)
		vim.api.nvim_buf_delete(filter_buf, { force = true })
    vim.api.nvim_win_close(main_win, true)
		vim.api.nvim_buf_delete(main_buf, { force = true })
		-- vim.api.nvim_set_hl(0, "CursorLine", { bg = config.color_cursor_mane_line })
		vim.cmd("stopi")

		-- теперь нужно переключиться в прежнее окно из которого было вызвано список буферов
    vim.api.nvim_set_current_win(current_win)
end

-- Функция для подсветки пути в имени файла
local function highlight_path_in_filename(line, line_number)

		if line:find("%", 1, true) then
			vim.api.nvim_buf_add_highlight(main_buf, ns, "MyHighlightPathCurr", line_number - 1, 5, 7)
		end

    local last_slash_pos = line:find("/[^/]*$")
    if not last_slash_pos then
        return
    end

    -- Добавляем подсветку с помощью vim.highlight (эта hl определена в malpha.nvim )
    vim.api.nvim_buf_add_highlight(main_buf, ns, "MyHighlightPath", line_number - 1, 8, last_slash_pos)
end

-- Функция для выбора буфера
local function select_buffer()
		local buf_number = tonumber(string.sub(vim.api.nvim_get_current_line(), 2, 4))
		close()
    -- Переключаемся на выбранный буфер
    -- vim.api.nvim_set_current_buf(vim.fn.bufnr(buf_number))
		vim.api.nvim_win_set_buf(current_win, vim.fn.bufnr(buf_number))
		-- теперь нужно переключиться в прежнее окно из которого было вызвано список буферов
    vim.api.nvim_set_current_win(current_win)
end

-- Функция для переключение на окно с буферами 
local function select_main_window()
    -- Возвращаемся в основной буфер
    vim.api.nvim_set_current_win(main_win)
		vim.api.nvim_win_set_option(0, "cursorline", true)
    -- Устанавливаем режим "только для чтения"
    vim.api.nvim_buf_set_option(main_buf, "readonly", true)
    vim.api.nvim_buf_set_option(main_buf, "modifiable", false)
		vim.cmd("stopi")
end

local function select_filter_window()
    -- в буфер фильтра

    -- Убираем режим "только для чтения"
    vim.api.nvim_buf_set_option(main_buf, "readonly", false)
    vim.api.nvim_buf_set_option(main_buf, "modifiable", true)

		-- очищаем поле ввода фильта если там находится путь к папке проекта (* не допустима в имени файла)
		if table.concat(vim.api.nvim_buf_get_lines(filter_buf, 0, -1, false), ""):find("*", 1, true) then
			vim.api.nvim_buf_set_lines(filter_buf, 0, -1, false, {})
		end

		vim.api.nvim_win_set_option(0, "cursorline", false)
    vim.api.nvim_set_current_win(filter_win)
		vim.cmd("star")
end

-- Функция для получения списка открытых буферов с номерами и атрибутами
local function get_open_buffers()
    original_lines = {}
    local current_buf = vim.api.nvim_get_current_buf() -- Текущий активный буфер
    local previous_buf = vim.fn.bufnr("#")             -- Предыдущий буфер
		local root_dir = vim.fn.getcwd() .. "/"

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.fn.buflisted(buf) == 1 and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
            -- local file_name = string.gsub(vim.api.nvim_buf_get_name(buf), root_dir, "", 1)
						-- уберем путь к текущиму каталогу, дополнительн уберем домашние директорию
            local file_name = string.gsub(string.gsub(vim.api.nvim_buf_get_name(buf), root_dir, "", 1), home_dir, "", 1)

            local buf_number = vim.api.nvim_buf_get_number(buf) -- Номер буфера
						local is_modified = vim.api.nvim_buf_get_option(buf, "modified")
						max_len_buffer = math.max(max_len_buffer, string.len(file_name))

            -- Определяем атрибуты буфера
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

            -- Формируем строку с информацией о буфере
            table.insert(original_lines, string.format(" %3d %s %s", buf_number, table.concat(attributes, ""), file_name))
        end
    end
end

-- Функция для создания основного окна
local function create_main_window()
    -- Создаём основной буфер
    main_buf = vim.api.nvim_create_buf(false, true)

    -- Устанавливаем текст в буфере
    vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, original_lines)

    -- vim.cmd("highlight HighlightPath guifg=" .. M.config.color_light_path)
		-- vim.cmd("highlight HighlightPathCurr guifg="..M.config.color_light_curr)

		-- устанавливаем hl
		vim.api.nvim_set_hl(0, "MyHighlightPathCurr", {
			fg = config.color_light_curr,      -- GUI цвет
			ctermfg = 180,       -- Терминальный цвет
			default = true,   -- наследовать отсутствующие атрибуты
		})

		ns = vim.api.nvim_create_namespace("file_paths_highlights")

		for i, line in ipairs(original_lines) do
			highlight_path_in_filename(line, i)
		end

    -- Создаём основное окно
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
    }

    -- Открываем основное окно
    main_win = vim.api.nvim_open_win(main_buf, true, wopts)
		vim.cmd("stopi")
		-- vim.api.nvim_set_hl(0, "CursorLine", { bg = config.color_cursor_line })
		vim.api.nvim_win_set_option(0, "cursorline", true)


		local opts = { noremap = true, silent = true, buffer = main_buf }
    -- Устанавливаем режим "только для чтения"
    vim.api.nvim_buf_set_option(main_buf, "readonly", true)
    vim.api.nvim_buf_set_option(main_buf, "modifiable", false)

		vim.keymap.set("n", "<Esc>", function() close() end, opts)
		vim.keymap.set("n", "q", function() close() end, opts)
		vim.keymap.set("n", "f", function() select_filter_window() end, opts)
		vim.keymap.set("n", "<c-Up>", function() select_filter_window() end, opts)
		vim.keymap.set("n", "<Home>", function() select_first_line() end, opts)
		vim.keymap.set("n", "<End>", function() select_last_line() end, opts)
		vim.keymap.set("n", "<CR>", function() select_buffer() end, opts)

    -- vim.api.nvim_buf_set_keymap(main_buf, "n", "<Esc>", "<Cmd>lua require('mbuffers').close()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(main_buf, "n", "q", "<Cmd>lua require('mbuffers').close()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(main_buf, "n", "f", "<Cmd>lua require('mbuffers').select_filter_window()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(main_buf, "n", "<c-Up>", "<Cmd>lua require('mbuffers').select_filter_window()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(main_buf, "n", "<Home>", "<Cmd>lua require('mbuffers').select_first_line()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(main_buf, "n", "<End>", "<Cmd>lua require('mbuffers').select_last_line()<CR>", { noremap = true, silent = true })
    -- -- vim.api.nvim_buf_set_keymap(main_buf, "n", "<Up>", "<Cmd>lua require('mbuffers').select_filter_up()<CR>", { noremap = true, silent = true })
    -- -- vim.api.nvim_buf_set_keymap(main_buf, "n", "<Up>", "<Cmd>lua require('mbuffers').select_up()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(main_buf, "n", "<CR>", "<Cmd>lua require('mbuffers').select_buffer()<CR>", { noremap = true, silent = true })

		-- Привязка цифровых клавиш (0-9)
		for i = 0, 9 do
			vim.keymap.set("n", tostring(i), function() n_number_pressed_find_line(i) end, opts)
			-- vim.api.nvim_buf_set_keymap(main_buf, 'n', tostring(i), "<Cmd>lua  require('mbuffers').n_number_pressed_find_line('"..i.."')<CR>", { noremap = true, silent = true })
		end
end

-- возвращает путь к каталогу проекта
local function get_dir_progect()
	local dir_progect = string.gsub(vim.fn.getcwd(), home_dir, "~", 1)
	-- уточним максимальную длину всех строк
	max_len_buffer = math.max(max_len_buffer, string.len(dir_progect) - 6)
	return " " .. dir_progect .. "/* "
end

-- Функция для создания окна ввода фильтра
local function create_filter_window()
    -- Создаём буфер для ввода фильтра
    filter_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(filter_buf, 0, -1, false, {get_dir_progect()})

    -- Создаём окно для ввода фильтра
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
    }

    -- Открываем окно для ввода фильтра
    filter_win = vim.api.nvim_open_win(filter_buf, true, wopts)

    -- vim.cmd("highlight MyRedText guibg=" .. M.config.color_light_filter)
		-- устанавливаем hl
		vim.api.nvim_set_hl(0, "MyRedText", {
			bg = config.color_light_filter,      -- GUI цвет
			ctermfg = 180,       -- Терминальный цвет
			default = true,   -- наследовать отсутствующие атрибуты
		})

		ns = vim.api.nvim_create_namespace("file_paths_highlights")
    vim.api.nvim_buf_add_highlight(filter_buf, ns, "MyRedText", 0, 0, -1)

    -- Переключаемся в режим редактирования
    -- vim.api.nvim_command("startinsert")
		vim.cmd("star")

		local opts = { noremap = true, silent = true, buffer = filter_buf }
    -- Устанавливаем клавишу Esc для закрытия окна
		vim.keymap.set("i", "<Esc>", function() close() end, opts)
		vim.keymap.set("i", "<CR>", function() select_main_window() end, opts)
		vim.keymap.set("i", "<Down>", function() select_main_window() end, opts)
    -- vim.api.nvim_buf_set_keymap(filter_buf, "i", "<Esc>", "<Cmd>lua require('mbuffers').close()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(filter_buf, "i", "<CR>", "<Cmd>lua require('mbuffers').select_main_window()<CR>", { noremap = true, silent = true })
    -- vim.api.nvim_buf_set_keymap(filter_buf, "i", "<Down>", "<Cmd>lua require('mbuffers').select_main_window()<CR>", { noremap = true, silent = true })

    -- Устанавливаем обработчик ввода текста
    -- local buf_number = vim.api.nvim_buf_get_number(filter_buf) -- Номер буфера
    vim.api.nvim_buf_attach(filter_buf, false, {
        on_lines = function()
					vim.schedule(function()
            -- Получаем текст фильтра
            local filter_text = table.concat(vim.api.nvim_buf_get_lines(filter_buf, 0, -1, false), "")

            -- Фильтруем строки в основном буфере
            local filtered_lines = {}
            for _, line in ipairs(original_lines) do
                if line:find(filter_text, 1, true) then
                    table.insert(filtered_lines, line)
                end
            end

            -- Обновляем основной буфер
            vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, filtered_lines)
						for i, line in ipairs(filtered_lines) do
							highlight_path_in_filename(line, i)
						end
					end)
        end,
    })
end



function M.setup(options)
	config = vim.tbl_deep_extend("force", config, options or {})

	-- получение цвета фона текущец строки
	-- local hl = vim.api.nvim_get_hl(0, { name = 'CursorLine' })
	-- if hl.bg then
	-- 	M.config.color_cursor_mane_line = hl.bg
	-- end

	home_dir = tostring(os.getenv("HOME"))
	-- vim.api.nvim_create_user_command("StartMbuffers", M.start, {})
end

-- Функция для запуска менеджера буферов с клавиатуры
function M.start()
	if vim.g.mm_windows ~= nil then
		return
	end
	vim.g.mm_windows = 1
	search_number_string = ""
	current_win = vim.api.nvim_get_current_win()
	get_open_buffers()

  -- Создаём окно ввода фильтра
  create_filter_window()

  -- Создаём основное окно
  create_main_window()
end

return M
