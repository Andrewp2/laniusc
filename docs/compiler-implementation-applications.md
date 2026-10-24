# Imported generic implementation applications

**Status: the selected imported implementation applications execute in
GPU-compiled x86_64 Linux output. Buffered library adapters have separate
runtime admission. This is not a claim about all generic source expressions
or user GPU kernels.**

## The missing boundary

An imported generic helper such as `core::io::write_all<W>` calls a required
member on `W`. Program evidence can select `impl<T> Write for Forward<T>`.
The replay must carry that particular implementation's substitution and route
the required member to its method under that substitution.

The previous transport retained only a method target. The catalog omitted
generic implementations, and the host assigned zero type and constant
parameters to every retained target. A target identifies a declaration; it
does not identify an application of that declaration. Local receiver matching
cannot reconstruct authority that belongs to a different imported unit.

The retained failure and successful direct/local controls are in
`tests/fixtures/stdlib_compiler_state/foundation_admission/stream_forward_current/`.
They remain historical evidence, separate from the new admission fixture.

## Authority and data

An implementation application starts from one admitted source call and one
accepted evidence occurrence in that call's exact obligation span. Minting
checks its source, predicate, ordinal, environment, catalog, arena and retained
proof root. A same-shaped type or a proof of a similar goal supplies none of
those joins.

The GPU projects the selected implementation, its accepted parameter bindings,
prerequisites and any supporting assumption path. An assumption can refer to
earlier accepted evidence; requiring an implementation directly on the first
proof row would lose valid nested forwarding. The bounded walk checks exact
supporting evidence and decreasing proof rows.

The initial GPU lookup uses the exact obligation row in accepted output.
Host acceptance appends retained evidence after uploading that submission's
input, so its newest retained row need not exist in the GPU input yet. Earlier
assumption hops use their already uploaded retained rows. Both readers check
the same accepted call, obligation, predicate, environment and proof relation;
an extra proof submission is unnecessary.

Projection output has a private, request-bound receipt. Raw output can be
admitted only against the current projection state. Once admitted, the owned
application can survive monotone proof-store growth, as its retained proof root
does. A stale raw receipt and a valid older owned root have different rules.

Materialized types and GPU-normalized typed constants supply argument data.
They cannot create call authority. Prerequisite proofs remain provenance;
routing the method creates an ordinary checked call whose obligations are
admitted through the existing program-evidence path. No child proof is
promoted into fabricated root evidence.

## Replay transport

The private body binding packet uses a versioned header and three rows per
binding. Its key is `(entry, subject type slot, required member, trait unit)`.
Each binding carries the selected target, declaration receiver mode, declaration
arities and its complete type/constant environment. Multiple entries may name
one method target under different environments.

Type roots and constant roots use the existing shared checked graph. Constants
retain their scalar identity and both 32-bit value words. The shader publishes
the selected environment, context aliases, arities and callee together while
preserving the previously checked receiver plan. Declaration receiver modes
are `0..3`; mode 3 is a typed first parameter. Checked call adjustments are
`0..2`. Existing normalization maps mode 3 to value adjustment 1 for an admitted
dotted call, or adjustment 0 for an admitted qualified call. The transport does
not add receiver eligibility or reconstruct a receiver plan.

The CPU installs the table atomically. Exact duplicates can collapse; conflicting
contracts for one key fail. Both CPU and GPU reject malformed versions, counts,
spans, slots and root domains. Capacity overflow is an error. Tables are never
silently truncated.

Every job rewrites the two-row header. Used bindings, environments and argument
references upload as separate prefixes, so ordinary jobs do not upload the
unused fixed-capacity pools. Direct nongeneric implementations retain a path
that requires no implementation-projection dispatch.

Current protocol limits are 8,192 body bindings, 8,192 environments, 32,768
argument references, and 32 parameters per domain. Shared graph limits remain
1,024 nodes and 16,384 edges. A projection batch holds at most 64 requests and
64 bindings per application, with bounded prerequisite and assumption pools.
These are compiler capacities, not standard-library API guarantees.

## Publication and cache reuse

