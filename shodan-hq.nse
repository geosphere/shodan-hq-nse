local http = require "http"
local io = require "io"
local json = require "json"
local stdnse = require "stdnse"
local openssl = stdnse.silent_require "openssl"


-- Set your Shodan API key here to avoid typing it in every time:
local apiKey = ""

author = "Glenn Wilkinson <@glennzw> (idea: Charl van der Walt <@charlvdwalt>)"
license = "Same as Nmap--See https://nmap.org/book/man-legal.html"
categories = {"discovery", "safe"}

description = [[
Queries Shodan API for given targets and produces similar output to
a -sV nmap scan. The ShodanAPI key can be set with the 'apikey' script
argument, or hardcoded in the .nse file itself.

N.B if you want this script to run completely passively make sure to
include the -sn -Pn -n flags.

Example usage:

nmap --script shodan-hq.nse x.y.z.0/24 -sn -Pn -n --script-args 'outfile=potato.csv,apikey=SHODANAPIKEY'

]]

---
-- @output
-- | 
-- | PORT	STATE	SERVICE	VERSION
-- | 80/tcp	open	Apache  httpd	
-- | 3306/tcp	open	MySQL	5.5.40-0+wheezy1
-- | 22/tcp	open	OpenSSH	6.0p1 Debian 4+deb7u2
--
--@args outfile Write the results to the specified CSV file
--@args apiKey Specify the ShodanAPI key. This can also be hardcoded in the nse file.

-- ToDo: * Have an option to compliment non banner scans with shodan data (e.g. -sS scan, but
--          grab service info from Shodan
--       * Have script arg to include extra host info. e.g. Coutry/city of IP, datetime of
--          scan, verbose port output (e.g. smb share info) 
--       * Warn user if they haven't set -sn -Pn and -n (and will therefore actually scan the host


-- Begin
local scriptApiKey = stdnse.get_script_args("apikey")
if (scriptApiKey ~= nil) then apiKey = scriptApiKey end
local outFile = stdnse.get_script_args("outfile")

if (outFile ~= nil) then file = io.open(outFile, "w") io.output(file) io.write("IP, Port, Service\n") end

function ts(v)
  if v == nil then return "" end
  return v
end

hostrule = function() return true end


prerule = function ()
    if (apiKey == "") then
        print("\nError: Please specify your ShodanAPI key with --script-args='apikey=<yourkey>', or set it in the .nse file. You can get a free key from https://developer.shodan.io\n")
    end
end

postrule = function ()
    nmap.registry.count = (nmap.registry.count or 0)
    print("+ Shodan done: " .. nmap.registry.count .. " hosts up.")
    if (outFile ~= nil) then io.close() print ("+ Wrote Shodan output to '" .. outFile .. "'\n") end
end

action = function(host)
    if (apiKey == "") then return nil end

    local response = http.get("api.shodan.io", 443, "/shodan/host/".. host.ip .."?key=" .. apiKey)
    if (response.status == 401) then
        return "Received 'Unauthorized' from Shodan API. Double check your API key."
    elseif (response.status == 404) then
	return "No information for IP " .. host.ip
    elseif (response.status ~= 200) then
        return "Bad response from Shodan for IP " .. host.ip .. " : " .. response.status
    end

    local stat, resp = json.parse(response.body)
    if (resp.error ~= nil) then
	return resp.error
    end

    if (resp.data ~= nil) then
        nmap.registry.count = (nmap.registry.count or 0) + 1
	hostnames = ""
	for k, h in pairs(resp.hostnames)
	do
		hostnames = h .. " " .. hostnames
	end
	local result = "Report for " ..host.ip
	if (string.len(hostnames) > 0)
 	then	
		result = result .. " (" .. hostnames .. ")"
	end
        result = result .. "\n\nPORT\t\tSTATE\tSERVICE\tVERSION\n"
        for key,e in ipairs(resp.data)
        do
            result = result ..  ts(e.port) .. "/" .. ts(e.transport) .. "\topen" .. ts(e.service) .. "\t" .. ts(e.product) .. "\t" .. ts(e.version) .. "\n"
            if (outFile ~= nil) then
                out = host.ip .. ", " .. ts(e.port) .. ", " .. ts(e.service) .. " " .. ts(e.product) .. "\n"
                io.write(out)
            end
        end
        return result
    else
        return "Unable to query data for IP " .. host.ip
    end
end
