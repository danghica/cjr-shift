func check(condition: Bool, label: String): Unit {
    if (!condition) { throw Exception("FAILED: ${label}") }
}
func samePieces(a: ShiftList, b: ShiftList): Bool {
    var x = a; var y = b
    while (!x.empty && !y.empty) {
        if (x.start != y.start || x.finish != y.finish) { return false }
        x = x.rest(()); y = y.rest(())
    }
    return x.empty && y.empty
}
func sameState(a: TrackerState, b: TrackerState): Bool {
    return a.pending == b.pending && samePieces(a.pieces, b.pieces)
}
main(): Int64 {
    let empty = emptyState()
    check(validState(empty), "empty state")
    check(endShift(empty, 1).code == 5, "end without start")
    check(deleteShift(empty, 1).code == 6, "delete missing")
    check(addPair(empty, 1, 1).code == 2, "zero duration")
    check(addPair(empty, 2, 1).code == 2, "reverse duration")
    check(addPair(empty, -1, 1).code == 1, "negative timestamp")
    var checks: Int64 = 6
    for (s in 0..50) {
        for (length in 1..50) {
            let e = s + length
            let added = addPair(empty, s, e)
            check(added.code == 0 && validState(added.state), "add preserves invariant")
            check(addPair(added.state, s, e).code == 3, "duplicate rejection")
            check(samePieces(queryContained(added.state, s, e).rows, added.state.pieces), "contained round trip")
            check(samePieces(queryIntersecting(added.state, s, e).rows, added.state.pieces), "intersecting round trip")
            let begun = startShift(empty, s)
            let completed = endShift(begun.state, e)
            check(sameState(completed.state, added.state), "equivalent insertion paths")
            check(startShift(added.state, s).code == 4, "start inside existing")
            check(startShift(added.state, e).code == 0, "start at touching endpoint")
            check(startShift(begun.state, e).code == 4, "second pending start")
            check(sameState(endShift(begun.state, s).state, begun.state), "failed completion preserves pending")
            check(sameState(added.state, addPair(added.state, s, e).state), "failed add preserves state")
            check(queryIntersecting(added.state, e, e+1).rows.empty, "touching query excludes")
            checks += 11
        }
    }
    let overnight = addPair(empty, 1430, 4330)
    check(validState(overnight.state), "multiple midnight invariant")
    check(overnight.state.pieces.start == 1430 && overnight.state.pieces.finish == 1440, "first split")
    let second = overnight.state.pieces.rest(())
    check(second.start == 1440 && second.finish == 2880, "second split")
    let third = second.rest(())
    check(third.start == 2880 && third.finish == 4320, "third split")
    let fourth = third.rest(())
    check(fourth.start == 4320 && fourth.finish == 4330 && fourth.rest(()).empty, "last split")
    let removed = deleteShift(overnight.state, 1440)
    check(removed.code == 0 && samePieces(removed.state.pieces.rest(()), third), "independent piece deletion")
    let midnightEnd = addPair(empty, 1430, 1440)
    check(midnightEnd.state.pieces.rest(()).empty, "no empty midnight piece")
    let future = addPair(empty, 200, 300).state
    check(addPair(future, 10, 20).code == 0, "flexible pair before future shift")
    check(startShift(future, 10).code == 4, "pending ordering rule")
    let reserved = startShift(future, 300).state
    check(addPair(reserved, 310, 320).code == 4, "reservation blocks future pair")
    check(addPair(reserved, 100, 200).code == 0, "pair may end before reservation")
    check(sameState(queryContained(reserved, 0, 400).state, reserved), "query state preservation")
    let loaded = initializeStore(reserved)
    check(loaded.code == 0 && sameState(loaded.state, reserved), "startup retains pending and pieces")
    let invalidLoad = initializeStore(TrackerState(consPiece(10, 10, emptyPieces()), -1))
    check(invalidLoad.code == 7 && invalidLoad.state.pieces.empty, "startup rejects corrupt snapshot")
    let proposal = prepareAddPair(initializeStore(empty), 1430, 4330)
    check(proposal.waiting && proposal.code == 0 && proposal.state.pieces.empty, "provisional add keeps committed state")
    check(readContained(proposal, 0, 5000).code == 8, "read blocks during save")
    check(prepareDeleteShift(proposal, 1430).code == 8, "write blocks during save")
    let rolledBack = completeStore(proposal, false)
    check(rolledBack.code == 9 && !rolledBack.waiting && sameState(rolledBack.state, empty), "midnight rollback")
    let saved = completeStore(proposal, true)
    check(saved.code == 0 && !saved.waiting && sameState(saved.state, proposal.candidate), "commit all pieces")
    let pendingProposal = prepareStartShift(initializeStore(empty), 60)
    check(completeStore(pendingProposal, false).state.pending == -1, "rollback pending start")
    let pendingSession = completeStore(pendingProposal, true)
    let completionProposal = prepareEndShift(pendingSession, 3000)
    check(completeStore(completionProposal, false).state.pending == 60, "rollback restores pending completion")
    let deletion = prepareDeleteShift(saved, 1440)
    check(sameState(completeStore(deletion, false).state, saved.state), "delete rollback")
    check(completeStore(saved, true).code == 10, "reject unsolicited acknowledgment")
    let rejected = prepareAddPair(saved, 1430, 1440)
    check(rejected.code == 3 && !rejected.waiting, "domain rejection has no storage request")
    println("PASS ${checks+24} native assertions")
    return 0
}
