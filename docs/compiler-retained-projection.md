# Retained instance projection

Retained projection turns closed instances of retained generic templates
([program retention](compiler-program-retention.md)) into native x86 object
code. It substitutes each instance's row, signature and use terms with the
[retained substitution](compiler-retained-substitution.md) engine, realizes
layouts on the GPU, projects the rows into the existing lowering inputs and
runs the existing lowering pipeline. It never runs a frontend, never lexes or
parses instance text and never calls source replay. General compilation does
not use it yet.

This document is the boundary contract. Implementation status and test
receipts are at the end.

## Producer contract

Discovery (or a test producer) writes three GPU buffers and owns them. The
host never writes a row of them.

### Instance records, `pj_instances`

Two uint4 per instance, indexed by **rank**. Ranks are dense, `0..count`,
and are the final deterministic order (declaration keys, then structural
environment order). Rank is the native instance symbol:
`(NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank)`
(`codegen/x86/finalize.rs`).

| Word | Contents |
| --- | --- |
| q0 | `(callable DeclId, closed ENV TermId, generation, flags)` |
| q1 | `(first route row, route count, 0, 0)` |

- The instance identity is `(DeclId, ENV)`. The ENV is a stored, closed,
  normalized `ENV` term whose owner word is the DeclId, the form the
  substitution engine accepts and publishes. Two ranks with one identity are
  rejected (`DUPLICATE`).
- `generation` is the store build generation (`rt_counts[78]`).
- `flags`: bit 0 `ENTRY` marks the program entry instance. An entry has no
  parameters. This exists for tests whose program root is an instance.
  Production roots are original objects whose provisional use symbols the
  GPU finalizer rewrites.
- The callable must be a committed, complete `FREE_FN` with a body segment.
  Only generic bodies have a segment
  ([program retention](compiler-program-retention.md), "Nongeneric bodies"),
  so the instances are generic instances. A use inside a nongeneric body
  whose environment is closed is a discovery root.
- Projection does not depend on the rank order. Errors are reported in
  (rank, row) order, so a producer with a deterministic rank order gives a
  deterministic first error.

### Routes, `pj_routes`

One uint4 per `(instance, use)`, at `q1.x + use ordinal`. The use ordinal is
the use's index in the callee's use block (`rt_dir` d2.w .. + d3.x), which is
also the body row's `r3.y`. `q1.y` must equal the block's use count.

`(library, namespace or unit, local, generation)`, the finalizer's route-row
format:

- an instance: `(NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank, gen)`;
- an ordinary `DeclNative` callee: `(library, unit, local symbol, gen)`,
  which must equal the callee's declaration key words `(x, y, w)`;
- a use that is not a call (record literal, constructor):
  `(0xffffffff, 0, 0, gen)`.

Projection validates every route of a call before publishing: generation,
range, and identity. An instance route must name a rank whose DeclId is the
use's callee and whose ENV equals the use's ENV substituted under the
caller's ENV (exact TermId). Each argument's substituted type must equal the
target's substituted parameter type, and the call row's type must equal the
target's result type. Exact closed types imply equal argument and result
ABI. Projection never chooses a target or a fallback. Bound-member uses need
a route from the trait solver's evidence; projection checks the route the
same way and does not select an implementation.

### Readiness, `pj_readiness`

One uint4 `(generation, flags, instance count, route count)`. Flags bit 0
routes published, bit 1 ABI certified by the producer. Projection requires
bit 0, checks the generation and the counts against the buffers, and
performs its own signature check (above) regardless of bit 1.

The GPU validates this header even when the instance count is zero. A
count larger than its buffer returns `INPUT_CAPACITY` before substitution
or lowering (detail 1 for instances, 2 for routes). The producer must grow
its buffers and rerun; projection never accepts a truncated prefix. A
current, ready header with zero instances produces no objects.

## Stages

All semantic work is GPU lane work. The host allocates, records, submits and
reads three compact status records: the plan totals, the check status with
the first error and batch maxima, and the batch table. It reads no instance,
term, row or route.

| Kernel | Lanes | Work |
| --- | --- | --- |
| `00_plan` | one per rank | validate readiness, the record and the directory entry; insert the identity; write the rank plan and counts |
| `01_scan` | one workgroup | exclusive scan of rows, tokens, seven side tables and requests |
| `02_requests` | one per request | `(DeclId, ENV, term, tag)`: result, parameters, rows, use environments, use results |
| substitution | engine | `RetainedSubstitution::run`; capacity overflow retries inside the engine |
| `03a_layout_init`, `03_layout` × 32 | one per TermId | closed nominal struct layouts and the lowering type tables, indexed by TermId |
| `04a_rows_init`, `04b_edges` | one per global row | clear row facts; expression parents |
| `05_check` | one per global row | forms, types, literal, operator and destination rules, calls, record literals, members |
| `05b_report` | 1 | first error in (rank, row) order, or CHECKED |
| `06_batch_plan` | one per batch | rank range, rows, tokens and side tables of each batch; maxima |
| `07_rows`, `08_side`, `09_batch_finish` | one per batch row / side row / 1 | lowering HIR and semantic columns, lowering counts |
| lowering | existing pipeline | `GpuCompiler::lower_projected_x86_batch`: semantic LIR, optimization, x86 object |

Every rank is checked before any batch is projected, so a rejected run
publishes no object. A batch holds the ranks whose first global row is in
`[b × batch_rows, (b + 1) × batch_rows)`. Instance rows are contiguous in
rank order behind one root row. Every call, also inside one batch, is a
dependency symbol call to the route's identity, so a call names the same
symbol in every batch, and the linker resolves calls across batches.

