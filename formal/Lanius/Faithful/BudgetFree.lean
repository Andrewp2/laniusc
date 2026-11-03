import Lanius.Faithful.BudgetClosed

/-! # Budget certificates of functions that reach neither `boxed`, `plus` nor `times` (F14)

Most of the self program's functions call neither `boxed` (they cost
nothing) nor `plus` or `times` (they have no precondition), and none of their
callees do. `budget`'s step-by-step run of such a function is wasted: its
certificate is `qcall progW`'s value being `qcall prog`'s at cost 0, which
holds for a reason that does not look at the run.

- `SrcEff.callsOk S` / `SrcStmt.callsOk S`: every function a body calls is
  in the set `S`. This is syntactic, and computable.
- `ZLe o o'`: where `o` has a value, `o'` has the same one, at cost 0.
- `qstmt_z`: a body that calls only functions in `S`, with calls that are
  `ZLe` on `S`, is `ZLe`.
- `qcall_z`: for a set `S` whose functions are all allowed by `ok`, are not
  `boxed` prims, and have bodies that call only functions in `S`, every run of
  `qcall` from `S` is `qcallB ok`'s at cost 0.
- `freeCheck`: that condition on a whole program, for `S` the bits of a
  number, computable, so the kernel checks it once for every function
  (`decide +kernel`).
- `bfree_of`: at `ok = okW`, a run of `progW` from such a function is the self
  program's, at cost 0. -/

namespace Lanius.Mini

/-! ## The functions a body calls -/

mutual
/-- Every function `e` calls is in `S`. -/
def SrcEff.callsOk (S : Nat → Bool) : SrcEff → Bool
  | .ePure _ => true
  | .eCall callee args => S callee && SrcEff.callsOkL S args
  | .eApply _ left right => SrcEff.callsOk S left && SrcEff.callsOk S right
  | .eNeg operand => SrcEff.callsOk S operand
  | .eNot operand => SrcEff.callsOk S operand
  | .eCast _ operand => SrcEff.callsOk S operand
  | .eIndex _ _ => true
  | .eStruct _ fields => SrcEff.callsOkL S fields
  | .eVariant _ _ payload => SrcEff.callsOkL S payload
  | .eMatch scrutinee _ _ _ values => SrcEff.callsOk S scrutinee && SrcEff.callsOkL S values
  | .eDivide _ left right => SrcEff.callsOk S left && SrcEff.callsOk S right
  | .eStride _ => true
  | .arraySlice _ _ => true
  | .eIf condition _ thenValue elseValue =>
      SrcEff.callsOk S condition && SrcEff.callsOk S thenValue && SrcEff.callsOk S elseValue
  | .eLet _ _ value _ body => SrcEff.callsOk S value && SrcEff.callsOk S body
  | .eLen _ | .eStr _ _ => true

/-- Every function the list calls is in `S`. -/
def SrcEff.callsOkL (S : Nat → Bool) : List SrcEff → Bool
  | [] => true
  | e :: es => SrcEff.callsOk S e && SrcEff.callsOkL S es
end

/-- Every function `s` calls is in `S`. The forms `qstmt` has no value at
call nothing it could see. -/
def SrcStmt.callsOk (S : Nat → Bool) : SrcStmt → Bool
  | .nop => true
  | .let _ _ _ body => SrcStmt.callsOk S body
  | .letStruct _ _ _ body => SrcStmt.callsOk S body
  | .letCall _ _ callee _ body => S callee && SrcStmt.callsOk S body
  | .letEnum _ _ _ _ body => SrcStmt.callsOk S body
  | .letMatch _ _ _ _ _ _ => true
  | .set _ _ => true
  | .setField _ _ _ => true
  | .setCall _ _ _ => true
  | .then first second => SrcStmt.callsOk S first && SrcStmt.callsOk S second
  | .if _ thenBranch elseBranch => SrcStmt.callsOk S thenBranch && SrcStmt.callsOk S elseBranch
  | .while _ body => SrcStmt.callsOk S body
  | .return _ => true
  | .letAlloc _ _ _ _ => true
  | .letLoad _ _ _ _ => true
  | .setByte _ _ _ => true
  | .free _ _ _ => true
  | .letSlice _ _ _ _ _ => true
  | .letIndex _ _ _ _ _ => true
  | .setIndex _ _ _ => true
  | .letEval _ _ value body => value.callsOk S && SrcStmt.callsOk S body
  | .setEval _ value => value.callsOk S
  | .ifEval condition thenBranch elseBranch =>
      condition.callsOk S && SrcStmt.callsOk S thenBranch && SrcStmt.callsOk S elseBranch
  | .whileEval condition body => condition.callsOk S && SrcStmt.callsOk S body
  | .returnEval value => value.callsOk S
  | .discard value => value.callsOk S
  | .setIndexEval _ _ _ => true
  | .setFieldEval _ _ _ => true
  | .returnUnit => true
  | .assert condition => condition.callsOk S
  | .break => true
  | .continue => true
  | .matchArm _ _ _ _ _ _ _ _ => true
  | .unreachable _ _ => true
  | .letView _ _ _ _ _ => true
  | .letStr _ _ _ => true

