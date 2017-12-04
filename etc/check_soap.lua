local pretty = require "pl.pretty"
local client = require "soap.client"
local host = arg[1] 
local port = 49000
local user = arg[3]
local pw = arg[4]
print(user, pw)
local services = {
   device = {
      url = "/upnp/control/deviceinfo",
      service = "DeviceInfo",
      action = "GetInfo",
      namespace = "urn:dslforum-org:service"
   },
   user = {
      url = "/upnp/control/userif",
      service = "UserInterface",
      action = "GetInfo",
      namespace = "urn:dslforum-org:service"
   },
   time = {
      url = "/upnp/control/time",
      service = "Time",
      action = "GetInfo",
      namespace = "urn:dslforum-org:service"
   },
   wlan = {
      url = "/upnp/control/wlanconfig1",
      service = "WLANConfiguration",
      action = "GetInfo",
      namespace = "urn:dslforum-org:service"
   },
   wlanchannelinfo = {
      url = "/upnp/control/wlanconfig1",
      service = "WLANConfiguration",
      action = "GetChannelInfo",
      namespace = "urn:dslforum-org:service"
   },
   wlanstats = {
      url = "/upnp/control/wlanconfig1",
      service = "WLANConfiguration",
      action = "GetStatistics",
      namespace = "urn:dslforum-org:service"
   },
   wlanstatsB = {
      url = "/upnp/control/wlanconfig1",
      service = "WLANConfiguration",
      action = "GetByteStatistics",
      namespace = "urn:dslforum-org:service"
   },
   wan = {
      url = "/upnp/control/wanpppconn1",
      service = "WANPPPConnection",
      action = "GetInfo",
      namespace = "urn:dslforum-org:service"
   },
   wanip = {
      url = "/upnp/control/wanipconnection1",
      service = "WANIPConnection",
      action = "GetExternalIPAddress",
      namespace = "urn:dslforum-org:service"
   },
   wanipv6 = {
      url = "/upnp/control/wanipconnection1",
      service = "WANIPConnection",
      action = "X_AVM_DE_GetIPv6Prefix",
      namespace = "urn:dslforum-org:service",
      index = 2
   },
   wanipstat = {
      url = "/upnp/control/wanipconnection1",
      service = "WANIPConnection",
      action = "GetStatusInfo",
      namespace = "urn:dslforum-org:service"
   },
   waniptype = {
      url = "/upnp/control/wanipconnection1",
      service = "WANIPConnection",
      action = "GetConnectionTypeInfo",
      namespace = "urn:dslforum-org:service"
   },
   wanif = {
      url = "/upnp/control/wancommonifconfig1",
      service = "WANCommonInterfaceConfig",
      action = "GetCommonLinkProperties",
      namespace = "urn:dslforum-org:service"
   },
   wanmon = {
      url = "/upnp/control/wancommonifconfig1",
      service = "WANCommonInterfaceConfig",
      action = "X_AVM-DE_GetOnlineMonitor",
      namespace = "urn:dslforum-org:service",
      param = {
         tag = "NewSyncGroupIndex",
         0
      }
   },
   waniftx = {
      url = "/upnp/control/wancommonifconfig1",
      service = "WANCommonInterfaceConfig",
      action = "GetTotalBytesSent",
      namespace = "urn:dslforum-org:service"
   },
   wanifrx = {
      url = "/upnp/control/wancommonifconfig1",
      service = "WANCommonInterfaceConfig",
      action = "GetTotalBytesReceived",
      namespace = "urn:dslforum-org:service"
   },
   waneth = {
      url = "/upnp/control/wanethlinkconfig1",
      service = "WANEthernetLinkConfig",
      action = "GetEthernetLinkStatus",
      namespace = "urn:dslforum-org:service"
   },
   laneth = {
      url = "/upnp/control/lanethernetifcfg",
      service = "LanEthernetInterfaceConfig",
      action = "GetInfo",
      namespace = "urn:dslforum-org:service"
   },
   lanethstats = {
      url = "/upnp/control/lanethernetifcfg",
      service = "LanEthernetInterfaceConfig",
      action = "GetStatistics",
      namespace = "urn:dslforum-org:service"
   },
   voip = {
      url = "/upnp/control/x_voip",
      service = "X_VoIP",
      action = "GetVoIPCommonCountryCode",
      namespace = "urn:dslforum-org:service"
   },
   layer3 = {
      url = "/upnp/control/layer3forwarding",
      service = "Layer3Forwarding",
      action = "GetDefaultConnectionService",
      namespace = "urn:dslforum-org:service"
   }
}
local svc = services[arg[2]]
local parm = {
   -- soapversion = "1.1",
   url = "http://" .. user .. ":" .. pw .."@" .. host .. ":" .. port .. svc.url,
   -- soapaction only require for soap 1.1
   soapaction = svc.namespace .. ":" .. svc.service .. ":1#" .. svc.action,
   namespace = svc.namespace .. ":" .. svc.service .. ":" .. (svc.index or "1"),
   method = svc.action,
   auth = "digest",
   entries = { -- `tag' will be filled with `method' field
      tag = "u:"..svc.action,
      svc.param
   }
}
print("parameters:", pretty.write(parm))
local ns, meth, ent = client.call(parm)
if not ns then
   print("error:", meth)
   for _, elem in ipairs (ent) do
      if type(elem) == "table" then
         print ("  "..elem.tag, elem[1])
      end
   end
   os.exit(1)
end
print("namespace: ".. ns)
print("method:", meth)
--print("result:", pretty.write(ent))
print("entries:")
for _, elem in ipairs (ent) do
   if type(elem) == "table" then
      print ("  "..elem.tag, elem[1])
   end
end
