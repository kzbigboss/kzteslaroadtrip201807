library(tidyverse)

## original data files
time_raw <- read_csv('/Users/kazzazmk/WorkDocs/Repo/kzteslaroadtrip201807/data/201807 time tracking.csv')

## prep time data
timelog <- time_raw %>%
  ### convert string to datetime
  mutate(
         `Start time` = as.POSIXct(time_raw$`Start time`, "%b %d, %Y at %I:%M:%S %p", tz = "America/Los_Angeles")
         ,`End time` = as.POSIXct(time_raw$`End time`, "%b %d, %Y at %I:%M:%S %p", tz = "America/Los_Angeles")
         , row_num = row_number()
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
        )

## check and see if each row can be identifed by the start time
#nrow(timelog)== timelog %>% summarize(n())

timelog <- timelog %>%
  mutate(prior_end = lag(end_time, 1)
         ,delta_prior_end = prior_end - start_time
         )