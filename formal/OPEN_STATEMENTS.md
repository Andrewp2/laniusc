# Open statements: proving by a graph of statements

Large proofs (F14's preconditions, F5, the rest of the roadmap) are split into
small statements that agents prove one at a time, as Prove2Me does
(arXiv 2608.28433; Anthropic's Fermat's Last Theorem run). Statements are
written first and never change; proofs come later, each compiling only what
it imports. The repository's rules stay as they are: no `sorry`, no new
axioms, no `native_decide`. An open statement is a proposition, not a theorem
with a hole.

## The three kinds of declaration

Everything lives under `formal/Lanius/Open/`, one statement per directory:

    Lanius/Open/<Area>/<Name>/Stmt.lean     the statement
    Lanius/Open/<Area>/<Name>/Red<k>.lean   reductions to other statements (any number)
    Lanius/Open/<Area>/<Name>/Proof.lean    its proof (at most one)
    Lanius/Open/<Area>/<Name>/NOTES.md      attempts, dead ends, hints (append only)

- **Statement** (`Stmt.lean`): a docstring saying in plain words what it
  claims and why it is needed, then

      def Lanius.Open.<Name> : Prop := ...

  It imports only definitions (the model, the semantics, Gen/ and the like),
  never another statement's proof. Once it is on `lang` it never changes:
  `open_graph.py check` compares it with the version the commit that added it
  had. A wrong or unprovable statement is replaced by a new one under a new
  name (`<Name>V2`), and the old one is left, unused.
- **Reduction** (`Red<k>.lean`): an ordinary, complete theorem

      theorem Lanius.Open.<Name>.red<k> (h₁ : Lanius.Open.<A>) (h₂ : Lanius.Open.<B>) :
          Lanius.Open.<Name> := ...

  whose hypotheses are all open statements. It imports their `Stmt.lean`s, not
  their proofs, so it builds before they are proved. A reduction with no
  hypotheses is a proof.
- **Proof** (`Proof.lean`): `theorem Lanius.Open.<Name>.proof : Lanius.Open.<Name>`.
  Once each hypothesis of some reduction is proved, the proof is one line,
  `red<k> A.proof B.proof`; `open_graph.py status` prints it.

The final theorems (TRUSTED_BASE's top theorems) use the `proof`s of their
root statements.

Imports: `Stmt.lean` imports definitions only; `Red<k>.lean` imports its own
`Stmt` and its hypotheses' `Stmt`s (and any proved lemmas it uses);
`Proof.lean` imports the reduction it applies and its hypotheses' `Proof`s.
Module names follow the path, e.g. `Lanius.Open.F14.PreLexSource.Stmt`. Each
file builds on its own, so an agent compiles only the statement it works on.

## Deleting a statement

A statement on `lang` is deleted only when a type change on `lang` stops it
elaborating (a structure gains a field, so its anonymous constructors no
longer fit), and only together with a `<Name>V2` that says the same thing
with the new constructor (it may say it for every value of the new field).
The commit that does it names both. Its proof, reductions and NOTES move to
the V2, whose NOTES say what it replaces. First case (11-03, F5 S6a-2,
`Binding.home`): `HomedCorrPush`, `HomedCorrPushPlain`, `HomedCorrPushHeld`,
`HomedCorrPopHome` and `HomedCorrPopPlain` became their V2s.

## Picking work

`python3 -I formal/tools/open_graph.py status` lists every statement:
proved; ready to assemble (some reduction's hypotheses all proved, with the
line to write); blocked (reductions waiting on open statements); and open
leaves (no reduction, no proof), with each docstring's first line and its
claim. Pick an open leaf or a ready one. Before starting, read its NOTES.md,
then claim it:

    python3 -I formal/tools/open_graph.py claim <Name> --agent <you>

A claim is a file under target/claude-work/open/claims/ (machine-local, not
in git); it lapses after 6 hours, and `release <Name>` drops it. A claim only
saves duplicate work: if two agents prove the same statement, either proof
is fine.

When an attempt fails, append what was tried and why it failed to NOTES.md,
so the next agent does not repeat it. When a statement turns out to be false
or too weak for its parent, write the corrected one as a new statement and
note in the old one's NOTES.md which one replaces it.

## What is checked

`open_graph.py check` (the gate's `open` step) checks that:
- every statement has a docstring and is unchanged since it was first committed;
- every reduction's hypotheses are open statements and its conclusion is its own statement;
- every proof proves exactly its own statement;
- nothing under Lanius/Open uses `sorry`, `admit`, `axiom`, `native_decide`,
  `bv_decide`, `implemented_by` or `extern`.

The gate builds the whole `LaniusOpen` library, so Lean checks every
declaration. Statements that a top theorem depends on are audited by
read-back: an agent that has not seen the source states each such Lean
statement in plain words, and a human compares that with what was intended.
Intermediate statements need no audit: a wrong one cannot help prove a
correctly stated top theorem.
