// SPDX-License-Identifier: MIT
// Based on: https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary

/// @title date
/// @dev Tested date range 1970/01/01 to 2345/12/31
/// Conventions:
/// Unit      | Range         | Notes
/// :-------- |:-------------:|:-----
/// timestamp | >= 0          | Unix timestamp, number of seconds since 1970/01/01 00:00:00 UTC
/// year      | 1970 ... 2345 |
/// month     | 1 ... 12      |
/// day       | 1 ... 31      |
/// hour      | 0 ... 23      |
/// minute    | 0 ... 59      |
/// second    | 0 ... 59      |
/// dayOfWeek | 1 ... 7       | 1 = Monday, ..., 7 = Sunday
module movemate::date {
    use std::error;

    const SECONDS_PER_DAY: u64 = 24 * 60 * 60;
    const SECONDS_PER_HOUR: u64 = 60 * 60;
    const SECONDS_PER_MINUTE: u64 = 60;
    const OFFSET19700101: u64 = 2440588;

    const DOW_MON: u64 = 1;
    const DOW_TUE: u64 = 2;
    const DOW_WED: u64 = 3;
    const DOW_THU: u64 = 4;
    const DOW_FRI: u64 = 5;
    const DOW_SAT: u64 = 6;
    const DOW_SUN: u64 = 7;

    const EYEAR_BEFORE_1970: u64 = 0;
    const EADDITION_ASSERTION_FAILED: u64 = 1;
    const ESUBTRACTION_ASSERTION_FAILED: u64 = 2;
    const EFROM_TIMESTAMP_LATER_THAN_TO_TIMESTAMP: u64 = 3;

    // ------------------------------------------------------------------------
    // Calculate the number of days from 1970/01/01 to year/month/day using
    // the date conversion algorithm from
    //   https://aa.usno.navy.mil/faq/JD_formula.html
    // and subtracting the offset 2440588 so that 1970/01/01 is day 0
    //
    // days = day
    //      - 32075
    //      + 1461 * (year + 4800 + (month - 14) / 12) / 4
    //      + 367 * (month - 2 - (month - 14) / 12 * 12) / 12
    //      - 3 * ((year + 4900 + (month - 14) / 12) / 100) / 4
    //      - offset
    // ------------------------------------------------------------------------
    public fun days_from_date(_year: u64, _month: u64, _day: u64): u64 {
        assert!(_year >= 1970, error::invalid_argument(EYEAR_BEFORE_1970));
        let monthMinus14DividedBy12TimesNegative1 = if (_month < 3) 1 else 0;
        let __days = _day
            + 1461 * (_year + 4800 - monthMinus14DividedBy12TimesNegative1) / 4;
        let mm14db12tn1Times12PlusMonth = monthMinus14DividedBy12TimesNegative1 * 12 + _month;
        __days = if (mm14db12tn1Times12PlusMonth >= 2) __days + 367 * (mm14db12tn1Times12PlusMonth - 2) / 12 else __days - 367 * (2 - mm14db12tn1Times12PlusMonth) / 12;
        __days = __days - 3 * ((_year + 4900 - monthMinus14DividedBy12TimesNegative1) / 100) / 4
            - 32075
            - OFFSET19700101;
        __days
    }

    // ------------------------------------------------------------------------
    // Calculate year/month/day from the number of days since 1970/01/01 using
    // the date conversion algorithm from
    //   http://aa.usno.navy.mil/faq/docs/JD_Formula.php
    // and adding the offset 2440588 so that 1970/01/01 is day 0
    //
    // int L = days + 68569 + offset
    // int N = 4 * L / 146097
    // L = L - (146097 * N + 3) / 4
    // year = 4000 * (L + 1) / 1461001
    // L = L - 1461 * year / 4 + 31
    // month = 80 * L / 2447
    // dd = L - 2447 * month / 80
    // L = month / 11
    // month = month + 2 - 12 * L
    // year = 100 * (N - 49) + year + L
    // ------------------------------------------------------------------------
    public fun days_to_date(days: u64): (u64, u64, u64) {
        let l = days + 68569 + OFFSET19700101;
        let n = 4 * l / 146097;
        l = l - (146097 * n + 3) / 4;
        let _year = 4000 * (l + 1) / 1461001;
        l = l - 1461 * _year / 4 + 31;
        let _month = 80 * l / 2447;
        let _day = l - 2447 * _month / 80;
        l = _month / 11;
        _month = _month + 2 - 12 * l;
        _year = 100 * (n - 49) + _year + l;

        (_year, _month, _day)
    }

    public fun timestamp_from_date(year: u64, month: u64, day: u64): u64 {
        days_from_date(year, month, day) * SECONDS_PER_DAY
    }

    public fun timestamp_from_date_time(year: u64, month: u64, day: u64, hour: u64, minute: u64, second: u64): u64 {
        days_from_date(year, month, day) * SECONDS_PER_DAY + hour * SECONDS_PER_HOUR + minute * SECONDS_PER_MINUTE + second
    }

