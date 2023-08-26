local ksb_util = require('kitty-scrollback.util')
local M = {}

local p
local opts

M.setup = function(private, options)
  p = private
  opts = options
end

-- copied from https://github.com/folke/lazy.nvim/blob/dac844ed617dda4f9ec85eb88e9629ad2add5e05/lua/lazy/view/float.lua#L70
M.size = function(max, value)
  return value > 1 and math.min(value, max) or math.floor(max * value)
end

M.paste_winopts = function(row, col, height_offset)
  local target_height    = M.size(vim.o.lines, math.floor(M.size(vim.o.lines, (vim.o.lines + 2) / 3))) + (height_offset or 0)
  local line_height_diff = vim.o.lines - row - target_height
  if line_height_diff < 0 then
    row = row - target_height - 2
  end
  local winopts = {
    relative = 'editor',
    zindex = 40,
    focusable = true,
    border = { '🭽', '▔', '🭾', '▕', '🭿', '▁', '🭼', '▏' },
    height = target_height,
  }
  if row then
    winopts.row = row
  end
  if col then
    winopts.col = col
    winopts.width = M.size(vim.o.columns, vim.o.columns - col) - 1
    if winopts.width < 0 then
      -- current line is larger than window, put window below current line
      vim.fn.setcursorcharpos({ vim.fn.line('.'), 0 })
      vim.cmd.redraw()
      winopts.width = vim.o.columns - 1
      winopts.col = 0
    end
  end
  return winopts
end

M.legend_winopts = function(paste_winopts)
  return {
    relative = 'win',
    win = p.paste_winid,
    zindex = paste_winopts.zindex + 1,
    focusable = false,
    border = { '▏', ' ', '▕', '▕', '🭿', '▁', '🭼', '▏' },
    height = 1,
    width = paste_winopts.width,
    row = paste_winopts.height + 1,
    col = -1,
    style = 'minimal',
  }
end

