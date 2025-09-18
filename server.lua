-- wfrp_gifts - server.lua (PLAYTIME-BASED with AFK gating + AFK/Back-from-AFK console prints)

-- =====================
-- Config / guards
-- =====================
local function clampMinutes(v, default)
    v = tonumber(v) or default
    if v < 1 then v = 1 end
    return v
end

local framework = (Config.Framework or "vorp"):lower()
local minutesPerGift = clampMinutes(Config.MinutesOnlinePerGift or 60, 60)

-- AFK gating (server-side thresholds)
local AFK_ACTIVE_TIMEOUT = tonumber((Config.AFK and Config.AFK.ActiveTimeoutSeconds) or 90) or 90
if AFK_ACTIVE_TIMEOUT < 30 then AFK_ACTIVE_TIMEOUT = 30 end -- sanity

-- Optional Discord logging (prefer convar at runtime)
CreateThread(function()
    local cv = GetConvar("wfrp_gifts_webhook", "")
    if cv and cv ~= "" then
        Config.DiscordWebhook = cv
    end
end)

-- Discord embed with timestamp
local function sendToDiscord(msg)
    if not Config.DiscordWebhook or Config.DiscordWebhook == "" then return end
    local nowISO = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local payload = {
        username = Config.DiscordLogName or "Gifts",
        embeds = {{
            description = msg,
            timestamp = nowISO
        }}
    }
    PerformHttpRequest(
        Config.DiscordWebhook,
        function() end,
        "POST",
        json.encode(payload),
        {["Content-Type"]="application/json"}
    )
end

-- =====================
-- Stable identifier
-- =====================
local function getStableId(src)
    local ids = GetPlayerIdentifiers(src) or {}
    local best
    for _, id in ipairs(ids) do
        if id:sub(1,8) == "license:" then best = id break end
    end
    if not best then
        for _, id in ipairs(ids) do
            if id:sub(1,6) == "steam:" then best = id break end
        end
    end
    return best or ids[1] or ("src:"..tostring(src))
end

-- =====================
-- Persistence (playtime minutes since last gift)
-- =====================
local PLAY_FILE = GetResourcePath(GetCurrentResourceName()) .. "/GiftPlaytime.json"

local playMinutes = {}   -- pid -> minutes accumulated toward next gift

local function loadPlaytime()
    local f = io.open(PLAY_FILE, "r")
    if not f then return end
    local raw = f:read("*a"); f:close()
    if raw and #raw > 0 then
        local ok, data = pcall(function() return json.decode(raw) end)
        if ok and type(data) == "table" then
            playMinutes = data
        end
    end
end

local function savePlaytime()
    local f, err = io.open(PLAY_FILE, "w+")
    if not f then
        print(("[wfrp_gifts] savePlaytime: failed to open %s (%s)"):format(PLAY_FILE, tostring(err)))
        return
    end
    f:write(json.encode(playMinutes or {}))
    f:close()
    --print(("[wfrp_gifts] playtime saved to %s"):format(PLAY_FILE))
end

AddEventHandler("onResourceStart", function(res)
    if GetCurrentResourceName() ~= res then return end
    loadPlaytime()
end)

AddEventHandler("onResourceStop", function(res)
    if GetCurrentResourceName() ~= res then return end
    savePlaytime()
end)

-- periodic autosave every 5 minutes
CreateThread(function()
    while true do
        Wait(5 * 60 * 1000)
        savePlaytime()
    end
end)

-- =====================
-- Activity tracking (AFK gating)
-- =====================
-- pid -> unix time of last ACTIVE heartbeat
local lastActiveAt = {}
-- pid -> whether we've ever seen activity since join (prevents false initial AFK prints)
local hasSeenActive = {}
-- pid -> current AFK state (boolean)
local isAfk = {}

RegisterNetEvent("wfrp_gifts:heartbeat")
AddEventHandler("wfrp_gifts:heartbeat", function(active)
    local src = source
    local pid = getStableId(src)
    if active then
        lastActiveAt[pid] = os.time()
        hasSeenActive[pid] = true
        if isAfk[pid] then
            isAfk[pid] = false
            --print(("[wfrp_gifts] BACK: %s (%d) returned from AFK"):format(GetPlayerName(src) or "Unknown", src))
        end
    end
end)

AddEventHandler("playerDropped", function()
    savePlaytime()
end)

-- =====================
-- Framework bridges
-- =====================
local function addMoneyVorp(source, amount)
    local ok, V = pcall(function() return VORP end)
    local core = ok and V or nil
    if core and core.getCharacter then
        local Character = core.getCharacter(source)
        if Character and Character.addCurrency then Character.addCurrency(0, amount) end
    else
        if exports and exports.vorp_core and exports.vorp_core.getCharacter then
            local Character = exports.vorp_core:getCharacter(source)
            if Character and Character.addCurrency then Character.addCurrency(0, amount) end
        end
    end
end

local function addItemVorp(source, item, count, meta)
    local inv = exports and exports.vorp_inventory
    if not inv or not inv.addItem then return false, "vorp_inventory export missing" end
    local ok, err = pcall(function() inv:addItem(source, item, count or 1, meta or {}) end)
    if not ok then return false, tostring(err) end
    return true
end

local function addItemQBR(source, item, count)
    if exports and exports['qbr-inventory'] and exports['qbr-inventory'].AddItem then
        local ok, err = pcall(function() exports['qbr-inventory']:AddItem(source, item, count or 1) end)
        if not ok then return false, tostring(err) end
        return true
    end
    return false, "qbr-inventory export missing"
