# Bidirectional iterator contracts

These fixtures import the actual standard library. Production iterator logic
is never replaced by a Rust or Python library implementation.

- `contracts.lani`: five allocation-free scenario functions for arbitrary-width
  nested values, full i32 endpoints, generic trait dispatch, reverse copies,
  source/callback order, mixed Chain ends and aliased Chain inputs.
- `extra_contracts.lani`: four focused scenarios for Some(None) FilterMap items,
  compound Map results, exact empty-child Chain transitions, packed/strided byte
  subviews and zero-sized Unit array items.
- `collections.lani`: four scenarios for borrowed/owning Vec, deque and ordered
  map/set leaves. Three String owners transfer and recover explicitly after
  abandoning Rev. Seven actual backing allocations are expected, with balanced
  address-and-size releases; adapters neither clone nor destroy nested owners.
- `model.lani`: six-u64 binary records select eleven source/adapter compositions,
  partial source consumption and mixed front/back schedules. Each response
  includes optional output, remaining source counts and successful pull/callback
  events. EOF child-call policy is checked separately by the contract fixtures.
- The two rejection files require an actual `rev` call to reject a forward-only
  source or a mismatched backward item type.

`tests/stdlib_reverse_iterator_execution.rs` compiles and executes the producers.
Its independent Rust oracle uses VecDeque remaining sequences for all five-pull
schedules and selected longer schedules, including empty Chain sides, reversed
chains, backward filtering/mapping, partial views/ranges and double reversal.
It does not mirror the production cursor or Chain state fields.

## Executable acceptance

All four registered runtime gates pass on Linux x86_64, with raw native programs
compiled from these Lanius sources by the GPU compiler. The four gates were run
in two filtered invocations, not one unfiltered suite run. Local logs are under
`target/stdlib-work/`:

| Log | Executed scope | Time |
| --- | --- | --- |
| `reverse-model-rust-first.log` | One registered model test; all **7,740 commands** match the independent Rust remaining-sequence and callback oracle in one native process | 9.40 s |
| `reverse-contracts-rust-formatted.log` | The other three registered tests: both allocation-free contract producers, collection owner recovery with all seven address/size-balanced mappings, and both actual-call LNC0008 bound rejections | 11.74 s |
| `reverse-timeline-driver-build.log` | New reverse and timeline drivers build with `--no-run`; this build-only receipt is separate from the runtime results above | 1.97 s |

Accepted producer SHA256 values:

| Producer | SHA256 |
| --- | --- |
| `contracts.lani` | `5c682a0548aae73c8b78e699d630075292d79bf0ee035f830e3e695e540cc920` |
| `extra_contracts.lani` | `9f6ac75aa1fa873530e340239b7841499be5dda998b6148a2654b7e78fbdc84e` |
| `collections.lani` | `bea024ff166fecf49b84188e55cddba844d5fc9431561a0ffec7d43dfc93f502` |
| `model.lani` | `7647a0e951da163a210b5f1b5a5aaa8c98055592475979e97fd54e1594b4f422` |

The successful contract producers have empty stdout/stderr. Their empty
allocation traces establish that these exercised constructors, adapters and
callbacks do not allocate. The collection gate observes seven successful
allocations and seven matching explicit releases; it does not inject allocation
failures. The model compares binary output with an independent oracle; it does
not claim an additional allocation-trace campaign.

No arbitrary callback termination, compiler-enforced borrow checking, automatic
destruction, formal proof, other target support or user-program GPU execution is
claimed. These are finite behavior tests, not proof of all possible iterator
implementations or schedules.
