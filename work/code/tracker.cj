// Generated from Tracker.v by the CJR printer; do not edit.
public struct ShiftList {
public let empty: Bool
public let start: Int64
public let finish: Int64
public let rest: (Unit) -> ShiftList
public init(empty: Bool, start: Int64, finish: Int64, rest: (Unit) -> ShiftList) {
this.empty = empty
this.start = start
this.finish = finish
this.rest = rest
}
}
public struct TrackerState {
public let pieces: ShiftList
public let pending: Int64
public init(pieces: ShiftList, pending: Int64) {
this.pieces = pieces
this.pending = pending
}
}
public struct TrackerResult {
public let code: Int64
public let state: TrackerState
public let rows: ShiftList
public init(code: Int64, state: TrackerState, rows: ShiftList) {
this.code = code
this.state = state
this.rows = rows
}
}
public struct TrackerSession {
public let state: TrackerState
public let candidate: TrackerState
public let waiting: Bool
public let code: Int64
public init(state: TrackerState, candidate: TrackerState, waiting: Bool, code: Int64) {
this.state = state
this.candidate = candidate
this.waiting = waiting
this.code = code
}
}
public func emptyPieces(): ShiftList {
return ShiftList(true, 0, 0, { unused: Unit => ({ cjrTypedValue: ShiftList => cjrTypedValue })(emptyPieces()) })
}
public func consPiece(pieceStart: Int64, pieceEnd: Int64, restPieces: ShiftList): ShiftList {
return ShiftList(false, pieceStart, pieceEnd, { unused: Unit => ({ cjrTypedValue: ShiftList => cjrTypedValue })(restPieces) })
}
public func nextMidnight(minute: Int64): Int64 {
return ((minute  -  (minute  %  1440))  +  1440)
}
public func minMinute(leftMinute: Int64, rightMinute: Int64): Int64 {
return if ((leftMinute  <=  rightMinute)) { leftMinute } else { rightMinute }
}
public func overlaps(pieces: ShiftList, startMinute: Int64, endMinute: Int64): Bool {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { false } else { if (({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(if ((endMinute  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)) { false } else { true }, if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  startMinute)) { false } else { true })) { true } else { overlaps(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), startMinute, endMinute) } }
}
public func endsAfter(pieces: ShiftList, startMinute: Int64): Bool {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { false } else { if (if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  startMinute)) { false } else { true }) { true } else { endsAfter(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), startMinute) } }
}
public func splitOnto(startMinute: Int64, endMinute: Int64, restPieces: ShiftList): ShiftList {
return if ((endMinute  <=  startMinute)) { restPieces } else { ({ => 
let boundary = minMinute(nextMidnight(startMinute), endMinute)
consPiece(startMinute, boundary, splitOnto(boundary, endMinute, restPieces))
})() }
}
public func insertDaily(pieces: ShiftList, startMinute: Int64, endMinute: Int64): ShiftList {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { splitOnto(startMinute, endMinute, pieces) } else { if ((startMinute  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)) { splitOnto(startMinute, endMinute, pieces) } else { consPiece((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish, insertDaily(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), startMinute, endMinute)) } }
}
public func selectPieces(pieces: ShiftList, lowerMinute: Int64, upperMinute: Int64, intersect: Bool): ShiftList {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { pieces } else { ({ => 
let selectedTail = selectPieces(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), lowerMinute, upperMinute, intersect)
if (if (intersect) { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(if ((upperMinute  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)) { false } else { true }, if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  lowerMinute)) { false } else { true }) } else { ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((lowerMinute  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start), ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  upperMinute)) }) { consPiece((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish, selectedTail) } else { selectedTail }
})() }
}
public func hasStart(pieces: ShiftList, startMinute: Int64): Bool {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { false } else { if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start  ==  startMinute)) { true } else { hasStart(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), startMinute) } }
}
public func removeStart(pieces: ShiftList, startMinute: Int64): ShiftList {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { pieces } else { if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start  ==  startMinute)) { removeStart(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), startMinute) } else { consPiece((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start, (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish, removeStart(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), startMinute)) } }
}
public func validPieces(pieces: ShiftList, previousEnd: Int64, pendingMinute: Int64): Bool {
return if ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).empty) { true } else { if (({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((0  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start), (previousEnd  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)), ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })(if (((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start)) { false } else { true }, ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  nextMidnight((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).start))))) { if (if ((pendingMinute  ==  -1)) { true } else { ((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish  <=  pendingMinute) }) { validPieces(((({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).rest)(()), (({ cjrTypedValue: ShiftList => cjrTypedValue })(pieces)).finish, pendingMinute) } else { false } } else { false } }
}
public func emptyState(): TrackerState {
return TrackerState(emptyPieces(), -1)
}
public func validState(tracker: TrackerState): Bool {
return ({ cjrLeft: Bool, cjrRight: Bool => cjrLeft && cjrRight })((-1  <=  (({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending), validPieces((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, 0, (({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending))
}
public func addPair(tracker: TrackerState, startMinute: Int64, endMinute: Int64): TrackerResult {
return if (if ((0  <=  startMinute)) { false } else { true }) { TrackerResult(1, tracker, emptyPieces()) } else { if ((endMinute  <=  startMinute)) { TrackerResult(2, tracker, emptyPieces()) } else { if (if (((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending  ==  -1)) { false } else { if ((endMinute  <=  (({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending)) { false } else { true } }) { TrackerResult(4, tracker, emptyPieces()) } else { if (overlaps((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, startMinute, endMinute)) { TrackerResult(3, tracker, emptyPieces()) } else { TrackerResult(0, TrackerState(insertDaily((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, startMinute, endMinute), (({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending), emptyPieces()) } } } }
}
public func startShift(tracker: TrackerState, startMinute: Int64): TrackerResult {
return if (if ((0  <=  startMinute)) { false } else { true }) { TrackerResult(1, tracker, emptyPieces()) } else { if (if (((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending  ==  -1)) { false } else { true }) { TrackerResult(4, tracker, emptyPieces()) } else { if (endsAfter((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, startMinute)) { TrackerResult(4, tracker, emptyPieces()) } else { TrackerResult(0, TrackerState((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, startMinute), emptyPieces()) } } }
}
public func endShift(tracker: TrackerState, endMinute: Int64): TrackerResult {
return if (((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending  ==  -1)) { TrackerResult(5, tracker, emptyPieces()) } else { ({ => 
let completed = addPair(TrackerState((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, -1), (({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending, endMinute)
if (((({ cjrTypedValue: TrackerResult => cjrTypedValue })(completed)).code  ==  0)) { completed } else { TrackerResult((({ cjrTypedValue: TrackerResult => cjrTypedValue })(completed)).code, tracker, emptyPieces()) }
})() }
}
public func queryContained(tracker: TrackerState, lowerMinute: Int64, upperMinute: Int64): TrackerResult {
return if (if ((0  <=  lowerMinute)) { false } else { true }) { TrackerResult(1, tracker, emptyPieces()) } else { if ((upperMinute  <=  lowerMinute)) { TrackerResult(2, tracker, emptyPieces()) } else { TrackerResult(0, tracker, selectPieces((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, lowerMinute, upperMinute, false)) } }
}
public func queryIntersecting(tracker: TrackerState, lowerMinute: Int64, upperMinute: Int64): TrackerResult {
return if (if ((0  <=  lowerMinute)) { false } else { true }) { TrackerResult(1, tracker, emptyPieces()) } else { if ((upperMinute  <=  lowerMinute)) { TrackerResult(2, tracker, emptyPieces()) } else { TrackerResult(0, tracker, selectPieces((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, lowerMinute, upperMinute, true)) } }
}
public func deleteShift(tracker: TrackerState, startMinute: Int64): TrackerResult {
return if (if ((0  <=  startMinute)) { false } else { true }) { TrackerResult(1, tracker, emptyPieces()) } else { if (hasStart((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, startMinute)) { TrackerResult(0, TrackerState(removeStart((({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pieces, startMinute), (({ cjrTypedValue: TrackerState => cjrTypedValue })(tracker)).pending), emptyPieces()) } else { TrackerResult(6, tracker, emptyPieces()) } }
}
public func initializeStore(loaded: TrackerState): TrackerSession {
return if (validState(loaded)) { TrackerSession(loaded, loaded, false, 0) } else { ({ => 
let empty = emptyState()
TrackerSession(empty, empty, false, 7)
})() }
}
public func stageChange(session: TrackerSession, change: TrackerResult): TrackerSession {
return if (((({ cjrTypedValue: TrackerResult => cjrTypedValue })(change)).code  ==  0)) { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerResult => cjrTypedValue })(change)).state, true, 0) } else { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, false, (({ cjrTypedValue: TrackerResult => cjrTypedValue })(change)).code) }
}
public func prepareAddPair(session: TrackerSession, startMinute: Int64, endMinute: Int64): TrackerSession {
return if ((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting) { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).candidate, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting, 8) } else { stageChange(session, addPair((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, startMinute, endMinute)) }
}
public func prepareStartShift(session: TrackerSession, startMinute: Int64): TrackerSession {
return if ((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting) { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).candidate, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting, 8) } else { stageChange(session, startShift((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, startMinute)) }
}
public func prepareEndShift(session: TrackerSession, endMinute: Int64): TrackerSession {
return if ((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting) { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).candidate, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting, 8) } else { stageChange(session, endShift((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, endMinute)) }
}
public func prepareDeleteShift(session: TrackerSession, startMinute: Int64): TrackerSession {
return if ((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting) { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).candidate, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting, 8) } else { stageChange(session, deleteShift((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, startMinute)) }
}
public func completeStore(session: TrackerSession, succeeded: Bool): TrackerSession {
return if ((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting) { if (succeeded) { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).candidate, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).candidate, false, 0) } else { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, false, 9) } } else { TrackerSession((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).candidate, false, 10) }
}
public func readContained(session: TrackerSession, lowerMinute: Int64, upperMinute: Int64): TrackerResult {
return if ((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting) { TrackerResult(8, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, emptyPieces()) } else { queryContained((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, lowerMinute, upperMinute) }
}
public func readIntersecting(session: TrackerSession, lowerMinute: Int64, upperMinute: Int64): TrackerResult {
return if ((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).waiting) { TrackerResult(8, (({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, emptyPieces()) } else { queryIntersecting((({ cjrTypedValue: TrackerSession => cjrTypedValue })(session)).state, lowerMinute, upperMinute) }
}

