# Shift browser UI

From the repository root, start the local server:

```sh
python3 work/UI/server.py
```

Open [http://127.0.0.1:8765](http://127.0.0.1:8765) in a browser. Keep the server
running while using the app; stop it with Ctrl+C. No JavaScript dependencies,
build step, account or internet connection are required.

By default the store is `work/UI/data/shifts.store`, relative to the application
folder, even when launching from another directory. To use another store,
including a file already used by the CLI:

```sh
python3 work/UI/server.py --store /absolute/path/shifts.store --port 8765
```

The store's parent directory must exist for a custom path. The server creates
an empty store when absent and validates existing data before serving the UI.
An invalid file is not overwritten. If the native CLI is absent, build it first
with `python3 work/CLI/build.py`.

## Use

Press **start** to save the browser's current local date and minute. The button
changes to **stop** after the save succeeds. Press stop to complete and save the
shift. A running shift survives page refreshes and server restarts.

The core records minutes rather than seconds; stopping in the same minute is
rejected, with the active shift preserved. The displayed seconds are measured
from the recorded start minute. The core store uses local civil dates. Compliance metadata separately retains time zones for elapsed-time assessment; use the same local timezone for a running shift.

**shifts** opens completed daily pieces, newest first, grouped by day, with
individual durations, daily totals and an overall total. A midnight-spanning
shift has independent daily pieces, as specified by the existing core. **back**
returns home. The home total includes the recorded minutes of a running shift
that fall today; the history total counts completed pieces only.

The burger menu includes **missed shift**, **compliance**, **settings** and **reset**. **missed shift** opens
a form with local date/time selectors labelled **start** and **end**. Press **add**
to save a completed shift and open the shifts page. Rejected entries remain in
the form for correction. The existing core rejects overlaps, nonpositive ranges
and conflicts with a running shift, and splits midnight-spanning shifts.

**reset** opens its confirmation dialog. The dialog explains that
reset deletes completed shifts and cancels a running shift. **keep my shifts**
or Escape cancels. Confirming reset atomically replaces the store with the
core's empty state. Failed saves retain the previous state.

If adding a missed shift reports that the running server does not support it,
stop the existing server with Ctrl+C, restart it with the same `--store` argument,
and reload the page. An older Python server can still serve updated JavaScript
files while its HTTP routes remain from the previous version. Action errors stay
visible through automatic state refreshes; dismissing an error never repeats a write.

## Hexagonal boundary

```text
Browser UI (JavaScript, clock, presentation)
                  ↕ JSON / HTTP
Local HTTP adapter → TrackerAdapter (protocol + metadata driver)
                  ↕ existing native core ports
       Unchanged verified CJR tracker core
                  ↕ proposed state / save outcome
       FileRepository + metadata/journal adapters → local files
```

`server.py` is an inbound HTTP adapter. `adapters.py` bridges ordinary JSON and
the native CLI representations; it does not implement tracker business rules.
`CorePort` calls the already extracted functions through `work/CLI/bin/tracker-core`.
Start/stop use `prepareStartShift` / `prepareEndShift`; missed shifts use the
existing `prepareAddPair` port. Each follows with `completeStore`
with the actual save outcome. The `readContained` port returns the internal
state used for presentation.

`FileRepository` reuses the existing CLI adapter's stable sibling lock, temporary
file, sync and atomic replacement. The protocol driver keeps an internal session
initialized at startup and reconciles external CLI changes under the shared
lock before requests. Reset is an administrative storage-adapter action: it
gets `emptyState` from the core, saves it atomically and initializes the new
session. It does not add a cancellation or reset operation to the core.

All browser, clock, HTTP, representation conversion and filesystem behavior
is outside the Rocq proof boundary. No core source, proof, extraction output
or CLI implementation was changed for this UI. Local write failure is handled;
directory-entry durability across power loss is not promised. The server listens
only on localhost. This is a local application, not a hosted website.

## Tests

```sh
python3 work/UI/test_server.py
node --test work/UI/test_ui.mjs
python3 work/code/test/run.py test
```

The server integration tests need permission to open temporary localhost ports.
They use temporary store files and the real native core, including simulated
save failures, concurrent starts, existing-file corruption and external changes.
The JavaScript tests independently exercise date conversion, midnight grouping,
ordering and durations. Browser checks cover the desktop phone layout, start,
stop, same-minute errors, reload recovery, shifts navigation and reset cancellation.
Mobile layout uses a responsive viewport; physical-device testing has not been performed.

See [validation record](validation.json), [adapter/API test log](tests.log),
[JavaScript test log](javascript-tests.log), and [CLI regression log](cli-regression-tests.log).

## Compliance, settings and recorded-time types

The burger menu now includes **compliance** and **settings**. Compliance has
optional start/end date-time fields and a **check** button. Blank start selects
the earliest recorded start; blank end selects the latest completed end. A running
shift never receives an invented end. Empty history is explained without claiming
it has passed validation.

Results distinguish confirmed violations, incomplete information and conditional
success. They show native validator codes, period boundaries, measurements and
limits, with links to the relevant Working Time Regulations. Confirmed violations
appear first; incomplete period details can be expanded. Weekly-rest findings
identify their calendar period separately from the adjacent daily-rest context.
The report becomes stale if settings or the underlying store change.

**settings** provides the three weekly/fortnightly rest arrangements. The default
is 24 uninterrupted hours per week. Fortnightly settings require an anchor Monday.
Night-worker and hazardous-night-work status independently start **Not set**.
These saved settings apply to every assessment, including older records. The
ordinary adult Great Britain profile uses 17-week reference periods and the
standard 23:00–06:00 night period. The strict hazardous-night check applies only
when night-worker and hazardous-work status are established. Unknown normal
hours keep an applicable average-night check incomplete; actual work is not
silently classified as normal hours or regular overtime.

On the main and missed-shift pages, **Attendence time** is unchecked by default,
meaning actual working time. Checked means attendance; no actual-work duration
or break deduction is inferred from it. While running, changing the checkbox
saves the classification immediately without changing the start timestamp. Stop
uses the final choice. Refreshes and server restarts preserve the running choice.
Midnight pieces retain their original logical shift's classification. Existing
records and shifts written by an older client or the CLI remain unclassified.

The application assumes all employment is recorded. Known work is passed to the
existing `validateWorkingTime` port; periods affected by attendance, unclassified
records, unknown applicability or incomplete history receive unknown evidence.
The adapter prepares context, translates time zones and presents results; hours,
rest gaps, thresholds and summary codes are calculated by the unchanged native
validator. Browser time-zone identifiers are saved with new logical shifts.
Ambiguous/nonexistent clock-change times remain unresolved, and an ambiguous
reference-period boundary does not suppress independent known violations.

Only ordinary unadjusted reference periods are prepared automatically. No excluded-
day replacement, alternative night period or exceptional agreement is inferred.
Reports state that these calculations are conditional on this standard profile;
they are not a complete legal-compliance certificate. Supporting history may be
needed outside the selected range. History before the earliest record is not
filled with zero work; the completed-record assumption extends to the check time,
with running shifts treated as unfinished. The local adapter limits inputs to
1,500 daily pieces, 1,200 prepared periods and a ten-year selected range to remain
within the native CLI's resource/argument limits. Inputs exceeding those limits
are explained without changing records.

A weekly-average violation asks **Did a voluntary written opt-out cover this
period?** The default is no opt-out. Yes/No answers are saved for precisely that
reference period, are visible and correctable, and trigger a recheck. They do not
waive rest or night-work limits. This records a user declaration; it does not
create, sign or authenticate an opt-out agreement.

### Local metadata and recovery

For a store `shifts.store`, `shifts.store.metadata.json` holds versioned settings,
logical-span/piece associations, the running classification, and scoped opt-out
answers. Settings and classifications never change the core store encoding.
Metadata files use owner-only permissions when created, like new store files.

`shifts.store.transaction.json` is a recovery journal for operations updating both
files. It records before/after snapshots under the existing store lock. A failed
metadata save restores the old core snapshot before reporting rollback. If
restoration fails, the journal is retained and normal access is blocked until
recovery. On startup or the next request, an expected before/after store snapshot
determines which metadata snapshot to restore. An unrelated external change or
corrupted metadata/journal is preserved and reported rather than overwritten.
Atomic replacement and file sync cover process interruption and definitive local
write errors; directory-entry durability across power loss is not promised.

Reset clears shifts, running classifications and assessment-specific opt-out
answers, retaining the working-time settings. External edits are reconciled by
piece identity; deleting or modifying part of a logical shift invalidates its
classification. Opt-out requests carry a revision including the core snapshot
fingerprint, so external CLI writes also invalidate a stale answer.

### Added local HTTP interfaces

All writes retain the localhost Host/Origin and `X-Tracker-UI` checks.

- `GET /api/settings` returns the current settings and state envelope.
- `POST /api/settings` saves `restScheme` (1/2/3), `fortnightStart` (date or blank),
  `nightWorker` and `hazardousNightWork` (true/false/null).
- `POST /api/attendance` saves a running shift's `start`, boolean `attendance`
  and browser `timeZone`.
- Start, stop and missed-shift requests accept `attendance` and `timeZone`.
  Missing classification from older clients remains unknown.
- `POST /api/compliance` accepts optional string `start`/`end` and `timeZone`.
  Successful transport returns the normal state envelope plus `report`; a native
  violation is a report, not an HTTP failure.
- `POST /api/opt-out` additionally accepts `optOut` containing numeric reference
  `start`/`end`, boolean `answer` and the last report's `revision`.

Run the added adapter/validator cases with:

```sh
python3 work/UI/test_compliance.py
```

They cover classification and profile persistence, midnight associations,
rollback/recovery, external edits, exact scoped opt-out corrections, rest and
hazardous-night independence, clock changes, and actual validator outputs. No
proof validation is needed or run for these UI-only changes. See
[compliance test log](compliance-tests.log) and [preview](compliance-preview.jpg).
