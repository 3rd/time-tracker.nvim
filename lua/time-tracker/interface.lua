--- @type Interface
local Interface = {
  new = function(self, interface)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    self.interface = interface
    return obj
  end,

  implements = function(self, interface)
    for k, _ in pairs(self.interface) do
      if type(interface[k]) ~= "function" then return false end
    end
    return true
  end,
}

return {
  Interface = Interface,
}
