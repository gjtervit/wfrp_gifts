-- wfrp_gifts - client.lua
-- AFK heartbeat with: movement, keypress, RedM PTT (N), pma-voice radioActive,
-- safe voice checks (Mumble/Network), and optional DEBUG prints.

-- =====================
-- SETTINGS
-- =====================
local HEARTBEAT_SEC     = 10         -- send every 10s
local MIN_MOVE_METERS   = 3.0        -- count as movement if >= this many meters since last ping
local TRACK_CONTROLS    = true       -- treat keypresses as activity
local DEBUG_AFK_CLIENT  = false      -- set true to print why activity is (not) detected

-- =====================
-- Back-compat (no-op)
-- =====================
RegisterNetEvent("ricxmas_gift:triggergift")
AddEventHandler("ricxmas_gift:triggergift", function() end)

-- =====================
-- Notification proxy
-- =====================
RegisterNetEvent('Notification:left_xmas')
AddEventHandler('Notification:left_xmas', function(t1, t2, dict, txtr, timer)
    if not HasStreamedTextureDictLoaded(dict) then
        RequestStreamedTextureDict(dict, true)
        while not HasStreamedTextureDictLoaded(dict) do
            Wait(5)
        end
    end
    local res = GetCurrentResourceName()
    exports[res]:LeftNot(
        tostring(t1 or ""),
        tostring(t2 or ""),
        tostring(dict or "scoretimer_textures"),
        tostring(txtr or "scoretimer_generic_tick"),
        tonumber(timer or 6000)
    )
end)

-- =====================
-- Helpers
-- =====================
local function dist(a, b)
    if not a or not b then return 0.0 end
    local ax, ay, az = a.x or a[1], a.y or a[2], a.z or a[3]
    local bx, by, bz = b.x or b[1], b.y or b[2], b.z or b[3]
    if not (ax and ay and az and bx and by and bz) then return 0.0 end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function isPlayerTalkingSafe()
    if type(NetworkIsPlayerTalking) == "function" then
        local ok, result = pcall(NetworkIsPlayerTalking, PlayerId())
        if ok and result then return true end
    end
    if type(MumbleIsPlayerTalking) == "function" then
        local ok, result = pcall(MumbleIsPlayerTalking, PlayerId())
        if ok and result then return true end
    end
    return false
end

-- =====================
-- Inputs tracked
-- =====================
local movementControls = {
    30,31,32,33,34,35,  -- A/D/W/S + sprint + jump
    21,22,24,25,44,51   -- sprint/cover/attack/aim/etc.
}

-- PTT: RedM "N" hash + FiveM fallback
local PTT_CONTROLS = {
    [0x4BC9DABB] = true, -- RedM hash: N (Push-to-Talk)
    [249]        = true, -- FiveM fallback; harmless on RedM
}

-- pma-voice radio transmit flag
local radioTalking = false
AddEventHandler('pma-voice:radioActive', function(active)
    radioTalking = active and true or false
    if DEBUG_AFK_CLIENT then
        print(('[wfrp_gifts][AFK] pma-voice radioActive = %s'):format(tostring(radioTalking)))
    end
    if radioTalking then
        -- Ensure AFK clears even between heartbeats
        TriggerServerEvent("wfrp_gifts:heartbeat", true)
    end
end)

local function anyControlPressed()
    if not TRACK_CONTROLS then return false end

    -- 1) PTT keys
    for code, _ in pairs(PTT_CONTROLS) do
        if IsControlPressed(0, code) or IsControlJustPressed(0, code) or IsDisabledControlPressed(0, code) then
            if DEBUG_AFK_CLIENT then print('[wfrp_gifts][AFK] Active via PTT key') end
            return true
        end
    end

    -- 2) Movement/action keys
    for _, c in ipairs(movementControls) do
        if IsControlPressed(0, c) or IsControlJustPressed(0, c) or IsDisabledControlPressed(0, c) then
            if DEBUG_AFK_CLIENT then print('[wfrp_gifts][AFK] Active via control '..tostring(c)) end
            return true
        end
    end

    -- 3) pma-voice radio
    if radioTalking then
        if DEBUG_AFK_CLIENT then print('[wfrp_gifts][AFK] Active via pma-voice radio') end
        return true
    end

    -- 4) Voice activity fallback
    if isPlayerTalkingSafe() then
        if DEBUG_AFK_CLIENT then print('[wfrp_gifts][AFK] Active via talking native') end
        return true
    end

    return false
end

-- =====================
-- Heartbeat
-- =====================
CreateThread(function()
    local last = nil
    while true do
        Wait(HEARTBEAT_SEC * 1000)
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local moved = dist(last, pos)
        local active = (moved >= MIN_MOVE_METERS) or anyControlPressed()
        if DEBUG_AFK_CLIENT then
            print(('[wfrp_gifts][AFK] moved=%.2f active=%s'):format(moved, tostring(active)))
        end
        TriggerServerEvent("wfrp_gifts:heartbeat", active)
        last = pos
    end
end)
