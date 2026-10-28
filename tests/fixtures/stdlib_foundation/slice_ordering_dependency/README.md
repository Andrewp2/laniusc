# Distinct comparison trait applications on one receiver

The first slice-ordering contract compile reports `LNC0027` at the second
`compare` implementation on `RecordOrder<T>`. The two implementations have
different complete trait arguments: `Comparator<Record<T>,Record<T>>` and
`Comparator<Record<T>,Lookup>`. The diagnostic describes equivalent duplicate
methods despite those distinct applications. Its receipt is
`target/stdlib-work/slice-ordering-contracts-first.log`; the original complete
producer is preserved as `full_contracts.lani`.

`same_receiver.lani` reduces the shape to a local `Compare<L,R>` trait and one
generic `Policy<T>` with both implementations. It imports no library module.
`split_receivers.lani` gives the two implementations different receiver types
while retaining the same method bodies, generic dispatch helper and borrowed
counter. Both programs check ordinary record comparisons and heterogeneous
lookup with compound records, full-width unsigned words and signed extrema.

The live contract uses separate row/key callback receivers sharing one policy.
This changes no library signature: the public APIs retain general
`Comparator<T,K>` bounds. It supplies no evidence that multiple trait
applications with different method names, receivers or argument shapes fail.
No compiler implementation is changed here.

## Frozen source identities

| File | SHA-256 |
| --- | --- |
| `full_contracts.lani` | `1e543ee5b5768b81a1659aa07fead0db982eb1cbc31b60eb048c90f55eba5794` |
| `same_receiver.lani` | `0e92a3c1f0778890b9b995c84b62c9b2cb8485a9ec982ce33ee5eb98bdbbaf0d` |
| `split_receivers.lani` | `b8ce37291489f5055981aa765a7056ad4930dd5b3cf553aa7a37bcedef446a6e` |

## Verification status

Both focused driver tests passed in **2.92 seconds**. The receipt is
`target/stdlib-work/slice-ordering-dependency-first.log`.

- `same_receiver.lani` independently reports `LNC0027` on line 27 at its second
  `compare`: “duplicate inherent methods have equivalent receiver patterns.”
  The local trait has distinct complete argument applications, and the source
  imports neither `core::ordering` nor any slice or iterator machinery.
- `split_receivers.lani` compiles and executes with exit status zero. Both
  comparison roles preserve the full-width words, signed extrema, compound
  payloads and shared callback count checked by its assertions.

These two passing tests establish **one reproduced diagnostic and one native
positive control**, not two executable forms. The driver may receive
whitespace-only formatting after this receipt; the source fixture identities
above retain the executed contents.

`tests/stdlib_slice_ordering_dependency_execution.rs` is an automatically
discovered Rust integration driver. It always requires the split-receiver
control to compile and execute. The same-receiver form must either produce
the source-local duplicate-member `LNC0027`, or compile and execute the same
assertions after a compiler repair. Valid source is never required to remain
rejected. This is dependency evidence, separate from library API acceptance.
