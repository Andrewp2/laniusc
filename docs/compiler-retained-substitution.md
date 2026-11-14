# Retained substitution

Retained substitution is the production engine that instantiates retained
terms ([program retention](compiler-program-retention.md)) under closed
environments on the GPU. It replaces the probe walk in
`retention_subst.slang` for production consumers. The probe stays for the
retention acceptance test until integration. No production code path calls
this engine yet. Discovery and projection are the planned consumers, and
source replay is still the active instantiation path.

| Part | Location |
| --- | --- |
| Kernels and shared module | `shaders/type_checker/retention/substitution/` |
| Layout constants (no buffers) | `shaders/type_checker/retention/substitution/sb_layout.slang` |
| Consumer check | `shaders/type_checker/retention/substitution/sb_consumer.slang` |
| Host object | `crates/laniusc-compiler/src/type_checker/program_retention/substitution.rs` |
| Test fixture interpreter | `shaders/tests/retention_subst_fixture.slang` |
| Test request producer over retained uses | `shaders/tests/retention_subst_uses.slang` |
| Test consumer | `shaders/tests/retention_subst_consumer.slang` |
| Tests | `tests/retained_substitution.rs` (in the `compiler` binary) |

## Producer contract

A GPU producer writes requests into `sb_requests` and their count into
`sb_request_count[0]` (`SubstitutionRequests`). A request is one uint4:

| Word | Contents |
| --- | --- |
| x | `DeclId` of the declaration whose binder chain the term uses |
| y | ENV `TermId`: the normalized closed environment the declaration owns |
| z | the term reference to substitute |
| w | a producer tag, returned unchanged |

- **Count.** The producer writes its full request count even when the
  buffers hold fewer rows. More requests than rows run nothing and publish
  nothing: `run` returns `SubstitutionRun::RequestCapacity { requested,
  capacity }` and the store is untouched. The producer owns the rerun. It
  runs its production again into buffers of at least `requested` rows. The
  engine never substitutes a prefix and never grows a blank tail.
- **Normalized ENV.** The request ENV is a stored, closed `ENV` of the
  request's declaration, and no term inside it holds a `CC_CAST`. The
  canonical store folds every concrete projection when it interns it
  (`ct_build_projection`), so every closed term it exports is normalized.
  Every ENV this engine publishes is normalized too. The engine checks the
  contract: it evaluates the ENV as a closed term and accepts the request
  only when that evaluation returns the ENV itself. Every binding's fit is
  therefore checked, including a binding that the term never reads, and a
  normalized ENV is the one identity of an instance.
- **Slot leaves.** A dependency-signature slot leaf is reported as
  `SLOT_PENDING`, never bound by slot position. Binding it needs the
  dependency's defining binder, which discovery knows and the term does
  not.

## Results

`sb_results` holds three uint4 per request:

| Word | Contents |
| --- | --- |
| r0 | `(result TermId or RT_UNKNOWN, status, failed node, failed env)` |
| r1 | `(failed child value, tag, run, store generation)` |
| r2 | `(ENV cause, inner status, inner ENV cause, 0)` |

Statuses:

| Code | Name | Meaning | Failed node |
| --- | --- | --- | --- |
| 0 | `OK` | r0.x is a closed, normalized, exactly interned term | — |
| 2 | `NOT_READY` | the store's `READY` bit is clear | request term |
| 3 | `DECL` | no committed, complete definition of the request declaration, or no committed definition of a nested ENV's owner | request term, or the nested ENV |
| 4 | `ENV` | an ENV that does not fit its owner; r2.x is the cause | see causes |
| 5 | `UNRESOLVED` | a sentinel or out-of-range reference | the reference |
| 6 | `PRIOR_FIT` | an `RT_FIT_FAILED` reference in the input | the reference |
| 7 | `FOREIGN` | a parameter leaf outside the declaration's binder | the leaf |
| 8 | `UNBOUND` | a binder parameter that the ENV leaves unbound | the leaf |
| 9 | `SLOT_PENDING` | a dependency-signature slot leaf | the leaf |
| 10 | `FIT_FAILED` | a constant projection does not fit its target | the `CC_CAST` term |
| 11 | `COUNT` | an array length that is not a count | the array term |
| 12 | `UNSUPPORTED` | a kind or a constant shape the canonical rules reject | the term |
| 13 | `DEPTH` | a type result would exceed the 64-level type graph | the term |
| 14 | `CAPACITY` | written only by an overflowed attempt; never published as a result | — |
| 15 | `INVARIANT` | an inconsistent store record (a NAMED head whose type-slot count or mask disagrees with its operands, a leaf whose constant bit disagrees with its parameter's domain, a binder slot of the wrong domain) | the term |
| 16 | `KIND` | an operand of the wrong kind: a non-type element or type operand, a non-value constant operand | the term; the failed value is the operand |
| 17 | `LIMIT` | a composed binder domain wider than the 32-slot ENV masks, or a NAMED term with more than 32 operands | the request ENV, or the term |

ENV causes (r2.x of an `ENV` result):

| Code | Cause | Failed node | Failed value |
| --- | --- | --- | --- |
| 1 | `NOT_ENV`: not a stored, closed `ENV` term | the request ENV | — |
| 2 | `OWNER`: owner word 0, or not the request's declaration | the ENV | — |
| 3 | `SHAPE`: a mask beyond the binder, or a wrong arity or type-slot count | the ENV | — |
| 4 | `BINDING`: a binding of the wrong class or constant scalar | the binding | the slot's parameter leaf |
| 5 | `EVAL`: the request ENV's closed evaluation failed; r2.y is its status and r2.z its ENV cause | the inner failed node | the inner failed value |
| 6 | `NONCANONICAL`: the request ENV's closed evaluation is a different term | the request ENV | the normalized ENV |

The failed environment is the task's environment: the request ENV, or 0
for a closed evaluation. Every request-ENV failure (`ENV`, `LIMIT`) names
the request ENV. `NOT_READY` and `DECL` of the request name 0. A
`FIT_FAILED` result's failed child value is the typed value that did not
fit. These words are store identities for later source mapping. The engine
writes no diagnostics.

The outcome of one request is chosen in a fixed order, never by timing:
the request's validation, then the request ENV's closed evaluation (`EVAL`,
then `NONCANONICAL`), then the term's own result.

## Publication contract

`run` returns `SubstitutionRun::Published(report)` only after a committed
attempt. `report.publication` is the `PublicationId`:

| Field | Meaning |
| --- | --- |
| `generation` | the store build (`ProgramRetention::generation`, `rt_counts[78]`) |
| `run` | the run that wrote the publication |
| `requests` | published rows |

Generations are nonzero and unique over every build of every store in the
process. Run numbers are nonzero and unique over every engine in the
process. `begin_build` takes a new generation and writes it to
`rt_counts[RT_C_GENERATION]`. Store growth copies the counters, so a
generation survives growth.

`RetainedSubstitution::publication(&store)` returns the current
publication, its id and its two buffers. It returns None after a run that
published nothing, after an error, after `begin_build` on the store, and
for any other store.

A GPU consumer imports `sb_consumer.slang`. It binds `sb_results` and
`sb_counts` read-only, the store, and the `run` it got from the same
`publication()` call. It reads a row's TermId only when
`sb_result_current(run, request)` holds:

- `sb_counts` says `PUBLISHED` in that run;
- `sb_counts`' generation is the bound store's current generation;
- the store is `READY`;
- the row is below the published count and its r1 carries the same run
  and generation.

So a consumer rejects results of an earlier build, of another store, of
another run in reused buffers, of a request-capacity or failed run, and an
old result buffer paired with new status words. An id and buffers taken
together from one earlier `publication()` call of the same build still
answer their own requests: committed terms are immutable and stay valid
for the whole build. A consumer that needs the newest results takes the
id again after each run.

## Validation

Each request is validated before it creates any task:

- the store's `READY` bit;
- the declaration: a valid `DeclId` whose committed entry names it, with
  state `COMMITTED` and no `INCOMPLETE` flag;
- the binder: at most 32 type and 32 constant slots (`LIMIT`);
- the ENV (`sb_check_env`): a stored, closed `ENV` term whose owner word is
  the declaration; masks within the binder's type and constant counts;
  arity equal to the mask popcounts; type-slot count equal to the type
  popcount;
- each bound slot: the binder's `ParamId` has the slot's domain
  (`INVARIANT` otherwise). A type slot is bound to a type: a scalar,
  `NAMED`, `ARRAY`, `SLICE` or `REF`. A constant slot is bound to a
  `CC_VALUE` of the parameter's declared scalar, or to a `CC_CAST` to it,
  which the ENV's closed evaluation then reports as `EVAL` or
  `NONCANONICAL`.

A partially bound ENV is accepted. A leaf whose slot is unbound returns
`UNBOUND` only when the term reaches it.

A parameter leaf binds by exact `ParamId`: the engine finds the ParamId in
the declaration's composed binder (at most 64 entries) and checks its
domain. An inherited impl parameter and a shadowing method parameter with
the same spelling are different `ParamId`s and bind to different slots.
The binding is a term in the receiving scope and is never substituted
again. A compound binding is still evaluated as a closed term.

## Evaluation rules

Each task checks the kinds of its evaluated operands. Every result is
closed, normalized and well kinded.

- **`NAMED`** keeps its words. Its type-slot count is its type-operand
  count, as the canonical builder writes it (`canonical_candidates`
  `build_row`), and its constant-operand mask has no bit at or past the
  arity (`INVARIANT`). An operand under a mask bit is a `CC_VALUE`, every
  other operand a type (`KIND`). At most 32 operands (`LIMIT`). The engine
  does not check the operand count or constant scalars against the
  nominal's own binder.
- **`ARRAY`** takes a type element (`KIND`) and its length's count class:
  a `CC_VALUE` length becomes `CC_COUNT(count)`
  (`constant_value_to_count`), and a value that is not a count (a negative
  value, a bool, a 64-bit value above 2^32) is `COUNT`. Equal counts of
  different scalars give one array identity.
- **`SLICE` and `REF`** take a type element (`KIND`).
- **`ENV`** keeps its words and is checked against its owner's committed
  binder with the same rules as a request ENV, except that a constant
  binding must already be a `CC_VALUE`. An owner word 0 is `ENV`/`OWNER`.
  An owner without a committed definition is `DECL`. A nested `ENV` (an
  inner call's environment in the callee's scope) becomes a closed,
  normalized `ENV` of the inner callee. This is the discovery step.
- **`CC_CAST(target; child)`** folds the child's typed value with the
  canonical rules (`ct_build_projection`). A child value that is not a
  count is `UNSUPPORTED`. This includes the count word `0xffffffff`, which
  the canonical store reserves for "not a count" (`ct_build_value`).
  `constant_value_from_count` folds the count into
  `CC_VALUE(target, count, 0)` or fails the fit (`FIT_FAILED`). Closed
  terms are evaluated too, so a result never contains a `CC_CAST`.
- Typed constants keep their scalar: `Boxed<5u8>` and `Boxed<5usize>` are
  two terms.
- A task's arguments are checked in argument order, and the first failing
  argument decides the task's failure. Its status, provenance and cause are
  copied from that argument's own result, so nested failures report the
  innermost failing node. Provenance never comes from memo contents, lane
  order or evaluation order: a later argument that fails at a lower level,
  and so is evaluated first, does not win.
- **Depth.** A type result whose height exceeds 64 returns `DEPTH`. This
  is the canonical limit: types intern in at most `CT_MAX_ROUNDS = 64`
  rounds, and `ct_match` descends one level below an interned type of
  height 64. An ENV is not a type and the canonical store does not hold it
  to that limit. Its height is one more than its tallest binding, and only
  the bindings are held to 64 levels. A type binding of height 64 is valid
  and its ENV has height 65.

## Work distribution

A task is one unique key `(environment, term)`. The environment is the
request's ENV `TermId`, whose owner word names the owning definition, or 0
for the environment-independent evaluation of a closed term. Each request
creates its term's root task and the closed-evaluation task of its ENV.
Requests with one ENV share that task. Leaves never become tasks: scalars,
arity-0 records, parameter leaves and sentinels are resolved in place on
the edge that reaches them. Tasks are interned in an open-addressing memo
(`sb_memo`) with full-key comparison. A lane writes its task record,
fences, then publishes it with a CAS. A lane that loses to an equal key
kills its record (counted in `SPARE_TASKS`). The hash only selects the
first probe, and `set_hash_mask(0)` forces every key onto one chain.

A task's level is `height(term) + height(env) - 1`, or `height(term)` for
environment 0. Every child task has a lower level: a child term is lower
than its parent, and a binding is lower than the ENV that holds it.

| Step | Lanes | Work |
| --- | --- | --- |
| 00 begin | 1 | refuse an oversized request count; open the attempt, save the store's term watermark and status words |
| 01 roots | one per request | validate; resolve the term and the ENV's closed evaluation to immediates or root tasks |
| 02 expand plan | 1 | frontier = tasks created since the last plan; plan `frontier × max arity` lanes |
| 03 expand | one per (frontier task, argument) | resolve one edge, creating the child task if new; a repeated argument shares the first occurrence's edge |
| 04 scatter | one per task | bucket live tasks by level (counts are kept at creation) |
| 05 eval plan | 1 | the next nonempty level |
| 06 eval | one per task of the level | check the operands' kinds, intern the task's result, or fail |
| 07 publish | one per request | choose each outcome; `CAPACITY` everywhere after an overflow |
| 08 finish | 1 | restore the store's status words; commit, or restore the store's term counters |
| 09 rollback | one per store term slot | clear slots of terms an overflowed attempt interned |

Work is O(tasks + edges) lane steps. An expansion lane also compares its
argument with the earlier arguments of the same task (at most 63), and a
binder search reads at most 64 words. An eval lane reads its task's
arguments, and an ENV task also reads its owner's binder (at most 64
slots). No lane walks a term DAG, a body or a table.

