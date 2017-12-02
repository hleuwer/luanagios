package.path = "?.lua;"..package.path
local pretty = require "pl.pretty"
local client = require "soap.client"
local host = "www.webservicex.net"
local url = "/geoipservice.asmx"
local action = "GetGeoIP"
local method = "GetGeoIP"
local param = {
   --   soapversion = "1.1",
   url = "http://"..host..url,
   -- soapaction only require for soap 1.1
   soapaction = "http://www.webservicex.net/"..action,
   -- xml namespace
   namespace = "http://www.webservicex.net/",
   method = method,
   entries =
      { -- `tag' will be filled with `method' field
         {
            tag = "IPAddress",
            -- "46.29.100.77"    -- www.telecom.de - works
            arg[1] or "193.242.192.41" -- www.unesco.org - works
            -- "108.177.119.94" -- www.google.de - not working
            -- "108.177.127.103"   -- www.google.com - not working
            -- "104.102.56.87"       -- www.panasoic.com - not working
            -- "40.69.210.172"       -- www.amnesty.org
            -- "91.102.11.190"          -- www.amnesty.de
            -- arg[1]
         }
      }
}
-- print("parameters:", pretty.write(param))
local ns, meth, ent = client.call(param)
if not ns then
   print("namespace:", ns)
   print(meth)
   for _, elem in ipairs(ent) do
      if type(elem) == "table" then
--         print("#1#", pretty.write(elem))
         print (elem.tag, elem[1])
      end
   end
   os.exit(1)
end
print("namespace:", ns)
print("method:", meth)
-- print("result:", pretty.write(ent))
print("entries:")
for _, elem in ipairs(ent) do
   if type(elem) == "table" then
      for _, selem in ipairs(elem) do 
         print (selem.tag, selem[1])
      end
   end
end
