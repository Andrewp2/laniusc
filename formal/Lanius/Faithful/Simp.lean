import Lanius.Faithful.Tactic

/-! The rewrites that run the pure semantics on a body of known syntax,
leaving only the calls (`pcall`), which the certificates of the callees
take care of. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (matchPattern matchPatterns)

@[pure_rule] theorem matchPatterns_binds : ∀ (bs : List Nat) (vs : List Value),
    matchPatterns (bs.map .bind) vs = if bs.length = vs.length then some (bs.zip vs) else none
  | [], [] => rfl
  | [], _ :: _ => rfl
  | _ :: _, [] => rfl
  | b :: bs, v :: vs => by
    simp only [List.map_cons, matchPatterns, matchPattern, matchPatterns_binds bs vs, List.length_cons,
      Nat.add_right_cancel_iff, List.zip_cons_cons]
    by_cases len : bs.length = vs.length <;> simp [len]

@[pure_rule] theorem parms_nil (call : Calls) (env : Env) (v : Value) (id k : Nat) (values : List SrcEff) :
    parms call env v id k [] values = none := by
  cases values <;> rfl

@[pure_rule] theorem parms_none (call : Calls) (env : Env) (v : Value) (id k : Nat) (bs : List Nat) (rest : List (List Nat)) :
    parms call env v id k (bs :: rest) [] = none := rfl

/-- The arm of the scrutinee's variant runs with its payload bound. -/
@[pure_rule] theorem parms_hit (call : Calls) (env : Env) (id k : Nat) (vs : List Value) (bs : List Nat)
    (rest : List (List Nat)) (value : SrcEff) (values : List SrcEff) (len : bs.length = vs.length) :
    parms call env (.enumeration id k vs) id k (bs :: rest) (value :: values) =
      peff call (env.bindAll (bs.zip vs)) value := by
  simp [parms, matchPattern, matchPatterns_binds, len]

/-- An arm of another variant is passed over. -/
@[pure_rule] theorem parms_miss (call : Calls) (env : Env) (id k k' : Nat) (vs : List Value) (bs : List Nat)
    (rest : List (List Nat)) (value : SrcEff) (values : List SrcEff) (ne : k ≠ k') :
    parms call env (.enumeration id k' vs) id k (bs :: rest) (value :: values) =
      parms call env (.enumeration id k' vs) id (k + 1) rest values := by
  have : (k == k') = false := by simpa using ne
  simp [parms, matchPattern, this]

@[pure_rule] theorem Env.get?_nil (id : Nat) : Env.get? [] id = none := rfl

@[pure_rule] theorem Env.get?_cons (k id : Nat) (v : Value) (env : Env) :
    Env.get? ((k, v) :: env) id = if k = id then some v else Env.get? env id := by
  by_cases h : k = id
  · simp [Env.get?, List.find?, h]
  · have : (k == id) = false := by simpa using h
    simp [Env.get?, List.find?, h, this]

@[pure_rule] theorem Env.bindAll_nil (env : Env) : env.bindAll [] = env := rfl

@[pure_rule] theorem Env.bindAll_cons (env : Env) (b : Nat × Value) (bs : List (Nat × Value)) :
    env.bindAll (b :: bs) = Env.bindAll (b :: env) bs := rfl

@[pure_rule] theorem bind_ite {α β : Type} (c : Prop) [Decidable c] (a b : Option α) (f : α → Option β) :
    (if c then a else b).bind f = if c then a.bind f else b.bind f := by
  split <;> rfl

@[pure_rule] theorem map_ite {α β : Type} (c : Prop) [Decidable c] (a b : Option α) (f : α → β) :
    (if c then a else b).map f = if c then a.map f else b.map f := by
  split <;> rfl

/-- A call that returned: the only binds the certificates split. -/
@[pure_rule] theorem pcall_bind {sp : SrcProgram} {prims : Prims} {n c : Nat} {vs : List Value} {β : Type}
    {f : Value → Option β} {w : β} :
    (pcall sp prims n c vs).bind f = some w ↔ ∃ x, pcall sp prims n c vs = some x ∧ f x = some w :=
  Option.bind_eq_some_iff

@[pure_rule] theorem pcall_map {sp : SrcProgram} {prims : Prims} {n c : Nat} {vs : List Value} {β : Type}
    {f : Value → β} {w : β} :
    (pcall sp prims n c vs).map f = some w ↔ ∃ x, pcall sp prims n c vs = some x ∧ f x = w :=
  Option.map_eq_some_iff

@[pure_rule] theorem Done.then_next (rest : Option Done) : Done.then rest .next = rest := rfl
@[pure_rule] theorem Done.then_ret (rest : Option Done) (v : Option Value) : Done.then rest (.ret v) = some (.ret v) := rfl

@[pure_rule] theorem doneValue_ret (ret : SrcType) (v : Value) : doneValue ret (.ret (some v)) = some v := rfl

@[pure_rule] theorem asBool_boolean (b : Bool) : asBool (.boolean b) = some b := rfl

/-- How a certificate unfolds a call of a function that is not a prim. -/
theorem pcall_succ {sp : SrcProgram} {prims : Prims} {n c : Nat} {vs : List Value} {f : SrcFunc}
    (np : prims.isPrim c = false) (found : sp.funcs[c]? = some f) :
    pcall sp prims (n + 1) c vs =
      if vs.length = f.params.length then
        (pstmt (pcall sp prims n) (paramEnv f.params vs) f.body).bind (doneValue f.ret)
      else none := by
  simp [pcall, np, found]

@[pure_rule] theorem ex_ex_eq_and {α β : Type} {p : α → Prop} {f : α → β} {q : β → Prop} :
    (∃ b, (∃ a, p a ∧ f a = b) ∧ q b) ↔ ∃ a, p a ∧ q (f a) :=
  ⟨fun ⟨_, ⟨a, pa, rfl⟩, qb⟩ => ⟨a, pa, qb⟩, fun ⟨a, pa, qa⟩ => ⟨_, ⟨a, pa, rfl⟩, qa⟩⟩

attribute [pure_rule] Option.bind_some Option.bind_none Option.map_some Option.map_none Option.bind_assoc
  Option.map_bind Option.bind_map Function.comp_def List.zip_cons_cons List.zip_nil_left List.map_cons List.map_nil
  List.length_cons List.length_nil ite_true ite_false if_true if_false Option.some.injEq reduceCtorEq exists_eq_left
  exists_eq_right exists_and_left exists_and_right and_true true_and ne_eq not_false_eq_true decide_true
  decide_false List.cons.injEq and_self eq_self_iff_true

@[pure_rule] theorem toOption_ok {ε α : Type} (x : α) : (Except.ok x : Except ε α).toOption = some x := rfl
@[pure_rule] theorem toOption_error {ε α : Type} (e : ε) : (Except.error e : Except ε α).toOption = none := rfl

/-- Run the pure meaning of a body as far as its calls. -/
macro "pure_simp" " at " h:ident : tactic => `(tactic|
  simp only [pure_rule, pstmt, peff, peffs, pexpr, pexprs, paramEnv, paramBindings, applyOp, binary, unary, cast,
    SrcOp.toCore, Nat.reduceEqDiff, Nat.reduceAdd, Nat.reduceSub, Nat.reduceMul, Nat.reduceMod, Nat.reducePow,
    Nat.reduceBEq, Nat.reduceBNe] at $h:ident)

end Lanius.Faithful
