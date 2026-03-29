-- Switches profiles based on video-bitrate for width >= 1600.
-- Threshold: 800000 bps (0.8 Mbps).

local threshold = 800000
local max_retries = 20  -- 10 seconds max; raw captures have no bitrate, default to HQ

local function apply_profile(bitrate)
    if bitrate >= threshold then
        mp.command("apply-profile 1080p_HQ")
        mp.msg.info("Applied 1080p_HQ (bitrate: " .. math.floor(bitrate / 1024) .. " Kbps)")
    else
        mp.command("apply-profile 1080p_LQ")
        mp.msg.info("Applied 1080p_LQ (bitrate: " .. math.floor(bitrate / 1024) .. " Kbps)")
    end
end

local retry_count = 0

local function check_bitrate()
    local bitrate = mp.get_property_number("video-bitrate")
    if bitrate and bitrate > 0 then
        retry_count = 0
        apply_profile(bitrate)
    elseif retry_count < max_retries then
        retry_count = retry_count + 1
        mp.add_timeout(0.5, check_bitrate)
    else
        retry_count = 0
        mp.command("apply-profile 1080p_HQ")
        mp.msg.info("Applied 1080p_HQ (no bitrate detected, raw/live source)")
    end
end

function on_file_loaded()
    local width = mp.get_property_number("width")
    if width == nil or width < 1600 then
        return
    end
    retry_count = 0
    mp.add_timeout(0.1, check_bitrate)  -- Start checking shortly after load
end

mp.register_event("file-loaded", on_file_loaded)