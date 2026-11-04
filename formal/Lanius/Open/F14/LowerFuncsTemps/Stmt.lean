module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.CompileValues

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- The functions lowering builds use at most as many temporaries as the
lowering costs (`funcsTemps`, the most any body uses, `SelfPre/CompileValues`).
`compile_func` adds a function's locals and its body's temporaries before its
room check, so the Mini compile's pre lemmas need `funcsTemps ≤ 2 ^ 62`
(`COMPILE_OVERRIDES` in `tools/pre_certs.py`); `compile_declared` has
`Cost_lower_funcs .. < b ≤ 2 ^ 62` there. Why it holds: `Stmt.temps` is the
deepest nesting of an expression's right operands (`max (temps l) (temps r + 1)`),
so a constructor raises it by at most one over its operands'. The lowering's
input holds no Mini expression, and the cost model charges each constructor it
applies one step (`Cost_element_base` is 4 for `elementBase`'s four nodes), so
an expression's temporaries are at most the steps that built it. A copied
operand keeps its temporaries (copies add width, not depth, so the weight has
no such bound). -/
def Lanius.Open.LowerFuncsTemps : Prop :=
  ∀ (n : Nat) (sigs own : List Sig) (decls : SrcDecls) (funcs : List SrcFunc) (fs : List Func),
    Cost_lower_funcs n sigs own decls funcs < 2 ^ 64 →
    lowerFuncs sigs own decls funcs = some fs →
    funcsTemps fs ≤ Cost_lower_funcs n sigs own decls funcs
