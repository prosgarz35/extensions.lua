package.path = package.path .. ";/etc/asterisk/?.lua"
package.loaded["lists"] = nil
local ok, lists = pcall(require, "lists")
local blacklist = ok and lists.blacklist or {}
local forbidden_outbound = ok and lists.forbidden_outbound or {}
local function reject(cause) channel.HANGUPCAUSE:set(cause) app.hangup() end
local function normalize_outbound(num)
    local d = num:gsub("%D+", "")
    if #d == 11 then
        if d:byte(1) == 55 then return d end
        if d:byte(1) == 56 then return "7" .. d:sub(2) end
    elseif #d == 6 then return "73843" .. d end
end
local function dial_ext(target, cid)
    if not target or target == "" then return reject(1) end
    if cid then channel.CALLERID("num"):set(cid) end
    app.dial(channel.PJSIP_DIAL_CONTACTS(target):get(), 30, "Ttr") app.hangup()
end
hints = { internal = {} }
for i = 501, 520 do hints.internal["" .. i] = "PJSIP/" .. i end
extensions = {
    internal = {
        ["555"] = function() app.confbridge("555", "default_bridge", "default_user", "default_menu") app.hangup() end,
        ["_5XX"] = function(_, e) dial_ext(e) end,
        ["_."] = function(_, e)
            local dialed = normalize_outbound(e)
            if not dialed then return reject(1) end
            if forbidden_outbound[dialed] then return reject(21) end
            local trunk = channel.OUTBOUND_TRUNK:get()
            if not trunk or trunk == "" then return reject(38) end
            channel.CALLERID("name"):set("")
            channel.CALLERID("num"):set(trunk)
            app.dial("PJSIP/" .. dialed .. "@" .. trunk, 30, "Ttr") app.hangup()
        end,
    },
    external = {
        ["_."] = function()
            local cid = channel.CALLERID("num"):get()
            if not cid or cid == "" or blacklist[cid] then return reject(21) end
            dial_ext(channel.INCOMING_TARGET:get(), "+" .. cid)
        end,
    },
}
