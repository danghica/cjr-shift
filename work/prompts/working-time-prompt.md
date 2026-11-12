# Working-time validation: accepted input

## Original request

add a new interface function that validates the existing shifts in the repository according to UK law. return a specific error code if the following conditions have been violated: **The 48-Hour Weekly Cap:** Workers cannot exceed an average of 48 hours per week (normally averaged over a rolling 17-week reference period) unless they have voluntarily signed an individual **opt-out agreement**. All overtime (paid, unpaid, voluntary, or compulsory) counts toward this total.  &#x20;

1. **Statutory Rest Entitlements:** Overtime cannot encroach upon mandatory rest:
   - **Daily rest:** At least 11 consecutive hours between shifts.
   - **Weekly rest:** At least 24 uninterrupted hours per week (or 48 consecutive hours per fortnight).  &#x20;
   - **In-work rest breaks:** At least 20 minutes of uninterrupted rest if the shift exceeds 6 hours.
2. **Night Work Restrictions:** Night workers must not exceed an average of 8 hours of work in any 24-hour period where by 'night' we meet any work shift including midnight to 5am.

## User clarifications (supersede simplified legal descriptions above)

Apply correct statutory rules. Accept additional Metadata.

No new algebraic properties

## Latest user amendments

no tracking of breaks

stop building. update the plan: no tracking of breaks.

These amendments supersede the original request to assess in-work rest breaks.
There will be no break records, break inputs, break metadata or break-tracking UI.
In-work break compliance is outside the validator's scope and must be reported
as not assessed, rather than passed or violated. Build work is stopped; the
current authorization is to update the specification plan only.

## Handoff

The user previously invoked cjr-build-core, then explicitly stopped building.
Implementation must not resume without a new request.
Preserve the existing tracker laws. Add a read-only pure validator; adapters
supply metadata and perform all explicit system interactions. Do not replace
statutory calculations with checks of precomputed native-adapter verdicts.

See [the accepted plan](working-time-plan.md). The original tracker and storage
inputs remain in prompt.md and plan.md.

## Build resumed

The user invoked cjr-build-core again after the no-break-tracking plan revision.
This authorizes resuming implementation under that revised scope.

Interface clarification during the resumed build:

> Accept the narrower interface

This accepts caller-supplied legal periods and applicability; calculations remain
inside the core. See the accepted refinement in working-time-plan.md.
