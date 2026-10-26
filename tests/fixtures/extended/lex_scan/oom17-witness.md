# Sticky regex build failure and eager frame setup

The first spans allocation-failure campaign stopped at OOM17 in
`target/stdlib-work/lex-scan-oom-native-io.log` (7.59 seconds). The app returned
4, wrote no stdout, and passed the exact address/length mapping ledger and
rule-descriptor retirement ledger. The failed assertion required the entire
request sequence to equal the successful baseline truncated at the fault.

The actual requests matched the baseline through the injected 192-byte code
allocation failure, then made one successful 160-byte request and immediately
released that allocation before releasing the remaining owners.

The canonical `extended/ext/regex.lani` explains the continuation:

1. `compile` calls the first `Builder.emit` for its accept instruction. Failed
   code-vector growth sets the sticky `failed` flag and AllocationFailed error.
2. The second `emit` sees the flag and returns without allocating.
3. `compile` still calls `Builder.build`, which unconditionally pushes its
   initial Frame before checking `!failed` in the build loop. That frame-vector
   setup makes the observed later request.
4. The loop does no build work. `compile` destroys frames, nullable flags and
   parser nodes, then releases partial code/terms and returns the original error.

This is bounded setup during error propagation, not an allocation retry or a
successful fallback. The public compile contract requires cleanup and an error;
it does not promise that the first failed request is the final attempted one.
No production change was made for this observation.

The corrected campaign checks the exact request prefix **through** each
injected ordinal, one reached ENOMEM marker on that mmap call, exit 4 and empty
stdout. Its complete ledger covers every successful mapping and exact release,
including allocations reached during failure propagation. The baseline must
identify one adjacent memory-event episode: allocate the code owner, allocate
a temporary frame owner, immediately release that same temporary owner. The
campaign derives its ordinal and request size from those lifetimes. Only a
failure at that parent request can continue with at most the one derived frame
request; that temporary must be released immediately, before outer cleanup.
No other post-failure allocation is accepted. Request byte sizes and this
particular continuation are observations of the captured native profile, not
public ABI or failure-allocation promises. The campaign explores
one injected failure per successful-baseline request; it does not inject a
second failure into allocations that exist only on an error path.

The corrected group passed native x86_64 Linux execution after GPU compilation
in **8.36 seconds**: `target/stdlib-work/lex-scan-oom-bounded-frame.log`.
All 30 reached baseline mmap fault positions passed in spans and all 30 in
counts. The group then completed its exact injected syscall/errno/ordinal
checks for EINTR and EIO, publication-prefix check, `/dev/full` and closed-stdin
cases. Only the harness changed between this acceptance and the initial OOM17
witness; no production change was made for the frame continuation.
