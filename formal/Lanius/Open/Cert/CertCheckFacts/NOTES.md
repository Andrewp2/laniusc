# CertCheckFacts

Notes (append only): attempts, dead ends, hints.

- 11-04: proved (Proof.lean). One lemma per loop, `loop fuel i = 0 → ∀ j ∈ [i, bound), fact j`, by
  induction on fuel with `split at h` and `omega` for the reject branches. Don't `simp`/`dsimp` the
  folded `nHyps`/`ruleWord` inside `h` before splitting: the `ite`'s Decidable instance stops matching
  and `split`/`rw` fail; unfold only the split-off condition.
