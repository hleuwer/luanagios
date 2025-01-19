#!/usr/bin/env lua
---
-- check_weather:
-- (c) Herbert Leuwer, May-2020
--

local getopt = require "alt_getopt"
local pretty = require "pl.pretty"
local http = require "socket.http"
--local json = require "dkjson"
local json = require "cjson"
require "DataDumper"

local tinsert, format = table.insert, string.format

local VERSION = "1.0"

local URL = "https://api.openweathermap.org/data/3.0/"
local GURL = "https://api.openweathermap.org/geo/1.0/"

local debug = os.getenv("debug") == "yes"

---
-- Helper print to STDERR.
-- @param fmt format string
-- @param ... print arguments.
local function eprintf(fmt, ...)
   io.stderr:write(format(fmt, ...))
   io.stderr:flush()
end

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

local function getDate(s)
   local t = {}
   rv = string.gsub(s,"(%w+)%p(%w+)%p(%w+)%s*(%w*)%p*(%w*)%p*(%w*)",
		    function(d, m, y, H, M, S)
		       t = {day=d, month=m, year=y, hour=H, min=M, sec=S}
		    end
   )
   return t
end
---
-- Get GEO location as latitude, longitude from given location name.
-- @param location Name of location.
-- @return Table with geo location la=LATTITUDE, lo=LONGITUDE.
local function getGeoLocation(location, appid, printurl)
   local t = {}
   local url = string.format("%sdirect?q=%s&limit=1&appid=%s",
				GURL, location, appid)
   dprintf("GEO  URL: %q", url)
   if printurl == true then
      eprintf("Url:\n")
      printf("%s", url)
      os.exit(0)
   else
      b, c, h = http.request(url)
      if b == nil then
	 return nil, "http request failure"
      else
	 if c ~= 200 then
	    return nil, t.message
	 else
	    t = json.decode(b)
	 end
      end
      return t[1]
   end
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
local function mkUrl(mode, location, language, units, exclude, appid, time)

   -- do not use
   --   local url = URL -- "http://api.openweathermap.org/data/2.5/"
   
   if mode == "forecast" then
      url = URL .. "onecall?"
   elseif mode == "current" then
      url = URL .. "onecall?"
   elseif mode == "location" then
      url = URL .. "direct?"
   elseif mode == "history" then
      url = URL .. "onecall/timemachine?"
   else
      return nil, "invalid mode"
   end

   local param = {}
   if type(location) == "string" then
      location, err = getGeoLocation(location, appid, false)
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
      tinsert(param, format("dt=%d", time))
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
   mode = "m",
   json = "j",
   url = "U",
   table = "t",
   api = "a"
}

local retval = {
   OK = 0,
   WARNING = 1,
   CRITICAL = 2,
   UNKNOWN = 3
}

local USAGE = {
   "usage: check_weather -H hostname -C community OPTIONS",
   "   -l, --loc=NAME                Location name, e.g. Berlin",
   "   -g, --geo=LA,LO               Location coordinates, LATITUDE,LONGITUDE",
   "   -m, --mode=MODE               Mode: current, forecast, history or location",
   "   -o, --out=OUTP                Output: all, coord, temp, ...",
   "   -f, --forecast=FORECAST       Forecast type: hourly, daily",
   "   -j, --json                    Print JSON response",
   "   -U, --url                     Print request URL",
   "   -d, --date=DATE               Date and time for history data",
   "   -s, --sample=SAMPLE           Sample in forecast or history list: 1 to N",
   "   -v, --verbose                 Verbose (detailed) output",
   "   -w, --warn=WARNTHRESHOLD      Warning threshold for defined OUTP",
   "   -c, --critical=CRITTHRESHOLD  Critical threshold for temperature",
   "   -u, --units=M|I               Units _Metric_ or _Imperial_",
   "   -L, --lang=LANG               de=german, en=ENGLISH (default)",
   "   -P, --password=APPID          App Id for the openweathermaps.org API",
   "   -h, --help                    Get this help",
   "   -V, --version                 Show version info",
   "   -t, --table                   Show as Lua table",
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
   "  = out=dew         dew point",
   "  - out=clouds      cloudiness",
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
local function getLoc(loc)
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
   de = "de_DE.UTF-16",
--   de = "de_DE",
--   de = "de_DE",
--   de = "de_DE.ISO8859-1",
--   de = "de_DE.ISO8859-15",
   en = "en_EN.UTF-16"
}

