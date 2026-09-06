# Proof-representation comparison

This isolated experiment compares fresh proofs of the same TokenScan node
validation and exact surface-reconstruction conjunction. It is not a full
frontend benchmark. Artifact data and authenticated views are prebuilt and
identical across alternatives; their costs remain in the full production
benchmark. No generated program proof is moved into shared infrastructure.

`Kernel.lean` uses the installed combined checker and `kernel_rfl`.
`Cbv.lean` applies proof-producing `cbv` to exactly the same equality.
`generate.py` emits explicit node, child, stack, consumption, validation,
and composition declarations. `RepresentationRules.lean` proves the generic
composition and reconstruction bridge. The generator is untrusted: the
kernel checks every declaration, exact agreement with the original artifact
node list, and the final conjunction. Reconstruction still uses `kernel_rfl`
over the named forest; this is a hybrid, not a fully proof-producing
reconstruction interpreter.

## Reproduce

Run sequentially from `formal/`, with the selected unit's `View` dependencies
already built. Keep generated output outside the source tree. First build
the generic rules (outside the program-specific timing):

```bash
lake env lean -R experiments/representation -M 12000 -DElab.async=false \
  -o /tmp/RepresentationRules.olean experiments/representation/RepresentationRules.lean
export LEAN_PATH="/tmp:$(lake env printenv LEAN_PATH)"
```

Generate a TokenScan proof, measuring generation separately:

```bash
/usr/bin/time -f 'WALL %e RSS_KB %M' python3 experiments/representation/generate.py \
  Lanius/Extraction/Artifacts/frontend_pack.json /tmp/Explicit.lean token_scan
/usr/bin/time -f 'WALL %e RSS_KB %M' timeout 60s lean -R /tmp -M 12000 \
  -DElab.async=false -o /tmp/Explicit.olean /tmp/Explicit.lean
```

The optional final generator argument selects a source basename, such as
`digits`. For the control and `cbv` templates, substitute the corresponding
Lean unit name (`TokenScan` or `Digits`) when comparing another source.

```bash
/usr/bin/time -f 'WALL %e RSS_KB %M' timeout 60s lean \
  -R experiments/representation -M 12000 -DElab.async=false \
  -o /tmp/Kernel.olean experiments/representation/Kernel.lean
/usr/bin/time -f 'WALL %e RSS_KB %M' timeout 60s lean \
  -R experiments/representation -M 12000 -DElab.async=false \
  -o /tmp/Cbv.olean experiments/representation/Cbv.lean
```

Do not run these jobs concurrently or increase the memory cap. Exit 124
means the timeout stopped the experiment, not that the proof passed.
Successful runs print the final conjunction's axioms. The allowed set is
`propext`, `Classical.choice`, and `Quot.sound`.

As a negative check, the TokenScan prefix through `valid0` was generated
with its production ID changed from 48 to 999999. Lean exited 1 with a
kernel declaration-type mismatch at `valid0`; the proposed invalid node
certificate was rejected. Log: `/tmp/lanius-representation-corrupt.log`.

## Initial result

On TokenScan (651 parse nodes), the current path took 3.15 s including
export, versus 17.83 s for the explicit encoding plus 0.22 s generation.
The initial control without export took 3.47 s; differences at that scale
are run variability, not evidence that export makes checking faster.
The compiled modules were 18,712 and 11,858,328 bytes respectively; these
sizes include declarations and metadata, not just the final proof term.
Peak RSS was 2,104,056 versus 2,457,456 KiB.

The explicit run spent 4.86 s in kernel checking, 5.67 s in elaboration,
and additional time compiling its data definitions. Its remaining
reconstruction certificate took 0.865 s. Both completed approaches proved
the same conjunction with the standard three axioms. `cbv` did not finish
within 60 s; its timeout-wrapper RSS was not a reliable Lean peak.

On Digits (2,333 parse nodes), the current path passed in 7.09 s including
export, with 6.13 s kernel checking and 2,924,472 KiB peak RSS. Explicit
generation took 0.25 s but checking did not finish within 60 s (reported
peak 3,816,048 KiB). This rules out
adopting this particular encoding on present evidence. It does not rule
out a more compact proof DAG, direct proof-term construction that avoids
thousands of source declarations, or domain-specific reconstruction rules.

The production full-check result remains 348.859 s. This experiment does
not establish a new full-run time or a route to three seconds.

Raw logs are `/tmp/lanius-representation-kernel-export.log`,
`/tmp/lanius-representation-explicit.log`, `/tmp/lanius-representation-cbv.log`,
`/tmp/lanius-representation-kernel-digits.log`, and
`/tmp/lanius-representation-explicit-digits.log`.
