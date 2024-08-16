local SessionInterface = require("time-tracker/interface").Interface:new({
  init = true,
  load_data = true,
  start_session = true,
  handle_activity = true,
  end_session = true,
})

--- @type TimeTracker
local TimeTracker = {
  --- @type SessionInterface
  impl = nil,

  new = function(self, session)
    assert(SessionInterface:implements(session))
    local tracker = {
      impl = session,
    }
    setmetatable(tracker, self)
    self.__index = self
    tracker.impl:init()
    return tracker
  end,

  load_data = function(self)
    return self.impl:load_data()
  end,

  start_session = function(self)
    return self.impl:start_session()
  end,

  handle_activity = function(self)
    return self.impl:handle_activity()
  end,

  end_session = function(self)
    return self.impl:end_session()
  end,
}

return {
  TimeTracker = TimeTracker,
}