local function printLocation(t)
   printf("LOCATION of %q", t.name)
   printf("  lattitude: %.2f", t.lat)
   printf("  longitude: %.2f", t.lon)
end

local function printWeather(t, units)
   if t.alerts ~= nil then
      printf("ALERTS:")
      for k, v in ipairs(t.alerts) do
	 printf("  alert %d:", k)
	 for __, w in ipairs(v.tags) do
	    printf("    %q", w)
	 end
	 printf("  start time : %s", date(v.start))
	 printf("  end time   : %s", date(v['end']))
	 printf("  description:\n  %q", v.description)
		  printf("  sender     : %q", v.sender_name)
      end
   end
   printf("WEATHER:")
   printf("  description: %q", t.weather[1].description)
   printf("  temperature: %.2f %s", t.temp, gU("temp", units))
   printf("  feels like : %.2f %s", t.feels_like, gU("temp", units))
   printf("  wind       : %.1f %s at %d deg", t.wind_speed, gU("wind", units), t.wind_deg)
   printf("  pressure   : %d hPa", t.pressure)
   printf("  humidity   : %d %%", t.humidity)
   printf("  dew point  : %.2f %s", t.dew_point, gU("temp", units))
   printf("  cloudiness : %d %%", t.clouds)
   printf("  uv index   : %.2f", t.uvi)
   if t.rain then
      printf("  rain       : %d mm/h", t.rain["1h"])
   end
   if t.snow then
      printf("  snow       : %d mm/h", t.snow["1h"])
   end
   printf("SUN:")
   printf("  date & time: %s", date(t.dt))
   printf("  sunrise    : %s", time(t.sunrise))
   printf("  sunset     : %s", time(t.sunset))

end

local function createRdata(state, name, tl, t, units, out)
   if out == "all" then
      rdata = {
	 format("%s - Weather in %s: %s, temperature %.1f %s",
		state, name, t.weather[1].description, t.temp, gU("temp", units)),
      }
   else
      if out == "geo" then
	 rdata = {format("%s - Weather in %s: %s, lattitude %.2f longitude %.2f",
			 state, name, t.weather[1].description, tl.lat, tl.lon)}
      elseif out == "temp" then
	 rdata = {format("%s - Weather in %s: %s, temperature %.1f %s",
			 state, name, t.weather[1].description, t.temp, gU("temp", units))}
      elseif out == "feels" then
	 rdata = {format("%s - Weather in %s: %s, feels like %.1f %s",
			 state, name, t.weather[1].description, t.feels_like, gU("temp", units))}
      elseif out == "pressure" then
	 rdata = {format("%s - Weather in %s: %s, pressure %d hPa",
			 state, name, t.weather[1].description, t.pressure)}
      elseif out == "humidity" then
	 rdata = {format("%s - Weather in %s: %s, humidity %d %%",
			 state, ame, t.weather[1].description, t.humidity)}
      elseif out == "wind" then
	 rdata = {format("%s - Weather in %s: %s, wind %.1f %s at %d deg",
			 state, name, t.weather[1].description, t.wind_speed, gU("wind", units), t.wind_deg)}
      elseif out == "clouds" then
	 rdata = {format("%s - Weather in %s: %s, cloudiness %d %%",
			 state, name, t.weather[1].description, t.clouds)}
      elseif out == "uvi" then
	 rdata = {format("%s - Weather in %s: %s, uvindex %.2f",
			 state, name, t.weather[1].description, t.uvi)}
      elseif out == "dew" then
	 rdata = {format("%s - Weather in %s: %s, dewpoint %.2f %s",
			 state, name, t.weather[1].description, t.dew_point, gU("temp", units))}
      elseif out == "sun" then
	 rdata = {format("%s - Weather in %s: %s, sunrise %s sunset %s",
			 state, name, t.weather[1].description, time(t.sunrise), time(t.sunset))}
      else
	 exitError("invalid output selection  %q", out)
      end
   end
   if out == "geo" or out == "all" then
      tinsert(rdata, format("lat=%.2f", tl.lat))
      tinsert(rdata, format("lon=%.2f", tl.lon))
   end
   if out == "temp" or out == "all" then
      tinsert(rdata, format("temp=%.1f %s", t.temp, gU("temp", units)))
   end
   if out == "feels" or out == "all" then
      tinsert(rdata, format("feels like=%.1f %s", t.feels_like, gU("temp", units)))
   end
   if out == "pressure" or out == "all" then
      tinsert(rdata, format("pressure=%d hPa", t.pressure))
   end
   if out == "humidity" or out == "all" then
      tinsert(rdata, format("humidity=%d %%", t.humidity))
   end
   if out == "uvi" or out == "all" then
      tinsert(rdata, format("uvindex=%.2f", t.uvi))
   end
   if out == "clouds" or out == "all" then
      tinsert(rdata, format("clouds=%d %%", t.clouds))
   end
   if out == "wind" or out == "all" then
      tinsert(rdata, format("wind=%.1f %s at %d deg", t.wind_speed, gU("wind", units), t.wind_deg))
   end
   if out == "dew" or out == "all" then
      tinsert(rdata, format("dew=%s %s", t.dew_point, gU("temp", units)))
   end
   if out == "sun" or out == "all" then
      tinsert(rdata, format("sunrise=%s", time(t.sunrise))) 
      tinsert(rdata, format("sunset=%s", time(t.sunset))) 
   end
   return rdata
