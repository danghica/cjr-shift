# Accepted core prompt

we are building a hexagonal cjr app in which the core will include several modules. the first module is a work time tracker. the data is stored externally in a way to be defined later (not part of the core). The data is time (date, hour, minute) and includes start time (of a shift) and end time (of a shift). If the shift spans midnight it will be broken up in two shifts, from start to midnight and from midnight to end. A shift can be added as a (start, end) pair also as a start shift followed by an end shift. The app will not allow a shift to be added so that its intersection with another shift is non-empty. the app will not allow a shift to be added unless the end time is strictly greater than the start time. The app will be able to query the store and return all the shifts that start and end before specified start-end dates; or that intersect specified start-end dates. The app will be able to delete from the store a shift identified by the start date.

## Agreed clarifications

- Pure operations receive and return state; all storage is external.
- Half-open intervals allow touching endpoints.
- The first query selects pieces contained in the supplied timestamp range.
- One pending start; no replacement; ending without a start fails. Failed completion retains the pending start.
- Split at every midnight; daily pieces are independent, including deletion.
- Gregorian local date and minute without timezone or daylight-saving conversions.
- A pending start reserves all later time. Reject it if an existing piece ends after it; pair additions while pending must end at or before it.
- Queries contain completed daily pieces only. Pair additions and completion are atomic.

## Appended algebraic properties (user wording)

If we add a shift and we query the existing shifts between the same start and end time you get exactly the shift that you added.
If we add a shift and we try to add it again we fail.
If we add a start date, then an end date separately then the effect is the same as adding a shift with that start and end date in a single go.
Just a start date cannot be added if there is any existing start date after it.

## Property refinements

- For midnight-spanning additions the round trip returns exactly the daily pieces, for either query mode.
- Keep the reservation rule, including rejection of starts inside an existing shift.
- Final user clarification: "Keep pair additions flexible: require equivalence only when the separate start is admissible. (Recommended). "

The equivalence law assumes no pending start initially and no intervening operation.

## Accepted storage revision

the relationship between the core and the external storage will change. on startup the core will populate an internal data structure from the external store. all the read and write operations will be performed on the internal data structure. whenever a write or delete operation is performed the external store will also be updated.

User clarification: "roll back on failure".

The user confirmed that the adapter performs external storage calls, while the core initializes from supplied data and returns storage changes for each mutation.

The accepted revised plan retains all domain rules and laws above. Mutations produce candidate state and an atomic storage request. Success is reported only after persistence succeeds. Failure restores the complete prior state, including pending start. Another operation must not observe or modify an unresolved mutation. Storage calls, technology and crash recovery remain outside the pure core.
