import Lanius.Mini.Semantics
import Lanius.Mini.Source

/-! Expressions: a lowered subset expression evaluates in Core without changing
the state, to a value its lowered mini expression represents. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr)

/-- Core's locals are the scope's bindings in the same order, each slot's cell
given by `frame`, and every binding's cell holds a value its slot represents. -/
structure Corr (scope : List Binding) (frame : Nat → Nat) (st : State) (env : Env) : Prop where
  locals : st.locals = scope.map fun b => (b.id, frame b.slot)
  values : ∀ b ∈ scope, ∃ v, st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some v⟩ ∧
    b.ty.HoldsAt v env b.slot

theorem lookup_mem {scope : List Binding} {id : Nat} {b : Binding}
    (found : lookup scope id = some b) : b ∈ scope ∧ b.id = id := by
  induction scope with
  | nil => simp [lookup] at found
  | cons head rest ih =>
    simp only [lookup] at found
    split at found
    · cases found; exact ⟨List.mem_cons_self .., by assumption⟩
    · exact ⟨List.mem_cons_of_mem _ (ih found).1, (ih found).2⟩

theorem find_locals (scope : List Binding) (frame : Nat → Nat) (id : Nat) :
    (scope.map fun b => (b.id, frame b.slot)).find? (fun binding => binding.1 == id) =
      (lookup scope id).map fun b => (b.id, frame b.slot) := by
  induction scope with
  | nil => rfl
  | cons head rest ih =>
    simp only [List.map_cons, List.find?_cons, lookup]
    by_cases h : head.id = id
    · simp [h]
    · have : (head.id == id) = false := by simpa using h
      simp [h, ih, this]

theorem Corr.cellId {scope frame st env} (corr : Corr scope frame st env) (id : Nat) :
    st.cellId? id = (lookup scope id).map fun b => frame b.slot := by
  simp only [State.cellId?, corr.locals, find_locals, Option.map_map]
  rfl

theorem Corr.local {scope frame st env} (corr : Corr scope frame st env) {id : Nat} {b : Binding}
    (found : lookup scope id = some b) (fuel : Nat) (prog : Core.Program) :
    ∃ v, evalExpr (fuel + 1) prog st (.local id) = .done v st ∧ b.ty.HoldsAt v env b.slot := by
  obtain ⟨v, entry, holds⟩ := corr.values b (lookup_mem found).1
  refine ⟨v, ?_, holds⟩
  simp only [evalExpr, corr.cellId, found, Option.map_some, entry]

/-- A Core binary operation other than && and || evaluates both sides. -/
theorem binary_sound {prog : Core.Program} {st : State} {env : Env} {l r : Core.Expr}
    {tl tr : Typed} {cop : Core.BinaryOp} {fuel : Nat} {v : Value} {st' : State}
    (hl : ∀ {fuel v st'}, evalExpr fuel prog st l = .done v st' →
      st' = st ∧ tl.ty.Holds v (tl.expr.eval env))
    (hr : ∀ {fuel v st'}, evalExpr fuel prog st r = .done v st' →
      st' = st ∧ tr.ty.Holds v (tr.expr.eval env))
    (general : cop ≠ .logicalAnd ∧ cop ≠ .logicalOr)
    (run : evalExpr (fuel + 1) prog st (.binary cop l r) = .done v st') :
    st' = st ∧ ∃ vl vr, tl.ty.Holds vl (tl.expr.eval env) ∧ tr.ty.Holds vr (tr.expr.eval env) ∧
      Semantics.evalBinaryValue prog.target cop vl vr = .ok v := by
  cases cop <;> simp only [ne_eq, not_true_eq_false, false_and, and_false, reduceCtorEq,
    not_false_eq_true, and_self] at general <;>
  · simp only [evalExpr] at run
    split at run
    · rename_i vl midl leftRun
      obtain ⟨rfl, holdsl⟩ := hl leftRun
      split at run
      · rename_i vr midr rightRun
        obtain ⟨rfl, holdsr⟩ := hr rightRun
        split at run
        · rename_i result evaluated
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨rfl, vl, vr, holdsl, holdsr, evaluated⟩
        · simp at run
      all_goals simp at run
    all_goals simp at run

section Values

open Semantics

theorem toInt_beq (a b : BitVec 32) : (a.toInt == b.toInt) = (a == b) := by
  rw [Bool.eq_iff_iff]
  simp [BitVec.toInt_inj]

variable (a b : BitVec 32)

theorem eval_add : evalBinaryValue .x86_64 .add (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a + b).toInt) := by
  simp [evalBinaryValue, evalSignedBinary, wrap_add]

theorem eval_sub : evalBinaryValue .x86_64 .subtract (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a - b).toInt) := by
  simp [evalBinaryValue, evalSignedBinary, wrap_sub]

theorem eval_mul : evalBinaryValue .x86_64 .multiply (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a * b).toInt) := by
  simp [evalBinaryValue, evalSignedBinary, wrap_mul]

theorem eval_bitAnd : evalBinaryValue .x86_64 .bitAnd (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a &&& b).toInt) := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
    signedBits_i32_bitvec_x86 a _ rfl, signedBits_i32_bitvec_x86 b _ rfl, wrap_nat]
  congr 3
  apply BitVec.eq_of_toNat_eq
  have bound := (a &&& b).isLt
  rw [BitVec.toNat_and] at bound
  simp only [BitVec.toNat_ofNat, BitVec.toNat_and]
  exact Nat.mod_eq_of_lt bound

theorem eval_bitOr : evalBinaryValue .x86_64 .bitOr (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a ||| b).toInt) := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
    signedBits_i32_bitvec_x86 a _ rfl, signedBits_i32_bitvec_x86 b _ rfl, wrap_nat]
  congr 3
  apply BitVec.eq_of_toNat_eq
  have bound := (a ||| b).isLt
  rw [BitVec.toNat_or] at bound
  simp only [BitVec.toNat_ofNat, BitVec.toNat_or]
  exact Nat.mod_eq_of_lt bound

