# Work time tracker implementation plan

Implement the accepted [prompt](prompt.md) as a pure module of a hexagonal CJR application, using the cjr-build-core workflow.

## Domain and operations

Timestamps are Gregorian dates with hour and minute. Completed shifts are half-open intervals with strictly positive duration. State contains nonoverlapping daily pieces and at most one pending start. Split at every midnight without empty pieces; pieces have independent start-timestamp identities.

- Add pair: validate and add every daily piece atomically; reject overlap, invalid duration and conflict with a pending reservation.
- Start: reject an existing pending start or any completed piece ending after the proposed timestamp.
- End: require a pending start and later end; add the daily pieces and clear pending only on success.
- Query contained: piece start >= lower and piece end <= upper.
- Query intersecting: positive-duration intersection with [lower,upper).
- Delete: remove the piece identified by its full start timestamp.

Return queries sorted by increasing start. Reject nonpositive query ranges and unknown deletion identities. Every error preserves state. A pending start reserves [start,infinity); pair additions must finish at or before it. Queries return completed pieces only.

## Laws and acceptance

Prove add/query round trip (both modes), duplicate rejection, pair versus start/end equivalence when the separate start is admissible and no operation intervenes, and pending-start ordering/reservation. Specify operation contracts and state invariants. Check adjacency, containment, overlap, invalid timestamps/durations, exact midnight, multiple midnights, pending failures, deletion, and query boundaries.

Deliver CJR encoded in Rocq, Iris contracts and proofs, extracted Cangjie, a CLI exposing all application operations with explicit state encoding, offline reference and architecture diagram, runtime tests and core benchmarks, readable specifications and concise project documentation. Keep storage, clocks, pending cancellation and other modules outside scope. Do not commit or push.

## Accepted storage implementation revision

1. Add initialization from an adapter-supplied snapshot, validated against the existing invariant.
2. Add a session holding committed state and at most one candidate mutation. Return a complete before/after snapshot replacement request, including pending starts and all midnight pieces.
3. Require an atomic external apply: success stores the candidate, failure leaves the external state unchanged. The adapter serializes access and reports a definitive persistence outcome.
4. Finalize success by adopting the candidate; finalize failure by restoring the previous state and reporting failure. Reject further reads/writes while an outcome is outstanding.
5. Prove initialization, staging, blocked-operation and completion Iris contracts, rollback, commit, invariant preservation and retention of the existing algebraic laws.
6. Extend extracted code, CLI protocol commands, native and adapter-facing tests, fresh benchmarks, offline reference/diagram and rendered specifications.

The CLI exposes pure protocol values and explicit outcome input; it does not implement a database. Existing state operations remain pure candidate calculators. An adapter loads once, keeps the session, applies each waiting request atomically and calls completion. No commit or push.
