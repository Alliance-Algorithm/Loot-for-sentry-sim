local socket = require("socket")

local host = "127.0.0.1"
local port = 34567
local message = "hello_from_lua\n"

local client, err = socket.tcp()
if not client then
    error("create tcp failed: " .. tostring(err))
end

client:settimeout(3)

local ok, connect_err = client:connect(host, port)
if not ok then
    error("connect failed: " .. tostring(connect_err))
end

local bytes, send_err = client:send(message)
if not bytes then
    error("send failed: " .. tostring(send_err))
end

print("sent: " .. message:gsub("\n", ""))
client:close()