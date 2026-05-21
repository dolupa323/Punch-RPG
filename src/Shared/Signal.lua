-- Signal.lua
-- Simple BindableEvent based signal implementation for event‑driven communication

local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({ Event = Instance.new("BindableEvent") }, Signal)
    return self
end

function Signal:Fire(...)
    self.Event:Fire(...)
end

function Signal:Connect(fn)
    return self.Event.Event:Connect(fn)
end

function Signal:Wait()
    return self.Event.Event:Wait()
end

return Signal
