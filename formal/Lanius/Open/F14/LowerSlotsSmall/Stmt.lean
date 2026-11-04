import Lanius.Faithful.SelfPre.EvalSlots
import Lanius.Faithful.SelfPre.CompileTypes
import Lanius.Faithful.SelfPre.NB

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- A statement's lowering names only slots below `2 ^ 60`, and its numbers are
the statement's, the scope's or below `2 ^ 60`, when the types it meets are
small (`ts`, `tsd` and the signatures' parameters, as the front end's checks
give), the scope's bindings end below `2 ^ 56` (`scopeTop`), its next slot plus
its lets' slots is below `2 ^ 56` (`SrcStmt.depth`) and its expressions'
unchecked nesting below `2 ^ 55` (`SrcStmt.slotNest`, SelfPre/EvalSlots).
GenPC's pre lemmas need it twice: `lower_body` takes the body's `Stmt.extent`,
whose `+ 1`s must not wrap (`Pre_Stmt_extent`), and `compile_lowered` (a
`COMPILE_FIXED_ROOTS` member) asks for the lowered functions' numbers below
`2 ^ 62`.

Why it holds. The slots a lowered statement names: a binding's (in scope, or a
`let`'s at `next`, which grows by the `let`'s type size, or a view's `length + 1`,
all counted by `SrcStmt.depth`), so below `2 ^ 56` plus a type's size; and the
evaluator's, which start at a statement's `next` or at a start that
`eval_args`, `eval_let_body` and `eval_arm_in` check against `evalSlotLimit`
(`2 ^ 40`), grow by one per unchecked step (`slotNest`) and end within a
value's type (its size at most `ts`, a call's result at most the signatures'
`ts`, an arm's payload at most `tsd`, an element at most its array's): below
`2 ^ 56 + 2 ^ 55 + 2 ^ 40 + 2 ^ 23 < 2 ^ 60`. The other numbers: a call's
callee (the statement's), its result count (a type's size), an `alloc`'s shift
(the statement's), a string's static offset (below `2 ^ 31`, `eval_str`'s
check), a call's block offsets (below `blockLimit`), and anything a binding
carries (the scope's). -/
def Lanius.Open.LowerSlotsSmall : Prop :=
  ∀ (body : SrcStmt) (sigs : List Sig) (decls : SrcDecls) (ret : SrcType) (scope : List Binding) (next : Nat),
    ts sigs ≤ 2 ^ 22 → sigsParams sigs ≤ 2 ^ 40 → tsd decls ≤ 2 ^ 22 → ts ret ≤ 2 ^ 22 →
    ts body ≤ 2 ^ 22 → ts scope ≤ 2 ^ 22 → scopeTop scope ≤ 2 ^ 56 →
    next + SrcStmt.depth body ≤ 2 ^ 56 → SrcStmt.slotNest body ≤ 2 ^ 55 →
      optExtent (SrcStmt.lower body sigs decls ret scope next) ≤ 2 ^ 60 ∧
        nb (SrcStmt.lower body sigs decls ret scope next) ≤ max (max (nb body) (nb scope)) (2 ^ 60)
