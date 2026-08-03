package.path = package.path .. ";/etc/asterisk/?.lua"
package.loaded["lists"] = nil
local lists = require("lists")
local blacklist = lists.blacklist
local forbidden_outbound = lists.forbidden_outbound
local function reject(cause)
    if cause then channel.HANGUPCAUSE:set(cause) end
    app.hangup()
end
local function normalize_outbound(num)
    local d = (num or ""):gsub("%D+", "")
    local len = #d
    
    if len == 11 and (d:sub(1, 1) == "7" or d:sub(1, 1) == "8") then
        return "7" .. d:sub(2)
    elseif len == 6 then
        return "73843" .. d
    end
    return nil
end
local function set_cid(num)
    if not num or num == "" then return end
    channel.CALLERID("num"):set(num)
end
local function dial_ext(target, cid)
    if not target or target == "" then return reject(1) end
    local contacts = channel.PJSIP_DIAL_CONTACTS(target):get() or ""
    local ds = contacts:gsub("%s+", "")
    if ds == "" then return reject(18) end
    set_cid(cid)
    app.dial(ds, 30, "Ttr")
end
extensions = {
    internal = {
        ["555"] = function()
            app.confbridge("555", "default_bridge", "default_user", "default_menu")
        end,
        ["_5XX"] = function(c, e)
            local cid = channel.CALLERID("num"):get()
            dial_ext(e, cid)
        end,
        ["_."] = function(c, e)
            local dialed = normalize_outbound(e)
            if not dialed then return reject(1) end
            if forbidden_outbound[dialed] then return reject(21) end
            local trunk = channel.OUTBOUND_TRUNK:get()
            if not trunk or trunk == "" then return reject(38) end
            set_cid(trunk)
            app.dial("PJSIP/" .. dialed .. "@" .. trunk, 30, "Ttr")
        end,
    },
    external = {
        ["_."] = function(c, e)
            local cid = (channel.CALLERID("num"):get() or ""):gsub("%D+", "")
            if cid == "" or blacklist[cid] then
                return reject(21)
            end
            local target = channel.INCOMING_TARGET:get()
            dial_ext(target, "+" .. cid)
        end,
    },
}
hints = {
    internal = (function()
        local t = {}
        for i = 501, 520 do
            t[tostring(i)] = "PJSIP/" .. i
        end
        return t
    end)()
}