## time-tracker.nvim

![image](https://github.com/3rd/time-tracker.nvim/assets/59587503/eb893321-2c2c-4291-abbb-ce91987c5916)

This is a Neovim plugin that tracks the time you spend working on your projects.
It will index your projects based on the current working directory, and track the time spent on each file within the project.

## Features

- Automatically tracks time spent on each project and file
- Displays project stats for the current session and all-time totals
- Displays all-time totals for all the tracked projects
- Small and easy to customize

## Setup

You need to call the setup function, optionally passing a configuration object (defaults below):

```lua
require("time-tracker").setup({
  data_file = vim.fn.stdpath("data") .. "/time-tracker.json",
  tracking_events = { "BufEnter", "BufWinEnter", "CursorMoved", "CursorMovedI", "WinScrolled" },
  tracking_timeout_seconds = 300, -- 5 minutes
  buffer_tracking_enabled = true,
})
```

## Usage

**time-tracker.nvim** automatically starts tracking time when you open Neovim and switch between projects or files.
\
You can interact with your data by using the following commands:

- `:TimeTracker` - Opens a pretty window that shows the tracked data.
- `:TimeTrackerData` - Opens the JSON file containing the raw time tracking data.

In the stats window, you can use the following key mappings:

- `q`: Close the time tracking window
- `c`: Show statistics for the current project
- `a`: Show statistics for all projects
