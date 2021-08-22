local M = {}

-- Edit user config file, based on the assumption it exists in the config as
-- theme = "theme name"
-- 1st arg as current theme, 2nd as new theme
M.change_theme = function(current_theme, new_theme)
   if current_theme == nil or new_theme == nil then
      print "Error: Provide current and new theme name"
      return false
   end
   if current_theme == new_theme then
      return
   end

   local user_config = vim.g.nvchad_user_config
   local file = vim.fn.stdpath "config" .. "/lua/" .. user_config .. ".lua"
   -- store in data variable
   local data = assert(M.file("r", file))
   -- escape characters which can be parsed as magic chars
   current_theme = current_theme:gsub("%p", "%%%0")
   new_theme = new_theme:gsub("%p", "%%%0")
   local find = "theme = .?" .. current_theme .. ".?"
   local replace = 'theme = "' .. new_theme .. '"'
   local content = string.gsub(data, find, replace)
   -- see if the find string exists in file
   if content == data then
      print("Error: Cannot change default theme with " .. new_theme .. ", edit " .. file .. " manually")
      return false
   else
      assert(M.file("w", file, content))
   end
end

-- clear command line from lua
M.clear_cmdline = function()
   vim.defer_fn(function()
      vim.cmd "echo"
   end, 0)
end

-- wrapper to use vim.api.nvim_echo
-- table of {string, highlight}
-- e.g echo({{"Hello", "Title"}, {"World"}})
M.echo = function(opts)
   if opts == nil or type(opts) ~= "table" then
      return
   end
   vim.api.nvim_echo(opts, false, {})
end

-- 1st arg - r or w
-- 2nd arg - file path
-- 3rd arg - content if 1st arg is w
-- return file data on read, nothing on write
M.file = function(mode, filepath, content)
   local data
   local fd = assert(vim.loop.fs_open(filepath, mode, 438))
   local stat = assert(vim.loop.fs_fstat(fd))
   if stat.type ~= "file" then
      data = false
   else
      if mode == "r" then
         data = assert(vim.loop.fs_read(fd, stat.size, 0))
      else
         assert(vim.loop.fs_write(fd, content, 0))
         data = true
      end
   end
   assert(vim.loop.fs_close(fd))
   return data
end

-- return a table of available themes
M.list_themes = function(return_type)
   local themes = {}
   -- folder where theme files are stored
   local themes_folder = vim.fn.stdpath "config" .. "/lua/colors/themes"
   -- list all the contents of the folder and filter out files with .lua extension, then append to themes table
   local fd = vim.loop.fs_scandir(themes_folder)
   if fd then
      while true do
         local name, typ = vim.loop.fs_scandir_next(fd)
         if name == nil then
            break
         end
         if typ ~= "directory" and string.find(name, ".lua") then
            -- return the table values as keys if specified
            if return_type == "keys_as_value" then
               themes[vim.fn.fnamemodify(name, ":r")] = true
            else
               table.insert(themes, vim.fn.fnamemodify(name, ":r"))
            end
         end
      end
   end
   return themes
end

-- reload a plugin ( will try to load even if not loaded)
-- can take a string or list ( table )
-- return true or false
M.reload_plugin = function(plugins)
   local status = true
   local function _reload_plugin(plugin)
      local loaded = package.loaded[plugin]
      if loaded then
         package.loaded[plugin] = nil
      end
      if not pcall(require, plugin) then
         print("Error: Cannot load " .. plugin .. " plugin!")
         status = false
      end
   end

   if type(plugins) == "string" then
      _reload_plugin(plugins)
   elseif type(plugins) == "table" then
      for _, plugin in ipairs(plugins) do
         _reload_plugin(plugin)
      end
   end
   return status
end

-- reload themes without restarting vim
-- if no theme name given then reload the current theme
M.reload_theme = function(theme_name)
   local reload_plugin = require("nvchad").reload_plugin

   -- if theme name is empty or nil, then reload the current theme
   if theme_name == nil or theme_name == "" then
      theme_name = vim.g.nvchad_theme
   end

   if not pcall(require, "colors.themes." .. theme_name) then
      print("No such theme ( " .. theme_name .. " )")
      return false
   end

   vim.g.nvchad_theme = theme_name

   -- reload the base16 theme and highlights
   require("colors").init(theme_name)

   if
      not reload_plugin {
         "plugins.configs.bufferline",
         "galaxyline",
         "plugins.configs.statusline",
      }
   then
      print "Error: Not able to reload all plugins."
      return false
   end

   -- yes, this is very hacky, but due to new_async in
   -- https://github.com/glepnir/galaxyline.nvim/blob/main/lua/galaxyline/provider.lua#L5-L36
   -- it doesn't work properly and some statusline stuff dissapears
   local vcs = require "galaxyline.provider_vcs"
   local fileinfo = require "galaxyline.provider_fileinfo"
   local buffer = require "galaxyline.provider_buffer"
   local extension = require "galaxyline.provider_extensions"
   local whitespace = require "galaxyline.provider_whitespace"
   local lspclient = require "galaxyline.provider_lsp"
   _G.galaxyline_providers = {
      BufferIcon = buffer.get_buffer_type_icon,
      BufferNumber = buffer.get_buffer_number,
      FileTypeName = buffer.get_buffer_filetype,
      GitBranch = vcs.get_git_branch,
      DiffAdd = vcs.diff_add,
      DiffModified = vcs.diff_modified,
      DiffRemove = vcs.diff_remove,
      LineColumn = fileinfo.line_column,
      FileFormat = fileinfo.get_file_format,
      FileEncode = fileinfo.get_file_encode,
      FileSize = fileinfo.get_file_size,
      FileIcon = fileinfo.get_file_icon,
      FileName = fileinfo.get_current_file_name,
      SFileName = fileinfo.filename_in_special_buffer,
      LinePercent = fileinfo.current_line_percent,
      ScrollBar = extension.scrollbar_instance,
      VistaPlugin = extension.vista_nearest,
      WhiteSpace = whitespace.get_item,
      GetLspClient = lspclient.get_lsp_client,
   }
   local diagnostic = require "galaxyline.provider_diagnostic"
   _G.galaxyline_providers.DiagnosticError = diagnostic.get_diagnostic_error
   _G.galaxyline_providers.DiagnosticWarn = diagnostic.get_diagnostic_warn
   _G.galaxyline_providers.DiagnosticHint = diagnostic.get_diagnostic_hint
   _G.galaxyline_providers.DiagnosticInfo = diagnostic.get_diagnostic_info

   return true
