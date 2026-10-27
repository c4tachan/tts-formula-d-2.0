-- UI updates that only go out when they change something.
--
-- Every UI.setAttribute and UI.setValue is sent to every player's client, and
-- a refresh after each click sets the same values over and over. This keeps
-- the last value sent for each element and drops the repeats.
--
-- Setting the whole XML (UI.setXmlTable) puts every element back to what the
-- XML says, so call reset() whenever that happens.

local Ui = {}

local attrs, values = {}, {}

function Ui.set(id, attr, value)
    value = tostring(value)
    local key = id .. "\0" .. attr
    if attrs[key] == value then
        return
    end
    attrs[key] = value
    UI.setAttribute(id, attr, value)
end

function Ui.value(id, value)
    value = value == nil and "" or tostring(value)
    if values[id] == value then
        return
    end
    values[id] = value
    UI.setValue(id, value)
end

--- Forget what was sent: the UI has been rebuilt from its XML. With
-- `prefix`, only for the elements whose ids start with it.
function Ui.reset(prefix)
    if not prefix then
        attrs, values = {}, {}
        return
    end
    for key in pairs(attrs) do
        if key:sub(1, #prefix) == prefix then attrs[key] = nil end
    end
    for id in pairs(values) do
        if id:sub(1, #prefix) == prefix then values[id] = nil end
    end
end

return Ui
