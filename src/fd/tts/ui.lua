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

--- Forget what was sent: the UI has been rebuilt from its XML.
function Ui.reset()
    attrs, values = {}, {}
end

return Ui