    public fun timestamp_to_date(timestamp: u64): (u64, u64, u64) {
        days_to_date(timestamp / SECONDS_PER_DAY)
    }

    public fun timestamp_to_date_time(timestamp: u64): (u64, u64, u64, u64, u64, u64) {
        let (year, month, day) = days_to_date(timestamp / SECONDS_PER_DAY);
        let secs = timestamp % SECONDS_PER_DAY;
        let hour = secs / SECONDS_PER_HOUR;
        secs = secs % SECONDS_PER_HOUR;
        let minute = secs / SECONDS_PER_MINUTE;
        let second = secs % SECONDS_PER_MINUTE;
        (year, month, day, hour, minute, second)
    }

    public fun is_valid_date(year: u64, month: u64, day: u64): bool {
        if (year >= 1970 && month > 0 && month <= 12) {
            let days_in_month = get_days_in_year_month(year, month);
            if (day > 0 && day <= days_in_month) return true;
        };
        false
    }

    public fun is_valid_date_time(year: u64, month: u64, day: u64, hour: u64, minute: u64, second: u64): bool {
        is_valid_date(year, month, day) && hour < 24 && minute < 60 && second < 60
    }

    public fun is_timestamp_leap_year(timestamp: u64): bool {
        let (year, _, _) = days_to_date(timestamp / SECONDS_PER_DAY);
        is_year_leap_year(year)
    }

    public fun is_year_leap_year(year: u64): bool {
        ((year % 4 == 0) && (year % 100 != 0)) || (year % 400 == 0)
    }

    public fun is_weekday(timestamp: u64): bool {
        get_day_of_week(timestamp) <= DOW_FRI
    }

    public fun is_weekend(timestamp: u64): bool {
        get_day_of_week(timestamp) >= DOW_SAT
    }

    public fun get_days_in_timestamp_month(timestamp: u64): u64 {
        let (year, month, _) = days_to_date(timestamp / SECONDS_PER_DAY);
        get_days_in_year_month(year, month)
    }

    public fun get_days_in_year_month(year: u64, month: u64): u64 {
        if (month == 1 || month == 3 || month == 5 || month == 7 || month == 8 || month == 10 || month == 12) return 31;
        if (month != 2) return 30;
        if (is_year_leap_year(year)) 29 else 28
    }

    // 1 = Monday, 7 = Sunday
    public fun get_day_of_week(timestamp: u64): u64 {
        let _days = timestamp / SECONDS_PER_DAY;
        (_days + 3) % 7 + 1
    }

    public fun get_year(timestamp: u64): u64 {
        let (year, _, _) = days_to_date(timestamp / SECONDS_PER_DAY);
        year
    }

    public fun get_month(timestamp: u64): u64 {
        let (_, month, _) = days_to_date(timestamp / SECONDS_PER_DAY);
        month
    }

    public fun get_day(timestamp: u64): u64 {
        let (_, _, day) = days_to_date(timestamp / SECONDS_PER_DAY);
        day
    }

    public fun get_hour(timestamp: u64): u64 {
        let secs = timestamp % SECONDS_PER_DAY;
        secs / SECONDS_PER_HOUR
    }

    public fun get_minute(timestamp: u64): u64 {
        let secs = timestamp % SECONDS_PER_HOUR;
        secs / SECONDS_PER_MINUTE
    }

    public fun get_second(timestamp: u64): u64 {
        timestamp % SECONDS_PER_MINUTE
    }

    public fun add_years(timestamp: u64, _years: u64): u64 {
        let (year, month, day) = days_to_date(timestamp / SECONDS_PER_DAY);
        year = year + _years;
        let days_in_month = get_days_in_year_month(year, month);
        if (day > days_in_month) day = days_in_month;
        let new_timestamp = days_from_date(year, month, day) * SECONDS_PER_DAY + timestamp % SECONDS_PER_DAY;
        assert!(new_timestamp >= timestamp, error::internal(EADDITION_ASSERTION_FAILED));
        new_timestamp
    }

    public fun add_months(timestamp: u64, _months: u64): u64 {
        let (year, month, day) = days_to_date(timestamp / SECONDS_PER_DAY);
        month = month + _months;
        year = year + (month - 1) / 12;
        month = (month - 1) % 12 + 1;
        let days_in_month = get_days_in_year_month(year, month);
        if (day > days_in_month) day = days_in_month;
        let new_timestamp = days_from_date(year, month, day) * SECONDS_PER_DAY + timestamp % SECONDS_PER_DAY;
        assert!(new_timestamp >= timestamp, error::internal(EADDITION_ASSERTION_FAILED));
        new_timestamp
    }

    public fun add_days(timestamp: u64, _days: u64): u64 {
        timestamp + _days * SECONDS_PER_DAY
    }

    public fun add_hours(timestamp: u64, _hours: u64): u64 {
        timestamp + _hours * SECONDS_PER_HOUR
    }

