## time-tracker.nvim

![image](https://github.com/3rd/time-tracker.nvim/assets/59587503/393550f7-e473-433f-a027-6b184472dc5d)

This is a Neovim plugin that tracks the time you spend working on your projects.
It will index your projects based on the current working directory, and track the time spent on each file within the project.

### Features

- Automatically tracks time spent on each project and file
- Displays project stats for the current session and all-time totals
- Displays all-time totals for all the tracked projects
- Small and easy to customize

### Setup & requirements

The data is stored in a SQLite database, you need to have `sqlite3` in your `PATH`.

**Install (Lazy):**

```lua
{
    "3rd/time-tracker.nvim",
    dependencies = {
        "3rd/sqlite.nvim",
    },
    event = "VeryLazy",
    opts = {
        data_file = vim.fn.stdpath("data") .. "/time-tracker.db",
    },
}
```

You need to call the setup function, optionally passing a configuration object (defaults below):

```lua
require("time-tracker").setup({
  data_file = vim.fn.stdpath("data") .. "/time-tracker.db",
  tracking_events = { "BufEnter", "BufWinEnter", "CursorMoved", "CursorMovedI", "WinScrolled" },
  tracking_timeout_seconds = 5 * 60, -- 5 minutes
})
```

### Usage

**time-tracker.nvim** automatically starts tracking time when you open Neovim and switch between projects or files.

- `:TimeTracker` - Opens a pretty window that shows your stats.

In the stats window, you can use the following key mappings:

- `q`: Close the time tracking window
- `c`: Show statistics for the current project
- `a`: Show statistics for all projects

### Development

```sh
git clone --recurse-submodules https://github.com/3rd/time-tracker.nvim
cd time-tracker.nvim
make # you'll see all the available commands
```
