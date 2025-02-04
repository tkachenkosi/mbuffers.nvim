-- Модуль для живого поиска
local M = {}

-- Основной буфер и окно
local main_buf, main_win
-- Буфер и окно для ввода фильтра
local filter_buf, filter_win
-- Исходные строки (для фильтрации)
local original_lines = {}
-- для вычисления ширины окна
local max_len_buffer = 0

local	config = {
	-- #112233
	width_win = 0,												-- ширина окна, если = 0 вычисляется
	color_cursor_line = "#2b2b2b",				-- цвет подсветки строки с курсором
	color_cursor_mane_line = "#2b2b2b",		-- цвет подсветки строки в основном редакторе
	color_light_path = "#ada085",					-- цвет выделения пути из имени файла
	color_light_filter = "#224466",				-- цвет строки ввода фильтра
}


-- Функция для подсветки пути в имени файла
local function highlight_path_in_filename(line, line_number)
    local last_slash_pos = line:find("/[^/]*$")
    if not last_slash_pos then
        return
    end

    -- Добавляем подсветку с помощью vim.highlight
    vim.api.nvim_buf_add_highlight(main_buf, -1, "HighlightPath", line_number - 1, 8, last_slash_pos)
end


-- Функция для получения списка открытых буферов с номерами и атрибутами
local function get_open_buffers()
    local buffers = {}
    local current_buf = vim.api.nvim_get_current_buf() -- Текущий активный буфер
    local previous_buf = vim.fn.bufnr("#")             -- Предыдущий буфер
		local root_dir = vim.fn.getcwd() .. "/"

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.fn.buflisted(buf) == 1 and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
            local file_name = string.gsub(vim.api.nvim_buf_get_name(buf), root_dir, "", 1) -- Получаем имя файла
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
            table.insert(buffers, string.format(" %3d %s %s", buf_number, table.concat(attributes, ""), file_name))
        end
    end

    return buffers
end

-- Функция для создания основного окна
local function create_main_window()
    -- Создаём основной буфер
    main_buf = vim.api.nvim_create_buf(false, true)

    -- Устанавливаем текст в буфере
    vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, original_lines)

    vim.cmd("highlight HighlightPath guifg=" .. config.color_light_path)
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

    local opts = {
        relative = "win",
        width = width,
        height = height,
        row = 1,
        col = col,
        style = "minimal",
    }

    -- Открываем основное окно
    main_win = vim.api.nvim_open_win(main_buf, true, opts)
		vim.cmd("stopi")
		vim.api.nvim_set_hl(0, "CursorLine", { bg = config.color_cursor_line })
		vim.api.nvim_win_set_option(0, "cursorline", true)

    -- Устанавливаем режим "только для чтения"
    vim.api.nvim_buf_set_option(main_buf, "readonly", true)
    vim.api.nvim_buf_set_option(main_buf, "modifiable", false)

    vim.api.nvim_buf_set_keymap(main_buf, "n", "<Esc>", "<Cmd>lua require('my.module').close_mbuffers()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(main_buf, "n", "q", "<Cmd>lua require('my.module').close_mbuffers()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(main_buf, "n", "f", "<Cmd>lua require('my.module').select_filter_window()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(main_buf, "n", "<c-Up>", "<Cmd>lua require('my.module').select_filter_window()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(main_buf, "n", "<Up>", "<Cmd>lua require('my.module').select_filter_up()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(main_buf, "n", "<CR>", "<Cmd>lua require('my.module').select_buffer()<CR>", { noremap = true, silent = true })
end

-- перехват движения вверх
function M.select_filter_up()
	vim.cmd('norm! k')
	if vim.api.nvim__buf_stats(0).current_lnum == 1 then
		-- переходим в окно фильта когда достигнута первая строчка списка
		M.select_filter_window()
	end
end

-- возвращает путь к каталогу проекта
local function get_dir_progect()
	local dir_progect = string.gsub(vim.fn.getcwd(), tostring(os.getenv("HOME")), "~", 1)
	-- уточним максимальную длину всех строк
	max_len_buffer = math.max(max_len_buffer, string.len(dir_progect) - 10)
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

    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = 0,
        col = col,
        style = "minimal",
    }

    -- Открываем окно для ввода фильтра
    filter_win = vim.api.nvim_open_win(filter_buf, true, opts)

    vim.cmd("highlight RedText guibg=" .. config.color_light_filter)
    vim.api.nvim_buf_add_highlight(filter_buf, -1, "RedText", 0, 0, -1)

    -- Переключаемся в режим редактирования
    -- vim.api.nvim_command("startinsert")
		vim.cmd("star")

    -- Устанавливаем клавишу Esc для закрытия окна
    vim.api.nvim_buf_set_keymap(filter_buf, "i", "<Esc>", "<Cmd>lua require('my.module').close_mbuffers()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(filter_buf, "i", "<CR>", "<Cmd>lua require('my.module').select_main_window()<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(filter_buf, "i", "<Down>", "<Cmd>lua require('my.module').select_main_window()<CR>", { noremap = true, silent = true })

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


-- Функция для выбора буфера
function M.select_buffer()
		local buf_number = tonumber(string.sub(vim.api.nvim_get_current_line(), 2, 4))
		M.close_mbuffers()
    -- Переключаемся на выбранный буфер
    vim.api.nvim_set_current_buf(vim.fn.bufnr(buf_number))
end

-- Функция для переключение на окно с буферами 
function M.select_main_window()
    -- Возвращаемся в основной буфер
		vim.api.nvim_win_set_option(0, "cursorline", false)
    vim.api.nvim_set_current_win(main_win)
		vim.api.nvim_win_set_option(0, "cursorline", true)
    -- Устанавливаем режим "только для чтения"
    vim.api.nvim_buf_set_option(main_buf, "readonly", true)
    vim.api.nvim_buf_set_option(main_buf, "modifiable", false)
		vim.cmd("stopi")
end

function M.select_filter_window()
    -- Возвращаемся в основной буфер

    -- Убираем режим "только для чтения"
    vim.api.nvim_buf_set_option(main_buf, "readonly", false)
    vim.api.nvim_buf_set_option(main_buf, "modifiable", true)

		-- очищаем поле ввода фильта если там находится путь к папке проекта (* не допустима в имени файла)
		if table.concat(vim.api.nvim_buf_get_lines(filter_buf, 0, -1, false), ""):find("*", 1, true) then
			vim.api.nvim_buf_set_lines(filter_buf, 0, -1, false, {})
		end

		vim.api.nvim_win_set_option(0, "cursorline", false)
    vim.api.nvim_set_current_win(filter_win)
		vim.api.nvim_win_set_option(0, "cursorline", true)
		vim.cmd("star")
end

function M.close_mbuffers()
    -- Закрываем окна для фильтра и буфероф
    vim.api.nvim_win_close(filter_win, true)
		vim.api.nvim_buf_delete(filter_buf, { force = true })
    vim.api.nvim_win_close(main_win, true)
		vim.api.nvim_buf_delete(main_buf, { force = true })
		vim.api.nvim_set_hl(0, "CursorLine", { bg = config.color_cursor_mane_line })
		vim.cmd("stopi")
end

function M.setup(options)
	config = vim.fbl_deep_extend("force", config, options or {})

	vim.api.nvim_create_user_command("StartMbuffers", M.start, {})
end

-- Функция для запуска менеджера буферов
function M.start()
	original_lines = get_open_buffers()

  -- Создаём окно ввода фильтра
  create_filter_window()

  -- Создаём основное окно
  create_main_window()
end

return M
