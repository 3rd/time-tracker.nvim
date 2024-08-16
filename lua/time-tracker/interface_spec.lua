local Interface = require("time-tracker/interface").Interface

local SessionInterface = Interface:new({
  init = true,
  start_session = true,
  end_session = true,
})

local FakeImpl = {
  init = function() end,
  start_session = function() end,
  end_session = function() end,
}
local InvalidImpl = {
  start_session = function() end,
  end_session = function() end,
}

describe("Interface", function()
  it("implements interface", function()
    expect(SessionInterface:implements(FakeImpl)).toBe(true)
    expect(SessionInterface:implements(InvalidImpl)).toBe(false)
  end)
end)