end

-- toggle between 2 themes
-- argument should be a table with 2 theme names
M.toggle_theme = function(themes)
   local current_theme = vim.g.current_nvchad_theme or vim.g.nvchad_theme
   for _, name in ipairs(themes) do
      if name ~= current_theme then
         if require("nvchad").reload_theme(name) then
            -- open a buffer and close it to reload the statusline
            vim.cmd "new|bwipeout"
            vim.g.current_nvchad_theme = name
            if M.change_theme(vim.g.nvchad_theme, name) then
               vim.g.nvchad_theme = name
            end
         end
      end
   end
end

-- update nvchad
M.update_nvchad = function()
   -- in all the comments below, config means user config
   local config_path = vim.fn.stdpath "config"
   local config_name = vim.g.nvchad_user_config or "chadrc"
   local config_file = config_path .. "/lua/" .. config_name .. ".lua"
   -- generate a random file name
   local config_file_backup = config_path .. "/" .. config_name .. ".lua.bak." .. math.random()
   local utils = require "nvchad"
   local echo = require("nvchad").echo
   local current_config = require("core.utils").load_config()
   local update_url = current_config.options.update_url or "https://github.com/NvChad/NvChad"
   local update_branch = current_config.options.update_branch or "main"

   -- ask the user for confirmation to update because we are going to run git reset --hard
   echo { { "Url: ", "Title" }, { update_url } }
   echo { { "Branch: ", "Title" }, { update_branch } }
   echo {
      { "\nUpdater will run", "WarningMsg" },
      { " git reset --hard " },
      {
         "in config folder, so changes to existing repo files except ",
         "WarningMsg",
      },

      { config_name },
      { " will be lost!\n\nUpdate NvChad ? [y/N]", "WarningMsg" },
   }

   local ans = string.lower(vim.fn.input "-> ") == "y"
   utils.clear_cmdline()
   if not ans then
      echo { { "Update cancelled!", "Title" } }
      return
   end

   -- first try to fetch contents of config, this will make sure it is readable and taking backup of its contents
   local config_contents = utils.file("r", config_file)
   -- also make a local backup in ~/.config/nvim, will be removed when config is succesfully restored
   utils.file("w", config_file_backup, config_contents)
   -- write original config file with its contents, will make sure charc is writable, this maybe overkill but a little precaution always helps
   utils.file("w", config_file, config_contents)

   -- function that will executed when git commands are done
   local function update_exit(_, code)
      -- restore config file irrespective of whether git commands were succesfull or not
      if pcall(function()
         utils.file("w", config_file, config_contents)
      end) then
         -- config restored succesfully, remove backup file that was created
         if not pcall(os.remove, config_file_backup) then
            echo { { "Warning: Failed to remove backup chadrc, remove manually.", "WarningMsg" } }
            echo { { "Path: ", "WarningMsg" }, { config_file_backup } }
         end
      else
         echo { { "Error: Restoring " .. config_name .. " failed.\n", "ErrorMsg" } }
         echo { { "Backed up " .. config_name .. " path: " .. config_file_backup .. "\n\n", "None" } }
      end

      -- close the terminal buffer only if update was success, as in case of error, we need the error message
      if code == 0 then
         vim.cmd "bd!"
         echo { { "NvChad succesfully updated.\n", "String" } }
      else
         echo { { "Error: NvChad Update failed.\n", "ErrorMsg" } }
      end
   end

   -- git commands that will executed, reset in case config was modfied
   -- use --rebase, to not mess up if the local repo is outdated
   local update_script = table.concat({
      "git reset --hard && git pull --set-upstream",
      update_url,
      update_branch,
      "--rebase",
   }, " ")

   -- open a new buffer
   vim.cmd "new"
   -- finally open the pseudo terminal buffer
   vim.fn.termopen(update_script, {
      -- change dir to config path so we don't need to move in script
      cwd = config_path,
      on_exit = update_exit,
   })
end

return M