M.open_legend_window = function(winopts, refresh_only)
  if not p.paste_winid then
    return
  end

  if not refresh_only or refresh_only == nil then
    -- if buffer already exists, assume window is already created and just readjust
    p.legend_bufid = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_option_value('filetype', 'help', {
      buf = p.legend_bufid,
    })

    p.legend_winid = vim.api.nvim_open_win(p.legend_bufid, false, M.legend_winopts(winopts))

    vim.api.nvim_set_option_value('conceallevel', 2, {
      win = p.legend_winid,
    })
  end

  local legend_msg = { '<leader>|y| Copy ', '<ctrl-enter> Execute ', '<shift-enter> Paste ', '*:w[rite]* Paste ', '*g?* Toggle Mappings' }
  local padding = math.floor(winopts.width / #legend_msg)
  local string_with_padding = '%' .. padding .. 's'
  local string_with_half_padding = '%' .. math.floor(padding / 4) .. 's'
  local first = true
  legend_msg =
    vim.tbl_map(function(msg)
      if first then
        first = false
        return string.format(string_with_half_padding .. '%s', ' ', msg)
      end
      return string.format(string_with_padding, msg)
    end, legend_msg)
  vim.api.nvim_buf_set_lines(p.legend_bufid, 0, -1, false,
    { table.concat(legend_msg) }
  )

  vim.api.nvim_set_option_value('winhighlight',
    'Normal:KittyScrollbackNvimPasteWinNormal,FloatBorder:KittyScrollbackNvimPasteWinFloatBorder,FloatTitle:KittyScrollbackNvimPasteWinFloatTitle',
    { win = p.legend_winid, }
  )
end

M.open_paste_window = function(start_insert)
  vim.cmd.stopinsert()
  vim.fn.cursor({ vim.fn.line('$'), 0 })
  if opts.kitty_get_text.extent == 'screen' or opts.kitty_get_text.extent == 'all' then
    vim.fn.search('.', 'b')
  end

  local lnum = ksb_util.size(vim.o.lines, vim.fn.winline() - 2 - vim.o.cmdheight)
  local col = vim.fn.wincol()
  if not p.paste_bufid then
    p.paste_bufid = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(p.paste_bufid, vim.fn.tempname())
    vim.api.nvim_set_option_value('filetype', 'sh', {
      buf = p.paste_bufid,
    })
  end
  if not p.paste_winid or vim.fn.win_id2win(p.paste_winid) == 0 then
    local winopts = M.paste_winopts(lnum, col)
    p.paste_winid = vim.api.nvim_open_win(p.paste_bufid, true, winopts)
    vim.api.nvim_set_option_value('scrolloff', 2, {
      win = p.paste_winid,
    })

    vim.schedule_wrap(M.open_legend_window)(winopts)

    local normal_hl = vim.api.nvim_get_hl(0, {
      name = 'Normal',
      link = false,
    })
    local normal_bg_color = normal_hl.bg or p.kitty_colors.background
    local floatborder_fg_color = ksb_util.darken(p.kitty_colors.foreground, 0.3, p.kitty_colors.background)

    vim.api.nvim_set_hl(0, 'KittyScrollbackNvimPasteWinNormal', {
      bg = normal_bg_color,
      blend = 4
    })
    vim.api.nvim_set_hl(0, 'KittyScrollbackNvimPasteWinFloatBorder', {
      bg = normal_bg_color,
      fg = floatborder_fg_color,
      blend = 4
    })
    vim.api.nvim_set_hl(0, 'KittyScrollbackNvimPasteWinFloatTitle', {
      bg = floatborder_fg_color,
      fg = normal_bg_color,
      blend = 4
    })
    vim.api.nvim_set_option_value('winhighlight',
      'Normal:KittyScrollbackNvimPasteWinNormal,FloatBorder:KittyScrollbackNvimPasteWinFloatBorder,FloatTitle:KittyScrollbackNvimPasteWinFloatTitle',
      { win = p.paste_winid, }
    )
    vim.api.nvim_set_option_value('winblend',
      4,
      { win = p.paste_winid, }
    )
  end
  if start_insert then
    vim.schedule(function()
      vim.fn.cursor(vim.fn.line('$', p.paste_winid), 1)
      vim.cmd.startinsert({ bang = true })
    end)
  end
  vim.cmd.redraw()
  vim.schedule_wrap(vim.cmd.doautocmd)('WinResized')
end

M.show_status_window = function()
  if opts.status_window.enabled then
    local kitty_icon = '󰄛'
    local love_icon = ''
    local vim_icon = ''
    local width = 9
    if opts.status_window.style_simple then
      kitty_icon = 'kitty-scrollback.nvim'
      love_icon = ''
      vim_icon = ''
      width = 25
    end
    local popup_bufid = vim.api.nvim_create_buf(false, true)
    local winopts = function()
      return {
        relative = 'editor',
        zindex = 39,
        style = 'minimal',
        focusable = false,
        width = ksb_util.size(p.orig_columns or vim.o.columns, width),
        height = 1,
        row = 0,
        col = vim.o.columns,
        border = 'none',
      }
    end
    local popup_winid = vim.api.nvim_open_win(popup_bufid, false,
      vim.tbl_deep_extend('force', winopts(), {
        noautocmd = true,
      })
    )
    vim.api.nvim_set_option_value('winhighlight', 'NormalFloat:KittyScrollbackNvimNormal', {
      win = popup_winid,
    })
    local count = 0
    local spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏', '✔' }
    if opts.status_window.style_simple then
      spinner = { '-', '-', '\\', '\\', '|', '|', '/', '/', '-', '-', '*' }
    end
    vim.fn.timer_start(
      80,
      function(status_window_timer) ---@diagnostic disable-line: redundant-parameter
        count = count + 1
        local spinner_icon = count > #spinner and spinner[#spinner] or spinner[count]
        local fmt_msg = ' ' .. spinner_icon .. ' ' .. kitty_icon .. ' ' .. love_icon .. ' ' .. vim_icon .. ' '
        vim.defer_fn(function()
          if spinner_icon == '' then
            vim.fn.timer_stop(status_window_timer)
            fmt_msg = ' ' .. kitty_icon .. ' ' .. love_icon .. ' ' .. vim_icon .. ' '
            local ok, _ = pcall(vim.api.nvim_win_get_config, popup_winid)
            if ok then
              vim.schedule(function()
                pcall(vim.api.nvim_win_set_config, popup_winid, vim.tbl_deep_extend('force', winopts(), {
                  width = ksb_util.size(p.orig_columns or vim.o.columns, winopts().width - 2)
                }))
              end)
            end
          end
          vim.api.nvim_buf_set_lines(popup_bufid, 0, -1, false, {})
          vim.api.nvim_buf_set_lines(popup_bufid, 0, -1, false, {
            fmt_msg
          })

          local nid = vim.api.nvim_create_namespace('scrollbacknvim')
          local startcol = 0
          local endcol = 0
          if spinner_icon ~= '' then
            endcol = #spinner_icon + 2
            vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, startcol, {
              hl_group = count >= #spinner and 'KittyScrollbackNvimReady' or 'KittyScrollbackNvimSpinner',
              end_col = endcol,
            })
          end
          if not opts.status_window.style_simple then
            startcol = endcol
            endcol = endcol + #kitty_icon + 1
            vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, startcol, {
              hl_group = 'KittyScrollbackNvimKitty',
              end_col = endcol,
            })
            startcol = endcol
            endcol = endcol + #love_icon + 1
            vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, startcol, {
              hl_group = 'KittyScrollbackNvimHeart',
              end_col = endcol,
            })
            startcol = endcol
            endcol = #fmt_msg
            vim.api.nvim_buf_set_extmark(popup_bufid, nid, 0, startcol, {
              hl_group = 'KittyScrollbackNvimVim',
              end_col = endcol
            })
          end
          if opts.status_window.autoclose then
            if count > #spinner then
              vim.fn.timer_start(60, function(close_window_timer) ---@diagnostic disable-line: redundant-parameter
                local ok, current_winopts = pcall(vim.api.nvim_win_get_config, popup_winid)
                if not ok then
                  vim.fn.timer_stop(close_window_timer)
                  vim.fn.timer_stop(status_window_timer)
                  return
                end
                if current_winopts.width > 2 then
                  ok, _ = pcall(vim.api.nvim_win_set_config, popup_winid, vim.tbl_deep_extend('force', winopts(), {
                    width = ksb_util.size(p.orig_columns or vim.o.columns, current_winopts.width - 1)
                  }))
                  if not ok then
                    vim.fn.timer_stop(close_window_timer)
                    vim.fn.timer_stop(status_window_timer)
                    return
                  end
                else
                  pcall(vim.api.nvim_win_close, popup_winid, true)
                  vim.fn.timer_stop(close_window_timer)
                  vim.fn.timer_stop(status_window_timer)
                end
              end, {
                ['repeat'] = -1,
              })
            end
          else
            if count > #spinner then
              local hl_def = vim.api.nvim_get_hl(0, {
                name = 'KittyScrollbackNvimReady',
              })
              local fg_dec = hl_def.fg
              local fg_hex = string.format('#%06x', fg_dec)
              local darken_hex = ksb_util.darken(fg_hex, 0.7)
              vim.api.nvim_set_hl(0, 'KittyScrollbackNvimReady', {
                fg = darken_hex
              })
              if count > #spinner + (#spinner / 2) then
                spinner[#spinner] = ''
              end
            end
          end
        end, count > #spinner and 200 or 0)
      end, {
        ['repeat'] = -1,
      }
    )
    vim.api.nvim_create_autocmd('WinResized', {
      group = vim.api.nvim_create_augroup('KittyScrollBackNvimStatusWindowResized', { clear = true }),
      callback = function()
        local ok, current_winopts = pcall(vim.api.nvim_win_get_config, popup_winid)
        if not ok then
          return true
        end
        ok, _ = pcall(vim.api.nvim_win_set_config, popup_winid, vim.tbl_deep_extend('force', winopts(), {
          width = ksb_util.size(vim.o.columns, current_winopts.width)
        }))
        return not ok
      end,
    })
  end
end

return M
