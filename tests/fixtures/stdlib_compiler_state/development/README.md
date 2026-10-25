# Original native benchmark delegation boundary

This retains the original `test::bench` implementation before its work loop and
measurement validation were factored into shared helpers. The old `native<W>`
called `measure<NativeClock,W>` directly.

With that exact library source, `native_clock_repro.lani` fails native compilation
with LNC0047: a replay argument has no complete GPU native layout. The otherwise
identical `native_clock_control.lani` compiles and executes after adding an unused
source `Clock` declaration and its `std::clock::Monotonic` implementation. The
control never constructs or calls that clock. Both callers perform the same
native workload with the same Work type and invocation.

This is evidence about that source composition. It does not establish a general
callback, trait, helper-call, or native clock limitation. Current production
`bench::native` uses concrete typed native reads and shares work/count/duration
logic with the injected path. `development_native_bench.lani` is its positive
native-only gate and has no source clock declaration. The reduced direct
`measure(NativeClock, Work)` caller also compiled against the current factored
library during investigation; no general prohibition on it is inferred.

To reproduce from the repository root, stage the retained module over a copy of
the current stdlib. A source root cannot override an already resolved stdlib
module, and symlinks outside a stdlib root are rejected by the loader.

```sh
probe_root="$(mktemp -d)"
cp -R stdlib/. "$probe_root/"
cp tests/fixtures/stdlib_compiler_state/development/prototype/test/bench.lani "$probe_root/test/bench.lani"
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc --stdlib-root "$probe_root" tests/fixtures/stdlib_compiler_state/development/native_clock_repro.lani -o target/stdlib-work/development-native-repro
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc --stdlib-root "$probe_root" tests/fixtures/stdlib_compiler_state/development/native_clock_control.lani -o target/stdlib-work/development-native-control
timeout --kill-after=2s 100s target/stdlib-work/development-native-control
rm -rf -- "$probe_root"
```

The failing command exits 1. Its normalized diagnostic is in
`native_clock_repro.stderr.txt`. The control exits 0 and reports 10000 iterations,
30000 work units, and an actual elapsed duration. Timings are not snapshots.

No compiler implementation or proof contract was changed for this workflow.
