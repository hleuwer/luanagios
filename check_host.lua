#!/usr/bin/env lua
---
-- check_host:
-- (c) Herbert Leuwer, Nov-2017
--
local getopt = require "alt_getopt"
local pretty = require "pl.pretty"
local snmp = require "snmp"

local VERSION = "1.0"

local host_tabs = {
   disk = "hrStorage",
   mem = "hrStorage",
   load = "hrProcessorLoad",
   uptime = "sysUpTime",
   itemp = "extOutput.3",
   otemp = "extOutput.2",
   alltemp = "extTable"
}

local long_opts = {
   verbose = "v",
   help    = "h",
   hostname = "H",
   community = "C",
   index = "i",
   descr = "d",
   version = "V",
   warning = "w",
   critical = "c",
   letter = "l",
   mode = "m"
}

local retval = {
   OK = 0,
   WARNING = 1,
   CRITICAL = 2,
   UNKNOWN = 3
}

local USAGE = {
   "usage: check_host -H hostname -C community OPTIONS",
   "   -h,--help                    Get this help",
   "   -v,--verbose                 Verbose (detailed) output",
   "   -H,--hostname=HOSTNAME       Define host ip address",
   "   -C,--community=COMMUNITY     Devine SNMP community",
   "   -m,--mode = MODE             Mode of check",
   "   -w,--warn=WARNTHRESHOLD      Warning threshold",
   "   -c,--critical=CRITTHRESHOLD  Critical threshold",
   "   -d,--descr=DESCR             Storage description",
   "   -l,--letter=LETTER           Alternate storage description",
   "   -i,--index                   Index in storage table",
   "   -V,--version                 Show version info"
}

local DESCRIPTION = {
   "This Nagios plugin retrieves the following status and performance data for host computers:",
   "  - mode=disk:    disk usage",
   "  - mode=mem:     memory usage",
   "  - mode=load:    processor load per core and average over all cores",
   "  - mode=uptime:  uptime of the host",
   "  - mode=otemp:   outside temperature sensor 1 DS18B20",
   "  - mode=itemp:   inside temperature sensor 2 DS18B20",
   "  - mode=alltemp: all installed temperature sensors DS18B20",
   " ",
   "The disk to be monitored can be selected in one of the following ways:",
   "  1) direct adressing via index in SNMP table (option --index), --index=31",
   "  2) indirect addressing via description (option --descr), e.g. --descr='/'",
   "  3) indirect addressing using a substring (option --letter), e.g. --letter='C:'",
   " ",
   "The memory to be monitored is best selected with --descr='Physical Memory' or",
   "with --letter='Physical' (substring).",
   "Disk and memory are retrieved from SNMP hrStorage entries.",
   "The processor load is retrieved from SNMP hrProcessorLoad entries.",
   " ",
   "Note: The DS18B20 temperature sensors use 1-wire interface serviced by software.",
   "      This leads to long execution times."
}

local function printf(fmt, ...)
   io.stdout:write(string.format(fmt.."\n", ...))
end

local function fprintf(fmt, ...)
io.stderr:write(string.format(fmt.."\n", ...))
end

local function exitUsage()
   printf("%s", table.concat(DESCRIPTION,"\n"))
   printf("")
   printf("%s", table.concat(USAGE, "\n"))
   os.exit(retval["OK"], true)
end

local function exitError(fmt, ...)
   printf("UKNOWN - check_host returned with error "..fmt, ...)
   os.exit(retval["UNKNOWN"], true)
end

local function getData(sess, mode)
   return sess[host_tabs[mode]]
end

local function getIndex(entries, descr, letter, mode)
   local index
   -- search disk index
   for k,v in pairs(entries) do
      if (letter and string.find(v, letter)) or (descr and entries[k] == descr) then
         index = string.gsub(k,"%w+%.(%w+)$", "%1")
         break
      end
   end
   if mode == "disk" or mode == "mem" and not index then
      exitError("Entry '%s' not found.", descr or letter)
   end
   return index
end

