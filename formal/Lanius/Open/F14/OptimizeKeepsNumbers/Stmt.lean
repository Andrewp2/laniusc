module

public import Lanius.Faithful.SelfPre.CompileValues

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- The optimizer raises neither a program's numbers (`nb`, the largest number
in it, `SelfPre/NB.lean`) nor its functions' temporaries (`funcsTemps`).
`compile_optimized` compiles `optimizeProgram p`, a result no post bounds, with
the Mini compile's pre lemmas, which need both below `2 ^ 62`; `p`'s are.
Why it holds: `optimizeFuncs` keeps each function's params, results and locals.
`Stmt.optimize` copies its statements' slots, counts and callees, drops
statements and branches, and changes expressions only by `Expr.subst` (a slot
whose value is known becomes that value, an atom: a literal or another slot,
`assigned` keeps no other fact, and its slot comes from an assignment in the
same body) and `Expr.optimize` (constant folding: an operation becomes a
literal, one of its operands, or itself on optimized operands). Literals are
`BitVec`s, which `nb` does not count, and an atom has no temporaries, so
neither grows: replacing a subexpression by one with no more temporaries
gives no more temporaries (`temps` is monotone in its operands'). -/
def Lanius.Open.OptimizeKeepsNumbers : Prop :=
  ∀ p : Program, nb (optimizeProgram p) ≤ nb p ∧ funcsTemps (optimizeProgram p).funcs ≤ funcsTemps p.funcs
