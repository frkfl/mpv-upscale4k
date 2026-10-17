-- Low-resolution dispatcher: applies [dvd] or [lowres] for width < 800 content.
-- Mirrors the 1080_profile.lua pattern — no profile-cond in the confs.
--
-- DVD detection:
--   AND: mpeg2 codec  +  width == 720  +  height == 480 or 576
--   OR (lazy, first match wins):
--     chapters > 0
--     audio-codec is ac3 / dts / eac3
--     pixel aspect ratio non-square (> 5% off 1:1)

local max_retries = 10

local function is_dvd()
    local codec   = mp.get_property("video-codec")
    local width   = mp.get_property_number("width")
    local height  = mp.get_property_number("height")
    local acodec  = mp.get_property("audio-codec")
    local chapters = mp.get_property_number("chapters")
    local par     = mp.get_property_number("video-params/par")

    -- Log everything so we can see what MPV actually reports
    mp.msg.info(string.format(
        "lowres dispatch: codec=%s width=%s height=%s acodec=%s chapters=%s par=%s",
        tostring(codec), tostring(width), tostring(height),
        tostring(acodec), tostring(chapters), tostring(par)
    ))

    -- AND: codec must contain "mpeg" + "2" with any separator (covers "MPEG-2 video", "mpeg2video", etc.)
    if codec == nil or not codec:lower():find("mpeg.?2") then
        mp.msg.info("DVD AND fail: codec=" .. tostring(codec))
        return false
    end
    if width ~= 720 then
        mp.msg.info("DVD AND fail: width=" .. tostring(width))
        return false
    end
    if height ~= 480 and height ~= 576 then
        mp.msg.info("DVD AND fail: height=" .. tostring(height))
        return false
    end

    -- Lazy OR
    chapters = chapters or 0
    if chapters > 0 then
        mp.msg.info("DVD OR hit: chapters=" .. chapters)
        return true
    end

    acodec = (acodec or ""):lower()
    if acodec:find("ac%-3") or acodec:find("ac3") or acodec:find("dts") or acodec:find("eac3") then
        mp.msg.info("DVD OR hit: acodec=" .. acodec)
        return true
    end

    if par ~= nil and math.abs(par - 1.0) > 0.05 then
        mp.msg.info("DVD OR hit: par=" .. string.format("%.3f", par))
        return true
    end

    mp.msg.info("DVD OR: no condition matched")
    return false
end

local retry_count = 0

local function dispatch()
    local codec = mp.get_property("video-codec")
    if codec ~= nil then
        retry_count = 0
        if is_dvd() then
            mp.command("apply-profile dvd")
            mp.msg.info("Applied dvd profile")
        else
            mp.command("apply-profile lowres")
            mp.msg.info("Applied lowres profile")
        end
    elseif retry_count < max_retries then
        retry_count = retry_count + 1
        mp.add_timeout(0.5, dispatch)
    else
        retry_count = 0
        mp.command("apply-profile lowres")
        mp.msg.warn("No codec after retries, defaulting to lowres")
    end
end

local function on_file_loaded()
    local width = mp.get_property_number("width")
    -- Only bail if width is definitively >= 800; nil means not yet known
    if width ~= nil and width >= 800 then return end

    retry_count = 0
    mp.add_timeout(0.1, dispatch)
end

mp.register_event("file-loaded", on_file_loaded)
