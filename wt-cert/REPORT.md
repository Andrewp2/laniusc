# Certificate checker spike: report (11-04, cert-spike d6bcfce2f)

Written by the coordinator from the cert agent's final report (the agent could not write this file).

## Built
- Format (FORMAT.md): Metamath Zero style. Each step names a rule, a substitution, its premises
  by index, and its result as a node in a shared, deduplicated term table. Every result is
  stated, so nodes, rules and steps are each checked on their own, with no recursion.
- Checker formal/cert/check.lani: 223 lines (about 130 of check logic). It agreed with a
  Python reference checker on 6,500 randomly corrupted certificates, rejected all 7 hand-made
  bad ones and accepted the honest one.
- Certificates: Export.lean walked all 13,651 theorems in GenP and GenPC and pulled out
  15,090 arithmetic and overflow side conditions (3,172 distinct). gen.py proves each in a
  27-axiom theory; Lean proves the 27 axioms true of Nat in about 1 s.

## Numbers (laptop, the same 3,172 obligations)
| | Spike | Lean |
|---|---|---|
| Check | 118-183 ms (0.2-0.3 us a step); 0.23 s with reading | 15.7-16.9 s of kernel alone on pre_auto's terms (about 5 ms each) |
| Search | 4.0 s in Python (1.27 ms each) | omega on the first 500: 34 s wall, 7 timeouts |
| Size | 578k steps, 23.6 MB (7.4 KB each) | 203 term nodes each |

Lean build of the generated modules:
| Module | Wall | Tactics | Kernel |
|---|---|---|---|
| GenP/SelfP02 | 3 min 54 s | 405 s | 31.5 s (7%) |
| GenP/SelfP00 | 5.3 s | about 10 s CPU (simp and elaboration) | 1.24 s (10%) |

About 90% of these builds is search that reruns on every build.

## One-line change
With obligations keyed by a hash of their statement, the median function has 5 obligations,
all shared with other functions, so a typical edit hits the cache. The worst function,
let_first, has 325 (0.43 s of search, about 20 ms of checking). Re-checking everything takes
0.18 s. In Lean the same edit rebuilds a whole module (SelfP02: 3 min 54 s).

## Costs and gaps
- Equality bookkeeping (transitivity, congruence) is 72% of the steps; a rewrite-at-position
  step would shrink certificates about 3x.
- Numbers checked bit by bit are expensive: one float bound takes 5,264 steps.
- Lean's search chose each obligation's hypotheses; gen.py only builds the proof from that choice.
- Whole theorems and the hand-written Mini proofs were not translated. That needs a tracing type
  checker for Lean's kernel plus its library (BitVec, Int, List): much larger than a spike.

## Logic limits for compiler specs
No quantifiers or lambdas inside formulas. Recursive definitions only as equation axioms (Lean
proves them once). No induction and no inductive types (Expr, Stmt, Instr). No computation by
evaluation, so every computation becomes steps. BitVec and Int theories would have to be
axiomatised or re-proved.

## Recommendation
Yes, as a Lanius-native verifier for generated, routine obligations, with Lean kept for the
theory and the hand proofs:
1. Now, inside Lean: split the generated proofs into modules named by a hash of their
   statements, so Lake's artifact cache stops re-running pre_auto on unchanged ones (about a
   10x cut for these builds, with no new checker).
2. Next: the flat checker for the arithmetic class, then the height and cost lemmas. The trusted
   base is the checker, the axioms (each proved in Lean) and the statement translation. Write
   the checker in the mini subset so the verified compiler can compile it.
3. Not yet: migrating the hand proofs (this needs bound variables, induction, inductive types
   and the library first).
