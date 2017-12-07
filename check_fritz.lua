#!/usr/bin/env lua
local pretty = require "pl.pretty"
local getopt = require "alt_getopt"
local client = require "soap.client"
local lfs = require "lfs"

local tmp_path = "/var/tmp/check_fritz/"
local VERSION = "1.0"

local format, tinsert = string.format, table.insert

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
   password = 'P',
   special = 's',
   logfile = 'L'
}

local retval = {
   OK = 0,
   WARNING = 1,
   CRITICAL = 2,
   UNKNOWN = 3
}

local USAGE = {
   "usage: check_fritz -H hostname -m mode OPTIONS",
   "   -H,--hostname=HOSTNAME       Define host ip address",
   "   -m,--mode=MODE               Mode of check",
   "   -u,--user=USER               Username",
   "   -P,--password=PASSWORD       Passowrd",
   "   -i,--index                   Index into tables",
   "   -c,--critical=CRITTHRESHOLD  Critical threshold",
   "   -w,--warn=WARNTHRESHOLD      Warning threshold",
   "   -L, --logfile=LOGFILENAME    Logfile name",
   "   -v,--verbose                 Verbose (detailed) output",
   "   -h,--help                    Get this help",
   "   -V,--version                 Show version info",
   "   -s,--special=SPECIAL         Mode specific control"
}

local DESCRIPTION = {
   "This Nagios plugin retrieves the following status and performance",
   "data for AVM routers.",
   "The following data items can be selected:",
   "   - mode=uptime:      Uptime in seconds",
   "   - mode=wanstatus:   Current WAN status",
   "   - mode=wanuptime:   Time since last WAN link break and IP address assignment",
   "   - mode=wanstats:    Downstream and upstream statistics (data rate in Mbit/s)",
   "   - mode=wlanchannel: Configured and possible channels",
   "   - mode=wlandevs:    WLAN connected device info",
   "   - mode=wlanstats    Downstream and upstream packet statistics (data rate in packets/s)",
   "   - mode=lanstats:    LAN statistics",
   "   - mode=time:        Local time in device",
   "   - mode=ssid:        WLAN SSID and status"
}

local function printf(fmt, ...)
   io.stdout:write(format(fmt.."\n", ...))
end

local function fprintf(fmt, ...)
   io.stderr:write(format(fmt.."\n", ...))
end

local function logprintf(logfile, fmt, ...)
   logfile:write(format(fmt.."\n", ...))
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
   f:write(format("%d\n%d\n", v, t))
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

local function tr64_wlanchannel(url)
   local res = tr64_call(url, services.wlan, "GetChannelInfo", nil)
   local channel = res.NewChannel
   local channel_list = res.NewPossibleChannels
   return channel, channel_list
end

local function tr64_wlandevs(url, special)
   local res = tr64_call(url, services.wlan, "GetTotalAssociations", nil)
   local ndev = tonumber(res.NewTotalAssociations)
   local mdev = 0
   local t = {}
   for i = 0, ndev-1 do
      local res = tr64_call(url, services.wlan, "GetGenericAssociatedDeviceInfo",
                            {tag = "NewAssociatedDeviceIndex", i})
      if (special ~= "auth-only") or (res.NewAssociatedDeviceAuthState == "1") then
         table.insert(t, {
                         MacAddress = res.NewAssociatedDeviceMACAddress,
                         IpAddress = res.NewAssociatedDeviceIPAddress,
                         AuthState = res.NewAssociatedDeviceAuthState,
                         Speed = res["NewX_AVM-DE_Speed"],
                         SignalStrength = res["NewX_AVM-DE_SignalStrength"] 
         })
         mdev = mdev + 1
      end
   end
   if special == "auth-only" then
      return mdev, t
   else
      return ndev, t
   end
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

