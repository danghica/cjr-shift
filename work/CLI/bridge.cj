import std.convert.*

// Adapter representation bound: leave headroom for next-midnight arithmetic.
let maxMinute: Int64 = 9223372036854774367
func parseNumber(text: String): Int64 {
    if (text.isEmpty()) { throw Exception("expected decimal integer") }
    for (c in text.toArray()) {
        if (c < 48 || c > 57) { throw Exception("expected unsigned decimal integer: ${text}") }
    }
    return Int64.parse(text)
}
func leap(year: Int64): Bool { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }
func monthLength(year: Int64, month: Int64): Int64 {
    if (month == 2) { return if (leap(year)) { 29 } else { 28 } }
    if (month == 4 || month == 6 || month == 9 || month == 11) { return 30 }
    return 31
}
func parseMinute(text: String): Int64 {
    if (text.startsWith("@")) {
        let value = parseNumber(text[1..])
        if (value > maxMinute) { throw Exception("minute exceeds native arithmetic bound") }
        return value
    }
    if (text.size != 16 || text[4] != 45 || text[7] != 45 || text[10] != 84 || text[13] != 58) {
        throw Exception("timestamp must be YYYY-MM-DDTHH:MM or @ordinal-minute")
    }
    let year = parseNumber(text[0..4]); let month = parseNumber(text[5..7])
    let day = parseNumber(text[8..10]); let hour = parseNumber(text[11..13]); let minute = parseNumber(text[14..16])
    if (year < 1 || month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59) { throw Exception("invalid Gregorian timestamp") }
    if (day > monthLength(year, month)) { throw Exception("invalid Gregorian day") }
    let y = year - 1
    var days = 365 * y + y / 4 - y / 100 + y / 400 + day - 1
    var m: Int64 = 1
    while (m < month) { days += monthLength(year, m); m += 1 }
    return days * 1440 + hour * 60 + minute
}
func parseState(text: String, checkDomain: Bool): TrackerState {
    let fields = text.split("|")
    if (fields.size != 2) { throw Exception("state format: PENDING|START,END;START,END (use - for no pending start)") }
    let pending = if (fields[0] == "-") { -1 } else { parseMinute(fields[0]) }
    var pieces = emptyPieces()
    if (!fields[1].isEmpty()) {
        let pairs = fields[1].split(";")
        var i = pairs.size
        while (i > 0) {
            i -= 1
            let pair = pairs[i].split(",")
            if (pair.size != 2) { throw Exception("each piece needs START,END") }
            pieces = consPiece(parseMinute(pair[0]), parseMinute(pair[1]), pieces)
        }
    }
    let tracker = TrackerState(pieces, pending)
    if (checkDomain && !validState(tracker)) { throw Exception("invalid state: pieces must be sorted, positive, daily, disjoint and before any pending start") }
    return tracker
}
func listJSON(pieces: ShiftList): String {
    var cursor = pieces; var text = "["; var sep = ""
    while (!cursor.empty) {
        text += "${sep}[${cursor.start},${cursor.finish}]"; sep = ","; cursor = cursor.rest(())
    }
    return text + "]"
}
func stateEncoding(tracker: TrackerState): String {
    var text = if (tracker.pending == -1) { "-|" } else { "@${tracker.pending}|" }
    var cursor = tracker.pieces; var sep = ""
    while (!cursor.empty) {
        text += "${sep}@${cursor.start},@${cursor.finish}"; sep = ";"; cursor = cursor.rest(())
    }
    return text
}
func printResult(result: TrackerResult): Int64 {
    let pending = if (result.state.pending == -1) { "null" } else { result.state.pending.toString() }
    println("{\"code\":${result.code},\"stateEncoding\":\"${stateEncoding(result.state)}\",\"state\":{\"pending\":${pending},\"shifts\":${listJSON(result.state.pieces)}},\"rows\":${listJSON(result.rows)}}")
    return if (result.code == 0) { 0 } else { 1 }
}

func parseSession(text: String): TrackerSession {
    let fields = text.split("#")
    if (fields.size != 4) { throw Exception("session format: STATE#CANDIDATE#WAITING#CODE") }
    if (fields[2] != "true" && fields[2] != "false") { throw Exception("WAITING must be true or false") }
    let code = parseNumber(fields[3])
    if (code > 10) { throw Exception("session code must be 0..10") }
    return TrackerSession(parseState(fields[0], true), parseState(fields[1], true), fields[2] == "true", code)
}
func sessionEncoding(session: TrackerSession): String {
    return "${stateEncoding(session.state)}#${stateEncoding(session.candidate)}#${session.waiting}#${session.code}"
}
func printSession(session: TrackerSession): Int64 {
    let request = if (session.waiting) {
        "{\"before\":\"${stateEncoding(session.state)}\",\"after\":\"${stateEncoding(session.candidate)}\"}"
    } else { "null" }
    println("{\"code\":${session.code},\"sessionEncoding\":\"${sessionEncoding(session)}\",\"stateEncoding\":\"${stateEncoding(session.state)}\",\"waiting\":${session.waiting},\"storageRequest\":${request}}")
    return if (session.code == 0) { 0 } else { 1 }
}
