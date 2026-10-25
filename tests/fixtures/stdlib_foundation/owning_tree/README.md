# Owning ordered-tree fixtures

These sources belong to `tests/stdlib_owning_tree_execution.rs`, using the
production stdlib and this directory as a durable user root. All four groups
passed on native Linux x86-64 using the GPU compiler on 2026-10-25: five
compilation jobs, five strict-checked ELF programs and five native process
runs. User programs execute on the CPU; no Wasm or user-program GPU execution
is claimed. The [module guide](../../../../docs/stdlib-owning-tree.md) records
the API, ownership and complexity contracts.

- `contracts.lani` checks mixed front/back pulls, source reuse, holes and spare
  capacity, exact stored representatives, rejected finish, O(1) recovery,
  recovered insert/remove/free-list reuse, repeated disarm, retained empty
  backing, imported Iterator consumers, no-Ord key types and empty/ZST cases.
  Eight explicit backing reservations are asserted.
- `strings.lani` transfers real key/value owners, reuses reset sources,
  releases remaining cursor resources, then reads and grows the independent
  yielded String owners. Exactly 18 allocation generations are asserted.
  `helper_only_strings.lani` releases map/set remainders through the deep
  helpers without caller finish-result projection, with eleven allocations.
- `transfer.lani` uses ordinary map/set fallible sinks. Duplicate rejection
  preserves the accepted prefix and returns the supplied owner; resumption
  consumes exactly the next remaining entry. Each pre-reserved phase has six
  allocations followed by six releases, with the rejected String released
  after all cursor/sink resources. No transfer step allocates.
- `model.lani` checks 192 paired owning map/set operations and 32 complete
  ordered recovery snapshots per engine against Rust BTreeMap. It recovers
  valid current trees, inserts/removes through existing AVL operations, and
  finally drains every representative. The only allocations are the two
  initial capacity-512 reservations. At least 145 keys remain during the
  mixed loop, followed by explicit exhaustion/finish checks.

The address/request-length ledger checks all 51 allocation generations across
the five native runs, rejecting unknown/double releases and leaked owners.
Cursor pulls use canonical O(log n) endpoint removal; recovery transfers
current valid tree/free-list state in O(1). The fixtures implement no Node
layout, balancing logic or raw schema reinterpretation.

## Acceptance receipts

Logs under `target/stdlib-work/` are:

| Receipt | Scope | Elapsed |
| --- | --- | ---: |
| `owning-tree-contracts-first.log` | One typed contract group / one native entry | 5.77 s |
| `owning-tree-owners-model-transfer.log` | Remaining three groups / four native entries | 15.02 s |

Times include compilation and verification, not isolated operation benchmarks.
These receipts cover the library family and these fixtures. Application
migration tests have separate evidence.
