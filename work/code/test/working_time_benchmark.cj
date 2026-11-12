import std.time.*
// Measures the private calculation layer; no file I/O, parsing or construction in timed loops.
main(): Int64 {
    for (size in [10, 100, 500]) {
        var pieces = emptyPieces()
        var i = size
        while (i > 0) { i -= 1; pieces = consPiece(i*1440, i*1440+480, pieces) }
        let work = pieces
        let period = wtConsPeriod(101, 0, size*1440, size*1440, 0, 0, 1, 0, false, wtEmptyPeriods())
        let metadata = WTMetadata(1, true, true, 0, size*1440, false, true,
            emptyPieces(), work, emptyPieces(), emptyPieces(), period)
        let expected = size*480*10080 + 2880*size*1440 + 101
        for (warm in 0..3) {
            let result = wtWeekly(metadata, work, period)
            if (result.measured + result.limit + result.code != expected) { throw Exception("working-time warmup checksum") }
        }
        for (trial in 0..7) {
            let before = MonoTime.now()
            var checksum: Int64 = 0
            for (repetition in 0..100) { let result = wtWeekly(metadata, work, period); checksum += result.measured + result.limit + result.code }
            let elapsed = (MonoTime.now()-before).toNanoseconds()
            if (checksum != expected*100) { throw Exception("working-time benchmark checksum") }
            println("weekly-calculation,${size},${trial},100,${elapsed},${checksum}")
        }
    }
    return 0
}