Each replay entry retains its owned implementation applications. Before
frontend execution and native publication, validation checks the exact origin,
entry, subject slot, trait/member, target, receiver and environment transport.

Cache hashes support lookup. Reuse also requires an exact immutable per-entry
contract containing source ownership and semantic implementation bindings.
Fresh accepted applications must authorize that contract. Native layouts are
separate GPU witnesses, including types that occur only inside a selected
implementation's environment. One shared-node readback obtains both ordinary
entry and implementation-environment witnesses.

## Focused acceptance

The `compiler_generic_impl_forwarding_execution` driver exercises
direct/local controls, imported and nested forwarding, short progress,
interruption, error progress, explicit flush, distinct same-layout owners,
typed constant applications and changed payload layouts. Missing and unrelated
bounds must reject at their source calls. A successful compile alone is not an
execution result: positive cases must produce strict-checker-accepted x86 ELF
and pass native value, alias and trace assertions.

Private protocol tests cover malformed receipts and tables, conflicting
contracts, retained roots, entry/environment swaps and cache-contract failures.
The normal shader instruction and local-memory budgets remain acceptance
gates. Broader GPU suites are not part of this focused admission.

Method-owned generics, nonempty inherited implementation scopes, symbolic
applications and foreign or incomplete applications remain explicit rejection
cases for this projection boundary. Their rejection must not be converted to
a nongeneric fallback. Buffered stream APIs have separate runtime admission;
these compiler gates do not establish their behavior.

## Accepted evidence

The final focused CPU gate passes **45 tests** in 0.51 seconds, including
aggregate capacity splitting, atomic rollback, exact cache contracts, typed
constant identity and declarations-only binding/layout reordering. The GPU
lineage gate passes in 1.84 seconds. It checks initial projection before the
new retained rows are uploaded, sibling/foreign evidence rejection, stale raw
receipts and retained application validity through later accepted growth.

The stream gate passes **seven compilation jobs and four native executions**
in 7.97 seconds. Missing Read, missing Write and unrelated-owner bounds reject
with source-local `LNC0008`. The repeated behavioral program follows those
rejections in the same compiler process. With
`LANIUS_CHECK_LIBRARY_INSTANCE_CACHE=1`, an observed two-body cache hit equals
fresh replay, including code, calls, contracts and layouts.

A separate constant gate passes one compilation and one native execution in
2.50 seconds. Values `4294967297` and `8589934593` have identical low words;
both complete values, different generic payload layouts, static mode-3 member
dispatch, source aliases and returned-copy independence pass native assertions.
Every executable passes the shared strict x86 checker and exits zero with
empty stdout/stderr. These are eight compilation jobs and five native runs
across the two tests.

One adjacent GPU materialization gate passes in 2.28 seconds. Eight roots use
eight distinct physical scratch buffers; a later one-root query retains those
same eight identities. Rejecting a 65-root query adds none. Production policy
bounds retained query work to 20,794,752 GPU bytes per controller, excluding
host plans/readbacks and other compiler buffers.

Normal shader budgets pass without changed limits:

| Kernel | Fully inlined instructions | Limit | Local array bytes |
| --- | ---: | ---: | ---: |
| Implementation application projection | 16,687 | 40,000 | 0 |
| Bound-member routing | 15,953 | 40,000 | 0 |
| Replay graph seeding | 2,421 | 40,000 | 0 |

The 918-SPIR-V manifest has SHA-256
`455fcd353d3e883a50b2e6f9c113fe1ab1c50974350f276b1eed9c8da78cfaca`.
Logs, binary hashes and source captures are under
`target/stdlib-work/implementation-applications/`. The scratch gate precedes
the independent initial-evidence reader repair; its materializer is unchanged.
These timings describe focused checks, not a compiler-throughput benchmark.

The original nested expression `W::echo(source.payload())` inside a generic
record field reported `LNC0006`; its
[source closure and diagnostic](../tests/fixtures/stdlib_compiler_state/implementation_application_static_result/README.md)
remain a dependency. The accepted constant program uses explicitly typed
symbolic locals. No concrete-type overload or constant substitution replaces
the generic application.
