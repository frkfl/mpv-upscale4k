-- Switches profiles based on video-bitrate for width >= 1600.
-- Threshold: 800000 bps (0.8 Mbps).

local threshold = 800000

local function apply_profile(bitrate)
    if bitrate >= threshold then
        mp.command("apply-profile 1080p_HQ")
        mp.msg.info("Applied 1080p_HQ (bitrate: " .. math.floor(bitrate / 1024) .. " Kbps)")
    else
        mp.command("apply-profile 1080p_LQ")
        mp.msg.info("Applied 1080p_LQ (bitrate: " .. math.floor(bitrate / 1024) .. " Kbps)")
    end
end

local function check_bitrate()
    local bitrate = mp.get_property_number("video-bitrate")
    if bitrate and bitrate > 0 then
        apply_profile(bitrate)
    else
        mp.add_timeout(0.5, check_bitrate)  -- Retry every 0.5s until available
    end
end

function on_file_loaded()
    local width = mp.get_property_number("width")
    if width == nil or width < 1600 then
        return
    end
    mp.add_timeout(0.1, check_bitrate)  -- Start checking shortly after load
end

mp.register_event("file-loaded", on_file_loaded)