local function main(...)

   local host = "localhost"
   local community = "public"
   local descr 
   local index
   local verbosity = 0
   local mode = "disk"
   local warn, warnp = 0, 0
   local crit, critp = 0, 0
   local rdata
   local have_index, have_descr
   
   optarg,optind = alt_getopt.get_opts (arg, "hVvH:C:i:d:m:w:c:l:", long_opts)

   for k,v in pairs(optarg) do
      if k == "H" then
         host = v
      elseif k == "C" then
         community = v
      elseif k == "d" then
         descr = v
         if not have_index then
            have_descr = true
         end
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
      elseif k == "l" then
         drive = v
         if not have_index and not have_descr then
            have_letter = true
         end
      elseif k == "V" then
         printf("check_host version %s", VERSION)
         os.exit(retval["OK"], true)
      end
   end
   local sess, err = snmp.open{
      peer = host,
      version = SNMPv2,
      community = community
   }
   if not sess then
      exitError(err)
   end

   -- read data from device
   local status, d = pcall(getData, sess, mode)
   if status ~= true then
      -- Depending on the captured error in getData we may receive the error code
      -- within a table. 
      if type(d) == "table" then
         exitError(d[1])
      end
      exitError(d)
   end
            
   if mode == "disk" or mode == "mem" then

      if not have_index and not have_descr and not have_letter then
         exitError("Either index or descr must be provided.")
      end
      if not have_index then
         index = getIndex(d, descr, drive)
      end

      local mb = 1024*1024
      local size = d["hrStorageSize."..index]
      local descr = d["hrStorageDescr."..index]
      local used = d["hrStorageUsed."..index]
      local bsize = d["hrStorageAllocationUnits."..index]
      local nusage = used/size
      local nsize = size * bsize
      local nused = used * bsize
      local nusage = used/size
      local usage = nusage*100
      -- check notifications
      state = "OK"
      if ((warn and warn ~= 0 and size*bsize > warn) or
         (warnp and warnp ~=0 and usage > warnp)) then
         state = "WARNING"
      end
      if ((crit and crit ~= 0 and size*bsize > crit) or
         (critp and critp ~= 0 and usage > critp)) then
         state = "CRITICAL"
      end
      
      if verbosity > 0 then
         printf("Memory size:   %d kBytes", d["hrMemorySize.0"])
         printf("Storage index: %d", index)
         printf("Storage descr: %s", descr)
         printf("Storage type:  %s", d["hrStorageType."..index])
         printf("Storage size:  %d MBytes", nsize/mb)
         printf("Storage used:  %d MBytes", nused/mb)
         printf("Storage unit:  %d Bytes", bsize)
         
      end
      
      rdata = {
         string.format("%s - %s at %.1f %% with %d MB of %d MB free",
                       state, descr, usage, (nsize-nused)/mb, nsize/mb),
         string.format("size=%d free=%d usage=%.1f%%;%d;%d;%d;%d",
                       nsize, nsize - nused, usage, warnp, critp, 0, 100)
      }
   elseif mode == "load" then
      warn = warn or warnp
      crit = crit or critp
      local idata = {}
      local load = 0
      local pdata = {} 
      local state = "OK"
      local t = {}
      for k,v in pairs(d) do
         table.insert(t, {key=k,val=v})
      end
      table.sort(t, function(a,b) return a.key < b.key end)
      for i, e in ipairs(t) do
         local v = e.val
         load = load + v
         if (warn and warn ~= 0 and v > warn) then
            state = "WARNING"
         end
         if (crit and crit ~= 0 and v > crit) then
            state = "CRITICAL"
         end
         table.insert(idata, string.format("%d",v))
         table.insert(pdata, string.format("load%d=%d%%", i, v))
      end
      load = load / #t
      table.insert(pdata, string.format("load=%.1f%%", load))
      if verbosity > 0 then
         printf("Number of cores:        %2d", #t)
         printf("Average load all cores: %2d %%", load)
         for i, e in ipairs(t) do
            printf("Load in core %d:         %2d %%", i, e.val)
         end
      end
      rdata = {
         string.format("%s - %.1f %% load in %d cores (%s)",
                       state, load, #t, table.concat(idata, ",")),
         string.format("%s;%d;%d;%d;%d", table.concat(pdata, " "), warn, crit, 0, 100)
      }
   elseif mode == "uptime" then
      local state = "OK"
      if verbosity > 0 then
         printf("Uptime:")
         printf("  %2d days", d.days)
         printf("  %2d hours", d.hours)
         printf("  %2d minutes", d.minutes)
         printf("  %2d seconds", d.seconds)
         printf("  %d ticks", d.ticks)
      end
      rdata = {
         string.format("%s - Uptime is %d days %02d:%02d:%02d (%d)", state, d.days, d.hours,
                       d.minutes, d.seconds, d.ticks),
         string.format("uptime=%dd %dh %dm %ds", d.days, d.hours, d.minutes, d.seconds)
      }
   elseif mode == "otemp" then
      local state = "OK"
      local temp = tonumber(d)
      if verbosity > 0 then
         printf("Temperature sensor outside:")
         printf("%.2f °C", temp) 
      end
      rdata = {
         string.format("%s - Temperature Outside is %.2f C", state, temp),
         string.format("TempOut=%.2f", temp)
      }
   elseif mode == "itemp" then
      local state = "OK"
      local temp = tonumber(d)
      if verbosity > 0 then
         printf("Temperature sensor inside:")
         printf("%.2f °C", temp) 
      end
      rdata = {
         string.format("%s - Temperature Inside is %.2f C", state, temp),
         string.format("TempIn=%.2f", temp)
      }
   elseif mode == "alltemp" then
      local state = "OK"
      local t,p = {},{}
      if verbosity > 0 then
         printf("Temperature Sensors:")
      end
      for k = 2, 5 do
         local temp = d["extOutput."..k]
         if verbosity > 0 then
            printf("sensor %d: %.2f C", k-1, tonumber(temp))
         end
         table.insert(p, string.format("%.2f", tonumber(temp)))
         table.insert(t, string.format("%.2f C", tonumber(temp)))
      end
      
      rdata = {
         string.format("%s - Sensors show %s", state, table.concat(t, " ")),
         string.format("Sensors=%s", table.concat(p, ","))
      }

   end
   printf("%s", table.concat(rdata, "|"))

   sess:close()
   
   return retval[state]
end

return main(unpack(arg))
