# Unsupported applied where subject in the ownership fixture

The isolated parser cause was **unsupported fixture syntax**. The canonical
`grammar/lanius.bnf` defines `where_predicate` as an identifier followed by a bound
list. An applied type such as `Make<J>` is not a permitted subject. The fixture
now borrows its concrete caller-owned mapper through a bare generic `M` bound.
No compiler change or arbitrary owning-generic failure is claimed.

## Retained controls

`original.lani` preserves the first full failing fixture, not a minimal input.
`applied_bound.lani` and `generic_bound.lani` are the minimal rejected/accepted
pair. The additional positive `concrete_mapper.lani` rules out the deep concrete
trait argument alone. All small controls have return-zero main bodies; they
establish declaration admission, with **no native execution or resource claim**.

| Retained source | SHA-256 | Compiler result |
| --- | --- | --- |
| `original.lani` | `ff7df4af164af5335a6386a4806bbc8ce8d871a5e9c7a6eed8d6a9af421fa343` | GPU parser code 4/final stack depth -4; 56,400 steps; no native emission |
| `applied_bound.lani` | `852f0efa3a5a86da9331923f4f0c1e851661fbb034804c091144a63f44a36413` | Same parser code/depth; 368 steps; then fallback LNC0008 |
| `generic_bound.lani` | `abbcedaf2978bd6f1adf26335b21adbebd638ad6af53508e6dac40f87361d9e9` | Compiled |
| `concrete_mapper.lani` | `835896e9887b881796672f36105c10f5443bb3acce5bbe1c5dbf556a20f61f40` | Compiled |

Logs under `target/stdlib-work/` are respectively
`nested-owners-lifecycle-first.log`,
`nested-owner-control-applied_bound-first.log`,
`nested-owner-control-generic_bound-first.log`, and
`nested-concrete-mapper-first.log`. The declaration controls used CLI `1c2718d4`
and current `core::iter` source `7256a394`. The original host fallback labelled a
concrete Mapper argument at line 224 (LNC0021); that label did not identify the
actual unsupported where subject.

## Reduction observations

These intermediate source controls were removed after isolation. Their logs and
hashes retain the observations; no unrun control is treated as evidence.

| Intermediate source hash | Observation | Log under `target/stdlib-work/` |
| --- | --- | --- |
| `769e917962be13764ee01989d77b39ad864141ecc9e65b8025494d00d37c0628` | Generic closing angles separated; same code/depth/steps, 3.81-second failed gate | `nested-owners-lifecycle-separated-angles.log` |
| `a0cf55b815deb7bf689917349142110e3c419800bd146425b8bf00bf7e444214` | Only main elided; same depth -4, 52,954 steps | `nested-owner-control-main_elided-first.log` |
| `81e894fc694a403e7649ea381de376015a11c9ee8e5b399d9ad21b908663bfc2` | Four nested generic dummy calls compiled | `nested-owner-control-four_nested_calls-first.log` |
| `208d95b4157fea4964257eb92f8d630438f47784352a8c6d6c03a31c083ff87f` | All 55 function bodies elided; same depth -4, 6,170 steps | `nested-owner-control-bodies_elided-first.log` |
| `633aef0bee37edd752c24a0b8681b39fa9d6f95072e8ab1f9c19e9c31508992c` | Actual local CursorOwner trait and both concrete cursor impls compiled | `nested-owner-control-cursor_owner-first.log` |

The closing-angle spelling, main calls, function bodies and local CursorOwner
implementation were therefore ruled out. Prepared but unrun generic-header and
imports-only alternatives were removed and establish no result.

## Fixture corrections and current acceptance

1. Source `3d44d59621d101c2de2dd56a6f296e904df4bf082085dc9bd1da9ce0b84c88e1`
   changed `run_map` to `<J,M>(...,mapper:&M,...)` with a bare M bound. The concrete
   `Make<Vec::IntoIter<String>>` or `Make<Deque::IntoIter<String>>` lives in the
   caller's selected branch through the synchronous helper. Parsing passed;
   source-pack typechecking then rejected the inferred cursor result at
   `found.is_none()` in `deep_inner` (CallMismatch token 1658/detail 332).
   `nested-owners-lifecycle-generic-mapper.log` records the 4.44-second failed
   pre-native gate. This is a separate source-admission result from the parser.
2. Source `e92ee3b894a6ce93eafed81a217ef9f04dd5dcf610239ea1c8cb503a608fdfc4`
   adds explicit J cursor locals and canonical Option result annotations. The
   actual mutated local is reinstalled before wrapper reuse or retirement;
   deep cleanup consumes/finishes only its transferred local. It compiled and
   reached native checkpoints. No owning type, callback order or resource scope
   was narrowed. The combined correction admits this fixture; it does not prove
   annotation alone fixed every possible inference shape.
3. `nested-owners-lifecycle-typed-cursors.log` is a mixed 8.66-second failed Rust
   gate: compilation/native checkpoints succeeded, then an oracle count wrongly
   equated lazy flat-map's two constructed inners with flatten's prebuilt three.
   Oracle `eb37f142` corrects only that model and adds four CPU regression controls;
   the source and strict live-resource/fault checks are unchanged.

The corrected executable was retained as `target/stdlib-work/nested-public-owners.elf`,
SHA-256 `3d99ec693eee833df297e5201e992210761845707a21ce00f7d176bc58b7d32c`.
All four **direct Python oracle** groups now pass against that exact native ELF,
including 132 individually reached allocation failures. Exact case scopes,
receipts, source/oracle hashes and the separate 41 CPU controls are in the
[ownership fixture guide](../../stdlib_execution/nested_iteration_owners/README.md).
This is not a claim of four passing Rust tests or a broader compiler repair.
