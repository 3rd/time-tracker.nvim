local t = require("testing")

describe("expect", function()
  it("asserts .toBe(value)", function()
    expect(1).toBe(1)
    expect(vim).toBe(vim)
  end)

  it("asserts .n.toBe(value)", function()
    expect(1).n.toBe(2)
    expect(vim).n.toBe(vim.api)
    expect({}).n.toBe({})
  end)

  it("asserts .toEqual(value)", function()
    expect(1).toEqual(1)
    expect(vim).toEqual(vim)
    expect({}).toEqual({})
    expect({ a = 1 }).toEqual({ a = 1 })
  end)

  it("asserts .n.toEqual(value)", function()
    expect(1).n.toEqual(2)
    expect(vim).n.toEqual(vim.api)
    expect({}).n.toEqual({ 1 })
    expect({ a = 1 }).n.toEqual({ a = 2 })
  end)

  it("asserts .toContain(value)", function()
    expect({ 1, 2, 3 }).toContain(2)
  end)
  it("asserts .n.toContain(value)", function()
    expect({ 1, 2, 3 }).n.toContain(4)
  end)

  it("asserts .toMatch(value)", function()
    expect("foobar").toMatch("foo")
  end)
  it("asserts .n.toMatch(value)", function()
    expect("foobar").n.toMatch("baz")
  end)

  it("asserts .toThrow()", function()
    expect(function()
      error("foo")
    end).toThrow("foo")
  end)
  it("asserts .n.toThrow()", function()
    expect(function() end).n.toThrow()
  end)

  it("asserts .toThrow(error)", function()
    expect(function()
      error("foo")
    end).toThrow("foo")
  end)
  it("asserts .n.toThrow(error)", function()
    expect(function()
      error("foo")
    end).n.toThrow("bar")
  end)
end)

describe("milkshake", function()
  it("brings all the boys to the yard", function()
    local target = {
      bring_boys = function()
        return false
      end,
    }
    local spy = t.spy(target, "bring_boys")

    expect(target.bring_boys()).toBe(false)
    expect(spy).toHaveBeenCalled()

    spy.mockReturnValueOnce(true)
    expect(target.bring_boys()).toBe(true)
    expect(target.bring_boys()).toBe(false)

    expect(spy).n.toHaveBeenCalledTimes(3)
  end)
end)