    public fun add_minutes(timestamp: u64, _minutes: u64): u64 {
        timestamp + _minutes * SECONDS_PER_MINUTE
    }

    public fun add_seconds(timestamp: u64, _seconds: u64): u64 {
        timestamp + _seconds
    }

    public fun sub_years(timestamp: u64, _years: u64): u64 {
        let (year, month, day) = days_to_date(timestamp / SECONDS_PER_DAY);
        year = year - _years;
        let days_in_month = get_days_in_year_month(year, month);
        if (day > days_in_month) day = days_in_month;
        let new_timestamp = days_from_date(year, month, day) * SECONDS_PER_DAY + timestamp % SECONDS_PER_DAY;
        assert!(new_timestamp <= timestamp, error::internal(ESUBTRACTION_ASSERTION_FAILED));
        new_timestamp
    }
    public fun sub_months(timestamp: u64, _months: u64): u64 {
        let (year, month, day) = days_to_date(timestamp / SECONDS_PER_DAY);
        let year_month = year * 12 + (month - 1) - _months;
        year = year_month / 12;
        month = year_month % 12 + 1;
        let days_in_month = get_days_in_year_month(year, month);
        if (day > days_in_month) day = days_in_month;
        let new_timestamp = days_from_date(year, month, day) * SECONDS_PER_DAY + timestamp % SECONDS_PER_DAY;
        assert!(new_timestamp <= timestamp, error::internal(ESUBTRACTION_ASSERTION_FAILED));
        new_timestamp
    }

    public fun sub_days(timestamp: u64, _days: u64): u64 {
        timestamp - _days * SECONDS_PER_DAY
    }

    public fun sub_hours(timestamp: u64, _hours: u64): u64 {
        timestamp - _hours * SECONDS_PER_HOUR
    }

    public fun sub_minutes(timestamp: u64, _minutes: u64): u64 {
        timestamp - _minutes * SECONDS_PER_MINUTE
    }

    public fun sub_seconds(timestamp: u64, _seconds: u64): u64 {
        timestamp - _seconds
    }

    public fun diff_years(from_timestamp: u64, to_timestamp: u64): u64 {
        assert!(from_timestamp <= to_timestamp, error::invalid_argument(EFROM_TIMESTAMP_LATER_THAN_TO_TIMESTAMP));
        let (from_year, _, _) = days_to_date(from_timestamp / SECONDS_PER_DAY);
        let (to_year, _, _) = days_to_date(to_timestamp / SECONDS_PER_DAY);
        to_year - from_year
    }

    public fun diff_months(from_timestamp: u64, to_timestamp: u64): u64 {
        assert!(from_timestamp <= to_timestamp, error::invalid_argument(EFROM_TIMESTAMP_LATER_THAN_TO_TIMESTAMP));
        let (from_year, from_month, _) = days_to_date(from_timestamp / SECONDS_PER_DAY);
        let (to_year, to_month, _) = days_to_date(to_timestamp / SECONDS_PER_DAY);
        to_year * 12 + to_month - from_year * 12 - from_month
    }

    public fun diff_days(from_timestamp: u64, to_timestamp: u64): u64 {
        assert!(from_timestamp <= to_timestamp, error::invalid_argument(EFROM_TIMESTAMP_LATER_THAN_TO_TIMESTAMP));
        (to_timestamp - from_timestamp) / SECONDS_PER_DAY
    }

    public fun diff_hours(from_timestamp: u64, to_timestamp: u64): u64 {
        assert!(from_timestamp <= to_timestamp, error::invalid_argument(EFROM_TIMESTAMP_LATER_THAN_TO_TIMESTAMP));
        (to_timestamp - from_timestamp) / SECONDS_PER_HOUR
    }

    public fun diff_minutes(from_timestamp: u64, to_timestamp: u64): u64 {
        assert!(from_timestamp <= to_timestamp, error::invalid_argument(EFROM_TIMESTAMP_LATER_THAN_TO_TIMESTAMP));
        (to_timestamp - from_timestamp) / SECONDS_PER_MINUTE
    }

    public fun diff_seconds(from_timestamp: u64, to_timestamp: u64): u64 {
        assert!(from_timestamp <= to_timestamp, error::invalid_argument(EFROM_TIMESTAMP_LATER_THAN_TO_TIMESTAMP));
        to_timestamp - from_timestamp
    }

    #[test]
    public entry fun test_days_from_date_examples() {
        assert!(days_from_date(2019, 12, 20) == 18250, 0);
    }

    #[test]
    public entry fun test_days_to_date_examples() {
        let (y, m, d) = days_to_date(18250);
        assert!(m == 12, 0);
        assert!(d == 20, 1);
        assert!(y == 2019, 2);
    }

    #[test]
    public entry fun test_days_to_date_date_to_days() {
        let i = 0;
        while (i <= 200 * 365) {
            let (y, m, d) = days_to_date(i);
            assert!(days_from_date(y, m, d) == i, 0);
            i = i + 99;
        }
    }
}
