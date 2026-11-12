// Independent exact-boundary expectations for the extracted assessment functions.
func wtTest(condition: Bool, label: String): Unit {
    if (!condition) { throw Exception("working-time test failed: ${label}") }
}
func wtTestPeriod(rule: Int64, finish: Int64, calendar: Int64, scheme: Int64): WTPeriods {
    return wtConsPeriod(rule, 0, finish, calendar, 0, 0, 1, scheme, false, wtEmptyPeriods())
}
func wtTestMetadata(periods: WTPeriods, normal: ShiftList, rest: ShiftList, night: ShiftList): WTMetadata {
    return WTMetadata(1, true, true, 0, 1000000, false, true, emptyPieces(), normal, rest, night, periods)
}
main(): Int64 {
    let nil = emptyPieces()
    let weekly = wtTestPeriod(101, 10080, 10080, 0)
    let blank = wtTestMetadata(weekly, nil, nil, nil)
    wtTest(wtWeekly(blank, consPiece(0, 2880, nil), weekly).code == 0, "48-hour boundary")
    wtTest(wtWeekly(blank, consPiece(0, 2881, nil), weekly).code == 101, "weekly one minute over")
    let daily = wtTestPeriod(102, 1440, 1440, 0)
    wtTest(wtDaily(consPiece(0, 780, nil), daily).code == 0, "11-hour boundary")
    wtTest(wtDaily(consPiece(0, 781, nil), daily).code == 102, "daily one minute short")
    let split = consPiece(0, 300, consPiece(300, 780, nil))
    wtTest(wtDaily(split, daily).code == 0, "adjacent midnight pieces do not alter rest")
    let weeklyRest = wtTestPeriod(103, 10080, 10080, 1)
    wtTest(wtWeeklyRest(consPiece(2100, 10080, nil), weeklyRest).code == 0, "weekly plus daily rest")
    wtTest(wtWeeklyRest(consPiece(2099, 10080, nil), weeklyRest).code == 103, "weekly rest one minute short")
    let fortnight = wtTestPeriod(103, 20160, 20160, 2)
    wtTest(wtWeeklyRest(consPiece(3540, 20160, nil), fortnight).code == 0, "fortnight continuous alternative")
    let normal = consPiece(0, 2880, nil)
    let rest = consPiece(8640, 10080, nil)
    let nightMeta = wtTestMetadata(weekly, normal, rest, nil)
    let nightPeriod = wtTestPeriod(105, 10080, 10080, 0)
    wtTest(wtAverageNight(nightMeta, nightPeriod).code == 0, "night average exact eight")
    let nightOver = wtTestMetadata(weekly, consPiece(0, 2881, nil), rest, nil)
    wtTest(wtAverageNight(nightOver, nightPeriod).code == 105, "night average one minute over")
    let hazardous = wtTestPeriod(106, 1440, 1440, 0)
    let hazardMeta = wtTestMetadata(hazardous, nil, nil, consPiece(0, 60, nil))
    wtTest(wtHazardNight(hazardMeta, consPiece(0, 480, nil), hazardous).code == 0, "hazard eight-hour boundary")
    wtTest(wtHazardNight(hazardMeta, consPiece(0, 481, nil), hazardous).code == 106, "hazard one minute over")
    let report = validateWorkingTime(emptyState(), 0, 10080, blank)
    wtTest(report.code == 21 && !report.breaksAssessed, "incomplete period coverage; breaks excluded")
    println("PASS 13 working-time boundary checks")
    return 0
}
