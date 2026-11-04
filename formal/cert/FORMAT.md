# Flat proof certificates (cert spike, format version 1)

Code: `formal/cert/` (check.lani is the checker,
certlib.py builds, writes and reference-checks, gen.py is one search).

## Idea

Proof search and proof checking are separate programs. The search writes a
certificate; the checker never searches, never normalises and never builds
a term. A proof is a flat array of steps. Each step names a rule
(an axiom or an earlier theorem), a substitution and its premises (earlier
steps, by index), and states its result as a node of a shared, hash-consed
term table. Since every result is given, every step is checked on its own:
the rule's statement under the substitution must match the step's result,
and each rule hypothesis under the substitution must match the result of
the premise named for it. There is no dependency between step checks, so
the checks can run in any order or in parallel. The design follows
Metamath / Metamath Zero (MM0): schematic rules applied by substitution,
checked in time linear in the certificate.

## Logic

* **Sorts.** Each sort has one flag: provable (its terms can be stated and
  proved; `wff` here) or not (`nat`). Sorts must be inhabited (a trust
  assumption on the theory, as in Metamath: a variable that appears in a
  proof but not in its statement stands for an arbitrary value).
* **Term constructors.** A result sort and a list of argument sorts.
* **Variables.** `Var(k, s)`: variable k of sort s. Variables are global
  nodes; in a rule they are the rule's schematic variables `0..nvars-1`.
* **Rules.** An axiom or a theorem: `nvars`, hypotheses (provable-sorted
  nodes) and a conclusion (a provable-sorted node). A theorem also owns a
  contiguous range of steps. Rule r may cite only rules `< r`, so theorems
  form a DAG by construction; all theorems can be checked at once.
* **Substitution.** A list of `nvars` node ids. Instantiating `Var(k, s)`
  gives `sigma[k]`, which must have sort `s`.
* **No binders.** There are no bound variables, no distinct-variable
  conditions and no definitional unfolding. All variables of a statement
  are implicitly universally quantified at the top. (See REPORT.md for what
  this rules out and how MM0 adds binders.)

## Binary layout

All words are little-endian 32-bit, each in `0 .. 2^31-1` (the checker
rejects any word with the top bit set). `VAR = HYP = 0x7FFFFFFF`.

```
header  8 words   magic 0x5452434C ('LCRT'), version 1,
                  ns, nc, nn, nr, nst, np            (section counts)
sorts   ns words  flags: 1 provable, 0 not
cons    nc x 3    result_sort, arity, argsorts_off   (argsorts in pool)
nodes   nn x 3    head, a, b
                    head <  nc : constructor, args at pool[a .. a+arity), b = 0
                    head = VAR : variable index a, sort b
rules   nr x 6    kind (0 axiom, 1 theorem), nvars, nhyps, hyps_off (pool),
                  concl, steps_end (theorem: steps [previous theorem's end, steps_end))
steps   nst x 4   rule, sigma_off, prems_off, result
                    rule = HYP : sigma_off is the theorem hypothesis index j
                    otherwise  : sigma = pool[sigma_off .. +nvars(rule)],
                                 prems = pool[prems_off .. +nhyps(rule)] (step indices)
pool    np words  argument lists, argument sorts, hypothesis lists,
                  substitutions and premise lists
```

The section offsets follow from the counts. A step carries no arity: the
number of substitution entries and premises comes from the rule it cites.

## Checks (check.lani, ~130 lines of logic)

All checks are local. With `sort(n)` = the constructor's result sort or the
variable's sort:

1. **Header.** Magic and version; counts small enough that no offset
   overflows; the sections exactly fill the input.
2. **Constructors.** Result and argument sorts exist; argument list in the pool.
3. **Nodes (each independently).** A constructor node's arguments are
   *earlier* nodes (`x < n`, so the table is a DAG in topological order)
   of the constructor's argument sorts. A variable's sort exists.
4. **Rules (each independently).** Conclusion and hypotheses are nodes of
   provable sorts; a theorem's step range is non-empty and follows the
   previous theorem's.
5. **Steps (each independently).** For step i of theorem t, steps `[s0, s1)`:
   * `HYP j`: `j < nhyps(t)` and `result = hyp_j(t)`.
   * rule r: `r < t`; substitution entries are nodes; each premise p has
     `s0 <= p < i`; `match(concl(r), sigma, result)`; for each hypothesis j
     of r, `match(hyp_j(r), sigma, result(prem_j))`.
6. **Theorems.** The last step's result is the conclusion; no step lies
   outside a theorem.

`match(t, sigma, x)` walks the template t against node x with an explicit
stack (no recursion): a variable `Var(k, s)` needs `k < nvars`,
`sigma[k] = x` and `sort(x) = s`; a constructor node needs x to have the
same head, then matches the arguments pairwise. Equal ids are equal terms,
so the hash-consing need not be perfect: a duplicated node can only make a
correct certificate fail, never let a wrong one pass.

The checker prints `ok AXIOMS THEOREMS STEPS DIGEST MICROS`. DIGEST is a
32-bit hash of every rule's kind, variable count, hypothesis count and
statement trees in prefix order. A certificate proves what its statements
say only if those statements (and the axioms) are the reviewed ones; the
generator prints the expected digest from its own statement list
(`certlib.digest`), the analogue of MM0's separate `.mm0` specification.

## For a GPU checker

The format is laid out so that a GPU version needs no recursion and no
dependency between work items:

* **Nodes, rules, steps** are three independent maps over flat arrays;
  acceptance is an AND-reduction of their flags.
* **Owner of a step.** The theorem of each step comes from a scan over the
  rules' `steps_end` (segmented broadcast), or the format can carry it per
  step (a local check: `start(t) <= i < end(t)`).
* **No term construction.** Results are given, so there is no pass that
  builds terms and no parallel hash-consing. (MM0's binary format omits
  results and rebuilds them on a stack; that is cheaper in bytes but
  sequential.) The "pass that computes each step's result" is the matching
  itself: the stated result is checked, not computed.
* **Matching without per-thread stacks.** A rule's statement trees are
  small and fixed. Flatten each rule once into a match program: one entry
  per template position with its path from the root (child indices) and
  either an expected head or a variable index. A work item is then
  (step, entry): follow the path from the step's result (depth hops),
  compare. The (step, entry) pairs are expanded by an exclusive scan over
  per-step entry counts, the same expand pattern as Pareas/LLP. Total work
  is the sum over steps of template size times depth, all of it independent.
* **Digest.** Per-rule tree hashes in parallel, combined by an ordered
  reduction.