local checks = {
   check_uptime = function(cfg)
      local t, seconds = tr64_uptime(cfg.url)
      local vout = {
         format("Uptime:  %2d seconds", seconds),
         format("Days:    %2d", t.days),
         format("Hours:   %2d", t.hours),
         format("Minutes: %2d", t.minutes),
         format("Seconds: %2d", t.seconds)
      }
      local rdata = {
         format("%s - Uptime %d seconds (%dd %dh %dm %ds)",
                state, seconds, t.days, t.hours, t.minutes, t.seconds),
         format("uptime=%d",seconds)
      }
      return rdata, vout
   end,
   
   check_wanuptime = function(cfg)
      local t, seconds, res = tr64_wanuptime(cfg.url)
      local vout = {
         format("WAN Link Status:   %s", res.NewConnectionStatus),
         format("WAN Link Type:     %s", res.NewConnectionType),
         format("WAN Link Mac:      %s", res.NewMACAddress),
         format("WAN IP Address:    %s", res.NewExternalIPAddress),
         format("WAN Down Max Rate: %.1f Mbit/s", tonumber(res.NewDownstreamMaxBitRate)/1000),
         format("WAN Up Max Rate:   %.1f Mbit/s", tonumber(res.NewUpstreamMaxBitRate)/1000),
         format("WAN Link Uptime:   %2d seconds", seconds),
         format("  Days:            %2d", t.days),
         format("  Hours:           %2d", t.hours),
         format("  Minutes:         %2d", t.minutes),
         format("  Seconds:         %2d", t.seconds)
      }
      local rdata = {
         format("%s - WAN uptime %d seconds (%dd %dh %dm %ds)",
                state, seconds, t.days, t.hours, t.minutes, t.seconds),
         format("wanuptime=%d",seconds)
      }
      return rdata, vout
   end,
   
   check_wanstatus = function(cfg)
      local nstatus, res = tr64_wanstatus(cfg.url)
      local vout = {
         format("WAN Link Status:   %s", res.NewConnectionStatus),
         format("WAN Link Type:     %s", res.NewConnectionType),
         format("WAN Link Mac:      %s", res.NewMACAddress),
         format("WAN IP Address:    %s", res.NewExternalIPAddress),
         format("WAN Down Max Rate: %.1f Mbit/s", tonumber(res.NewDownstreamMaxBitRate)/1000),
         format("WAN Up Max Rate:   %.1f Mbit/s", tonumber(res.NewUpstreamMaxBitRate)/1000),
         format("WAN Link Uptime:   %2d seconds", tonumber(res.NewUptime))
      }
      local rdata ={
         format("%s - WAN status %d (%s)", state, nstatus, res.NewConnectionStatus),
         format("wanstatus=%d", nstatus)
      }
      return rdata, vout
   end,
   
   check_wanstats = function(cfg)
      local txb, rxb, txt, rxt = tr64_wanstats(cfg.url)
      local wanstats_tx_file = cfg.host .. "__wanstats_tx"
      local wanstats_rx_file = cfg.host .. "__wanstats_rx"
      local txbl, txtl, rxbl, rxtl
      txbl, txtl = get_stats(wanstats_tx_file)
      rxbl, rxtl = get_stats(wanstats_rx_file)
      local rxd = rxb - rxbl
      -- n bit counter wraps with break of uplink; no measurement possible then
      if rxd < 0 then rxd = 0 end	
      local txd = txb - txbl
      if txd < 0 then txd = 0 end 
      rxrate = rxd * 8 / (rxt - rxtl)
      txrate = txd * 8 / (txt - txtl)
      if rxrate < 0 or txrate < 0 then
         -- Should never happen because we try to compensate counter wrap above
         exitError(format(
                      "negative rate: txb=%d rxb=%d txbl=%d rxbl=%d time=%s",
                      txb, rxb, txbl, rxbl, os.date()))
      end
      put_stats(wanstats_tx_file, txb, txt)
      put_stats(wanstats_rx_file, rxb, rxt)
      local vout = {
         format("WAN Statistics:"),
         format("Received Bytes:    %d Bytes (%.1f MBytes)", rxb, rxb/1e6),
         format("Transmitted Bytes: %d Bytes (%.1f MBytes)", txb, txb/1e6),
         format("Receive Rate:      %.1f bit/s", rxrate),
         format("Transmit Rate:     %.1f bit/s", txrate),
         format("Time Interval:     %d %d seconds", txt - txtl, rxt - rxtl)
      }
      local rdata = {
         format("%s - RX: %d Bytes (%.1f bit/s), TX: %d Bytes (%.1f bit/s)",
                state, rxb, rxrate, txb, txrate),
         format("rxrate=%dbit/s txrate=%dbit/s;%d;%d;%d;%d",
                rxrate, txrate, 0, 0, 0, 0)
      }
      return rdata, vout
   end,
   
   check_lanstats = function(cfg)
      local txb, rxb, xt = tr64_lanstats(cfg.url)
      local lanstats_tx_file = cfg.host .. "__lanstats_tx"
      local lanstats_rx_file = cfg.host .. "__lanstats_rx"
      local txbl, rxbl, xtl
      txbl, xtl = get_stats(lanstats_tx_file)
      rxbl, xtl = get_stats(lanstats_rx_file)
      local txd = txb - txbl
      -- compensate 32 bit counter wrap
      if txd < 0 then txd = txd + 2^32 end
      local rxd = rxb - rxbl
      if rxd < 0 then rxd = rxd + 2^32 end
      rxrate = rxd * 8 / (xt - xtl)
      txrate = txd * 8 / (xt - xtl)
      if rxrate < 0 or txrate < 0 then
         -- Should never happen because we try to compensate counter wrap above
         exitError(format(
                      "negative rate: txb=%d rxb=%d txbl=%d rxbl=%d time=%s",
                      txb, rxb, txbl, rxbl, os.date()))
      end
      put_stats(lanstats_tx_file, txb, xt)
      put_stats(lanstats_rx_file, rxb, xt)
      local vout = {
         format("LAN Statistics:"),
         format("Received Bytes:    %d Bytes (%.1f MBytes)", rxb, rxb/1e6),
         format("Transmitted Bytes: %d Bytes (%.1f MBytes)", txb, txb/1e6),
         format("Receive Rate:      %.1f bit/s", rxrate),
         format("Transmit Rate:     %.1f bit/s", txrate),
         format("Time Interval:     %d seconds", xt - xtl)
      }
      local rdata = {
         format("%s - RX: %d Bytes (%.1f bit/s), TX: %d Bytes (%.1f bit/s)",
                state, rxb, rxrate, txb, txrate),
         format("rxrate=%dbit/s txrate=%dbit/s;%d;%d;%d;%d", rxrate, txrate, 0, 0, 0, 0)
      }
      return rdata, vout
   end,
   
   check_ssid = function(cfg)
      local ssid, res = tr64_ssid(cfg.url)
      local retstr
      if res.NewEnable == "0" or res.NewStatus == "Down" then
         state = "CRITICAL"
         retstr = format("WLAN %q is down", res.NewSSID)
      else
         retstr = format("WLAN %q is up", res.NewSSID)
      end
      local vout = {
         format("WLAN status:"),
         format("SSID:       %s", res.NewSSID),
         format("Enabled:    %s", res.NewEnable),
         format("Status:     %s", res.NewStatus),
         format("BeaconType: %s", res.NewBeaconType),
         format("BSSID:      %s", res.NewBSSID)
      }
      
      local rdata = {
         format("%s - %s", state, retstr),
         format("enable=%d status=%s", res.NewEnable, res.Newstatus) 
      }
      return rdata, vout
   end,
   
   check_wlanstats = function(cfg)
      local txp, rxp, xt = tr64_wlanstats(cfg.url)
      local wlanstats_tx_file = cfg.host .. "__wlanstats_tx"
      local wlanstats_rx_file = cfg.host .. "__wlanstats_rx"
      local txpl, rxpl, xtl
      txpl, xtl = get_stats(wlanstats_tx_file)
      rxpl, xtl = get_stats(wlanstats_rx_file)
      local txd = txp - txpl
      -- compensate 32 bit counter wrap
      if txd < 0 then txd = txd + 2^32 end
      local rxd = rxp - rxpl
      if rxd < 0 then rxd = rxd + 2^32 end
      rxrate = rxd * 8 / (xt - xtl)
      txrate = txd * 8 / (xt - xtl)
      if rxrate < 0 or txrate < 0 then
         -- Should never happen because we try to compensate counter wrap above
         exitError(format(
                      "negative rate: txp=%d rxp=%d txpl=%d rxpl=%d time=%s",
                      txp, rxp, txpl, rxpl, os.date()))
      end
      put_stats(wlanstats_tx_file, txp, xt)
      put_stats(wlanstats_rx_file, rxp, xt)
      local vout = {
         format("WLAN Statistics:"),
         format("Received Packets:    %d packets", rxp),
         format("Transmitted Packets: %d packets", txp),
         format("Receive Rate:        %.1f packets/s", rxrate),
         format("Transmit Rate:       %.1f packets/s", txrate),
         format("Time Interval:       %d seconds", xt - xtl)
      }
      local rdata = {
         format("%s - RX: %d packets (%.1f packets/s), TX: %d packets (%.1f packets/s)",
                state, rxp, rxrate, txp, txrate),
         format("rxrate=%dpackets/s txrate=%dpackets/s;%d;%d;%d;%d",
                rxrate, txrate, 0, 0, 0, 0)
      }
      return rdata, vout
   end,
   
   check_time = function(cfg)
      local dat, offs, res = tr64_time(cfg.url)
      local tim = os.time(dat)
      local retstr = string.gsub(os.date("%D %T", tim),"/",".")
      local vout = {
         format("Local time information:"),
         format("Date and Time: %s", retstr),
         format("Offset:        %s:%s", offs.hour, offs.min),
         format("Returned:      %s", res.NewCurrentLocalTime),
         format("Reference:     %s", os.date("%d.%m.%y %H:%M:%S")),
         format("NTP Server 1:  %s", res.NewNTPServer1),
         format("NTP Server 2:  %s", res.NewNTPServer2)
      }
      local rdata = {
         format("%s - Local time is %s", state, retstr),
         format("time=%s reftime=%s", tim, os.time())
      }
      return rdata, vout
   end,
   
   check_wlanchannel = function(cfg)
      local ch, chl = tr64_wlanchannel(cfg.url)
      local vout = {
         format("Channel information:"),
         format("Active Channel:     %s", ch),
         format("Available Channels: %s", chl)
      }
      local rdata = {
         format("%s - active channel %s", state, ch),
         format("channel=%s", ch)
      }
      return rdata, vout
   end,
   
   check_wlandevs = function(cfg)
      local ndev, devs = tr64_wlandevs(cfg.url, cfg.special)
      local vout = {
         format("WLAN device information:")
      }
      if cfg.special == "auth-only" then
         tinsert(vout, format("Number of devices known and authenticated: %d", ndev))
      else
         tinsert(vout, format("Number of devices known: %d", ndev))
      end
      for i = 1, ndev do
         local dev = devs[i]
         tinsert(vout, format("  Device %d:", i))
         tinsert(vout, format("  MacAddress:      %s", dev.MacAddress))
         tinsert(vout, format("  IpAddress:       %s", dev.IpAddress))
         tinsert(vout, format("  AuthState:       %s", dev.AuthState))
         tinsert(vout, format("  Speed:           %s Mbit/s", dev.Speed))
         tinsert(vout, format("  Signal Strength: %d %%", tonumber(dev.SignalStrength)))
      end
      local rdata = {}
      if cfg.special == "auth-only" then
         tinsert(rdata, format("%s - %d devices authenticated", state, ndev))
         tinsert(rdata, format("ndev=%d", ndev))
      else
         tinsert(rdata, format("%s - %d devices kown", state, ndev))
         tinsert(rdata, format("ndev=%d", ndev))
      end
      return rdata, vout
   end
}

