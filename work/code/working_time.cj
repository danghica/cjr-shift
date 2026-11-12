public struct WTPeriods {
public let empty: Bool
public let rule: Int64
public let start: Int64
public let finish: Int64
public let calendarMinutes: Int64
public let extraStart: Int64
public let extraEnd: Int64
public let evidence: Int64
public let restScheme: Int64
public let dailyRestOverlap: Bool
public let rest: (Unit) -> WTPeriods
public init(empty: Bool, rule: Int64, start: Int64, finish: Int64, calendarMinutes: Int64, extraStart: Int64, extraEnd: Int64, evidence: Int64, restScheme: Int64, dailyRestOverlap: Bool, rest: (Unit) -> WTPeriods) {
this.empty = empty
this.rule = rule
this.start = start
this.finish = finish
this.calendarMinutes = calendarMinutes
this.extraStart = extraStart
this.extraEnd = extraEnd
this.evidence = evidence
this.restScheme = restScheme
this.dailyRestOverlap = dailyRestOverlap
this.rest = rest
}
}
public struct WTMetadata {
public let jurisdiction: Int64
public let adult: Bool
public let ordinaryRegime: Bool
public let coverageStart: Int64
public let coverageEnd: Int64
public let periodCoverageComplete: Bool
public let elapsedWorkKnown: Bool
public let otherWork: ShiftList
public let normalWork: ShiftList
public let weeklyRest: ShiftList
public let nightWork: ShiftList
public let periods: WTPeriods
public init(jurisdiction: Int64, adult: Bool, ordinaryRegime: Bool, coverageStart: Int64, coverageEnd: Int64, periodCoverageComplete: Bool, elapsedWorkKnown: Bool, otherWork: ShiftList, normalWork: ShiftList, weeklyRest: ShiftList, nightWork: ShiftList, periods: WTPeriods) {
this.jurisdiction = jurisdiction
this.adult = adult
this.ordinaryRegime = ordinaryRegime
this.coverageStart = coverageStart
this.coverageEnd = coverageEnd
this.periodCoverageComplete = periodCoverageComplete
this.elapsedWorkKnown = elapsedWorkKnown
this.otherWork = otherWork
this.normalWork = normalWork
this.weeklyRest = weeklyRest
this.nightWork = nightWork
this.periods = periods
}
}
public struct WTFinding {
public let code: Int64
public let rule: Int64
public let start: Int64
public let finish: Int64
public let measured: Int64
public let limit: Int64
public init(code: Int64, rule: Int64, start: Int64, finish: Int64, measured: Int64, limit: Int64) {
this.code = code
this.rule = rule
this.start = start
this.finish = finish
this.measured = measured
this.limit = limit
}
}
public struct WTFindings {
public let empty: Bool
public let entry: WTFinding
public let rest: (Unit) -> WTFindings
public init(empty: Bool, entry: WTFinding, rest: (Unit) -> WTFindings) {
this.empty = empty
this.entry = entry
this.rest = rest
}
}
public struct WTReport {
public let code: Int64
public let findings: WTFindings
public let breaksAssessed: Bool
public init(code: Int64, findings: WTFindings, breaksAssessed: Bool) {
this.code = code
this.findings = findings
this.breaksAssessed = breaksAssessed
}
}
public func wtMax(left: Int64, right: Int64): Int64 {
return if ((left  <=  right)) { right } else { left }
}
public func wtMin(left: Int64, right: Int64): Int64 {
return if ((left  <=  right)) { left } else { right }
}
public func wtClip(start: Int64, finish: Int64, pieceStart: Int64, pieceEnd: Int64): Int64 {
return wtMax(0, (wtMin(finish, pieceEnd)  -  wtMax(start, pieceStart)))
}
public func wtMinutes(pieces: ShiftList, start: Int64, finish: Int64): Int64 {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { 0 } else { (wtClip(start, finish, (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish)  +  wtMinutes(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), start, finish)) }
}
public func wtOrdered(pieces: ShiftList, previous: Int64): Bool {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { true } else { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((previous  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start), if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)) { false } else { true }), wtOrdered(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish)) }
}
public func wtMerge(left: ShiftList, right: ShiftList): ShiftList {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(left)).empty) { right } else { if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(right)).empty) { left } else { if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(left)).start  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(right)).start)) { consPiece((({ cjrTypedValue: ShiftList => cjrTypedValue })(left)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(left)).finish, wtMerge(((({ cjrTypedValue: ShiftList => cjrTypedValue })(left)).rest)(()), right)) } else { consPiece((({ cjrTypedValue: ShiftList => cjrTypedValue })(right)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(right)).finish, wtMerge(left, ((({ cjrTypedValue: ShiftList => cjrTypedValue })(right)).rest)(()))) } } }
}
public func wtLongestRest(pieces: ShiftList, cursor: Int64, finish: Int64): Int64 {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { wtMax(0, (finish  -  cursor)) } else { if ((finish  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)) { wtMax(0, (finish  -  cursor)) } else { wtMax(wtMax(0, ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start  -  cursor)), wtLongestRest(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), wtMax(cursor, (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish), finish)) } }
}
public func wtRestCount(pieces: ShiftList, cursor: Int64, finish: Int64, required: Int64): Int64 {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { if ((required  <=  (finish  -  cursor))) { 1 } else { 0 } } else { if ((finish  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)) { if ((required  <=  (finish  -  cursor))) { 1 } else { 0 } } else { (if ((required  <=  ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start  -  cursor))) { 1 } else { 0 }  +  wtRestCount(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), wtMax(cursor, (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish), finish, required)) } }
}
public func wtInside(small: ShiftList, large: ShiftList): Bool {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(small)).empty) { true } else { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((wtMinutes(large, (({ cjrTypedValue: ShiftList => cjrTypedValue })(small)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(small)).finish)  ==  ((({ cjrTypedValue: ShiftList => cjrTypedValue })(small)).finish  -  (({ cjrTypedValue: ShiftList => cjrTypedValue })(small)).start)), wtInside(((({ cjrTypedValue: ShiftList => cjrTypedValue })(small)).rest)(()), large)) }
}
public func wtRestValid(rests: ShiftList, work: ShiftList): Bool {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(rests)).empty) { true } else { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((wtMinutes(work, (({ cjrTypedValue: ShiftList => cjrTypedValue })(rests)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(rests)).finish)  ==  0), wtRestValid(((({ cjrTypedValue: ShiftList => cjrTypedValue })(rests)).rest)(()), work)) }
}
public func wtEmptyPeriods(): WTPeriods {
return WTPeriods(true, 0, 0, 0, 0, 0, 0, 0, 0, false, { unused: Unit => ({ cjrTypedValue: WTPeriods => cjrTypedValue })(wtEmptyPeriods()) })
}
public func wtConsPeriod(rule: Int64, start: Int64, finish: Int64, calendar: Int64, extraStart: Int64, extraEnd: Int64, evidence: Int64, restScheme: Int64, dailyRestOverlap: Bool, rest: WTPeriods): WTPeriods {
return WTPeriods(false, rule, start, finish, calendar, extraStart, extraEnd, evidence, restScheme, dailyRestOverlap, { unused: Unit => ({ cjrTypedValue: WTPeriods => cjrTypedValue })(rest) })
}
public func wtEmptyFindings(): WTFindings {
return WTFindings(true, WTFinding(0, 0, 0, 0, 0, 0), { unused: Unit => ({ cjrTypedValue: WTFindings => cjrTypedValue })(wtEmptyFindings()) })
}
public func wtConsFinding(entry: WTFinding, rest: WTFindings): WTFindings {
return WTFindings(false, entry, { unused: Unit => ({ cjrTypedValue: WTFindings => cjrTypedValue })(rest) })
}
public func wtFinding(period: WTPeriods, code: Int64, value: Int64, bound: Int64): WTFinding {
return WTFinding(code, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish, value, bound)
}
public func wtPeriodKnown(tracker: TrackerState, metadata: WTMetadata, period: WTPeriods): Bool {
return ({ => 
let last = if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  101)) { wtMax((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraEnd) } else { (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish }
({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).elapsedWorkKnown, ((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).coverageStart  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start)), (last  <=  (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).coverageEnd)), if (((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending  ==  -1)) { true } else { (last  <=  (({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending) })
})()
}
public func wtGoodPeriod(period: WTPeriods): Bool {
return ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(if (if (if (if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  101)) { true } else { ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  102) }) { true } else { ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  103) }) { true } else { ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  105) }) { true } else { ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  106) }, (0  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start)), if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start)) { false } else { true }), (0  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).calendarMinutes)), (0  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraStart)), ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraStart  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraEnd)), (0  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).evidence)), ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).evidence  <=  3)), if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  102)) { (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish  -  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start)  ==  1440) } else { true }), if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  106)) { (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish  -  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start)  ==  1440) } else { true }), if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  103)) { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((1  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).restScheme), ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).restScheme  <=  3)), if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).restScheme  ==  1)) { ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).calendarMinutes  ==  10080) } else { ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).calendarMinutes  ==  20160) }) } else { true }), if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  101)) { if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraStart  ==  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraEnd)) { true } else { ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraStart) } } else { true })
}
public func wtGoodPeriods(periods: WTPeriods, lower: Int64, upper: Int64): Bool {
return if ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).empty) { true } else { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(wtGoodPeriod(periods), if ((upper  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).start)) { false } else { true }), if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).finish  <=  lower)) { false } else { true }), wtGoodPeriods(((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).rest)(()), lower, upper)) }
}
public func wtWeekly(metadata: WTMetadata, work: ShiftList, period: WTPeriods): WTFinding {
return if (if (({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).calendarMinutes  <=  0)) { false } else { true }, if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraStart  ==  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraEnd)) { true } else { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).coverageStart  <=  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraStart), ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraEnd  <=  (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).coverageEnd)) })) { false } else { true }) { wtFinding(period, 21, 0, 0) } else { ({ => 
let a = (wtMinutes(work, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish)  +  wtMinutes(work, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraStart, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).extraEnd))
wtFinding(period, if (((a  *  10080)  <=  (2880  *  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).calendarMinutes))) { 0 } else { 101 }, (a  *  10080), (2880  *  (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).calendarMinutes))
})() }
}
public func wtDaily(work: ShiftList, period: WTPeriods): WTFinding {
return ({ => 
let a = wtLongestRest(work, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish)
wtFinding(period, if ((660  <=  a)) { 0 } else { 102 }, a, 660)
})()
}
public func wtWeeklyRest(work: ShiftList, period: WTPeriods): WTFinding {
return ({ => 
let extra = if ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).dailyRestOverlap) { 0 } else { 660 }
({ => 
let required = (if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).restScheme  ==  3)) { 2880 } else { 1440 }  +  extra)
({ => 
let count = wtRestCount(work, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish, required)
({ => 
let a = if (({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).restScheme  ==  2), ((2880  +  extra)  <=  wtLongestRest(work, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish)))) { wtMax(2, count) } else { count }
({ => 
let needed = if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).restScheme  ==  2)) { 2 } else { 1 }
wtFinding(period, if ((needed  <=  a)) { 0 } else { 103 }, a, needed)
})()
})()
})()
})()
})()
}
public func wtAverageNight(metadata: WTMetadata, period: WTPeriods): WTFinding {
return ({ => 
let denominator = ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).calendarMinutes  -  wtMinutes((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).weeklyRest, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish))
if ((denominator  <=  0)) { wtFinding(period, 20, denominator, 0) } else { ({ => 
let a = wtMinutes((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).normalWork, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish)
wtFinding(period, if (((a  *  1440)  <=  (480  *  denominator))) { 0 } else { 105 }, (a  *  1440), (480  *  denominator))
})() }
})()
}
public func wtHazardNight(metadata: WTMetadata, work: ShiftList, period: WTPeriods): WTFinding {
return if ((wtMinutes((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).nightWork, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish)  ==  0)) { wtFinding(period, 0, 0, 480) } else { ({ => 
let a = wtMinutes(work, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).start, (({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).finish)
wtFinding(period, if ((a  <=  480)) { 0 } else { 106 }, a, 480)
})() }
}
public func wtAssess(tracker: TrackerState, metadata: WTMetadata, work: ShiftList, period: WTPeriods): WTFinding {
return if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).evidence  ==  2)) { wtFinding(period, 0, 0, 0) } else { if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).evidence  ==  3)) { wtFinding(period, 22, 0, 0) } else { if (if (({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).evidence  ==  1), wtPeriodKnown(tracker, metadata, period))) { false } else { true }) { wtFinding(period, 21, 0, 0) } else { if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  101)) { wtWeekly(metadata, work, period) } else { if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  102)) { wtDaily(work, period) } else { if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  103)) { wtWeeklyRest(work, period) } else { if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(period)).rule  ==  105)) { wtAverageNight(metadata, period) } else { wtHazardNight(metadata, work, period) } } } } } } }
}
public func wtAssessAll(tracker: TrackerState, metadata: WTMetadata, work: ShiftList, periods: WTPeriods): WTFindings {
return if ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).empty) { wtEmptyFindings() } else { wtConsFinding(wtAssess(tracker, metadata, work, periods), wtAssessAll(tracker, metadata, work, ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).rest)(()))) }
}
public func wtHasCode(findings: WTFindings, code: Int64): Bool {
return if ((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).empty) { false } else { if (((({ cjrTypedValue: WTFinding => cjrTypedValue })((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).entry)).code  ==  code)) { true } else { wtHasCode(((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).rest)(()), code) } }
}
public func wtFirstViolation(findings: WTFindings): Int64 {
return if ((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).empty) { 0 } else { ({ => 
let rest = wtFirstViolation(((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).rest)(()))
if ((100  <=  (({ cjrTypedValue: WTFinding => cjrTypedValue })((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).entry)).code)) { if ((rest  ==  0)) { (({ cjrTypedValue: WTFinding => cjrTypedValue })((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).entry)).code } else { wtMin((({ cjrTypedValue: WTFinding => cjrTypedValue })((({ cjrTypedValue: WTFindings => cjrTypedValue })(findings)).entry)).code, rest) } } else { rest }
})() }
}
public func wtSummary(findings: WTFindings, complete: Bool): Int64 {
return ({ => 
let violation = wtFirstViolation(findings)
if (if ((violation  ==  0)) { false } else { true }) { violation } else { if (wtHasCode(findings, 20)) { 20 } else { if (wtHasCode(findings, 22)) { 22 } else { if (if (if (complete) { false } else { true }) { true } else { wtHasCode(findings, 21) }) { 21 } else { 0 } } } }
})()
}
public func wtValidMetadata(tracker: TrackerState, metadata: WTMetadata, lower: Int64, upper: Int64): Bool {
return ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((0  <=  lower), if ((upper  <=  lower)) { false } else { true }), (0  <=  (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).coverageStart)), ((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).coverageStart  <=  (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).coverageEnd)), wtOrdered((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, 0)), wtOrdered((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).otherWork, 0)), wtOrdered(wtMerge((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).otherWork), 0)), wtOrdered((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).normalWork, 0)), wtOrdered((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).weeklyRest, 0)), wtOrdered((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).nightWork, 0)), wtInside((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).normalWork, wtMerge((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).otherWork))), wtInside((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).nightWork, wtMerge((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).otherWork))), wtRestValid((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).weeklyRest, wtMerge((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).otherWork))), wtGoodPeriods((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).periods, lower, upper))
}
public func wtSupported(metadata: WTMetadata): Bool {
return ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(if (((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).jurisdiction  ==  1)) { true } else { ((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).jurisdiction  ==  2) }, (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).adult), (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).ordinaryRegime)
}
public func wtHasRule(periods: WTPeriods, rule: Int64): Bool {
return if ((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).empty) { false } else { if (((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).rule  ==  rule)) { true } else { wtHasRule(((({ cjrTypedValue: WTPeriods => cjrTypedValue })(periods)).rest)(()), rule) } }
}
public func wtCompletePeriods(periods: WTPeriods): Bool {
return ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(wtHasRule(periods, 101), wtHasRule(periods, 102)), wtHasRule(periods, 103)), wtHasRule(periods, 105)), wtHasRule(periods, 106))
}
public func validateWorkingTime(tracker: TrackerState, assessmentStart: Int64, assessmentEnd: Int64, metadata: WTMetadata): WTReport {
return if (if (wtValidMetadata(tracker, metadata, assessmentStart, assessmentEnd)) { false } else { true }) { WTReport(20, wtEmptyFindings(), false) } else { if (if (wtSupported(metadata)) { false } else { true }) { WTReport(22, wtEmptyFindings(), false) } else { ({ => 
let findings = wtAssessAll(tracker, metadata, wtMerge((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).otherWork), (({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).periods)
WTReport(wtSummary(findings, ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).periodCoverageComplete, wtCompletePeriods((({ cjrTypedValue: WTMetadata => cjrTypedValue })(metadata)).periods))), findings, false)
})() } }
}

