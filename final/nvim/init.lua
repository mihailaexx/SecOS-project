-- ============ Core options ============
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.scrolloff = 8
vim.opt.wrap = false
vim.opt.undofile = true

-- ============ Plugins ============
vim.pack.add({
  { src = "https://github.com/stevearc/oil.nvim" },
  { src = "https://github.com/kdheepak/lazygit.nvim" },
  { src = "https://github.com/catppuccin/nvim", name = "catppuccin" },
  { src = "https://github.com/nvim-lua/plenary.nvim" },
})

vim.cmd.colorscheme("catppuccin-mocha")

require("oil").setup({
  view_options = { show_hidden = true },
  keymaps = { ["q"] = "actions.close" },
})

-- ============ Keymaps ============
local map = vim.keymap.set
map("n", "-", "<cmd>Oil<CR>", { desc = "Open parent dir" })
map("n", "<leader>e", "<cmd>Oil<CR>", { desc = "File explorer" })
map("n", "<leader>g", "<cmd>LazyGit<CR>", { desc = "Lazygit" })
map("n", "<leader>w", "<cmd>w<CR>")
map("n", "<leader>q", "<cmd>q<CR>")
map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- ============ VSCode-style keymaps ============
-- Move line/selection (Alt+Up/Down)
map("n", "<A-Down>", "<cmd>m .+1<CR>==", { desc = "Move line down" })
map("n", "<A-Up>",   "<cmd>m .-2<CR>==", { desc = "Move line up" })
map("i", "<A-Down>", "<Esc><cmd>m .+1<CR>==gi", { desc = "Move line down" })
map("i", "<A-Up>",   "<Esc><cmd>m .-2<CR>==gi", { desc = "Move line up" })
map("x", "<A-Down>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("x", "<A-Up>",   ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Duplicate line/selection (Alt+Shift+Up/Down)
map("n", "<A-S-Down>", "<cmd>t.<CR>",   { desc = "Duplicate line down" })
map("n", "<A-S-Up>",   "<cmd>t.-1<CR>", { desc = "Duplicate line up" })
map("i", "<A-S-Down>", "<Esc><cmd>t.<CR>gi",   { desc = "Duplicate line down" })
map("i", "<A-S-Up>",   "<Esc><cmd>t.-1<CR>gi", { desc = "Duplicate line up" })
map("x", "<A-S-Down>", ":t '><CR>gv", { desc = "Duplicate selection down" })
map("x", "<A-S-Up>",   ":t '<-1<CR>gv", { desc = "Duplicate selection up" })

-- Select all — C-a is tmux prefix, so use <leader>a in nvim
map("n", "<leader>a", "ggVG", { desc = "Select all" })

-- Save (Ctrl+S)
map({ "n", "x" }, "<C-s>", "<cmd>w<CR>",      { desc = "Save" })
map("i",          "<C-s>", "<Esc><cmd>w<CR>", { desc = "Save" })

-- Undo (Ctrl+Z) / Redo (Ctrl+Shift+Z)
map({ "n", "i" }, "<C-z>",   "<cmd>undo<CR>", { desc = "Undo" })
map({ "n", "i" }, "<C-S-z>", "<cmd>redo<CR>", { desc = "Redo" })

-- Toggle comment (Ctrl+/) — built-in commenting (nvim 0.10+)
-- Some terminals deliver Ctrl+/ as <C-_>; map both.
map("n", "<C-/>", "gcc", { desc = "Toggle comment", remap = true })
map("x", "<C-/>", "gc",  { desc = "Toggle comment", remap = true })
map("n", "<C-_>", "gcc", { desc = "Toggle comment", remap = true })
map("x", "<C-_>", "gc",  { desc = "Toggle comment", remap = true })

-- Keep selection after indent/outdent (Tab/Shift-Tab in visual)
map("x", "<Tab>",   ">gv", { desc = "Indent" })
map("x", "<S-Tab>", "<gv", { desc = "Outdent" })

-- Delete line (Ctrl+Shift+K)
map({ "n", "i" }, "<C-S-k>", "<cmd>delete<CR>", { desc = "Delete line" })
