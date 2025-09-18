Config = Config or {}

-- UI
Config.Title = "Wild Frontier Gifts"

-- Framework: "vorp", "qbr", or "redemrp"
Config.Framework = "vorp"

-- Minutes of CONNECTED time required per gift
Config.MinutesOnlinePerGift = 30

Config.AFK = {
    -- How long after the last ACTIVE heartbeat a player is still counted as "active" (seconds)
    ActiveTimeoutSeconds = 90
}

-- Optional Discord logging (leave blank to disable; or set convar `setr wfrp_gifts_webhook "https://discord.com/api/webhooks/..."`)
Config.DiscordWebhook = "https://discord.com/api/webhooks/..."
Config.DiscordLogName = "Wild Frontier Gifts"

-- Rewards
-- { type="item", name="bread", count=1, notify="You received bread!" }
-- { type="money", amount=5, notify="You found $5!" }

Config.Gifts = {
    { type="item", name="giftscase", count=1, notify="You received a gift case!" },
    { type="item", name="raffle_ticket", count=2, notify="You received some raffle tickets!" },
    --{ type="money", amount=5, notify="You found $5 in your satchel." },
    -- add more as needed
}