end

local function addItemRedEMRP(source, item, count)
    local ok, err = pcall(function()
        TriggerEvent("redemrp_inventory:addItem", source, item, count or 1, nil, function() end)
    end)
    if not ok then return false, tostring(err) end
    return true
end

local function addMoneyQBR(source, amount)
    if exports and exports['qbr-core'] and exports['qbr-core'].AddMoney then
        local ok, err = pcall(function() exports['qbr-core']:AddMoney(source, "cash", amount) end)
        if not ok then return false, tostring(err) end
        return true
    end
    return false, "qbr-core export missing"
end

local function addMoneyRedEMRP(source, amount)
    local ok, err = pcall(function()
        TriggerEvent("redemrp:getPlayerFromId", source, function(user)
            if user and user.addMoney then user.addMoney(amount) end
        end)
    end)
    if not ok then return false, tostring(err) end
    return true
end

local function giveItem(source, item, count, meta)
    if framework == "vorp" then return addItemVorp(source, item, count, meta)
    elseif framework == "qbr" then return addItemQBR(source, item, count)
    elseif framework == "redemrp" then return addItemRedEMRP(source, item, count)
    else return addItemVorp(source, item, count, meta) end
end

local function giveMoney(source, amount)
    if framework == "vorp" then return addMoneyVorp(source, amount)
    elseif framework == "qbr" then return addMoneyQBR(source, amount)
    elseif framework == "redemrp" then return addMoneyRedEMRP(source, amount)
    else return addMoneyVorp(source, amount) end
end

-- =====================
-- Gift selection helpers
-- =====================
local function resolveItemName(entry)
    if type(entry) ~= "table" then return nil end
    local n = entry.name or entry.item or entry.id
    if type(n) ~= "string" then return nil end
    n = n:gsub("^%s+", ""):gsub("%s+$", "")
    if n == "" then return nil end
    return n
end

local function resolveCount(entry)
    local c = entry.count or entry.amount or 1
    c = tonumber(c) or 1
    if c < 1 then c = 1 end
    return math.floor(c)
end

-- =====================
-- Award logic
-- =====================
-- Give ALL configured gifts each award cycle (items and/or money)
local function awardGiftTo(source, pid)
    if not Config.Gifts or #Config.Gifts == 0 then return end

    local messages = {}
    for _, entry in ipairs(Config.Gifts) do
        if entry.type == "money" then
            local amount = (entry.count or entry.amount or 1)
            giveMoney(source, amount)
            messages[#messages+1] = (entry.notify or ("Received $"..tostring(amount)))
        elseif entry.type == "item" then
            local itemName = resolveItemName(entry)
            local count = resolveCount(entry)
            if itemName then
                local ok, err = giveItem(source, itemName, count, entry.metadata or entry.meta or {})
                if ok then
                    messages[#messages+1] = (entry.notify or ("Received x"..tostring(count).." "..tostring(itemName)))
                else
                    print(("[wfrp_gifts] addItem failed for '%s' x%d: %s"):format(tostring(itemName), count, tostring(err)))
                end
            else
                print("[wfrp_gifts] Invalid gift entry (missing item name).")
            end
        else
            print("[wfrp_gifts] Invalid gift entry type; expected 'item' or 'money'.")
        end
    end

    if #messages == 0 then return end

    -- consume one gift interval
    local cur = playMinutes[pid] or 0
    if cur >= minutesPerGift then
        playMinutes[pid] = cur - minutesPerGift
    else
        playMinutes[pid] = 0
    end
    savePlaytime()

    -- notify (combine into one line so you don't spam)
    local text = table.concat(messages, "\n")
    TriggerClientEvent("Notification:left_xmas", source, Config.Title or "Gifts", text, "scoretimer_textures", "scoretimer_generic_tick", 6000)

    -- discord (single message)
    sendToDiscord(("[%s]\n%s"):format(GetPlayerName(source) or pid, text))
end

-- =====================
-- Minute ticker with AFK gate + prints
-- =====================
CreateThread(function()
    while true do
        Wait(60 * 1000) -- 1 minute
        local now = os.time()
        local players = GetPlayers()
        for _, sid in ipairs(players) do
            local src = tonumber(sid)
            local pid = getStableId(src)

            local last = lastActiveAt[pid] or 0
            local seen = hasSeenActive[pid] or false
            local afkNow = (now - last) > AFK_ACTIVE_TIMEOUT

            -- Print once when transitioning into AFK (only if we've seen them active before)
            if seen and afkNow and not isAfk[pid] then
                isAfk[pid] = true
                --print(("[wfrp_gifts] AFK: %s (%d) is now AFK"):format(GetPlayerName(src) or "Unknown", src))
            elseif not afkNow and isAfk[pid] then
                -- Fallback: if heartbeat missed the transition, print return here
                isAfk[pid] = false
                --print(("[wfrp_gifts] BACK: %s (%d) returned from AFK"):format(GetPlayerName(src) or "Unknown", src))
            end

            -- Only count this minute if player recently active
            if not afkNow then
                local cur = playMinutes[pid] or 0
                cur = cur + 1
                playMinutes[pid] = cur

                if cur >= minutesPerGift then
                    awardGiftTo(src, pid)
                end
            end
        end
    end
end)

-- Back-compat: do nothing on old client trigger
RegisterServerEvent("ricxmas_gift:addgift")
AddEventHandler("ricxmas_gift:addgift", function()
    -- No-op in playtime mode
end)