The dependency span is the number of expansion rounds plus the number of
nonempty levels. Both are bounded by the term height plus the
environment height, and each by the 256 task levels. Indirect dispatch
arguments make empty rounds dispatch no workgroups. The host records one
batch of `k` expansion rounds, the scatter, `k` evaluation rounds and the
end steps (`k` = 8). It submits the batch and reads the status words, then
records batches of `2k`, `4k`, … until the attempt is final. An attempt
that is not final after `2 × (256 + 1)` = 514 recorded rounds of each kind
lost its phase: the run fails closed (below).

Measured on the focused tests (this desktop's GPU, release build, host wall
time per run including readbacks):

| Fixture | Requests | Tasks | Edges resolved | Rounds (expand + eval) | Max frontier | Dispatches | Time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 40-level shared DAG (2^40 leaves as a tree), three equal requests | 3 | 41 | 44 | 40 + 40 | 6 | 498 | 6 ms |
| 4096 environments × 2 templates | 8192 | 49152 | 73728 | 8 + 9 | 16384 | 220 (4 attempts) | 5 ms |
| all contract cases (depth 64, 64-slot ENV, fits, kinds, nested ENVs, invalid requests) | 77 | 326 | 537 | 63 + 65 | 108 | 1014 | 11–12 ms |
| the same with tiny tables and a store with room for half the results | 77 | 326 | 537 | 63 + 65 | 108 | 1826 (5 attempts) | 23–38 ms |
| two exported jobs, requests from retained uses | 93 | 13 | 14 | 2 + 2 | — | — | — |