end Lanius.Mini

namespace Lanius.Faithful.Budget

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Termination
open Lanius.Core (Value)

/-! ## The same value, at no cost -/

/-- Where `o` has a value, `o'` has the same one, and its cost is 0. -/
def ZLe {α : Type} (o o' : Option (α × Nat)) : Prop :=
  ∀ x, o = some x → o' = some x ∧ x.2 = 0

/-- The calls are `ZLe` on `S`. -/
def QCallsZ (S : Nat → Bool) (call call' : QCalls) : Prop :=
  ∀ c vs, S c = true → ZLe (call c vs) (call' c vs)

section
variable {α β : Type}

theorem zle_none : ZLe (none : Option (α × Nat)) none := fun _ h => by cases h

theorem zle_some (x : α) : ZLe (some (x, 0)) (some (x, 0)) := fun _ h => by
  cases h
  exact ⟨rfl, rfl⟩

theorem zle_qfree (o : Option α) : ZLe (qfree o) (qfree o) := by
  cases o with
  | none => exact zle_none
  | some x => exact zle_some x

theorem zle_qthen {o o' : Option (α × Nat)} {k k' : α → Option (β × Nat)}
    (ho : ZLe o o') (hk : ∀ x, ZLe (k x) (k' x)) : ZLe (qthen o k) (qthen o' k') := by
  intro w h
  cases o with
  | none => cases h
  | some p =>
    obtain ⟨h1, h2⟩ := ho p rfl
    rw [h1]
    cases hq : k p.1 with
    | none => rw [qthen_some, hq] at h; cases h
    | some q =>
      rw [qthen_some, hq, addC_some] at h
      cases h
      obtain ⟨h3, h4⟩ := hk p.1 q hq
      rw [qthen_some, h3, addC_some, h2, h4]
      exact ⟨rfl, rfl⟩

theorem zle_bind {γ : Type} (a : Option γ) {k k' : γ → Option (β × Nat)}
    (hk : ∀ x, ZLe (k x) (k' x)) : ZLe (a.bind k) (a.bind k') := by
  cases a with
  | none => exact zle_none
  | some x => exact hk x

theorem zle_ite (c : Prop) [Decidable c] {a a' b b' : Option (α × Nat)} (ha : ZLe a a') (hb : ZLe b b') :
    ZLe (if c then a else b) (if c then a' else b') := by
  split
  · exact ha
  · exact hb

theorem zle_qpop {o o' : Option (Out × Nat)} (ho : ZLe o o') : ZLe (qpop o) (qpop o') := by
  intro w h
  cases o with
  | none => cases h
  | some p =>
    obtain ⟨h1, h2⟩ := ho p rfl
    rw [h1]
    unfold qpop at h ⊢
    simp only [Option.map_some, Option.some.injEq] at h ⊢
    subst h
    exact ⟨rfl, h2⟩

theorem zle_qbinary (op : Core.BinaryOp) {a a' b b' : Option (Value × Nat)} (ha : ZLe a a') (hb : ZLe b b') :
    ZLe (qbinary op a b) (qbinary op a' b') :=
  zle_qthen ha fun _ => zle_qthen hb fun _ => zle_qfree _

theorem zle_qapplyOp (op : SrcOp) {a a' b b' : Option (Value × Nat)} (ha : ZLe a a') (hb : ZLe b b') :
    ZLe (qapplyOp op a b) (qapplyOp op a' b') := by
  cases op with
  | logicalAnd =>
    exact zle_qthen ha fun l => zle_bind (asBool l) fun x => zle_ite (x = true) hb (zle_some _)
  | logicalOr =>
    exact zle_qthen ha fun l => zle_bind (asBool l) fun x => zle_ite (x = true) (zle_some _) hb
  | plus | minus | times | bitAnd | bitOr | bitXor | shiftLeft | shiftRight | less | lessEq | greater
  | greaterEq | equal | notEqual => exact zle_qbinary _ ha hb

theorem zle_outThen {rest rest' : Env → Option (Out × Nat)} (hr : ∀ e, ZLe (rest e) (rest' e)) :
    ∀ o, ZLe (Out.qthen rest o) (Out.qthen rest' o)
  | .next e => hr e
  | .brk _ => zle_some _
  | .cont _ => zle_some _
  | .ret _ => zle_some _

theorem zle_qloop {test test' : Env → Option (Bool × Nat)} {body body' : Env → Option (Out × Nat)}
    (ht : ∀ e, ZLe (test e) (test' e)) (hb : ∀ e, ZLe (body e) (body' e)) :
    ∀ (n : Nat) (env : Env), ZLe (qloop test body n env) (qloop test' body' n env)
  | 0, _ => zle_none
  | n + 1, env => by
    rw [qloop, qloop]
    refine zle_qthen (ht env) fun b => zle_ite (b = true) (zle_qthen (hb env) fun o => ?_) (zle_some _)
    cases o with
    | next e => exact zle_qloop ht hb n e
    | cont e => exact zle_qloop ht hb n e
    | brk e => exact zle_some _
    | ret value => exact zle_some _

end

/-! ## Bodies -/

section
variable {S : Nat → Bool} {call call' : QCalls}

mutual
theorem qeff_z (hc : QCallsZ S call call') :
    ∀ (env : Env) (e : SrcEff), e.callsOk S = true → ZLe (qeff call env e) (qeff call' env e)
  | _, .ePure _, _ => zle_qfree _
  | env, .eCall callee args, hs => by
    simp only [SrcEff.callsOk, Bool.and_eq_true] at hs
    simp only [qeff]
    exact zle_qthen (qeffs_z hc env args hs.2) fun vs => hc callee vs hs.1
  | env, .eApply op l r, hs => by
    simp only [SrcEff.callsOk, Bool.and_eq_true] at hs
    simp only [qeff]
    exact zle_qapplyOp op (qeff_z hc env l hs.1) (qeff_z hc env r hs.2)
  | env, .eNeg o, hs => by
    simp only [SrcEff.callsOk] at hs
    simp only [qeff]
    exact zle_qthen (qeff_z hc env o hs) fun _ => zle_qfree _
  | env, .eNot o, hs => by
    simp only [SrcEff.callsOk] at hs
    simp only [qeff]
    exact zle_qthen (qeff_z hc env o hs) fun _ => zle_qfree _
  | env, .eCast ty o, hs => by
    simp only [SrcEff.callsOk] at hs
    simp only [qeff]
    exact zle_qthen (qeff_z hc env o hs) fun _ => zle_qfree _
  | _, .eIndex _ _, _ => zle_none
  | env, .eStruct ty fields, hs => by
    simp only [SrcEff.callsOk] at hs
    simp only [qeff]
    exact zle_qthen (qeffs_z hc env fields hs) fun _ => zle_some _
  | env, .eVariant ty variant payload, hs => by
    simp only [SrcEff.callsOk] at hs
    simp only [qeff]
    exact zle_qthen (qeffs_z hc env payload hs) fun _ => zle_some _
  | env, .eMatch scrutinee ety rty binders values, hs => by
    simp only [SrcEff.callsOk, Bool.and_eq_true] at hs
    simp only [qeff]
    exact zle_qthen (qeff_z hc env scrutinee hs.1) fun v => qarms_z hc env v _ 0 binders values hs.2
  | env, .eDivide op l r, hs => by
    simp only [SrcEff.callsOk, Bool.and_eq_true] at hs
    simp only [qeff]
    exact zle_qbinary _ (qeff_z hc env l hs.1) (qeff_z hc env r hs.2)
  | _, .eStride _, _ => zle_none
  | _, .arraySlice _ _, _ => zle_none
  | env, .eIf c _ a b, hs => by
    simp only [SrcEff.callsOk, Bool.and_eq_true] at hs
    simp only [qeff]
    exact zle_qthen (qeff_z hc env c hs.1.1) fun x => zle_bind (asBool x) fun bb =>
      zle_ite (bb = true) (qeff_z hc env a hs.1.2) (qeff_z hc env b hs.2)
  | env, .eLet id _ value _ body, hs => by
    simp only [SrcEff.callsOk, Bool.and_eq_true] at hs
    simp only [qeff]
    exact zle_qthen (qeff_z hc env value hs.1) fun v => qeff_z hc ((id, v) :: env) body hs.2
  | _, .eLen _, _ | _, .eStr _ _, _ => zle_none

theorem qeffs_z (hc : QCallsZ S call call') :
    ∀ (env : Env) (es : List SrcEff), SrcEff.callsOkL S es = true → ZLe (qeffs call env es) (qeffs call' env es)
  | _, [], _ => zle_some _
  | env, e :: es, hs => by
    simp only [SrcEff.callsOkL, Bool.and_eq_true] at hs
    simp only [qeffs]
    exact zle_qthen (qeff_z hc env e hs.1) fun _ => zle_qthen (qeffs_z hc env es hs.2) fun _ => zle_some _

theorem qarms_z (hc : QCallsZ S call call') :
    ∀ (env : Env) (v : Value) (id k : Nat) (binders : List (List Nat)) (values : List SrcEff),
      SrcEff.callsOkL S values = true → ZLe (qarms call env v id k binders values) (qarms call' env v id k binders values)
  | _, _, _, _, [], _, _ => fun _ h => by simp [qarms] at h
  | _, _, _, _, _ :: _, [], _ => fun _ h => by simp [qarms] at h
  | env, v, id, k, bs :: rest, value :: values, hs => by
    simp only [SrcEff.callsOkL, Bool.and_eq_true] at hs
    simp only [qarms]
    split
    · exact qarms_z hc env v id (k + 1) rest values hs.2
    · exact qeff_z hc _ value hs.1
end

/-- A body that calls only functions in `S`, with calls `ZLe` on `S`, is `ZLe`. -/
theorem qstmt_z (hc : QCallsZ S call call') (fuel : Nat) (s : SrcStmt) :
    s.callsOk S = true → ∀ (env : Env), ZLe (qstmt call fuel env s) (qstmt call' fuel env s) := by
  induction s with
  | nop => intro _ env; exact zle_some _
  | «let» id ty value body ih =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_bind _ fun v => zle_qpop (ih hs _)
  | letStruct id ty fields body ih =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_bind _ fun v => zle_qpop (ih hs _)
  | letCall id ty callee args body ih =>
    intro hs env
    simp only [SrcStmt.callsOk, Bool.and_eq_true] at hs
    simp only [qstmt]
    exact zle_qthen (zle_bind _ fun vs => hc callee vs hs.1) fun v => zle_qpop (ih hs.2 _)
  | letEnum id ty variant payload body ih =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_bind _ fun v => zle_qpop (ih hs _)
  | letMatch => intro _ env; exact zle_none
  | set => intro _ env; exact zle_qfree _
  | setField => intro _ env; exact zle_none
  | setCall => intro _ env; exact zle_none
  | «then» first second ih1 ih2 =>
    intro hs env
    simp only [SrcStmt.callsOk, Bool.and_eq_true] at hs
    simp only [qstmt]
    exact zle_qthen (ih1 hs.1 env) (zle_outThen fun e => ih2 hs.2 e)
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro hs env
    simp only [SrcStmt.callsOk, Bool.and_eq_true] at hs
    simp only [qstmt]
    exact zle_bind _ fun b => zle_ite (b = true) (ih1 hs.1 env) (ih2 hs.2 env)
  | «while» condition body ih =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_qloop (fun _ => zle_qfree _) (fun e => ih hs e) fuel env
  | «return» => intro _ env; exact zle_qfree _
  | letAlloc => intro _ env; exact zle_none
  | letView => intro _ env; exact zle_none
  | letStr => intro _ env; exact zle_none
  | letLoad => intro _ env; exact zle_none
  | setByte => intro _ env; exact zle_none
  | free => intro _ env; exact zle_none
  | letSlice => intro _ env; exact zle_none
  | letIndex => intro _ env; exact zle_none
  | setIndex => intro _ env; exact zle_none
  | letEval id ty value body ih =>
    intro hs env
    simp only [SrcStmt.callsOk, Bool.and_eq_true] at hs
    simp only [qstmt]
    exact zle_qthen (qeff_z hc env value hs.1) fun v => zle_qpop (ih hs.2 _)
  | setEval id value =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_qthen (qeff_z hc env value hs) fun _ => zle_qfree _
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro hs env
    simp only [SrcStmt.callsOk, Bool.and_eq_true] at hs
    simp only [qstmt]
    exact zle_qthen (qeff_z hc env condition hs.1.1) fun c => zle_bind (asBool c) fun b =>
      zle_ite (b = true) (ih1 hs.1.2 env) (ih2 hs.2 env)
  | whileEval condition body ih =>
    intro hs env
    simp only [SrcStmt.callsOk, Bool.and_eq_true] at hs
    simp only [qstmt]
    exact zle_qloop (fun e => zle_qthen (qeff_z hc e condition hs.1) fun _ => zle_qfree _)
      (fun e => ih hs.2 e) fuel env
  | returnEval value =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_qthen (qeff_z hc env value hs) fun _ => zle_some _
  | discard value =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_qthen (qeff_z hc env value hs) fun _ => zle_some _
  | setIndexEval => intro _ env; exact zle_none
  | setFieldEval => intro _ env; exact zle_none
  | returnUnit => intro _ env; exact zle_some _
  | «assert» condition =>
    intro hs env
    simp only [SrcStmt.callsOk] at hs
    simp only [qstmt]
    exact zle_qthen (qeff_z hc env condition hs) fun c => zle_bind (asBool c) fun b =>
      zle_ite (b = true) (zle_some _) zle_none
  | «break» => intro _ env; exact zle_some _
  | «continue» => intro _ env; exact zle_some _
  | matchArm => intro _ env; exact zle_none
  | unreachable => intro _ env; exact zle_none

end

/-! ## Calls -/

/-- What `qcall_z` needs of a set of functions. -/
def FreeSet (sp : SrcProgram) (prims : Prims) (ok S : Nat → Bool) : Prop :=
  ∀ c, S c = true → ok c = true ∧ (prims.isPrim c = true → prims.boxed.contains c = false) ∧
    ∀ f, prims.isPrim c = false → sp.funcs[c]? = some f → f.body.callsOk S = true

/-- A run from a function of a `FreeSet` is `qcallB`'s, at cost 0. -/
theorem qcall_z {sp : SrcProgram} {prims : Prims} {cost : Nat → Nat} {ok S : Nat → Bool}
    (hS : FreeSet sp prims ok S) : ∀ n, QCallsZ S (qcall sp prims cost n) (qcallB sp prims cost ok n)
  | 0 => fun _ _ _ => zle_none
  | n + 1 => fun c vs hc => by
    obtain ⟨hok, hbx, hf⟩ := hS c hc
    simp only [qcall, qcallB, hok, if_true]
    by_cases prim : prims.isPrim c = true
    · rw [if_pos prim, if_pos prim, hbx prim]
      cases single vs with
      | none => exact zle_none
      | some v => exact zle_some v
    · rw [if_neg prim, if_neg prim]
      cases hfc : sp.funcs[c]? with
      | none => exact zle_none
      | some f =>
        simp only
        refine zle_ite _ ?_ zle_none
        exact zle_qthen (qstmt_z (qcall_z hS n) n f.body (hf f (by simpa using prim) hfc) _) fun _ => zle_qfree _

/-! ## The check over a whole program -/

/-- `FreeSet` at the bits of `mask`, for the functions `fs` from index `i`
on, and no bit of `mask` past them. -/
def freeCheck (mask : Nat) (prims : Prims) (ok : Nat → Bool) : Nat → List SrcFunc → Bool
  | i, [] => mask >>> i == 0
  | i, f :: fs =>
    (!mask.testBit i ||
      (ok i && (!prims.isPrim i || !prims.boxed.contains i) &&
        (prims.isPrim i || f.body.callsOk mask.testBit))) &&
    freeCheck mask prims ok (i + 1) fs

theorem freeCheck_spec {mask : Nat} {prims : Prims} {ok : Nat → Bool} :
    ∀ (i : Nat) (fs : List SrcFunc), freeCheck mask prims ok i fs = true →
      ∀ c, i ≤ c → mask.testBit c = true →
        ok c = true ∧ (prims.isPrim c = true → prims.boxed.contains c = false) ∧
          ∀ f, prims.isPrim c = false → fs[c - i]? = some f → f.body.callsOk mask.testBit = true
  | i, [], h, c, le, bit => by
    simp only [freeCheck, beq_iff_eq] at h
    have : mask.testBit c = (mask >>> i).testBit (c - i) := by
      rw [Nat.testBit_shiftRight]
      congr 1
      omega
    rw [this, h, Nat.zero_testBit] at bit
    cases bit
  | i, f :: fs, h, c, le, bit => by
    simp only [freeCheck, Bool.and_eq_true] at h
    by_cases eq : c = i
    · subst eq
      simp only [bit, Bool.not_true, Bool.false_or, Bool.and_eq_true] at h
      obtain ⟨⟨⟨hok, hb⟩, hbody⟩, _⟩ := h
      refine ⟨hok, fun p => ?_, fun g np hg => ?_⟩
      · simpa [p] using hb
      · simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at hg
        subst hg
        simpa [np] using hbody
    · obtain ⟨hok, hb, hbody⟩ := freeCheck_spec (i + 1) fs h.2 c (by omega) bit
      refine ⟨hok, hb, fun g np hg => hbody g np ?_⟩
      have : c - i = (c - (i + 1)) + 1 := by omega
      rw [this, List.getElem?_cons_succ] at hg
      exact hg

theorem freeSet_of_check {mask : Nat} {sp : SrcProgram} {prims : Prims} {ok : Nat → Bool}
    (h : freeCheck mask prims ok 0 sp.funcs = true) : FreeSet sp prims ok mask.testBit := by
  intro c bit
  obtain ⟨hok, hb, hbody⟩ := freeCheck_spec 0 sp.funcs h c (Nat.zero_le c) bit
  exact ⟨hok, hb, fun f np hf => hbody f np (by simpa using hf)⟩

open Lanius.Faithful.SelfPanics in
/-- **The budget certificate of a function that reaches neither `boxed`,
`plus` nor `times`**, from the kernel's check of the self program at the
bits of `mask`: a run of `progW` from such a function is the self program's,
at cost 0. -/
theorem bfree_of {mask : Nat} (check : freeCheck mask SelfPure.prims okW 0 Self.prog.funcs = true)
    {ix n : Nat} {vs : List Value} {w : Value} {k : Nat} (bit : mask.testBit ix = true)
    (h : qcall progW SelfPure.prims uc n ix vs = some (w, k)) :
    qcall Self.prog SelfPure.prims uc n ix vs = some (w, k) ∧ 0 = k := by
  have hS : FreeSet progW SelfPure.prims okW mask.testBit := by
    intro c hc
    obtain ⟨hok, hb, hbody⟩ := freeSet_of_check check c hc
    refine ⟨hok, hb, fun f np hf => hbody f np ?_⟩
    have ne := okW_ne hok
    rwa [progW, wrapAt_ne ne.2, wrapAt_ne ne.1] at hf
  obtain ⟨h1, h2⟩ := qcall_z hS n ix vs bit (w, k) h
  exact ⟨(qcall_of_okW h1).1, h2.symm⟩

end Lanius.Faithful.Budget
