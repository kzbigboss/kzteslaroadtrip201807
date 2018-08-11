library(tidyverse)
library(zoo)
library(revgeo)

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

## check and see if each row can be identifed by the start time
## wasn't successful trying to use standard deviation / quartiles to
## automatically determine trip end points.  decided to do it manually.

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

## tons of features in the tesla data, removing some
tesla_worked <- tesla_raw %>%
  select(Date, latitude, longitude, battery_level, outside_tempF, inside_tempF, charging_state
         ,fast_charger_type, state, shift_state, speed, battery_range, charge_rate, elevation, heading
         ,odometer, ideal_battery_range, power)
  #select(-vehicle_id, -display_name, -color, -backseat_token, -vin, -backseat_token_updated_at, -id, -id_s, -vehicle_name, -odometerF)

## cross join the time start/end times against the tesla dataset
## and filter out data points that aren't part of transit times
## during the road trip.

tesla_cross <- tesla_worked %>%
  crossing(timelog_ranges) %>% ## cross join to timelog ranges, not ideal but quick at this size
  filter(Date >= trip_start & Date <= trip_end) %>% ## filter out records that aren't between timelog ranges
  select(-trip_start, -trip_end) %>%
  mutate(odometer = na.locf(odometer)) %>% ##some readings missing, sliding results forward
  mutate(odo_trip_delta = na.fill(if_else(trip_day == lag(trip_day), odometer - lag(odometer,1) , 0),0) ) %>% ## calc change in odometer for trip days
  mutate(odo_overall_delta = na.fill(odometer - lag(odometer,1),0) ) ## calc change in overall odometer

write_csv(tesla_worked, '/Users/kazzazmk/WorkDocs/Repo/kzteslaroadtrip201807/data/201807 tesla tracking.csv')

tesla_worked %>% mutate(date_part = as.Date(Date)) %>% filter(date_part > as.Date("2018-07-13")) %>% group_by(date_part) %>% summarize(n())

#tesla_part <- tesla_worked %>% sample(100) %>% rowwise() %>% mutate(revgeoresult = revgeo(longitude = longitude, latitude = latitude))

tesla_geo_charging <- tesla_raw %>% filter(fast_charger_type == 'Tesla') %>% select() %>% group_by(latitude, longitude) %>% summarize(count = n(), start_time = min(Date), end_time = max(Date)) %>% filter(count > 1) %>% ungroup(.) %>% mutate(duration = end_time - start_time)

tesla_geo_charging <- tesla_raw %>% 
  filter(fast_charger_type == 'Tesla') %>% 
  select(latitude, longitude, Date, charge_current_request, charge_miles_added_rated, charge_rate, charger_voltage, charge_energy_added) %>%
  filter(charge_rate > 0) %>%
  group_by(latitude, longitude) %>%
  summarize(count = n()
            ,start_time = min(Date)
            ,end_time = max(Date)
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

write_csv(tesla_geo_charging, '/Users/kazzazmk/WorkDocs/Repo/kzteslaroadtrip201807/data/201807 tesla geo reverse results.csv')
