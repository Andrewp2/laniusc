# Archive namespace planner execution fixtures

These fixtures execute the actual pure `ext::archive_plan` module. Both focused
filters have native x86_64 Linux acceptance, across separate invocations. They
do not parse archives, create filesystem entries or establish extraction safety
by themselves.

The exact filters in `tests/extended_archive_plan_execution.rs` are:

- `namespace_model_paths_limits_and_sticky_failures_execute`
- `reserved_storage_allocation_failures_release_partial_plans`

`contracts.lani` checks owned path copying from an offset/strided input view,
stable borrowed views across later adds and implied-directory upgrade, dense
explicit entry order, all read bounds, idempotent seal/destroy and poison after
post-seal use. It covers malformed raw names, both ancestor-conflict orders,
explicit duplicates, invalid ordinal, independent limits and exact fits.
Small known work counts check add `a` = 9 units, first seal = 1, exact success,
one-below failure and sticky no-work replay. Invalid constructor limits and
empty zero-storage plans are included. Its trace must release every source
mapping with the original address and requested size.

`model.lani` consumes a test-only binary sequence and emits actual operation
results plus the final public node/path/component/order descriptors. The Rust
oracle uses a BTreeMap keyed by complete canonical byte prefixes, independently
of production parent/component scanning and work metering. The 76 authored
plans cover raw non-UTF-8 bytes, case-sensitive identities, file/directory
duplicates, malformed names, capacity edges, ordinal errors, and reproducible
varied trees with later conflicts. After each rejection, further calls must
repeat its original kind/ordinal/offset with unchanged namespace and work.
The shared input backing is overwritten between adds, testing independent
owned copies. Every final public field and raw path/component is compared;
success requires seal, while poisoned plans remain uncertified.

`allocations.lani` reserves all three nonempty capacities, adds an implied
directory/file then upgrades the directory, seals and explicitly destroys.
The successful trace must show exactly three mappings and their releases,
with no add/seal growth. Its output reservation must equal the sum of actual
requested mapping bytes. Each of the three reached allocation requests is
then denied with ENOMEM; source instruction, complete request and prior request
prefix must match the accepted baseline. Status 4, no stdout and exact release
of every earlier successful owner are required. The mapping ledger rejects
unknown/double releases, mismatched sizes, unreached failures and live owners.
It does not use process exit to release planner storage.

The production compiler writes each ELF through the unchanged shared strict
ELF/jump checker. Individual product runs have explicit 10- or 15-second
timeouts. Source is Lanius; the Rust namespace implementation is an independent
test oracle, not a library fallback. Generated binary frames are fixture data,
not a production archive format or transport API.

## Accepted receipts and hashes

Receipt paths are under `target/stdlib-work/`:

| Receipt | Accepted scope and invocation result |
| --- | --- |
| `archive-plan-and-zip-drivers-build.log` | Two shared test drivers built successfully in 1.45 s |
| `archive-plan-first.log` | Four allocation processes passed, including all three reached source ENOMEM positions. The namespace filter failed at model admission after direct contracts passed. The 11.29 s is the total mixed invocation, not an allocation-only duration |
| `archive-plan-model-import-retry.log` | Namespace filter passed in 10.10 s: direct contracts plus 76 independent namespace model cases |

The first model compilation failed with `LNC0007` at `model.lani:25:45`: the
qualified Result type needs a direct `import core::result;`. Only that fixture
import changed before the accepted retry. The planner, Rust driver, contracts
and allocation fixture were unchanged. Allocation acceptance was retained,
without rerunning its filter. The 76 namespaces are evaluated in one model
process; they are not 76 process invocations or a synthetic aggregate timing.

| Source | SHA-256 |
| --- | --- |
| `extended/ext/archive_plan.lani` | `6eaeedc3d55da398812459b10838952b46075d645cde952b5ccf8752538d3c3e` |
| `tests/extended_archive_plan_execution.rs` | `60645802895adf8c1756f400e8e18b8c23ea4d0bbb7d49c8f80d0f9f267c5bda` |
| `contracts.lani` | `84cdf55d17216b2624043c49ec3ae26787a7bc8b139ebfd22027154bcb66f648` |
| `model.lani` | `6520883693d78af7af3c2f10e996a6bea9e4bad920cabbe29d66defbc1d2ac84` |
| `allocations.lani` | `f37b9fded7901edff5f7d9f1e22155a1ea19df34c724afbc0c549683b0ad6074` |

| Retained native ELF | SHA-256 |
| --- | --- |
| `/tmp/laniusc_archive_plan_contracts_lani_328072_0` | `97f4b04f6a08187bb6ad0ca5790e5164822b24814f1fcf4699173d7529585cc9` |
| `/tmp/laniusc_archive_plan_model_lani_328072_3` | `bc365c609e3e3421f95cc17edf9d687e64f7243a91553fe8bda6809d020dd773` |
| `/tmp/laniusc_archive_plan_allocations_lani_326901_3` | `38a79b440e9b0a3b16de9887266fa27802cc3f060f9db64c90ea77234a9048e6` |

Logs and retained ELFs are local artifacts. These receipts establish this
finite native host planner profile, not GPU-kernel execution, another target,
archive parsing or filesystem materialization.
