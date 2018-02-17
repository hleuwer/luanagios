# luanagios
Nagios Plugins written with Lua.

Luanagios allows to write NAGIOS check plugins in Lua.

Currently two modules are provided: 
* check_host.lua
* check_fritz.lua

Access to the devices occurs either via SNMP v2 or via TR-64 SOAP access.

For SNMP access to hosts the module [LuaSNMP](https://github.com/hleuwer/luasnmp "LuaSNMP repository") is used. This requires a running SNMP agent 
in the host, which can easily be installed on Linux computer and is by default available
on MACOSX and Windows hosts. On Windows hosts the SNMP agent service must first be enabled.

TR-64 access to AVM FritzBox uses the module [luasoap](https://github.com/hleuwer/luasoap "luasoap repository").
Note, that the given link refers to a cloned repository for luasoap, which contains a couple of changes that were necessary for supporting luanagios.
A corresponding pull-request for the changes is pending in the original [repository](https://github.com/tomasguisasola/luasoap "Orignal luasoap repository").

The Lua module [lua-http-digest](https://github.com/catwell/lua-http-digest "lua-http-digest repository")is used for HTTP digest authentication to AVM FritzBox routers.


## check_host.lua:
```
This Nagios plugin retrieves the following status and performance data for host computers:
  - mode=disk:    disk usage
  - mode=mem:     memory usage
  - mode=load:    processor load per core and average over all cores
  - mode=uptime:  uptime of the host
  - mode=otemp:   outside temperature sensor 1 DS18B20
  - mode=itemp:   inside temperature sensor 2 DS18B20
  - mode=alltemp: all installed temperature sensors DS18B20

The disk to be monitored can be selected in one of the following ways:
  1) direct adressing via index in SNMP table (option --index), --index=31
  2) indirect addressing via description (option --descr), e.g. --descr='/'
  3) indirect addressing using a substring (option --letter), e.g. --letter='C:'

The memory to be monitored is best selected with --descr='Physical Memory' or
with --letter='Physical' (substring).
Disk and memory are retrieved from SNMP hrStorage entries.
The processor load is retrieved from SNMP hrProcessorLoad entries.

Note: The DS18B20 temperature sensors use 1-wire interface serviced by software.
      This leads to long execution times.

usage: check_host -H hostname -C community OPTIONS
   -h,--help                    Get this help
   -v,--verbose                 Verbose (detailed) output
   -H,--hostname=HOSTNAME       Define host ip address
   -C,--community=COMMUNITY     Devine SNMP community
   -m,--mode = MODE             Mode of check
   -w,--warn=WARNTHRESHOLD      Warning threshold
   -c,--critical=CRITTHRESHOLD  Critical threshold
   -d,--descr=DESCR             Storage description
   -l,--letter=LETTER           Alternate storage description
   -i,--index                   Index in storage table
   -V,--version                 Show version info

```
## check_fritz.lua:
```
This Nagios plugin retrieves the following status and performance
data for AVM routers.
The following data items can be selected:
   - mode=uptime:     uptime in seconds
   - mode=wanstatus:  current WAN status
   - mode=wanuptime:  time since last WAN link break and IP address assignment
   - mode=wanstats:   downstream and upstream statistics (data rate in Mbit/s)
   - mode=wlanstats   downstream and upstream packet statistics (data rate in packets/s)
   - mode=lanstats:   LAN statistics
   - mode=time:       Local time in device
   - mode=ssid:       WLAN SSID and status
usage: check_storage -H hostname -C community OPTIONS
   -h,--help                    Get this help
   -v,--verbose                 Verbose (detailed) output
   -H,--hostname=HOSTNAME       Define host ip address
   -m,--mode=MODE               Mode of check
   -w,--warn=WARNTHRESHOLD      Warning threshold
   -c,--critical=CRITTHRESHOLD  Critical threshold
   -i,--index                   Index in storage table
   -u,--user=USER               Username
   -P,--password=PASSWORD       Passowrd
   -V,--version                 Show version info
```
