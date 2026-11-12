# File-backed tracker CLI

From the repository root:

```sh
./work/CLI/bin/tracker initializeStore shifts.store
./work/CLI/bin/tracker addPair shifts.store 2026-11-11T09:00 2026-11-11T17:00
./work/CLI/bin/tracker queryContained shifts.store 2026-11-11T00:00 2026-11-12T00:00
./work/CLI/bin/tracker deleteShift shifts.store 2026-11-11T09:00
./work/CLI/bin/tracker help
```

`initializeStore FILE` creates an empty store if missing, or loads and validates
an existing store. It never resets an existing store. Use the same filename in
subsequent commands; relative paths are relative to the current working directory.
The JSON `storeFile` field supplies the absolute filename.

Files contain the existing UTF-8 state encoding, with a final newline:
`PENDING|START,END;START,END`. For example, `-|` is empty and
`@60|` contains a pending start. The adapter serializes returned core state;
it does not reimplement overlap, date, splitting or reservation rules.

Each file-backed invocation loads once into an internal session. Mutation
commands, including `prepare*`, run the verified prepare operation, atomically
save its proposed state, and call `completeStore` with the actual result.
There is no manual acknowledgment step for file-backed calls. Reads do not
rewrite the store. A failed save returns code 9, exit status 1, the previous
state and `storageError`. Invalid arguments and file loading errors exit 2.
An invalid loaded domain state returns code 7 and is never overwritten.

A sibling `.lock` file serializes cooperating CLI processes. The adapter writes
and syncs a temporary sibling, then atomically replaces the store. Existing
permissions are preserved; new stores are owner-readable and owner-writable.
External editors must follow the same lock discipline. Atomic replacement
handles definitive local write failures; directory-entry durability across
power loss is not promised.

Other commands still accept explicit state/session encodings for simulation.
An existing filename takes precedence; otherwise `|` or `#` indicates a raw
encoding. `sessionEncoding` alone has no file association: keep using `storeFile`
for persistent operations. The internal `bin/tracker-core` binary retains the
original pure interface; the public `bin/tracker` entry point supplies file I/O.

Build with `python3 work/CLI/build.py` (or the existing workspace native build).
The public entry point requires Python 3 on a POSIX system. The verified CJR
sources and extracted business logic are unchanged. The file adapter is outside
the Rocq proof boundary.

Run `python3 work/CLI/test_file_store.py` for file integration, injected write
failure and concurrent-writer checks. The workspace test runner also executes
these checks. See [HTML reference](doc/index.html), [architecture diagram](doc/architecture.svg),
[file adapter](file_store.py), and [test results](file-store-tests.json).
