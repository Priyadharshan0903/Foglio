import Foundation
@testable import FoglioCore

func datePickerTests() {
    Check.suite("Themed date picker — calendar boundaries") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        let dates = DatePickerCalendar(calendar: calendar)
        func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let march = dates.days(in: date(2026, 3, 15))
        Check.equal(march.count, 42, "six complete weeks keep popover size stable")
        Check.equal(march.first!, date(2026, 3, 1), "Sunday-first month has no unnecessary leading week")
        Check.equal(march.last!, date(2026, 4, 11), "adjacent-month dates complete the grid")
        Check.equal(Set(march).count, 42, "DST transition cannot duplicate a calendar day")
        Check.expect(march.allSatisfy { calendar.component(.hour, from: $0) == 0 }, "grid dates remain at local midnight across DST")
        Check.equal(dates.addingDays(1, to: date(2026, 3, 8, hour: 12)), date(2026, 3, 9), "tomorrow uses calendar days at spring DST")
        Check.equal(dates.addingDays(7, to: date(2026, 10, 30)), date(2026, 11, 6), "next week survives autumn DST")
        Check.equal(dates.movingMonth(date(2026, 12, 31), by: 1), date(2027, 1, 1), "next month crosses year and avoids month-end overflow")
        Check.equal(dates.movingMonth(date(2027, 1, 31), by: -1), date(2026, 12, 1), "previous month crosses year")
        let leapDays = dates.days(in: date(2028, 2, 1)).filter { calendar.component(.month, from: $0) == 2 }
        Check.equal(leapDays.count, 29, "leap February offers every valid day")
        Check.equal(dates.days(in: date(2027, 2, 1)).filter { calendar.component(.month, from: $0) == 2 }.count, 28, "ordinary February has 28 days")
        Check.equal(dates.weekdays.first!, "S", "weekday headers use calendar's first weekday")
        var monday = calendar; monday.firstWeekday = 2
        let mondayDates = DatePickerCalendar(calendar: monday)
        Check.equal(mondayDates.days(in: date(2026, 3, 1)).first!, date(2026, 2, 23), "Monday-first grid aligns the preceding days")
        Check.equal(mondayDates.weekdays.first!, "M", "weekday labels rotate with calendar settings")
        Check.equal(dates.string(date(2026, 12, 31), template: "yMMMd"), "Dec 31, 2026", "field includes year and local date")
        var indian = calendar; indian.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let indianDates = DatePickerCalendar(calendar: indian)
        let local = indian.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        Check.equal(indianDates.days(in: local).filter { indian.isDate($0, inSameDayAs: local) }.count, 1, "non-integral UTC offsets keep the selected local day")
        var islamic = Calendar(identifier: .islamicCivil); islamic.timeZone = calendar.timeZone
        let other = DatePickerCalendar(calendar: islamic)
        let grid = other.days(in: date(2026, 10, 11))
        Check.equal(grid.count, 42, "calendar grid also supports non-Gregorian calendar preferences")
        Check.equal(islamic.component(.weekday, from: grid.first!), islamic.firstWeekday, "non-Gregorian weeks retain their start day")
    }
}
