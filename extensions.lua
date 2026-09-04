package.path = package.path .. ";/etc/asterisk/?.lua"
local ok, lists = pcall(require, "lists")
local blacklist = ok and lists.blacklist or {}
local forbidden_outbound = ok and lists.forbidden_outbound or {}
local function normalize_outbound(num)
    local d = num:gsub("%D+", "")
    if d == "112" then return "73843321515" end
    if #d == 6 then return "73843" .. d end
    if #d == 11 then
        local first = d:byte(1)
        if first == 55 then return d end
        if first == 56 then return "7" .. d:sub(2) end
    end
end
local function dial_ext(target, cid)
    if (target or "") == "" then return app.Hangup(3) end
    if cid then channel.CALLERID("num"):set(cid) end
    local contacts = channel.PJSIP_DIAL_CONTACTS(target):get()
    if (contacts or "") == "" then return app.Hangup(17) end
    app.Dial(contacts, 30, "Tt")
end
hints = { internal = {} }; for i = 501, 520 do hints.internal["" .. i] = "PJSIP/" .. i end
extensions = {
    internal = {
        ["555"] = function() app.ConfBridge("555", "default_bridge", "default_user", "default_menu") end,
        ["_5XX"] = function(_, e) dial_ext(e) end,
        ["_."] = function(_, e)
            local dialed = normalize_outbound(e)
            if not dialed then return app.Hangup(28) end
            if forbidden_outbound[dialed] then return app.Hangup(21) end
            local trunk = channel.OUTBOUND_TRUNK:get()
            if (trunk or "") == "" then return app.Hangup(3) end
            channel.CALLERID("name"):set(""); channel.CALLERID("num"):set(trunk)
            app.Dial("PJSIP/" .. dialed .. "@" .. trunk, 30, "Tt")
        end,
    },
    external = {
        ["_."] = function()
            local cid = channel.CALLERID("num"):get() or ""
            if cid == "" or blacklist[cid] then return app.Hangup(21) end
            dial_ext(channel.INCOMING_TARGET:get(), "+" .. cid)
        end,
    },
}
