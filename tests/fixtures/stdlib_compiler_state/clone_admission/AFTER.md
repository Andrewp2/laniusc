# Re-admission after the root-owned compiler correction

The original README, SHA256SUMS, failure logs, emitted controls and old compiler
binary remain unchanged as before-fix evidence. This note records a separate
re-admission, not a reinterpretation of those earlier outcomes.

After root admitted symbolic-error positive/swapped-parameter controls and two
conflicting-error negative controls, these exact frozen generated entries were
compiled again under the shared GPU lock using the intended copied-stdlib
`core::clone` and `alloc::clone` modules and ordinary copied String impl:

| Entry | Compile | Shared x86 checker | Native result |
| --- | --- | --- | --- |
| `overlay-user/generic_return.lani` | Pass | Pass | Exit0, exact2mapping/2release ledger |
| `overlay-user/main.lani` | Pass | Pass | Exit0, exact14mapping/14release ledger |

The full entry uses nonzero-start counted String views with distinguishing
empty guards and duplicate borrowed aliases. It destroys the original String,
reads cloned backing bytes, grows and destroys one popped clone, reads siblings
again, and explicitly destroys the remaining vector. It then exercises two
successful independent two-String Pair clones followed by an injected failure
inside the third Pair after its first String clone. The leaf releases its own
temporary; the imported generic helper releases the completed Pair prefix and
outer Vec, preserves source bytes, and transports exact index2/tag102/phase1/
u64 marker through the generic E result. Both native executions are now admitted
for these fixtures.

The earlier fixed-E `pair_fixed.lani` trap remains a separate preserved
before-fix artifact; that smaller control was not rerun in this admission.
The current full generic Pair composition passes. No claim is made about an
allocated E payload, every allocation failure, arbitrary nesting, zero-sized
values, or other element implementations from this minimal admission. No
production cloning API was added; implementation waits for root authorization.

After artifacts/logs are in `target/stdlib-work/clone-admission/`:

- `compiler-after-fix.sha256` and `compiler-after-fix-version.log`
- `after-generic-return-compile.log`, executable and trace
- `after-full-compile.log`, executable and trace
- `after-native-ledgers.log`

`AFTER_SHA256SUMS` pins the frozen source snapshot, current compiler and shared
checker for this re-admission. Production/compiler changes were owned by root;
this provider changed no compiler source and performed no Cargo build.