end

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
   local loc, geoloc = "Langballig",
      {
	 lat=54.7919719,
	 lon=9.663334714510913
      }
   local lang = "de"
   local units = "metric"
   local out = "all"
   local fctype = "daily"
   local sample = 2
   local appid = nil
   local rdata
   local res
   local tabout = false
   local printjson = false
   local printurl = false
   local date_time = os.time()

   optarg,optind = alt_getopt.get_opts (arg, "hVvm:w:c:d:l:L:P:g:o:f:s:u:tjUa:", long_opts)

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
	 geoloc = getLoc(v)
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
      elseif k == "t" then
	 tabout = true
      elseif k == "j" then
	 printjson = true
      elseif k == "U" then
	 printurl = true
      elseif k == "d" then
	 date_time = os.time(getDate(v))
	 if date_time < os.time{year = 1979, month = 1, day = 1} then
	    exitError("no history data before 1.1.1979")
	 end
	 --date_time = os.time{day=17, month=1, year=2025, hour=12, min=59, sec=30}
      end
   end
   -- We set the locale according to language
   os.setlocale(locales[lang])
--   os.setlocale(locales["en"], "numeric")

   if mode == "coord" then
      local t, err, h = getGeoLocation(loc, appid, printurl)
      if t == nil then
	 state = "ERROR"
	 rdata = {
	    format("%s - %s", state, err)
	 }
      else
	 if verbosity > 0 then
	    printLocation(t)
	 end
	 rdata = {
	    format("%s - %s la=%.2f lo=%.2f", state, loc, t.lat, t.lon)
	 }
      end
   else
      local url, err = mkUrl(mode, loc, lang, units, nil, appid, date_time)
      dprintf("URL: %q", url, err)
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
      if printurl == true then
	 eprintf("Url:\n")
	 printf("%s", url)
	 return 0
      end
      local b, c, h = http.request(url)
      if b == nil then
	 return nil, c
      end
      local t = json.decode(b)
      if loc ~= nil then
	 t.name = loc
      end
      if printjson == true then
	 eprintf("Json:\n")
	 printf("%s", b)
	 return 0
      end
      if tabout == true then
	 eprintf("Json:\n")
	 printf("%s", b)
	 eprintf("Lua:\n")
	 printf("%s", DataDumper(t, nil, true, 0))
	 return 0
      end

      --
      -- current
      --
      if mode == "current" then
	 if verbosity > 0 then
	    printLocation(t)
	    printWeather(t.current, units)
	 end
	 rdata = createRdata(state, t.name, t, t.current, units, out)
	 ---
	 --- forecast
	 ---
      elseif mode == "forecast" then
	 if fctype == "daily" and (sample < 2 or sample > 8) and mode == "forecast" then
	    exitError("invalid sample %d for daily forecast", sample - 1)
	 end
	 if fctype == "hourly" and (sample < 2 or sample > 25) then
	    exitError("invalid sample %d for hourly %s", sample - 1, mode)
	 end
	 if verbosity > 0 then
	    printLocation(t)
	    if fctype == "hourly" then
	       printf("HOURLY FORECAST")
	       for k, u in ipairs(t.hourly) do
		  if k > 1 then
		     printf("  %s: temperature: %.1f feels like: %.1f wind: %.1f %s at %d deg %s",
			    os.date("%d.%m.%Y %H:%M", u.dt), u.temp, u.feels_like,
			    u.wind_speed, gU("wind", units), u.wind_deg,
			    u.weather[1].description)
		  end
	       end
	    elseif fctype == "daily" then
	       printf("DAILY FORECAST")
	       for k, u in ipairs(t.daily) do
		  if k > 1 then
		     printf("  %s: sun rise/set: %s/%s temp day/night: %.1f/%.1f %s humidity: %s %% wind: %.1f %s at %d deg %s",
			    os.date("%d.%m.%Y", u.dt), 
			    os.date("%H:%M", u.sunrise), os.date("%H:%M", u.sunset),
			    u.temp.day, u.temp.night, gU("temp", units), u.humidity,
			    u.wind_speed, gU("wind", units), u.wind_deg,
			    u.weather[1].description)
		  end
	       end
	    end
	 end
	 if fctype == "daily" then
	    rdata = {
	       format("%s - Weather %s %s in %s: %s",
		      state, fctype, mode, loc, t.daily[sample].weather[1].description)
	    }
	    tinsert(rdata, format("temp=%.1f %s", t.daily[sample].temp.day, gU("temp", units)))
	    tinsert(rdata, format("date=%s", os.date("%d.%m.%Y", t.daily[sample].dt)))
	 else
	    rdata = {
	       format("%s - Weather %s %s in %s: %s",
		      state, fctype, mode, loc, t.hourly[sample].weather[1].description)
	    }
	    tinsert(rdata, format("temp=%.1f %s", t.hourly[sample].temp, gU("temp", units)))
	    tinsert(rdata, format("date=%s", os.date("%d.%m.%Y %H:%M", t.hourly[sample].dt)))
	 end
	 ---
	 --- history
	 ---
      elseif mode == "history" then
	 if verbosity > 0 then
	    printf("LOCATION of %q", loc)
	    printf("  lattitude: %.2f", t.lat)
	    printf("  longitude: %.2f", t.lon)
	    printf("WEATHER: %s", os.date("%d.%m.%Y %H:%M:%S", t.data[1].dt))
	    printf("  description: %q", t.data[1].weather[1].description)
	    printf("  temperature: %.2f %s", t.data[1].temp, gU("temp", units))
	    printf("  feels like : %.2f %s", t.data[1].feels_like, gU("temp", units))
	    printf("  pressure   : %d hPa", t.data[1].pressure)
	    printf("  humidity   : %d %%", t.data[1].humidity)
	    printf("  dew point  : %d %s", t.data[1].dew_point, gU("temp", units))
	    printf("  clouds     : %d %%", t.data[1].clouds)
--	    printf("  uvindex    : %d", t.data[1].uvi)
	    printf("SUN:")
	    printf("  sunrise    : %s", time(t.data[1].sunrise))
	    printf("  sunset     : %s", time(t.data[1].sunset))
	 end
	 rdata = {
	    format("%s - Weather %s for %s in %s: %s",
		   state, mode, os.date("%d.%m.%Y %H:%M:%S", t.data[1].dt), loc, t.data[1].weather[1].description)
	 }
	 tinsert(rdata, format("temp=%.1f %s", t.data[1].temp, gU("temp", units)))
	 tinsert(rdata, format("date=%s", os.date("%d.%m.%Y %H:%M:%S", t.data[1].dt)))
      end
   end
   printf("%s", table.concat(rdata, "|"))
   return retval[state]
end

return main(table.unpack(arg))
