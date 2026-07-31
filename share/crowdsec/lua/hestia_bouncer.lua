-- HestiaRE CrowdSec Layer-A bouncer (#186): own minimal L7 ban enforcement.
--
-- Why own and dependency-free (not the upstream lua-cs-bouncer): that is ~14
-- security-relevant files (captcha/challenge/appsec/stream/metrics) we never use;
-- we need only "is this IP banned right now -> 403". Same call as the #471 sanitizer:
-- small owned code over a vendored library. The LAPI is local (127.0.0.1) with tiny
-- JSON replies, so a raw HTTP/1.0 GET beats pulling in resty.http (48 KB).
--
-- Fail-OPEN by default: a broken/unreachable LAPI must never take customer sites
-- down. A ban is enforced only on a definite positive answer.

local _M = {}

-- Populated by init() from the key/config file the apply helper writes.
local conf = {
	host = "127.0.0.1",
	port = 8054,
	api_key = nil,
	cache_ttl = 30, -- clean answers: short, so new bans take effect quickly
	ban_ttl = 60, -- ban answers: cached a bit longer to spare the LAPI under flood
	timeout = 1000, -- ms; on timeout we fail open, so keep it tight
	fail_open = true,
	dict = nil,
}

function _M.init(o)
	o = o or {}
	conf.host = o.host or conf.host
	conf.port = tonumber(o.port) or conf.port
	conf.api_key = o.api_key
	conf.cache_ttl = tonumber(o.cache_ttl) or conf.cache_ttl
	conf.ban_ttl = tonumber(o.ban_ttl) or conf.ban_ttl
	conf.timeout = tonumber(o.timeout) or conf.timeout
	if o.fail_open ~= nil then
		conf.fail_open = o.fail_open
	end
	conf.dict = ngx.shared[o.dict or "crowdsec_cache"]
end

-- Minimal HTTP/1.0 GET to the local LAPI. HTTP/1.0 + "Connection: close" means the
-- server closes after the body (no chunked framing), so receive("*a") is the whole
-- response. Returns body, status  or  nil, err.
local function lapi_get(path)
	local sock = ngx.socket.tcp()
	sock:settimeout(conf.timeout)
	local ok, err = sock:connect(conf.host, conf.port)
	if not ok then
		return nil, "connect: " .. (err or "?")
	end
	local req = "GET " .. path .. " HTTP/1.0\r\n"
		.. "Host: " .. conf.host .. "\r\n"
		.. "X-Api-Key: " .. (conf.api_key or "") .. "\r\n"
		.. "Accept: application/json\r\n"
		.. "Connection: close\r\n\r\n"
	local _, serr = sock:send(req)
	if serr then
		sock:close()
		return nil, "send: " .. serr
	end
	local raw, rerr = sock:receive("*a")
	sock:close()
	if not raw then
		return nil, "receive: " .. (rerr or "?")
	end
	local hdr_end = raw:find("\r\n\r\n", 1, true)
	if not hdr_end then
		return nil, "malformed response"
	end
	local status = tonumber(raw:match("^HTTP/%d%.%d%s+(%d%d%d)"))
	return raw:sub(hdr_end + 4), status
end

-- true = banned, false = clean, nil = unknown (LAPI trouble -> caller decides).
local function lookup(ip)
	if conf.dict then
		local c = conf.dict:get(ip)
		if c ~= nil then
			return c == 1
		end
	end
	local body, status = lapi_get("/v1/decisions?type=ban&ip=" .. ip)
	if not body then
		ngx.log(ngx.ERR, "[crowdsec] LAPI query failed: ", status)
		return nil
	end
	-- Clean replies are literally "null"; a ban is a JSON array whose decision
	-- objects each carry a "duration" field. A field-presence test is enough for the
	-- boolean and keeps us free of a JSON dependency (no cjson on the nginx lua path).
	local banned = (status == 200) and body:find('"duration"', 1, true) ~= nil
	if conf.dict then
		conf.dict:set(ip, banned and 1 or 0, banned and conf.ban_ttl or conf.cache_ttl)
	end
	return banned
end

-- access-phase entry point: require("hestia_bouncer").allow()
function _M.allow(ip)
	ip = ip or ngx.var.remote_addr
	if not ip then
		return
	end
	local ok, banned = pcall(lookup, ip)
	if not ok then
		ngx.log(ngx.ERR, "[crowdsec] bouncer error: ", banned)
		banned = nil
	end
	if banned == true then
		return ngx.exit(ngx.HTTP_FORBIDDEN)
	end
	-- banned == nil means we could not tell; honour the fail-open policy.
	if banned == nil and not conf.fail_open then
		return ngx.exit(ngx.HTTP_FORBIDDEN)
	end
end

return _M