local function main(...)

   local cfg = {
      host = "fritz.box",
      port = 49000,
      warn = 0,
      warnp = 0,
      crit= 0,
      critp = 0,
      mode = nil,
      verbosity = 0,
      logfilename = "tmp/check_fritz.log",
      logfile = nil,
      state = "OK"
   }
   
   optarg,optind = alt_getopt.get_opts (arg, "hVvH:C:i:m:w:c:u:P:s:L:", long_opts)

   for k,v in pairs(optarg) do
      if k == "H" then
         cfg.host = v
      elseif k == "i" then
         cfg.index = v
         cfg.have_index = true
      elseif k == "m" then
         cfg.mode = v
      elseif k == "h" then
         exitUsage()
      elseif k == "w" then
         if string.sub(v, -1) == "%" then
            cfg.warnp = tonumber(string.sub(v, 1, -2))
         else
            cfg.warn = tonumber(v)
         end
      elseif k == "c" then
         if string.sub(v, -1) == "%" then
            cfg.critp = tonumber(string.sub(v, 1, -2))
         else
            cfg.crit = tonumber(v)
         end
      elseif k == "v" then
         cfg.verbosity = 1
      elseif k == "V" then
         printf("check_fritz version %s", VERSION)
         os.exit(retval["OK"], true)
      elseif k == "u" then
         cfg.user = v
      elseif k == "P" then
         cfg.password = v
      elseif k == "s" then
         cfg.special = v
      elseif k == "L" then
         cfg.logfilename = v
      end
   end

   cfg.url = "http://" .. cfg.user .. ":" .. cfg.password .. "@" .. cfg.host .. ":" .. cfg.port
   cfg.logfile = io.open(cfg.logfilename,  "a+")
   
   local rdata, vout

   if cfg.mode ~= nil then
      rdata, vout = checks["check_"..cfg.mode](cfg)
   else
      exitError("unkown mode %q", cfg.mode)
   end

   if cfg.verbosity > 0 then
      printf("%s", table.concat(vout, "\n"))
   end
   
   printf("%s", table.concat(rdata, "|"))
   return retval[cfg.state]
end

return main(unpack(arg))
