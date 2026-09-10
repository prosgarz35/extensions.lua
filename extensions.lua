package.path = package.path .. ";/etc/asterisk/?.lua"
local ok, lists = pcall(require, "lists")
local blacklist = ok and lists.blacklist or {}
local forbidden_outbound = ok and lists.forbidden_outbound or {}
local dial_codes = { BUSY = 21, NOANSWER = 19, CONGESTION = 34, CHANUNAVAIL = 34 }
local function normalize_outbound(num)
    local d = num:gsub("%D+", "")
    if d == "112" then return "73843321515" end
    if #d == 6 then return "73843" .. d end
    if #d == 11 then
        local b = d:byte(1)
        if b == 55 then return d end
        if b == 56 then return "7" .. d:sub(2) end
    end
end
local function dial_ext(target, cid)
    if (target or "") == "" then return app.Hangup(28) end
    if cid then channel.CALLERID("num"):set(cid) end
    local contacts = channel.PJSIP_DIAL_CONTACTS(target):get()
    if (contacts or "") == "" then return app.Hangup(20) end
    app.Dial(contacts, 30, "Tt")
    return app.Hangup(dial_codes[channel.DIALSTATUS:get()] or 16)
end
local function handle_internal(_, e) return dial_ext(e) end
local function handle_outbound(_, e)
    local dialed = normalize_outbound(e)
    if not dialed then return app.Hangup(28) end
    if forbidden_outbound[dialed] then return app.Hangup(21) end
    local trunk = channel.OUTBOUND_TRUNK:get()
    if (trunk or "") == "" then return app.Hangup(38) end
    channel.CALLERID("name"):set(""); channel.CALLERID("num"):set(trunk)
    app.Dial("PJSIP/" .. dialed .. "@" .. trunk, 30, "Tt")
end
hints = { internal = {} }; for i = 501, 525 do hints.internal["" .. i] = "PJSIP/" .. i end
extensions = {
    internal = {
        ["555"]             = function() app.ConfBridge("555", "default_bridge", "default_user", "default_menu") end,
        ["_50Z"]            = handle_internal,
        ["_51X"]            = handle_internal,
        ["_52[0-5]"]        = handle_internal,
        ["112"]             = handle_outbound,
        ["_XXXXXX"]         = handle_outbound,
        ["_+7XXXXXXXXXX"]   = handle_outbound,
        ["_[78]XXXXXXXXXX"] = handle_outbound,
    },
    external = {
        ["_X."] = function()
            local cid = channel.CALLERID("num"):get() or ""
            if cid == "" or blacklist[cid] then return app.Hangup(21) end
            return dial_ext(channel.INCOMING_TARGET:get(), "+" .. cid)
        end,
    },
}
