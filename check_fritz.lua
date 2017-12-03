#!/usr/bin/env lua
local pretty = require "pl.pretty"
local getopt = require "alt_getopt"
local client = require "soap.client"
local lfs = require "lfs"

local tmp_path = "/var/tmp/check_fritz/"
local VERSION = "1.0"

-- Services database

local services = {
   wlan = {
      url = "/upnp/control/wlanconfig1",
      service = "WLANConfiguration",
      action = "GetInfo",
      namespace = "urn:dslforum-org:service"
   },
   wlanstats = {
      url = "/upnp/control/wlanconfig1",
      service = "WLANConfiguration",
      action = "GetStatistics",
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


local long_opts = {
   verbose = "v",
   help    = "h",
   hostname = "H",
   version = "V",
   warning = "w",
   critical = "c",
   letter = "l",
   mode = "m",
   user = 'u',
   password = 'P'
}

local retval = {
   OK = 0,
   WARNING = 1,
   CRITICAL = 2,
   UNKNOWN = 3
}

local USAGE = {
   "usage: check_storage -H hostname -C community OPTIONS",
   "   -h,--help                    Get this help",
   "   -v,--verbose                 Verbose (detailed) output",
   "   -H,--hostname=HOSTNAME       Define host ip address",
   "   -m,--mode=MODE               Mode of check",
   "   -w,--warn=WARNTHRESHOLD      Warning threshold",
   "   -c,--critical=CRITTHRESHOLD  Critical threshold",
   "   -i,--index                   Index in storage table",
   "   -u,--user=USER               Username",
   "   -P,--password=PASSWORD       Passowrd",
   "   -V,--version                 Show version info"
}

local DESCRIPTION = {
   "This Nagios plugin retrieves the following status and performance",
   "data for AVM routers.",
   "The following data items can be selected:",
   "   - mode=uptime:     uptime in seconds",
   "   - mode=wanstatus:  current WAN status",
   "   - mode=wanuptime:  time since last WAN link break and IP address assignment",
   "   - mode=wanstats:   downstream and upstream statistics (data rate in Mbit/s)",
   "   - mode=wlanstats   downstream and upstream packet statistics (data rate in packets/s)",
   "   - mode=lanstats:   LAN statistics",
   "   - mode=time:       Local time in device",
   "   - mode=ssid:       WLAN SSID and status"
}

local function printf(fmt, ...)
   io.stdout:write(string.format(fmt.."\n", ...))
end

local function fprintf(fmt, ...)
   io.stderr:write(string.format(fmt.."\n", ...))
end

local function exitUsage()
   printf("%s", table.concat(DESCRIPTION,"\n"))
   printf("%s", table.concat(USAGE, "\n"))
   os.exit(retval["OK"], true)
end

local function exitError(fmt, ...)
   printf("UKNOWN - check_fritz returned with error: "..fmt, ...)
   os.exit(retval["UNKNOWN"], true)
end

local function make_restab(res)
   local t = {}
   for _, e in ipairs (res) do
      if type(e) == "table" then
         t[e.tag] = e[1]
      end
   end
   return t
end

local function put_stats(fn, v, t)
   local f = io.open(tmp_path .. fn, "w+b")
   if not f then
      exitError("Unable to open file %s for writing\n", tmp_path .. fn)
   end
   f:write(string.format("%d\n%d\n", v, t))
   f:close()
end

local function get_stats(fn)
   local f, err = io.open(tmp_path .. fn, "rb")
   if not f then
      if string.find(err, "No such file") then
         put_stats(fn, 0, 0)
         f, err = io.open(tmp_path .. fn, "rb")
         if not f then
            exitError("Unable to open file %s for reading\n", tmp_path .. fn)
         end
      else
         exitError("Unable to open file %s for reading\n", tmp_path .. fn)
      end
   end
   v = tonumber(f:read("*l"))
   t = tonumber(f:read("*l"))
   f:close()
   return v, t
end

local function tr64_call(url, service, action, param)
   local soap_param = {
      -- soapversion = "1.1",
      url = url .. service.url,
      -- soapaction only require for soap 1.1
      soapaction = service.namespace .. ":" .. service.service .. ":1#" .. (action or service.action),
      namespace = service.namespace .. ":" .. service.service .. ":" .. (service.index or "1"),
      method = service.action,
      auth = "digest",
      entries = { -- `tag' will be filled with `method' field
         tag = "u:"..service.action,
         param
      }
   }
--   printf("soap parameters: %s", pretty.write(soap_param))
   local rnamespace, rmeth, rval = client.call(soap_param)
   if rnamespace == nil then
      exitError(rmeth)
   end
   local restab = make_restab(rval)
--   print("soap result: %s", pretty.write(restab))
   return restab, rnamespace, rmeth
end

local function secs2date(secs)
   local days = math.floor(secs / 86400)
   local hours = math.floor(secs / 3600) - (days * 24)
   local minutes = math.floor(secs / 60) - (days * 1440) - (hours * 60)
   local seconds = secs % 60
   return {
      days = days, hours = hours, minutes = minutes, seconds = seconds
   }
end

local function tr64_uptime(url)
   local res = tr64_call(url, services.device, nil, nil)
   local upt = secs2date(res.NewUpTime)
   return upt, res.NewUpTime
end

local function tr64_time(url)
   local res = tr64_call(url, services.time, nil, nil)
   local date, time, offs
   local t, o = {},{}
   string.gsub(res.NewCurrentLocalTime, "([0-9%-]+)T([^%+]+)%+([0-9%:]+)",
               function(d, t, o)
                  date = d
                  time = t
                  offs = o
   end)
   string.gsub(date, "(%d+)%-(%d+)%-(%d+)",
               function(y, m, d)
                  t.year = y
                  t.month = m
                  t.day = d
   end)
   string.gsub(time, "(%d+)%:(%d+)%:(%d+)",
               function(h, m, s)
                  t.hour = h
                  t.min = m
                  t.sec = s
   end)
   string.gsub(offs, "(%d+)%:(%d+)",
               function(h, m)
                  o.hour = h
                  o.min = m
   end)
   return t, o, res
end

local function tr64_wanuptime(url)
   local res = tr64_call(url, services.wan, nil, nil)
   if res.NewConnectionStatus == "Connected" then
      local upt = secs2date(res.NewUptime)
      return upt, res.NewUptime, res
   else
      exitError("Link not conneced")
   end
end

local function tr64_wanstatus(url)
   local res = tr64_call(url, services.wan, nil, nil)
   if res.NewConnectionStatus == "Connected" then
      return 1, res
   else
      return 0, res
   end
end

local function tr64_wanstats(url)
   local txtime = os.time()
   local txres = tr64_call(url, services.waniftx, nil, nil)
   local rxres  = tr64_call(url, services.wanifrx, nil, nil)
   local txbytes = tonumber(txres.NewTotalBytesSent)
   local rxbytes = tonumber(rxres.NewTotalBytesReceived)
   local rxtime = txtime
   return txbytes, rxbytes, txtime, rxtime
end

local function tr64_wlanstats(url)
   local xtime = os.time()
   local res = tr64_call(url, services.wlanstats, nil, nil)
   local txpackets = tonumber(res.NewTotalPacketsSent)
   local rxpackets = tonumber(res.NewTotalPacketsReceived)
   return txpackets, rxpackets, xtime
end

local function tr64_ssid(url)
   local res = tr64_call(url, services.wlan, nil, nil)
   local ssid = res.NewSSID
   local enable = res.NewEnable
   local status = res.NewStatus
   return ssid, res
end
   
local function tr64_lanstats(url)
   local xtime = os.time()
   local res = tr64_call(url, services.lanethstats, nil, nil)
   local txbytes = tonumber(res.NewBytesSent)
   local rxbytes = tonumber(res.NewBytesReceived)
   return txbytes, rxbytes, xtime
end

local function main(...)

   local host = "fritz.box"
   local port = 49000
   local verbosity = 0
   local mode
   local warn, warnp = 0, 0
   local crit, critp = 0, 0
   local rdata

   optarg,optind = alt_getopt.get_opts (arg, "hVvH:C:i:m:w:c:u:P:", long_opts)

   for k,v in pairs(optarg) do
      if k == "H" then
         host = v
      elseif k == "i" then
         index = v
         have_index = true
      elseif k == "m" then
         mode = v
      elseif k == "h" then
         exitUsage()
      elseif k == "w" then
         if string.sub(v, -1) == "%" then
            warnp = tonumber(string.sub(v, 1, -2))
         else
            warn = tonumber(v)
         end
      elseif k == "c" then
         if string.sub(v, -1) == "%" then
            critp = tonumber(string.sub(v, 1, -2))
         else
            crit = tonumber(v)
         end
      elseif k == "v" then
         verbosity = 1
      elseif k == "V" then
         printf("check_fritz version %s", VERSION)
         os.exit(retval["OK"], true)
      elseif k == "u" then
         user = v
      elseif k == "P" then
         password = v
      end
   end

   local url = "http://" .. user .. ":" .. password .. "@" .. host .. ":" .. port
   
   local state = "OK"

   if mode == "uptime" then
      local t, seconds = tr64_uptime(url)
      if verbosity > 0 then
         printf("Uptime:  %2d seconds", seconds)
         printf("Days:    %2d", t.days)
         printf("Hours:   %2d", t.hours)
         printf("Minutes: %2d", t.minutes)
         printf("Seconds: %2d", t.seconds)
      end
      rdata = {
         string.format("%s - Uptime %d seconds (%dd %dh %dm %ds)",
                       state, seconds, t.days, t.hours, t.minutes, t.seconds),
         string.format("uptime=%d;%d;%d;%d;%d",seconds, 0, 0, 0, 0)
      }
   elseif mode == "wanuptime" then
      local t, seconds, res = tr64_wanuptime(url)
      if verbosity > 0 then
         printf("WAN Link Status:   %s", res.NewConnectionStatus)
         printf("WAN Link Type:     %s", res.NewConnectionType)
         printf("WAN Link Mac:      %s", res.NewMACAddress)
         printf("WAN IP Address:    %s", res.NewExternalIPAddress)
         printf("WAN Down Max Rate: %.1f Mbit/s", tonumber(res.NewDownstreamMaxBitRate)/1000)
         printf("WAN Up Max Rate:   %.1f Mbit/s", tonumber(res.NewUpstreamMaxBitRate)/1000)
         printf("WAN Link Uptime:   %2d seconds", seconds)
         printf("  Days:            %2d", t.days)
         printf("  Hours:           %2d", t.hours)
         printf("  Minutes:         %2d", t.minutes)
         printf("  Seconds:         %2d", t.seconds)
      end
      rdata = {
         string.format("%s - WAN uptime %d seconds (%dd %dh %dm %ds)",
                       state, seconds, t.days, t.hours, t.minutes, t.seconds),
         string.format("wanuptime=%d;%d;%d;%d;%d",seconds, 0, 0, 0, 0)
      }
   elseif mode == "wanstatus" then
      local nstatus, res = tr64_wanstatus(url)
      if verbosity > 0 then
         printf("WAN Link Status:   %s", res.NewConnectionStatus)
         printf("WAN Link Type:     %s", res.NewConnectionType)
         printf("WAN Link Mac:      %s", res.NewMACAddress)
         printf("WAN IP Address:    %s", res.NewExternalIPAddress)
         printf("WAN Down Max Rate: %.1f Mbit/s", tonumber(res.NewDownstreamMaxBitRate)/1000)
         printf("WAN Up Max Rate:   %.1f Mbit/s", tonumber(res.NewUpstreamMaxBitRate)/1000)
         printf("WAN Link Uptime:   %2d seconds", tonumber(res.NewUptime))
      end
      rdata ={
         string.format("%s - WAN status %d (%s)", state, nstatus, res.NewConnectionStatus),
         string.format("wanstatus=%d;%d;%d;%d;%d", nstatus, 0, 0, 0, 0);
      }
   elseif mode == "wanstats" then
      local txb, rxb, txt, rxt = tr64_wanstats(url)
      local wanstats_tx_file = host .. "__wanstats_tx"
      local wanstats_rx_file = host .. "__wanstats_rx"
      local txbl, txtl, rxbl, rxtl
      txbl, txtl = get_stats(wanstats_tx_file)
      rxbl, rxtl = get_stats(wanstats_rx_file)
      local rxd = rxb - rxbl
      if rxd < 0 then rxd = rxd + 2^32 end	
      local txd = txb - txbl
      if txd < 0 then txd = txd + 2^32 end 
      rxrate = rxd * 8 / (rxt - rxtl)
      txrate = txd * 8 / (txt - txtl)
      if rxrate < 0 or txrate < 0 then
         exitError("negative rate")
      end
      put_stats(wanstats_tx_file, txb, txt)
      put_stats(wanstats_rx_file, rxb, rxt)
      if verbosity > 0 then
         printf("WAN Statistics:")
         printf("Received Bytes:    %d Bytes (%.1f MBytes)", rxb, rxb/1e6)
         printf("Transmitted Bytes: %d Bytes (%.1f MBytes)", txb, txb/1e6)
         printf("Receive Rate:      %.1f bit/s", rxrate)
         printf("Transmit Rate:     %.1f bit/s", txrate)
         printf("Time Interval:     %d %d seconds", txt - txtl, rxt - rxtl)
      end
      rdata = {
         string.format("%s - RX: %d Bytes (%.1f bit/s), TX: %d Bytes (%.1f bit/s)",
                       state, rxb, rxrate, txb, txrate),
         string.format("rxrate=%dbit/s txrate=%dbit/s;%d;%d;%d;%d",
                       rxrate, txrate, 0, 0, 0, 0)
      }
   elseif mode == "lanstats" then
      local txb, rxb, xt = tr64_lanstats(url)
      local lanstats_tx_file = host .. "__lanstats_tx"
      local lanstats_rx_file = host .. "__lanstats_rx"
      local txbl, rxbl, xtl
      txbl, xtl = get_stats(lanstats_tx_file)
      rxbl, xtl = get_stats(lanstats_rx_file)
      local txd = txb - txbl
      if txd < 0 then txd = txd + 2^32 end
      local rxd = rxb - rxbl
      if rxd < 0 then rxd = rxd + 2^32 end
      rxrate = rxd * 8 / (xt - xtl)
      txrate = txd * 8 / (xt - xtl)
      if rxrate < 0 or txrate < 0 then
         exitError("negative rate")
      end
      put_stats(lanstats_tx_file, txb, xt)
      put_stats(lanstats_rx_file, rxb, xt)
      if verbosity > 0 then
         printf("LAN Statistics:")
         printf("Received Bytes:    %d Bytes (%.1f MBytes)", rxb, rxb/1e6)
         printf("Transmitted Bytes: %d Bytes (%.1f MBytes)", txb, txb/1e6)
         printf("Receive Rate:      %.1f bit/s", rxrate)
         printf("Transmit Rate:     %.1f bit/s", txrate)
         printf("Time Interval:     %d seconds", xt - xtl)
      end
      rdata = {
         string.format("%s - RX: %d Bytes (%.1f bit/s), TX: %d Bytes (%.1f bit/s)",
                       state, rxb, rxrate, txb, txrate),
         string.format("rxrate=%dbit/s txrate=%dbit/s;%d;%d;%d;%d", rxrate, txrate, 0, 0, 0, 0)
      }
   elseif mode == "ssid" then
      local ssid, res = tr64_ssid(url)
      local retstr
      if res.NewEnable == "0" or res.NewStatus == "Down" then
         state = "CRITICAL"
         retstr = string.format("WLAN %q is down", res.NewSSID)
      else
         retstr = string.format("WLAN %q is up", res.NewSSID)
      end
      if verbosity > 0 then
         printf("WLAN status:")
         printf("SSID:       %s", res.NewSSID)
         printf("Enabled:    %s", res.NewEnable)
         printf("Status:     %s", res.NewStatus)
         printf("BeaconType: %s", res.NewBeaconType)
         printf("BSSID:      %s", res.NewBSSID)
      end
      rdata = {
         string.format("%s - %s", state, retstr),
         string.format("enable=%d status=%s;%d;%d;%d;%d",
                       res.NewEnable, res.Newstatus, 0, 0, 0, 0) 
      }
   elseif mode == "wlanstats" then
      local txp, rxp, xt = tr64_wlanstats(url)
      local wlanstats_tx_file = host .. "__wlanstats_tx"
      local wlanstats_rx_file = host .. "__wlanstats_rx"
      local txpl, rxpl, xtl
      txpl, xtl = get_stats(wlanstats_tx_file)
      rxpl, xtl = get_stats(wlanstats_rx_file)
      local txd = txp - txpl
      if txd < 0 then txd = txd + 2^32 end
      local rxd = rxp - rxpl
      if rxd < 0 then rxd = rxd + 2^32 end
      rxrate = rxd * 8 / (xt - xtl)
      txrate = txd * 8 / (xt - xtl)
      if rxrate < 0 or txrate < 0 then
         exitError("negative rate")
      end
      put_stats(wlanstats_tx_file, txp, xt)
      put_stats(wlanstats_rx_file, rxp, xt)
      if verbosity > 0 then
         printf("WLAN Statistics:")
         printf("Received Packets:    %d packets", rxp)
         printf("Transmitted Packets: %d packets", txp)
         printf("Receive Rate:        %.1f packets/s", rxrate)
         printf("Transmit Rate:       %.1f packets/s", txrate)
         printf("Time Interval:       %d seconds", xt - xtl)
      end
      rdata = {
         string.format("%s - RX: %d packets (%.1f packets/s), TX: %d packets (%.1f packets/s)",
                       state, rxp, rxrate, txp, txrate),
         string.format("rxrate=%dpackets/s txrate=%dpackets/s;%d;%d;%d;%d",
                       rxrate, txrate, 0, 0, 0, 0)
      }
   elseif mode == "time" then
      local dat, offs, res = tr64_time(url)
      local tim = os.time(dat)
      local retstr = string.gsub(os.date("%D %T", tim),"/",".")
      if verbosity > 0 then
         printf("Local time information:")
         printf("Date and Time: %s", retstr)
         printf("Offset:        %s:%s", offs.hour, offs.min)
         printf("Returned:      %s", res.NewCurrentLocalTime)
         printf("Reference:     %s", os.date("%d.%m.%y %H:%M:%S"))
         printf("NTP Server 1:  %s", res.NewNTPServer1)
         printf("NTP Server 2:  %s", res.NewNTPServer2)
      end
      rdata = {
         string.format("%s - Local time is %s", state, retstr),
         string.format("time=%s reftime=%s;%d;%d;%d;%d", tim, os.time(), 0, 0, 0, 0)
      }
   else      
      exitError("unkown mode %q", mode)
   end
   printf("%s", table.concat(rdata, "|"))
   return retval[state]
end

return main(unpack(arg))
