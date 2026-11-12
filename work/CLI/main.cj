import std.console.*

main(args: Array<String>): Int64 {
    try {
        if (args.size == 0 || args[0] == "help") {
            if (args.size > 1) { throw Exception("help takes no arguments") }
            println(helpText())
            return 0
        }
        let command = args[0]
        if (command == "validateWorkingTime") {
            if (args.size != 5) { throw Exception("validateWorkingTime requires STATE START END METADATA") }
            let tracker = parseState(args[1], true)
            wtCheckPieces(tracker.pieces)
            if (tracker.pending > 6000000000) { throw Exception("pending timestamp exceeds working-time bound") }
            return printWTReport(validateWorkingTime(tracker, wtMinute(args[2]), wtMinute(args[3]), parseWTMetadata(args[4])))
        }
        if (command == "emptyState") {
            if (args.size != 1) { throw Exception("emptyState takes no arguments") }
            return printResult(TrackerResult(0, emptyState(), emptyPieces()))
        }
        if (command == "initializeStore") {
            if (args.size != 2) { throw Exception("initializeStore requires loaded STATE") }
            return printSession(initializeStore(parseState(args[1], false)))
        }
        if (command == "completeStore" || command.startsWith("prepare") || command == "readContained" || command == "readIntersecting") {
            if (args.size < 2) { throw Exception("missing SESSION argument") }
            let session = parseSession(args[1])
            if (command == "completeStore") {
                if (args.size != 3 || (args[2] != "true" && args[2] != "false")) { throw Exception("completeStore requires SESSION true|false") }
                return printSession(completeStore(session, args[2] == "true"))
            }
            if (command == "prepareAddPair" || command == "readContained" || command == "readIntersecting") {
                if (args.size != 4) { throw Exception("${command} requires SESSION START END") }
                let start = parseMinute(args[2]); let finish = parseMinute(args[3])
                if (command == "prepareAddPair") { return printSession(prepareAddPair(session, start, finish)) }
                if (command == "readContained") { return printResult(readContained(session, start, finish)) }
                return printResult(readIntersecting(session, start, finish))
            }
            if (args.size != 3) { throw Exception("${command} requires SESSION TIMESTAMP") }
            let minute = parseMinute(args[2])
            if (command == "prepareStartShift") { return printSession(prepareStartShift(session, minute)) }
            if (command == "prepareEndShift") { return printSession(prepareEndShift(session, minute)) }
            if (command == "prepareDeleteShift") { return printSession(prepareDeleteShift(session, minute)) }
            throw Exception("unknown command: ${command}")
        }
        if (args.size < 2) { throw Exception("missing STATE argument; run help") }
        let tracker = parseState(args[1], command != "validState")
        if (command == "validState") {
            if (args.size != 2) { throw Exception("validState requires STATE") }
            let valid = validState(tracker)
            println("{\"valid\":${valid}}")
            return if (valid) { 0 } else { 1 }
        }
        if (command == "addPair" || command == "queryContained" || command == "queryIntersecting") {
            if (args.size != 4) { throw Exception("${command} requires STATE START END") }
            let start = parseMinute(args[2]); let finish = parseMinute(args[3])
            if (command == "addPair") { return printResult(addPair(tracker, start, finish)) }
            if (command == "queryContained") { return printResult(queryContained(tracker, start, finish)) }
            return printResult(queryIntersecting(tracker, start, finish))
        }
        if (command == "startShift" || command == "endShift" || command == "deleteShift") {
            if (args.size != 3) { throw Exception("${command} requires STATE TIMESTAMP") }
            let minute = parseMinute(args[2])
            if (command == "startShift") { return printResult(startShift(tracker, minute)) }
            if (command == "endShift") { return printResult(endShift(tracker, minute)) }
            return printResult(deleteShift(tracker, minute))
        }
        throw Exception("unknown command: ${command}; run help")
    } catch (err: Exception) {
        Console.stdErr.writeln("error: ${err.message}")
        return 2
    }
}
