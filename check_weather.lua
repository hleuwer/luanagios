#!/usr/bin/env lua
---
-- check_weather:
-- (c) Herbert Leuwer, May-2020
--

local getopt = require "alt_getopt"
local pretty = require "pl.pretty"
local http = require "socket.http"
local json = require "dkjson"

local tinsert, format = table.insert, string.format

local VERSION = "1.0"

local URL = "http://api.openweathermap.org/data/2.5/"

local debug = os.getenv("debug") == "yes"

---
-- Get GEO location as latitude, longitude from given location name.
-- @param location Name of location.
-- @return Table with geo location la=LATTITUDE, lo=LONGITUDE.
local function get_geo_location(location, appid)
   local t = {}
   local url = string.format("%sweather?q=%s&APPID=%s",
			     URL, location, appid)
   b, c, h = http.request(url)
   if b == nil then
      return nil, "http request failure"
   else
      t = json.decode(b)
      if c ~= 200 then
	 return nil, t.message
      end
   end
   return t.coord
end

---
-- Create request URL.
-- @param apitype Type of api: `'forecast', 'current', 'history'`. Default: current.
-- @param location Location in geo coordinates: ``{lat=LAT, lon=LON}`. Default: Berlin.
-- @param language Language: de, en, ...  Default: de.
-- @param units Units to be used in response: 'metric', 'imperial'. Default: metric.
-- @param exclude Fields to exclude from response: 'current', 'minutely', 'hourly', 'daily'.
--                Default: include all
-- @param appid API key.
-- @return Request URL with all parameters included.
local function mkUrl(mode, location, language, units, exclude, appid)

   local url = URL -- "http://api.openweathermap.org/data/2.5/"
   
   if mode == "forecast" then
      url = url .. "onecall?"
   elseif mode == "current" or mode == "location" then
      url = url .. "weather?"
   elseif mode == "history" then
      url = url .. "onecall/timemachine?"
   else
      return nil, "invalid mode"
   end

   local param = {}
   if type(location) == "string" then
      location, err = get_geo_location(location, appid)
      if not location then
	 return nil, err
      end
   elseif type(location) ~= "table" then
      return nil, "invalid location"
   end

   tinsert(param, format("lat=%.2f", location.lat))
   tinsert(param, format("lon=%.2f", location.lon))
   tinsert(param, format("lang=%s", language or "de"))
   tinsert(param, format("units=%s", units or "metric"))
   if mode == "history" then
      tinsert(param, format("dt=%d", os.time()))
   end
   if mode == "forecast" then
      if exclude ~= nil then
	 tinsert(param, format("exclude=%s", exclude))
      end
   end
   tinsert(param, format("appid=%s", appid))
   
   url = url .. table.concat(param, "&")

   return url
end

-- Options
local long_opts = {
   verbose = "v",
   help    = "h",
   version = "V",
   warning = "w",
   critical = "c",
   mode = "m",
   password = "P",
   loc = "l",
   out = "o",
   forecast = "f",
   sample = "s",
   loc = "l",
   geo = "g",
   units = "u",
   lang = "L",
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
   "   -l, --loc=NAME                Location name, e.g. Berlin",
   "   -g, --geo=LA,LO               Location coordinates, LATITUDE,LONGITUDE",
   "   -m, --mode=MODE               Mode: current, forecast, history or location",
   "   -o, --out=OUTP                Output: all, coord, temp, ...",
   "   -f, --forecast=FORECAST       Forecast type: hourly, daily",
   "   -s, --asmple=SAMPLE           Sample in forecast or history list: 1 to N",
   "   -v, --verbose                 Verbose (detailed) output",
   "   -w, --warn=WARNTHRESHOLD      Warning threshold for defined OUTP",
   "   -c, --critical=CRITTHRESHOLD  Critical threshold for temperature",
   "   -u, --units=M|I               Units _Metric_ or _Imperial_",
   "   -L, --lang=LANG               de=german, en=ENGLISH (default)",
   "   -P, --password=APPID          App Id for the openweathermaps.org API",
   "   -h, --help                    Get this help",
   "   -V, --version                 Show version info"
}

local DESCRIPTION = {
   "This Nagios plugin retrieves weather information from Open Weathermap.",
   "  Two modes are supported:",
   "  - mode=current   current weather",
   "  - mode=forecast  current, hourly and daily forecast",
   "  - mode=history   history weather data",
   "  - mode=coord     geo coordinates",   
   " ",
   "  The following values are delivered for current and forecast",
   "  - out=all         all of the below values are delivered",
   "  - out=geo         latitude and longitude",
   "  - out=temp        temperature",
   "  - out=feels       temperature",
   "  - out=pressure    presure",
   "  - out=humidity    humidity",
   "  - out=uvi         UV index",
   "  - out=wind        wind speed, gust and direction",
   "  - out=weather     weather description",
   " ",
   "  Forecast types",
   "  - forecast=hourly hourly forecast for 24 hours",
   "  - forecast=daily  daily forecast for 7 days",
   " ",
   "  Forcast samples",
   "  - sample=1..7     daily forecast sample day 1 to 7",
   "  - sample=1..24    hourly forecast sample hour 1 to 24",
   " ",
   "Notes: ",
   "(1) The call frequency is limited depending on the underlying",
   "    contract with openweathermap.org."
}

---
-- Formatted print to stdout.
-- @param fmt Format definition.
-- @return nil or err + errmessage
local function printf(fmt, ...)
   io.stdout:write(format(fmt.."\n", ...))
end

---
-- Formatted print to stderr.
-- @param fmt Format definition.
-- @return nil or err + errmessage
local function fprintf(fmt, ...)
   return io.stderr:write(format(fmt.."\n", ...))
end

local function dprintf(fmt, ...)
   if debug == true then
      io.stderr:write(">> " .. format(fmt.."\n", ...))
   end
end

---
-- Prints usage string and exits.
-- @return Never returns.
local function exitUsage()
   printf("%s", table.concat(DESCRIPTION,"\n"))
   printf("")
   printf("%s", table.concat(USAGE, "\n"))
   os.exit(retval["OK"], true)
end

---
-- Exit with error message.
-- @param fmt Format for error message to output to stderr.
-- @return Never returns.
local function exitError(fmt, ...)
   fprintf("UKNOWN - check_host returned with error: "..fmt, ...)
   os.exit(retval["UNKNOWN"], true)
end

---
-- Convert 'LA,LO' command parameter to table.
-- @param loc Loacation as number pair LA,LO.
-- @return Table with components la=LA and lo=LO.
local function get_loc(loc)
   local t = {}
   string.gsub(loc,"(%w+),(%w+)$",
	       function(la, lo)
		  t.la = tonumber(la)
		  t.lo = tonumber(lo)
	       end
   )
   return t
end

local UNITS = {
   temp = {
      default = "K",
      metric = "°C",
      imperial = "°F"
   },
   wind = {
      default = "m/s",
      metric = "m/s",
      imperial = "mi/h"
   }
}

local function gU(what, units)
   return UNITS[what][units]
end

local function date(secs)
   return os.date("%A %d.%B %Y %H:%M:%S", secs)
end

local function time(secs)
   return os.date("%H:%M:%S", secs)
end
local locales = {
   de = "de_DE.UTF-8",
--   de = "de_DE.ISO8859-15",
   en = "en_EN.UTF-8"
}
---
-- Main function.
-- @return 0 on success, nil + error message on failure.
local function main(...)
   local descr 
   local index
   local verbosity = 0
   local mode = "current"
   local state = "OK"
   local warn, warnp = 0, 0
   local crit, critp = 0, 0
   local loc, geoloc = "Hamburg", {lat=53.55, lon=10}
   local lang = "de"
   local units = "metric"
   local out = "all"
   local fctype = "daily"
   local sample = 2
   local appid = nil
   local rdata
   local res

   optarg,optind = alt_getopt.get_opts (arg, "hVvm:w:c:l:L:P:g:o:f:s:u:", long_opts)

   for k,v in pairs(optarg) do
      if k == "m" then
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
      elseif k == "l" then
	 loc = v
      elseif k == "g" then
	 geoloc = get_loc(v)
      elseif k == "o" then
	 out = v
      elseif k == "f" then
	 fctype = v
      elseif k == "s" then
	 sample = tonumber(v) + 1
      elseif k == "v" then
         verbosity = 1
      elseif k == "V" then
         printf("check_host version %s", VERSION)
         os.exit(retval["OK"], true)
      elseif k == "L" then
	 lang  = v
      elseif k == "u" then
	 units = v
      elseif k == "P" then
	 appid = v
      end
   end
   -- We set the locale according to language
   os.setlocale(locales[lang])

   if mode == "coord" then
      local t, err, h = get_geo_location(loc)
      if t == nil then
	 state = "ERROR"
	 rdata = {
	    format("%s - %s", state, err)
	 }
      else
	 if verbosity > 0 then
	    printf("Coordinates of %q:", loc)
	    printf("  lattitude: %.2f", t.lat)
	    printf("  longitude: %.2f", t.lon)
	 end
	 rdata = {
	    format("%s - %s la=%.2f lo=%.2f", state, loc, t.lat, t.lon)
	 }
      end
   else
      local url, err = mkUrl(mode, loc, lang, units, nil, appid)
      dprintf(url, err)
      if not url then
	 state = "UNKNOWN"
	 if verbosity > 0 then
	    printf("ERROR: %s", err)
	 end
	 rdate = {
	    format("%s - %s", state, err)
	 }
	 printf("%s - %s", state, err)
	 return retval[state]
      end
      local b, c, h = http.request(url)
      if b == nil then
	 return nil, c
      end
      local t = json.decode(b)
      dprintf(pretty.write(t))
      --
      -- current
      --
      if mode == "current" then
	 if verbosity > 0 then
	    printf("Coordinates of %q", t.name)
	    printf("  lattitude: %.2f", t.coord.lat)
	    printf("  longitude: %.2f", t.coord.lon)
	    printf("Weather:")
	    printf("  description: %q", t.weather[1].description)
	    printf("  temperature: %.2f %s", t.main.temp, gU("temp", units))
	    printf("  feels like : %.2f %s", t.main.feels_like, gU("temp", units))
	    printf("  pressure   : %d hPa", t.main.pressure)
	    printf("  humidity   : %d %%", t.main.humidity)
	    printf("  wind       : %.1f %s at %d deg", t.wind.speed, gU("wind", units), t.wind.deg)
	    printf("Times::")
	    printf("  date & time: %s", date(t.dt))
	    printf("  sunrise    : %s", time(t.sys.sunrise))
	    printf("  sunset     : %s", time(t.sys.sunset))
	 end
	 if out == "all" then
	    rdata = {
	       format("%s - Weather in %s: %s, temperature %.1f %s",
		      state, t.name, t.weather[1].description, t.main.temp, gU("temp", units)),
	    }
	 else
	    if out == "geo" then
	       rdata = {format("%s - Weather in %s: %s, lattitude %.2f longitude %.2f",
			       state, t.name, t.weather[1].description, t.coord.lat, t.coord.lon)}
	    elseif out == "temp" then
	       rdata = {format("%s - Weather in %s: %s, temperature %.1f %s",
			       state, t.name, t.weather[1].description, t.main.temp, gU("temp", units))}
	    elseif out == "feels" then
	       rdata = {format("%s - Weather in %s: %s, feels like %.1f %s",
			       state, t.name, t.weather[1].description, t.main.feels_like, gU("temp", units))}
	    elseif out == "pressure" then
	       rdata = {format("%s - Weather in %s: %s, pressure %d hPa",
			       state, t.name, t.weather[1].description, t.main.pressure)}
	    elseif out == "humidity" then
	       rdata = {format("%s - Weather in %s: %s, humidity %d %%",
			       state, t.name, t.weather[1].description, t.main.humidity)}
	    elseif out == "wind" then
	       rdata = {format("%s - Weather in %s: %s, wind %.1f %s at %d deg",
			       state, t.name, t.weather[1].description, t.wind.speed, gU("wind", units), t.wind.deg)}
	    else
	       exitError("invalid output selection  %q", out)
	    end
	 end
	 
	 if out == "geo" or out == "all" then
	    tinsert(rdata, format("lat=%.2f", t.coord.lat))
	    tinsert(rdata, format("lon=%.2f", t.coord.lon))
	 end
	 if out == "temp" or out == "all" then
	    tinsert(rdata, format("temp=%.1f %s", t.main.temp, gU("temp", units)))
	 end
	 if out == "feels" or out == "all" then
	    tinsert(rdata, format("feels like=%.1f %s", t.main.feels_like, gU("temp", units)))
	 end
	 if out == "pressure" or out == "all" then
	    tinsert(rdata, format("pressure=%d hPa", t.main.pressure))
	 end
	 if out == "humidity" or out == "all" then
	    tinsert(rdata, format("humidity=%d %%", t.main.humidity))
	 end
	 if out == "uvi" then
	 end
	 if out == "wind" or out == "all" then
	    tinsert(rdata, format("wind=%.1f %s at %d deg", t.wind.speed, gU("wind", units), t.wind.deg))
	 end

      elseif mode == "forecast" or mode == "history" then
	 if mode == "forecast" then
	    if fctype == "daily" and (sample < 2 or sample > 8) and mode == "forecast" then
	       exitError("invalid sample %d for daily forecast", sample - 1)
	    end
	 else
	    fctype = "hourly"
	    if (sample < 2 or sample > 19) then
	       exitError("invalid sample %d for hourly history", sample - 1)
	    end
	 end
	 if fctype == "hourly" and (sample < 2 or sample > 25) then
	    exitError("invalid sample %d for hourly %s", sample - 1, mode)
	 end
	 if verbosity > 0 then
	    printf("Coordinates of %q", loc)
	    printf("  lattitude: %.2f", t.lat)
	    printf("  longitude: %.2f", t.lon)
	    if fctype == "hourly" then
	       printf("Hourly %s", mode)
	       for k, u in ipairs(t.hourly) do
		  if k > 1 then
		     printf("  %s: temperature: %.1f feels like: %.1f wind: %.1f %s at %d deg %s",
			    os.date("%d.%m.%Y %H:%M", u.dt), u.temp, u.feels_like,
			    u.wind_speed, gU("wind", units), u.wind_deg,
			    u.weather[1].description)
		  end
	       end
	    elseif fctype == "daily" and mode == "forecast" then
	       printf("Daily forecast")
	       for k, u in ipairs(t.daily) do
		  if k > 1 then
		     printf("  %s: sun rise: %s set: %s temp day: %.1f night: %.1f humidity: %s %% wind: %.1f %s at %d deg %s",
			    os.date("%d.%m.%Y", u.dt), 
			    os.date("%H:%M", u.sunrise), os.date("%H:%M", u.sunset),
			    u.temp.day, u.temp.night, u.humidity,
			    u.wind_speed, gU("wind", units), u.wind_deg,
			    u.weather[1].description)
		  end
	       end
	    end
	 end
	 if fctype == "daily" then
	    if mode == "forecast" then
	       rdata = {
		  format("%s - Weather %s %s in %s: %s",
			 state, fctype, mode, loc, t.daily[sample].weather[1].description)
	       }
	       tinsert(rdata, format("temp=%.1f %s", t.daily[sample].temp.day, gU("temp", units)))
	       tinsert(rdata, format("date=%s", os.date("%d.%m.%Y", t.daily[sample].dt)))
	    end
	 else
	    rdata = {
	       format("%s - Weather %s %s in %s: %s",
		      state, fctype, mode, loc, t.hourly[sample].weather[1].description)
	    }
	    tinsert(rdata, format("temp=%.1f %s", t.hourly[sample].temp, gU("temp", units)))
	    tinsert(rdata, format("date=%s", os.date("%d.%m.%Y %H:%M", t.hourly[sample].dt)))
	 end
      end
   end
   printf("%s", table.concat(rdata, "|"))
   return retval[state]
end

return main(table.unpack(arg))
