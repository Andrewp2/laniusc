# Borrowed reader adapter contracts

`tests/stdlib_io_adapters_execution.rs` registers three native execution tests
and one capability-rejection test containing six marked negative fixtures.
The production APIs are `core::io::Take` and `Chain`; the authoritative contract
is `docs/library-io-adapters-plan.md`.

## Direct native scopes

- `borrowed_reader_adapters_execute_mixed_protocol_and_nested_admission` runs
  `admission.lani`: mixed Read/fill/consume calls share quota and source selection,
  the literal binary result and complete destination guards match, reopening a
  limit resumes the source, ordinary EOF preserves quota, and both Take<Chain>
  and Chain<Take,Take> execute over real SliceReaders.
- `borrowed_reader_adapters_preserve_quotas_handoff_errors_faults_and_actual_strides`
  runs five scenario functions in `contracts.lani`. Actual descending stack
  byte slices and packed +1-byte slices alternate as source/destination. Returned
  fill start/length/stride, exact bytes, complete destination guards, source
  cursor/call counts and selected traces are asserted. Full-width quota starts
  at u64::MAX, decrements exactly across reads/consumes, and can be reset above
  the signed and 32-bit boundaries. Positive short reads return immediately.
  Take's underlying EOF remains observational; first-reader Chain EOF commits
  permanently across mixed protocols and second errors. Second EOF can recover.
  All ten ordinary Error variants, including Err(InvalidCount) and a retained
  Host payload, propagate without implicit retry or permanent fault. A malformed
  successful read/fill/consume faults Take or either Chain selection permanently.
  Invalid read metadata, overflowing/negative fill metadata, and negative,
  excessive or short consume acknowledgements are distinct cases. Faults
  precede invalid/zero requests and setter attempts. A deliberately broken read
  leaves an observed destination/source effect while adapter quota retains only
  previously confirmed progress. Positive consume neither fills nor transitions;
  it needs no cached fill and preserves accounting on provider rejection.
- `borrowed_reader_adapters_preflight_full_ranges_zero_requests_and_capability_independence`
  runs `preflight.lani`. Invalid full read ranges reject even at zero quota;
  valid zero reads/consumes and empty Take fills call no provider. A zero quota
  rejects excess consume locally. A provider whose every operation asserts
  false is the no-call tripwire, with null backing only on paths guaranteed not
  to access it. Constructors and Take's setter work with a type implementing
  neither protocol. Read-only and BufRead-only providers compose independently
  through Take and Chain and generic helpers, with original read destination
  offsets/counts, guards and exact cursor/call observations.

Every native fixture requires strict x86_64 ELF validation and the shared
in-function jump checks before execution. Its child has a ten-second timeout.
Full syscall traces permit exactly one successful launch and one successful
exit, with no allocator, file, descriptor, clock or other intervening host
calls. This proves no host effects for these pure fixtures; it does not exercise
allocation-failure recovery. Separate real-owner tests cover buffering,
retained unread bytes and reached allocator failures.

## Independent capabilities

`borrowed_reader_adapter_read_and_bufread_bounds_are_independent` checks six
LNC0008 diagnostics at marked `require_read`/`require_bufread` calls:

- Take<BufferedOnly> lacks Read; Take<ReadOnly> lacks BufRead.
- Chain lacks Read when either its first or its second provider has only BufRead.
- Chain lacks BufRead when either provider has only Read.

Factories intentionally have no protocol bounds. The negative fixtures demand
capabilities from the constructed adapters; constructor rejection is not the
expected result. The positive preflight fixture executes each supported
single-protocol composition. Negative compilations are not native executions.

## Runtime receipts

All four registered groups passed on the accepted source:

- Tiny admission: one native test in 6.45 seconds, with a separate Rust build
  of 1.64 seconds, recorded in
  `target/stdlib-work/io-adapters-admission-first.log`. The other three groups
  were filtered out of that invocation.
- Full contracts, preflight and the six-fixture capability group: three tests
  in 8.31 seconds, with a separate Rust build of 1.73 seconds, recorded in
  `target/stdlib-work/io-adapters-direct-first.log`. Admission was filtered out.

These are three distinct native executions with full host-effect observations
and one diagnostic group containing six negative compilations. The capability
rejections are not six additional native executions. Production remained at
source SHA256 prefix `6d3a6046` across these receipts.

Accepted runtime scope is native Linux x86_64 CPU output from the GPU compiler.
User GPU execution, other targets, automatic lifetime enforcement, arbitrary
provider recovery and formal proofs are not established. Test-run timings do
not measure reader throughput or impose a host-time bound.
