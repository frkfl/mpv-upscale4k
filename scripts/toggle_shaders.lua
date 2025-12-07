local mp = require "mp"

local saved_shaders = nil

local function toggle_shaders()
    local cur = mp.get_property("glsl-shaders") or ""

    if saved_shaders == nil then
        -- Save current shaders and clear
        if cur ~= "" then
            saved_shaders = cur
            mp.set_property("glsl-shaders", "")
            mp.osd_message("GLSL shaders: OFF")
        else
            mp.osd_message("GLSL shaders: already OFF")
        end
    else
        -- Restore saved shaders
        mp.set_property("glsl-shaders", saved_shaders)
        saved_shaders = nil
        mp.osd_message("GLSL shaders: ON")
    end
end

mp.add_key_binding(nil, "toggle-shaders", toggle_shaders)
