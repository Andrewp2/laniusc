# Active-owner server caps and cancellation

This separate actual `ext::server_poll::Server` control covers seven finite
profiles with real Protocol backing and accepted loopback socket owners:

| Profile | Required behavior |
| --- | --- |
| Operation cap | Two owners are live when scheduler operations run out; mandatory cleanup still closes and destroys both. |
| Wait-permit cap | Two owners are live with `polls = 0`; preparation fails with PollLimit before issuing a permit or physical poll. |
| Handler cap | Two owners are live, one with a latched Head, when `handler_calls = 0` prevents the callback. |
| Accept cap | One owner is live when `accept_calls = 1` prevents the next acquisition; a second peer stays unaccepted. |
| Stop accepting | Two input-held owners remain live after stop; a third peer stays unaccepted. The first two then half-close, drive genuine positive-capacity EOF through the public poll/step loop, and complete Empty without being aborted. |
| Abort all | Both active owners retire on the first abort; repetition performs no second close or backing release. |
| Active destroy | Destroy retires both active owners and discards its report; repeated destroy returns false and active calls become Inactive. |

Every cap checks its exact first cause, cached repeated failure, ordered
Aborted outcomes, released byte/work reservations and cleanup metadata. The
operation cap leaves cleanup to run after the remaining allowance cannot pay
the next scheduler pass. These are abstract scheduler units, not CPU work or
preemption. Metadata-only HTTP errors keep this distinct from the separate
owned nested E/A campaign. Handler request bytes are scripted into the real
Protocol to expose the Head decision; no HTTP response or TLS is claimed.

Across the seven profiles, thirteen actually accepted peers must observe
native EOF. The stop case adds two positive-capacity server EOF reads.
The independent strace oracle checks exact source mmap/munmap ownership and
socket/close ownership, plus `/proc` descriptors, before acknowledging process
exit; it checks the completed trace again afterward. The unlinked executable
has no native CRT/OpenSSL heap mixed into this source allocation ledger.
The stop case uses the actual Server `poll_once` path; none of the four cap
profiles performs a physical poll. There is no injected host fault, reached
allocation failure, genuine timeout or TLS evidence in this group.

Run through the root's serialized GPU/native queue:

```sh
timeout --kill-after=2s 110s cargo test --test extended_server_poll_limits_execution -- --exact active_owner_caps_and_cancellation_preserve_cleanup_and_first_failure --nocapture
```

The corrected root gate passes all seven profiles in 13.42 seconds:
`target/stdlib-work/server-poll-active-limits-api-retry.log`, with exact summary
`server-poll-limits cases=7`. The retained unlinked executable is
`/tmp/server_poll_limits_native_241557_0`. This accepts the finite active-cap
and cancellation scope above, including pre-exit ownership checks. The oracle's
native deadline is twelve seconds; parent and compilation have separate bounds.

The first root invocation stopped during fixture type checking in 4.12 seconds:
`target/stdlib-work/server-poll-active-limits-first.log`, LNC0027 at the
Protocol `before_io` call. The fixture omitted its required Stage argument.
The corrected call supplies Stage::Head for the positive-capacity head EOF
read; all behavioral assertions are retained. No native case ran, and this
receipt establishes neither a scheduler runtime failure nor acceptance.

## Additive reached-poll faults

`poll_faults.lani` uses the actual plain Factory/Exchange inside a stopped,
one-owner Server. It first consumes a real readable poll result and one partial
request byte, then reaches actual EAGAIN. This leaves old readable storage in
PollSet before the separately marked target wait. No test Driver simulates
these socket operations.

`poll_faults_oracle.py` calibrates a successful baseline, then injects EINTR
and EIO into the exact reached target poll ordinal. Every run binds binary
markers, the accepted fd/generation, request set and syscall result. Prefix
ordinal drift, a fault reaching setup/warmup instead, or unreached injection
fails the oracle. The baseline is calibration, separate from the two fault
profiles:

- EINTR consumes one physical call and wait permit. A step without fresh hints
  performs no receive. A new epoch rejects the old publication; zero hints do
  not restore old readable results. A fresh physical poll then observes actual
  EOF and lets the ordinary rejected partial request retire.
- EIO remains the shared Poll(Io(Host(5))) cause. The live owner is closed and
  its Protocol backing destroyed before return; repeated failure observations
  perform no extra poll. The report retains its ordered abort and confirmed
  prefix, and the caller's listener stays open until explicit release.

Each baseline/fault process has its own pre-exit source-map, native-fd and
exact close ledger, plus the final trace audit. This adds no timeout, clock,
accept, send, allocation or TLS fault campaign. The accepted seven-case
`main.lani` and its original oracle remain unchanged.

Both injected profiles and the separate baseline calibration pass in
`target/stdlib-work/server-poll-marked-poll-faults-format-retry.log`, exit zero
with exact summary `server-poll-faults cases=2 calibration=1`. This Python-only
retry reused `/tmp/server_poll_faults_native_249145_0` without a GPU recompile.
These two native fault profiles remain separate from the seventeen accepted
scripted scheduler profiles; the baseline is calibration rather than a third
fault case. Its filter is
`reached_poll_interruptions_reprepare_and_fatal_poll_errors_retire_live_owners`
in `extended_server_poll_limits_execution`. CPU-only oracle rejection controls
are in `poll_faults_controls.py`; all twenty-two pass and execute no Lanius
program.

The first marked-poll invocation ran for 15.03 seconds in
`target/stdlib-work/server-poll-marked-poll-faults-first.log`. Compilation and
native assertions ran, but the EIO oracle required a literal single space
before the close result. The actual successful `close(5)` had strace's aligned
spacing. The Python-only correction parses the exact fd and result and still
requires exactly one successful close inside the same target marker frame.
No production/Lanius source or behavioral assertion was changed. That first
invocation is an oracle formatting-assumption failure, not a scheduler failure
or a complete passing group.
