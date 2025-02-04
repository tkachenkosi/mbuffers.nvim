### A minimalistic and highly-efficient buffer manager for the Neovim editor.
---
#### Installation and Usage:
```
{
"tkachenkosi/mbuffers.nvim",
config = function()
	require("mbuffers").setup({
		width_win = 0,
	})
end,
}

DEFAULT_OPTIONS = {
width_win = 0,				-- the width of the window, if = 0 is calculated
color_cursor_line = "#2b2b2b",		-- the color of the line highlight with the cursor
color_cursor_mane_line = "#2b2b2b",	-- the color of the line highlight in the main editor
color_light_path = "#ada085",	   	-- the color of the path selection from the file name
color_light_filter = "#224466",		-- the color of the filter input line
}
```
#### Keys in the buffer list window:
Esc, q      - close the buffer manager window

f, c-Up, Up - and switch to the filter input line

CR          - open the selected buffer

#### Keys in the filter input window:
Esc         - close the buffer manager window

CR, Down    - go to the buffer list window

#### Command:

|:StartMbuffers|