The ENV evaluation adds one task per distinct request ENV with a compound
record: 1 task for the DAG, 4096 for the 4096 environments. The
4096-environment run grows its task table three times from the default
16384 tasks. Its span is the template height, independent of the number
of environments. A 64-level chain needs about 128 dependent rounds, which
costs four batches, five readbacks and about 1000 recorded dispatches,
most of them empty. A run with no tasks costs 38 dispatches and one
readback (0.7 ms).

## Capacity, transactions and errors

An attempt is one transaction over the substitution's tables and the
store's term arena.

- Step 00 refuses a request count above the bound buffers' rows. It sets
  `STATE_REQUEST_CAPACITY` with the count in `REQUEST_DEMAND`, touches no
  store word and dispatches nothing.
- Otherwise step 00 saves the store's term and argument counters, spare
  counters, overflow word and term demands, then clears the overflow word
  and the term demands.
- Step 08 restores the saved overflow word and term demands on every
  outcome, after recording the attempt's own store overflow and demand.
- Any task, edge or memo overflow, and any store interning failure, sets an
  overflow bit. The planners then stop the attempt, step 07 writes
  `CAPACITY` for every request, and step 08 restores the store's term and
  argument counters and spare counters. It counts the term records the
  attempt allocated (`STORE_ROLLED_BACK`). Step 09 clears every term slot
  that points at or past the saved term watermark. Linear probing stays
  sound because every older key stopped at a slot that was occupied before
  the attempt.
- The host grows the overflowed tables. Its own tables grow to twice the
  recorded demand. The store grows through `ProgramRetention::grow` from the
  recorded store demand, which copies committed arenas and rehashes. The
  host then runs the attempt again over the same retained terms and
  requests. There is no frontend rerun and no replay. Every retry grows a
  table, and the attempt count has no cap below the device limits. An
  attempt that overflows without a table to grow is an error.
- A table larger than the device's storage-binding limit, and an expansion
  round wider than 2^32 lanes (`OVERFLOW_LANES`), are errors.
- **Errors fail closed.** Any host error during a run, including a
  readback failure, a lost phase or a device limit, clears the store's
  `READY` bit, clears the engine's publication and writes 0 to the `STATE`
  word. This mirrors an export error. The build cannot be used after it;
  the next build starts with `begin_build`.
- A committed attempt keeps the terms it interned in the store. They are
  complete records with exact identities, and they are dead after the next
  `begin_build`.

Allocations and pipelines persist across runs and builds. Every run clears
the memo and the status words. Nothing from an earlier run or build is
read.