The host driver is `type_checker::program_retention::projection::RetainedProjection`.
`run(compiler, store, inputs, options)` returns `Objects { objects, report }`
or `Rejected { error, report }`. `ProjectionError` carries the code, detail,
rank, DeclId, body-relative row and token, file id and file-relative byte.

## Supported forms

v1 projects free functions whose bodies use: parameters, `let`, `return`,
`if`, `while`, `break`, `continue`, assignment, unary and binary operators,
integer, float and boolean literals, names of locals and parameters, member
reads of nominal structs, struct literals and direct calls. Types are scalars
and closed nominal structs whose fields are scalars, closed structs or the
struct's own type parameters.

Every other form fails closed with its template location:

| Form | Error |
| --- | --- |
| enums, `match`, patterns (role PATTERN) and bound rows (role BOUND) | `ROLE` or `FORM` |
| arrays, slices, references, strings, index expressions, `for`, `?` | `FORM` or `TYPE` |
| methods, receiver adjustments, intrinsics, host calls, constructors, function references | `USE` |
| constant generics, constant values of rows | `FORM` |
| a use whose recorded result is not a stored term | `USE` (detail `0xfffe`) |

## Root obligations

| Obligation | State |
| --- | --- |
| Pattern rows are not constructor uses; enum instances are reached from signature, parameter, scrutinee and row terms | Enums and `match` are rejected (`FORM`, `ROLE`). The producer reaches instances only through DIRECT uses. |
| A nested pattern's matched type is the enclosing payload's schema-substituted type | Not implemented; patterns are rejected. |
| Substitute u1.z/u1.w under the instance ENV and validate the adjustment | Not implemented; any receiver adjustment or METHOD use is rejected (`USE`). The receiver contract to port: `enter`/`read`/`peek` borrow mode 2, deref 1; by-value `(2, 0)`; twice borrowed `(2, 2)`; consuming self `(1, 0)`. |
| r3.y is a predicate ordinal only when r3.z is BOUND (4), a use index otherwise | Implemented in `05_check` and `07_rows`. |
| The accepted call result (u1.y, `67555902e`) | `05_check` requires u1.y to be a stored term, and its substitution to equal the row type and the target's result. |

## Gaps

- **Original objects.** Nongeneric bodies keep no segment. Their own jobs
  lower them, so a program whose `main` calls an instance needs the original
  object and the GPU finalizer's route rewrite. The slice test makes the
  projected `start<u8>` the entry instead.
- **DeclNative routes** (calls from an instance to a nongeneric function) are
  checked (declaration key, closed signature) but not linked in a test.
- **Trait routes.** The catalog publication (`docs/compiler-retained-trait-catalog.md`,
  "Publication") gives a goal call its impl method DeclId and bindings.
  Discovery must intern the ENV and write the route; projection rejects
  METHOD uses until receivers are ported.
- **Float literal status.** Only f32 overflow is detected; the frontend's
  other float statuses are not retained.
- **Lowering retry.** `lower_projected_x86_batch` retries once at the
  lowering's output demand. No test forces that retry.

## Receipts

`cargo test --release --test compiler retained_projection:: -- --test-threads=1`
(5 tests) under the GPU validation lock:

- `retained_projection_executes_two_unit_program`: two units retained, the
  frontend released and its scratch poisoned. The test producer finds the
  root `start<u8>` and instances `swap<bool>`, `scale<i32>`, `keep<u32>` and
  `keep<i32>`. The program uses `PairA {i32, u32}` and `PairB {u32, i32}`, the
  private generic `keep` and private `Hidden<T>`, an f64 value, contextual
  literals and instance routes. It exits 7. The fallback counters
  (`compiler::fallback_counters`) show no frontend check and no replay
  lowering during projection and link.
- `retained_projection_batches_retries_reuse_and_staleness`: `batch_rows`
  16 gives 4 objects with cross-batch calls, and exits 7. A tiny substitution
  capacity takes 3 attempts with 2 growths. Identity mask 0 puts every
  identity on one chain. A new store build rejects the old records with
  `READINESS`. The same projection then lowers an unrelated program
  (exit 6).
- `retained_projection_rejects_instance_rule_violation`: the retained
  literal of `v + 37` in `bump<T>` is rewritten to 300. The run is rejected
  with `RULE` / `INTEGER_RANGE` at the byte of `37`, and no batch is lowered.
- `retained_projection_rejects_truncated_and_unready_inputs`: excess
  instance and route counts, missing readiness and stale empty inputs
  reject before substitution. A valid empty input returns no objects.
  With the old count clamp, the excess-instance case published the valid
  resident prefix and failed the test.
- `retained_projection_oracle_columns` captures the frontend's lowering
  columns for a matching program; it fixed the column defaults.

## Costs

The two-unit slice: 5 instances, 90 rows, 117 requests, 1 batch.

| Figure | Value |
| --- | --- |
| projection dispatches | 44 (plan 2, requests 1, layout 33, rows and check 5, batch 3) |
| substitution dispatches | 38 |
| host readbacks | 3, 560 bytes |
| allocations | 8, 1.8 MB (first run) |
| plan / substitution / check | 0.6 ms / 1.0 ms / 2.7 ms |
| lowering of the batch | 45 ms (the first lowering job of the process) |

Work is O(rows + requests + terms × 32 layout rounds). The span is the
substitution's term height plus 32 layout rounds and two tree walks of at
most 256 steps per row. Memory is O(ranks + rows + TermIds) for the check
and O(largest batch) for the lowering columns.
