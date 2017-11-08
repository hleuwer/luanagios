#!/usr/bin/env lua
local getopt = require "alt_getopt"
local pretty = require "pl.pretty"
local snmp = require "snmp"

local VERSION = "1.0"

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

local USAGE = [[
usage: check_storage -H hostname -C community OPTIONS")
   -h,--help                    Get this help
   -v,--verbose                 Verbose (detailed) output      
   -H,--hostname=HOSTNAME       Define host ip address
   -C,--community=COMMUNITY     Devine SNMP community
   -w,--warn=WARNTHRESHOLD      Warning threshold
   -c,--critical=CRITTHRESHOLD  Critical threshold
   -d,--descr=DESCR             Storage description
   -l,--letter=LETTER           Alternate storage description
   -i,--index                   Index in storage table
   -V,--version                 Show version info
]]

local DESCRIPTION = [[
This Nagios plugin check any entry in a hosts SNMP 'hrStorage' table.
The entry in this table can be retrieved in one of the following ways:
  1) direct adressing via index (option --index)
  2) indirect addressing via description (option --descr)
  3) indirect addressing using a substring 
]]

local function printf(fmt, ...)
   io.stdout:write(string.format(fmt.."\n", ...))
end

local function fprintf(fmt, ...)
   io.stderr:write(string.format(fmt.."\n", ...))
end

local function exitUsage()
   printf("%s", DESCRIPTION)
   printf("%s", USAGE)
   os.exit(retval["OK"])
end

local function exitError(fmt, ...)
   fprintf("error: "..fmt, ...)
   os.exit(retval["UNKNOWN"])
end

local function getIndex(entries, descr, letter)
   local index
   -- search disk index
   for k,v in pairs(entries) do
      if (letter and string.find(v, letter)) or (descr and entries[k] == descr) then
         index = string.gsub(k,"%w+%.(%w+)$", "%1")
         break
      end
   end
   if not index then
      exitError("Entry '%s' not found.", descr or letter)
   end
   return index
end

local function main(...)
   
   local host = "localhost"
   local community = "public"
   local descr 
   local index
   local mode = "disk"
   local warn, warnp = 0, 0
   local crit, critp = 0, 0
   
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
         verbose = true
      elseif k == "l" then
         drive = v
         if not have_index and not have_descr then
            have_letter = true
         end
      elseif k == "V" then
         printf("check_storage version %s", VERSION)
         os.exit(retval["OK"])
      end
   end

   local sess, err = assert(snmp.open{
                               peer = host,
                               version = SNMPv2,
                               community = community
   })
   
   if mode == "disk" or mode == "mem" then

      -- read the storage table from device
      local d = sess.hrStorage

      if not have_index and not have_descr and not have_letter then
         exitError("Either index or descr must be provided.")
      end
      
      if not have_index then
         index = getIndex(d, descr, drive)
      end

      if false then
         if mode == "disk" then
            process_disk(d, index)
         elseif mode == "mem" then
            process_mem(d, index)
         end
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

      if verbose then
         printf("Memory size:   %d kBytes", d["hrMemorySize.0"])
         printf("Storage index: %d", index)
         printf("Storage descr: %s", descr)
         printf("Storage type:  %s", d["hrStorageType."..index])
         printf("Storage size:  %d MBytes", nsize/mb)
         printf("Storage used:  %d MBytes", nused/mb)
         printf("Storage unit:  %d Bytes", bsize)
                
      end
      
      local t = {
         string.format("%s - %s at %.1f %% with %d MB of %d MB free",
                       state, descr, usage, (nsize-nused)/mb, nsize/mb),
         string.format("|size=%d free=%d usage=%.1f%%;%d;%d;%d;%d",
                        nsize, nsize - nused, usage, warnp, critp, 0, 100)
      }
      printf("%s", table.concat(t))
   end

   sess:close()
   
   return retval[state]
end

main(unpack(arg))
