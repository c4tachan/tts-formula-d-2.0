-- Big Box mod menu board: track selection.
--
-- The 2020 version of this script was 1739 lines: three map URL tables plus one
-- near-identical `setupXxx()` handler per map, each paired by hand with a button
-- in the XML. Both sides now generate from tools/extract/maps.json, so adding a
-- track means adding one record there.

local Maps = require("fd.data.maps")

local MAP_TILE_GUID = "ebde54"
local SETUP_BAG_GUID = "0fde3b"
local MOD_MENU_BAG_GUID = "a57988"

local memoryBagSetup
local memoryBagModMenu

function onLoad()
    memoryBagSetup = getObjectFromGUID(SETUP_BAG_GUID)
    memoryBagModMenu = getObjectFromGUID(MOD_MENU_BAG_GUID)
end

-- TTS calls UI handlers as (player, value, elementId), where `value` is the
-- argument baked into the attribute, e.g. onClick="selectMap(FDMonaco)".

--- Swap the board tile to the chosen track.
function selectMap(player, mapId)
    local map = Maps.byId[mapId]
    if not map then
        broadcastToAll("Unknown track id: " .. tostring(mapId), { 1, 0.4, 0.4 })
        return
    end
    setMapImage(map.url)
    broadcastToAll(player.steam_name .. " selected " .. map.name, { 0.6, 0.9, 0.6 })
end

function setMapImage(url)
    local tile = getObjectFromGUID(MAP_TILE_GUID)
    if not tile then
        broadcastToAll("Map tile " .. MAP_TILE_GUID .. " is missing.", { 1, 0.4, 0.4 })
        return
    end
    local custom = tile.getCustomObject()
    custom.image = url
    custom.secondary_image = url
    tile.setCustomObject(custom)
    tile.reload()
end

local function showPanel(active)
    self.UI.setAttribute("menuButtonPanel", "active", active == nil)
    for _, id in ipairs({ "mapSelectionFD", "mapSelectionFDe", "mapSelectionCustom" }) do
        self.UI.setAttribute(id, "active", id == active)
    end
end

function returnToMenu() showPanel(nil) end
function openMapSelectionFD() showPanel("mapSelectionFD") end
function openMapSelectionFDe() showPanel("mapSelectionFDe") end
function openMapSelectionCustom() showPanel("mapSelectionCustom") end

function toggleHideSetup()
    if Global.getVar("setup_packed") then
        memoryBagSetup.call("buttonClick_place", {})
    else
        memoryBagSetup.call("buttonClick_recall", {})
    end
end

function hideModMenu()
    Global.setVar("mod_packed", true)
    memoryBagModMenu.call("buttonClick_recall", {})
    UI.setAttribute("showModMenuButton", "active", true)
end
