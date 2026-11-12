import std.time.*
func countPieces(xs: ShiftList): Int64 {
    var cursor = xs; var n: Int64 = 0
    while (!cursor.empty) { n += 1; cursor = cursor.rest(()) }
    return n
}
main(): Int64 {
    for (size in [10, 100, 500]) {
        var tracker = emptyState()
        for (i in 0..size) {
            let r = addPair(tracker, i*3, i*3+1)
            if (r.code != 0) { throw Exception("benchmark construction failed") }
            tracker = r.state
        }
        let snapshot = tracker
        let session = initializeStore(snapshot)
        let prepared = prepareAddPair(session, size*3, size*3+1)
        for (operation in ["contained", "intersecting", "add", "start", "delete", "initialize", "prepare", "commit", "rollback", "readSession"]) {
            let work = { =>
                if (operation == "contained") { countPieces(queryContained(snapshot, 0, size*3).rows) }
                else if (operation == "intersecting") { countPieces(queryIntersecting(snapshot, 0, size*3).rows) }
                else if (operation == "add") { countPieces(addPair(snapshot, size*3, size*3+1).state.pieces) }
                else if (operation == "start") { startShift(snapshot, size*3).state.pending }
                else if (operation == "initialize") { countPieces(initializeStore(snapshot).state.pieces) }
                else if (operation == "prepare") { countPieces(prepareAddPair(session, size*3, size*3+1).candidate.pieces) }
                else if (operation == "commit") { countPieces(completeStore(prepared, true).state.pieces) }
                else if (operation == "rollback") { countPieces(completeStore(prepared, false).state.pieces) }
                else if (operation == "readSession") { countPieces(readContained(session, 0, size*3).rows) }
                else { countPieces(deleteShift(snapshot, (size-1)*3).state.pieces) }
            }
            let expected = if (operation == "add" || operation == "prepare" || operation == "commit") { size+1 } else if (operation == "start") { size*3 } else if (operation == "delete") { size-1 } else { size }
            for (warm in 0..3) { if (work() != expected) { throw Exception("warmup checksum") } }
            for (trial in 0..7) {
                let before = MonoTime.now()
                var checksum: Int64 = 0
                for (repetition in 0..100) { checksum += work() }
                let elapsed = (MonoTime.now()-before).toNanoseconds()
                if (checksum != expected*100) { throw Exception("benchmark checksum") }
                println("${operation},${size},${trial},100,${elapsed},${checksum}")
            }
        }
    }
    return 0
}