theorem eval_bitXor : evalBinaryValue .x86_64 .bitXor (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a ^^^ b).toInt) := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
    signedBits_i32_bitvec_x86 a _ rfl, signedBits_i32_bitvec_x86 b _ rfl, wrap_nat]
  congr 3
  apply BitVec.eq_of_toNat_eq
  have bound := (a ^^^ b).isLt
  rw [BitVec.toNat_xor] at bound
  simp only [BitVec.toNat_ofNat, BitVec.toNat_xor]
  exact Nat.mod_eq_of_lt bound

theorem eval_order (cop : Core.BinaryOp) (op : CmpOp)
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge)) :
    evalBinaryValue .x86_64 cop (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
      .ok (.boolean (op.holds a b)) := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp [evalBinaryValue, evalSignedBinary, CmpOp.holds, BitVec.slt, BitVec.sle]

theorem eval_eq_int : evalBinaryValue .x86_64 .equal (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.boolean (CmpOp.eq.holds a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holds, toInt_beq]

theorem eval_ne_int : evalBinaryValue .x86_64 .notEqual (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.boolean (CmpOp.ne.holds a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holds, toInt_beq, bne]

theorem eval_eq_bool (x y : Bool) : evalBinaryValue .x86_64 .equal (.boolean x) (.boolean y) =
    .ok (.boolean (CmpOp.eq.holds (boolBits x) (boolBits y))) := by
  cases x <;> cases y <;> simp [evalBinaryValue, scalarEqual, CmpOp.holds, boolBits]

theorem eval_ne_bool (x y : Bool) : evalBinaryValue .x86_64 .notEqual (.boolean x) (.boolean y) =
    .ok (.boolean (CmpOp.ne.holds (boolBits x) (boolBits y))) := by
  cases x <;> cases y <;> simp [evalBinaryValue, scalarEqual, CmpOp.holds, boolBits]

end Values

theorem holds_compare (c : Bool) : SrcType.Holds .bool (.boolean c) (if c then 1 else 0) :=
  ⟨c, rfl, by cases c <;> rfl⟩

theorem SrcExpr.lower_sound (e : SrcExpr) {scope : List Binding} {frame : Nat → Nat} {st : State}
    {env : Env} {prog : Core.Program} (corr : Corr scope frame st env) (target : prog.target = .x86_64) :
    ∀ {t : Typed} {fuel : Nat} {v : Value} {st' : State}, e.lower scope = some t →
      evalExpr fuel prog st e.toCore = .done v st' → st' = st ∧ t.ty.Holds v (t.expr.eval env) := by
  induction e with
  | int x =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, Option.some.injEq] at lowered
      subst lowered
      simp only [SrcExpr.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨rfl, rfl⟩
  | boolean x =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, Option.some.injEq] at lowered
      subst lowered
      simp only [SrcExpr.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨rfl, x, rfl, rfl⟩
  | «local» id =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerLocal] at lowered
      split at lowered
      · simp at lowered
      · rename_i b found
        simp only [lowerScalarLocal] at lowered
        split at lowered
        · rename_i scalar
          simp only [Option.some.injEq] at lowered
          subst lowered
          obtain ⟨w, eval, holds⟩ := corr.local found fuel prog
          simp only [SrcExpr.toCore, eval, Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨rfl, (SrcType.holdsAt_scalar scalar).mp holds⟩
        · simp at lowered
  | field id index =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      cases fuel with
      | zero => simp [SrcExpr.toCore, evalExpr] at run
      | succ fuel =>
        simp only [SrcExpr.lower, lowerField] at lowered
        split at lowered
        · simp at lowered
        rename_i b found
        simp only [lowerFieldOf] at lowered
        split at lowered
        · simp at lowered
        · simp at lowered
        rename_i sid fields hty
        simp only [lowerFieldAt] at lowered
        split at lowered
        · simp at lowered
        rename_i f fieldFound
        split at lowered
        · rename_i scalar
          simp only [Option.some.injEq] at lowered
          subst lowered
          obtain ⟨w, eval, holds⟩ := corr.local found fuel prog
          rw [hty] at holds
          cases holds with
          | struct fieldsHold =>
            obtain ⟨fv, got, holdsField⟩ := fieldsHold.get fieldFound
            simp only [SrcExpr.toCore, evalExpr] at run
            simp only [evalExpr] at eval
            rw [eval] at run
            simp only [got, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            exact ⟨rfl, by simpa [Expr.eval] using (SrcType.holdsAt_scalar scalar).mp holdsField⟩
        · simp at lowered
        simp at lowered
  | negate operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerNegate] at lowered
      split at lowered
      · simp at lowered
      · rename_i inner innerLowered
        simp only [lowerNegateTyped] at lowered
        split at lowered
        · rename_i isInt
          simp only [Option.some.injEq] at lowered
          subst lowered
          simp only [SrcExpr.toCore, evalExpr] at run
          split at run
          · rename_i w mid innerRun
            obtain ⟨rfl, holds⟩ := ih innerLowered innerRun
            cases hty : inner.ty <;> simp [hty, SrcType.isI32] at isInt
            rw [hty] at holds
            simp only [SrcType.Holds] at holds
            subst holds
            simp only [Semantics.evalUnaryValue, target, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            exact ⟨rfl, by simp [SrcType.Holds, Expr.eval, wrap_neg]⟩
          all_goals simp at run
        · simp at lowered
  | not operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerNot] at lowered
      split at lowered
      · simp at lowered
      · rename_i inner innerLowered
        simp only [lowerNotTyped] at lowered
        split at lowered
        · rename_i isBool
          simp only [Option.some.injEq] at lowered
          subst lowered
          simp only [SrcExpr.toCore, evalExpr] at run
          split at run
          · rename_i w mid innerRun
            obtain ⟨rfl, holds⟩ := ih innerLowered innerRun
            cases hty : inner.ty <;> simp [hty, SrcType.isBool] at isBool
            rw [hty] at holds
            obtain ⟨x, rfl, bits⟩ := holds
            simp only [Semantics.evalUnaryValue, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            refine ⟨rfl, !x, rfl, ?_⟩
            cases x <;> simp [Expr.eval, CmpOp.holds, bits, boolBits]
          all_goals simp at run
        · simp at lowered
  | apply op left right ihl ihr =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerApply] at lowered
      split at lowered
      · simp at lowered
      rename_i tl leftLowered
      split at lowered
      · simp at lowered
      rename_i tr rightLowered
      have hl : ∀ {fuel v st'}, evalExpr fuel prog st left.toCore = .done v st' →
          st' = st ∧ tl.ty.Holds v (tl.expr.eval env) := fun h => ihl leftLowered h
      have hr : ∀ {fuel v st'}, evalExpr fuel prog st right.toCore = .done v st' →
          st' = st ∧ tr.ty.Holds v (tr.expr.eval env) := fun h => ihr rightLowered h
      simp only [SrcExpr.toCore] at run
      cases op
      case plus | minus | times | bitAnd | bitOr | bitXor =>
        obtain ⟨rfl, vl, vr, holdsl, holdsr, evaluated⟩ :=
          binary_sound hl hr (by simp [SrcOp.toCore]) run
        simp only [SrcOp.lower, arith] at lowered
        split at lowered
        · rename_i types
          simp only [Option.some.injEq] at lowered
          subst lowered
          cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
          rw [htl] at holdsl
          rw [htr] at holdsr
          simp only [SrcType.Holds] at holdsl holdsr
          subst holdsl holdsr
          rw [target] at evaluated
          simp only [SrcOp.toCore, eval_add, eval_sub, eval_mul, eval_bitAnd, eval_bitOr,
            eval_bitXor, Except.ok.injEq] at evaluated
          subst evaluated
          exact ⟨rfl, by simp [SrcType.Holds, Expr.eval, BinOp.apply]⟩
        · simp at lowered
      case less | lessEq | greater | greaterEq =>
        obtain ⟨rfl, vl, vr, holdsl, holdsr, evaluated⟩ :=
          binary_sound hl hr (by simp [SrcOp.toCore]) run
        simp only [SrcOp.lower, order] at lowered
        split at lowered
        · rename_i types
          simp only [Option.some.injEq] at lowered
          subst lowered
          cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
          rw [htl] at holdsl
          rw [htr] at holdsr
          simp only [SrcType.Holds] at holdsl holdsr
          subst holdsl holdsr
          rw [target] at evaluated
          simp only [SrcOp.toCore] at evaluated
          first
            | rw [eval_order (op := .lt) (h := .inl ⟨rfl, rfl⟩)] at evaluated
            | rw [eval_order (op := .le) (h := .inr (.inl ⟨rfl, rfl⟩))] at evaluated
            | rw [eval_order (op := .gt) (h := .inr (.inr (.inl ⟨rfl, rfl⟩)))] at evaluated
            | rw [eval_order (op := .ge) (h := .inr (.inr (.inr ⟨rfl, rfl⟩)))] at evaluated
          simp only [Except.ok.injEq] at evaluated
          subst evaluated
          refine ⟨rfl, ?_⟩
          simp only [Expr.eval]
          exact holds_compare _
        · simp at lowered
      case equal | notEqual =>
        obtain ⟨rfl, vl, vr, holdsl, holdsr, evaluated⟩ :=
          binary_sound hl hr (by simp [SrcOp.toCore]) run
        simp only [SrcOp.lower, equality] at lowered
        split at lowered
        · rename_i types
          simp only [Option.some.injEq] at lowered
          subst lowered
          refine ⟨rfl, ?_⟩
          rw [target] at evaluated
          simp only [SrcOp.toCore] at evaluated
          cases htl : tl.ty <;> cases htr : tr.ty <;>
            simp [htl, htr, SrcType.same, SrcType.isI32, SrcType.isBool] at types <;>
            rw [htl] at holdsl <;> rw [htr] at holdsr
          · simp only [SrcType.Holds] at holdsl holdsr
            subst holdsl holdsr
            simp only [eval_eq_int, eval_ne_int, Except.ok.injEq] at evaluated
            subst evaluated
            simp only [Expr.eval]
            exact holds_compare _
          · obtain ⟨x, rfl, bitsl⟩ := holdsl
            obtain ⟨y, rfl, bitsr⟩ := holdsr
            simp only [eval_eq_bool, eval_ne_bool, Except.ok.injEq] at evaluated
            subst evaluated
            simp only [Expr.eval, bitsl, bitsr]
            exact holds_compare _
          · simp [SrcType.Holds] at holdsl
          · simp [SrcType.Holds] at holdsl
        · simp at lowered
      case logicalAnd =>
        simp only [SrcOp.lower, conjunction] at lowered
        split at lowered
        · rename_i types
          simp only [Option.some.injEq] at lowered
          subst lowered
          cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isBool] at types
          simp only [SrcOp.toCore, evalExpr] at run
          split at run
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            refine ⟨rfl, false, rfl, ?_⟩
            simp [Expr.eval, BinOp.apply, bitsl, boolBits]
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            obtain ⟨rfl, holdsr⟩ := hr run
            rw [htr] at holdsr
            obtain ⟨y, rfl, bitsr⟩ := holdsr
            refine ⟨rfl, y, rfl, ?_⟩
            cases y <;> simp [Expr.eval, BinOp.apply, bitsl, bitsr, boolBits]
          · rename_i w mid notFalse notTrue leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, rfl, _⟩ := holdsl
            cases x <;> simp_all
          all_goals simp at run
        · simp at lowered
      case logicalOr =>
        simp only [SrcOp.lower, disjunction] at lowered
        split at lowered
        · rename_i types
          simp only [Option.some.injEq] at lowered
          subst lowered
          cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isBool] at types
          simp only [SrcOp.toCore, evalExpr] at run
          split at run
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            refine ⟨rfl, true, rfl, ?_⟩
            simp only [Expr.eval, BinOp.apply, CmpOp.holds, bitsl, boolBits]
            have : (1 : BitVec 32) ||| tr.expr.eval env ≠ 0 := by
              intro h
              have := congrArg (fun x : BitVec 32 => x.getLsbD 0) h
              simp at this
            simp
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            obtain ⟨rfl, holdsr⟩ := hr run
            rw [htr] at holdsr
            obtain ⟨y, rfl, bitsr⟩ := holdsr
            refine ⟨rfl, y, rfl, ?_⟩
            cases y <;> simp [Expr.eval, BinOp.apply, CmpOp.holds, bitsl, bitsr, boolBits]
          · rename_i w mid notTrue notFalse leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, rfl, _⟩ := holdsl
            cases x <;> simp_all
          all_goals simp at run
        · simp at lowered

end Lanius.Mini
