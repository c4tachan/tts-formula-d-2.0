mod_packed = false
setup_packed = false

function onLoad(saved_data)
    
    if saved_data ~= "" then
        local loaded_data = JSON.decode(saved_data)

        mod_packed = loaded_data.mp
        setup_packed = loaded_data.sp
    else
        mod_packed=true
        setup_packed=true
    end

    if mod_packed then
        UI.setAttribute("showModMenuButton", "active", true)
    else
        UI.setAttribute("showModMenuButton", "active", false)
    end
    --print("Mod, Setup packed: " .. tostring(mod_packed) .. ', ' .. tostring(setup_packed))
end

function onSave()
    local data_to_save = {["mp"]=mod_packed, ["sp"]=setup_packed}
    --print (data_to_save)
    saved_data = JSON.encode(data_to_save)
    self.script_state = saved_data

    return saved_data
end

function showModMenu()
    

    local memoryBagModMenuGUID = "a57988"
    local memoryBagModMenu = getObjectFromGUID(memoryBagModMenuGUID)

    memoryBagModMenu.call('buttonClick_place',{})
    mod_packed = false
    UI.setAttribute("showModMenuButton", "active", false)

end