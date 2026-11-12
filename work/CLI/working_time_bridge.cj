// Representation bridge only. All assessments run in the extracted CJR implementation.
func wtBoolean(text: String): Bool {
    if (text == "true") { return true }
    if (text == "false") { return false }
    throw Exception("expected true or false in working-time metadata")
}
func wtMinute(text: String): Int64 {
    let minute = parseMinute(text)
    if (minute > 6000000000) { throw Exception("working-time timestamp exceeds the supported native bound") }
    return minute
}
func wtCheckPieces(pieces: ShiftList): Unit {
    var cursor = pieces
    var count: Int64 = 0
    while (!cursor.empty) {
        count += 1
        if (count > 10000 || cursor.start > 6000000000 || cursor.finish > 6000000000) {
            throw Exception("working-time input exceeds native representation bounds")
        }
        cursor = cursor.rest(())
    }
}
func wtParsePieces(text: String): ShiftList {
    let tracker = parseState(text, false)
    if (tracker.pending != -1) { throw Exception("metadata interval lists cannot contain a pending start") }
    wtCheckPieces(tracker.pieces)
    return tracker.pieces
}
func parseWTMetadata(text: String): WTMetadata {
    let fields = text.split("~")
    if (fields.size != 12) { throw Exception("working-time metadata must contain 12 fields; use the public CLI JSON bridge") }
    var periods = wtEmptyPeriods()
    if (!fields[11].isEmpty()) {
        let rows = fields[11].split(";")
        if (rows.size > 10000) { throw Exception("too many assessment periods") }
        var i = rows.size
        while (i > 0) {
            i -= 1
            let row = rows[i].split(",")
            if (row.size != 9) { throw Exception("assessment period must contain 9 fields") }
            let calendar = parseNumber(row[3])
            let evidence = parseNumber(row[6])
            let scheme = parseNumber(row[7])
            if (calendar > 6000000000 || evidence > 3 || scheme > 3) { throw Exception("working-time metadata value exceeds native bounds") }
            periods = wtConsPeriod(parseNumber(row[0]), wtMinute(row[1]), wtMinute(row[2]), calendar,
                wtMinute(row[4]), wtMinute(row[5]), evidence, scheme, wtBoolean(row[8]), periods)
        }
    }
    let jurisdiction = parseNumber(fields[0])
    if (jurisdiction > 2) { throw Exception("jurisdiction must be 1 (GB), 2 (NI), or 0 (unknown)") }
    return WTMetadata(jurisdiction, wtBoolean(fields[1]), wtBoolean(fields[2]), wtMinute(fields[3]), wtMinute(fields[4]),
        wtBoolean(fields[5]), wtBoolean(fields[6]), wtParsePieces(fields[7]), wtParsePieces(fields[8]),
        wtParsePieces(fields[9]), wtParsePieces(fields[10]), periods)
}
func wtMessage(code: Int64): String {
    if (code == 0) { return "No violation detected for the supplied periods and declared applicability; breaks are outside scope." }
    if (code == 20) { return "Invalid or contradictory working-time metadata." }
    if (code == 21) { return "Assessment incomplete: check applicability evidence, work classification, history coverage, pending shifts and period coverage." }
    if (code == 22) { return "The supplied legal regime or exception is outside the supported ordinary-adult scope." }
    if (code == 101) { return "The supplied reference period exceeds the 48-hour weekly average limit." }
    if (code == 102) { return "The supplied daily period lacks 11 consecutive hours of rest." }
    if (code == 103) { return "The supplied weekly or fortnightly period lacks the required continuous rest." }
    if (code == 105) { return "The supplied night-work reference period exceeds the eight-hour normal-hours average." }
    return "The supplied hazardous-night-work period exceeds eight hours of actual work."
}
func printWTReport(report: WTReport): Int64 {
    var cursor = report.findings
    var rows = "["
    var sep = ""
    while (!cursor.empty) {
        let f = cursor.entry
        let unit = if (f.rule == 101 || f.rule == 105) { "scaled_comparison" } else if (f.rule == 103) { "rest_periods" } else { "minutes" }
        rows += "${sep}{\"code\":${f.code},\"rule\":${f.rule},\"start\":${f.start},\"end\":${f.finish},\"measured\":${f.measured},\"limit\":${f.limit},\"unit\":\"${unit}\"}"
        sep = ","
        cursor = cursor.rest(())
    }
    rows += "]"
    println("{\"code\":${report.code},\"message\":\"${wtMessage(report.code)}\",\"findings\":${rows},\"breaksAssessed\":${report.breaksAssessed},\"excludedChecks\":[{\"rule\":104,\"status\":\"not_assessed\",\"reason\":\"outside_scope\"}]}")
    return if (report.code == 0) { 0 } else { 1 }
}
