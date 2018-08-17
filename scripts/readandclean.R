library(tidyverse)
library(zoo)
library(revgeo)
library(knitr)

## original data files
time_raw <- read_csv('/Users/kazzazmk/WorkDocs/Repo/kzteslaroadtrip201807/data/201807 time tracking.csv')
tesla_raw <- read_csv('/Users/kazzazmk/Downloads/TeslaFi72018.csv')
attr(tesla_raw$Date, "tzone") <- "America/Los_Angeles"  #read_csv is defaulting to UTC, need to update to Pacific time for deltas

## prep time data
timelog <- time_raw %>%
  ### convert string to datetime
  mutate(
         `Start time` = as.POSIXct(time_raw$`Start time`, "%b %d, %Y at %I:%M:%S %p", tz = "America/Los_Angeles")
         ,`End time` = as.POSIXct(time_raw$`End time`, "%b %d, %Y at %I:%M:%S %p", tz = "America/Los_Angeles")
         ) %>%
  ### rename to friendly names
  rename(start_time = `Start time`
         ,end_time = `End time`
         ,task = `Task name`
         ,description = `Task description`
         ,duration_time = Duration
         ,duration_hours = `Duration in hours`
         ,note = Note
         ,category = Category
        ) %>%
  select(-description) %>%
  filter(tolower(task) != 'sleep')

## wasn't successful trying to use standard deviation / quartiles to
## automatically determine trip end points.  decided to do it manually:
timelog <- timelog %>%
  mutate(trip_day = case_when(
     end_time <= as.POSIXct("2018-07-15 00:59:04", tz = "America/Los_Angeles") ~ 1
    ,end_time <= as.POSIXct("2018-07-15 17:47:37", tz = "America/Los_Angeles") ~ 2
    ,end_time <= as.POSIXct("2018-07-17 21:05:32", tz = "America/Los_Angeles") ~ 3
    ,end_time <= as.POSIXct("2018-07-19 20:43:23", tz = "America/Los_Angeles") ~ 4
    ,end_time <= as.POSIXct("2018-07-23 17:46:52", tz = "America/Los_Angeles") ~ 5
    ,end_time <= as.POSIXct("2018-07-24 15:27:48", tz = "America/Los_Angeles") ~ 6
    ,TRUE ~ 0
    )
  )

## figure out each trip day's start/end times
timelog_ranges <- timelog %>%
  group_by(trip_day) %>%
  summarize(trip_start = min(start_time)
            ,trip_end = max(end_time)
            )

## tons of features in the tesla data, focusing on only what I need
tesla_worked <- tesla_raw %>%
  select(Date, latitude, longitude, battery_level, outside_tempF, inside_tempF, charging_state
         ,fast_charger_type, state, shift_state, speed, battery_range, charge_rate, elevation, heading
         ,odometer, ideal_battery_range, power) %>%
  ## nulls exist in a few measure, using LOCF to roll forward previous observations
  mutate(elevation = na.locf(elevation, na.rm = FALSE)
         ,battery_level = na.locf(battery_level, na.rm = FALSE)
         )

write_csv(tesla_worked, '/Users/kazzazmk/WorkDocs/Repo/kzteslaroadtrip201807/data/201807 tesla tracking.csv')

## want to create a dataset dedicated to supercharging.
## able to rely on the 'fast_charger_type' attribute.
tesla_geo_charging <- tesla_raw %>% filter(fast_charger_type == 'Tesla') %>% select() %>% group_by(latitude, longitude) %>% summarize(count = n(), start_time = min(Date), end_time = max(Date)) %>% filter(count > 1) %>% ungroup(.) %>% mutate(duration = end_time - start_time)

tesla_geo_charging <- tesla_raw %>% 
  filter(fast_charger_type == 'Tesla') %>% 
  select(latitude, longitude, Date, charge_current_request, charge_miles_added_rated, charge_rate, charger_voltage, charge_energy_added, battery_level) %>%
  filter(charge_rate > 0) %>%
  group_by(latitude, longitude) %>%
  summarize(record_count = n()
            ,start_time = min(Date)
            ,end_time = max(Date)
            ,start_battery = min(battery_level)
            ,end_battery = max(battery_level)
            ,avg_amp = mean(charge_current_request)
            ,miles_added = max(charge_miles_added_rated)
            ,avg_charging_mph = mean(charge_rate)
            ,avg_voltage = mean(charger_voltage)
            ,energy_added = max(charge_energy_added)
            ) %>%
  mutate(duration = end_time - start_time
         ,revgeoresult = revgeo(longitude = longitude, latitude = latitude)
         ) %>%
  separate(revgeoresult, sep = ',', into = c("street","city","state","zip","country")) %>%
  arrange(start_time)

tesla_geo_charging <- tesla_geo_charging %>% ungroup(.) %>% mutate(rownum = row_number()) %>% filter(rownum != 1) %>% mutate(duration = duration / 60) %>% mutate(rownum = row_number())
tesla_geo_reddit <- tesla_geo_charging %>% mutate(duration_hrs = round(duration, 2)) %>% rename(chargeno = rownum) %>% select(chargeno, city, state, duration_hrs, start_battery, end_battery, avg_amp, avg_charging_mph, avg_voltage, energy_added, miles_added)

write_csv(tesla_geo_charging, '/Users/kazzazmk/WorkDocs/Repo/kzteslaroadtrip201807/data/201807 tesla geo reverse results.csv')

write_csv(tesla_geo_reddit, '/Users/kazzazmk/WorkDocs/Repo/kzteslaroadtrip201807/data/201807 tesla geo reverse results with battery.csv')