## Tests

`cargo test --release --test compiler retained_substitution_ -- --test-threads=1`

- `retained_substitution_is_memoized_parallel_and_exact`: the shared DAG
  (exactly 41 tasks, 40 rounds each way, one result for three equal
  requests), 4096 independent environments (span ≤ 10 + 11 rounds, frontier
  ≥ 8192), and every contract case. Each failure checks its status, failed
  node, failed environment, failed value and ENV causes where they are
  defined. The cases cover:
  - depth 64 and 65, an ENV binding a height-64 type, a nested ENV over
    it, and a height-65 binding (`ENV`/`EVAL`/`DEPTH`);
  - a 64-slot ENV, a 32-operand application and a 33-slot binder (`LIMIT`);
  - count-class equality and typed-constant separation (`Boxed<5u8>` and
    `Boxed<5usize>`);
  - `u8`/`i8` fit boundaries, nested projections, and first-failing
    argument order with the first argument failing at a higher level;
  - `COUNT` and `UNSUPPORTED` for a negative i32, a bool, a u64 above 2^32
    and the u32 count `0xffffffff`, and an array of that count;
  - well-kindedness: a value as an array or slice element, a NAMED with a
    wrong type-slot count, a mask bit past its arity, a type under a mask
    bit and a value under a type position;
  - nested ENVs with a value in a type slot, a wrong constant scalar, owner
    0 and an owner without a definition;
  - request ENVs: a pending fit in a binding the term does not read
    (`EVAL`/`FIT_FAILED`), a fitting pending binding and a pending fit
    inside a type binding (`NONCANONICAL`, with the normalized ENV as the
    exact failed value), and every ENV and declaration rejection with its
    cause;
  - sentinels, a leaf whose constant bit disagrees with its parameter
    (`INVARIANT`), foreign, unbound and slot leaves, and
    inherited/shadowing parameters.
- `retained_substitution_grows_retries_and_resets_per_build`: tiny
  substitution tables plus a store with room for half the results, once
  with every store key on one probe chain and once with the full hash.
  Each run interns store terms in an attempt, overflows the store at a
  later level and rolls back (29 term records), then grows and retries
  (5 attempts, 3 own growths, 1 store growth). The results match the
  reference structurally, including failed environments and causes. After
  the run every term slot points below the term counter at a published
  record, no two published records are key-equal, the committed fixture
  terms are unchanged, and the store's overflow and demand words are back
  to their values before the run. The test also covers a repeated run,
  forced memo collisions, a fresh build in the same allocations, and a
  store that is not `READY`.
- `retained_substitution_publications_are_identified_and_fail_closed`: a
  short request buffer (`RequestCapacity`, store unchanged, earlier
  publication withdrawn) and the producer's rerun into grown storage; the
  GPU consumer check against a reused buffer with an older run, a
  replaced result buffer, another engine's run, another store and the
  store's next build; and a host error (a table above the device limit)
  that clears `READY` so the consumer rejects the remaining publication.
- `retained_substitution_instantiates_exported_foreign_templates`: two
  frontend jobs export, the frontend is dropped and the exporter scratch is
  poisoned. A GPU kernel turns each foreign generic use into requests for
  the callee's result, parameters, body rows and inner call environments
  and results. Every request succeeds and each callee result equals the
  caller's checked type. The inner environment of `identity` is
  `ENV(identity; U = i32)` for `wrap(7)` and `wrap(1)`, one TermId, and a
  different ENV over `Local<bool>` for `wrap(Local { .. })`. In `shadow`,
  `identity(self.value)` binds the impl's `T`, so its environment is the
  same `ENV(identity; U = i32)`, not one over the method's `bool`.

The synthetic programs are construction scripts run by a single GPU lane,
so every identity, including each expected result, comes from the store
interner. The host encodes only the script and the expected outcomes.

## Integration boundary

- Discovery must produce requests on the GPU, honor the producer contract
  above and consume publications through `sb_consumer.slang`. Slot leaves
  need discovery's dependency binder mapping before they can be requested.
- NAMED operands are not checked against the nominal's own binder (operand
  count and constant scalars). The frontend fixes them; a consumer that
  needs that check has to add it with the nominal's committed entry.
- The retention probe still calls `rt_subst`. Production consumers must use
  this engine.
- A store flag that marks terms containing `CC_CAST` would let closed,
  cast-free subterms skip their environment-0 tasks, including the ENV
  evaluation of a request. That is a store layout change and needs
  coordination with the exporter.
- The engine does not remove source replay. Replay deletion depends on
  discovery, projection and publication.
