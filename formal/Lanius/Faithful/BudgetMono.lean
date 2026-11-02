import Lanius.Faithful.Budget

/-! # A run's cost grows with the cost of each `boxed` call (F14)

`qcall` counts `cost c` at each call of a `boxed` prim `c`. The budget
certificates count blocks (`uc`, 1 for each), the heap counts bytes
(`boxCost prog`, at least 8 for each): a run has the same value under both,
and where every `boxed` prim costs at least as much under `cost'` as under
`cost`, the run costs at least as much under `cost'`.

- `CLe o o'`: where `o` has a value, `o'` has the same one at a cost at
  least `o`'s.
- `qcall_cle`: `qcall` at `cost` and at `cost'` are `CLe` when
  `cost c ≤ cost' c` at every `boxed` prim `c`. -/

namespace Lanius.Faithful.Budget

open Lanius.Mini
open Lanius.Faithful
open Lanius.Core (Value)

/-- Where `o` has a value, `o'` has the same one, at a cost at least `o`'s. -/
def CLe {α : Type} (o o' : Option (α × Nat)) : Prop :=
  ∀ x, o = some x → ∃ k, o' = some (x.1, k) ∧ x.2 ≤ k

section
variable {α β : Type}

theorem cle_none (o' : Option (α × Nat)) : CLe none o' := fun _ h => by cases h

theorem cle_refl (o : Option (α × Nat)) : CLe o o := fun x h => ⟨x.2, by rw [h], Nat.le_refl _⟩

theorem cle_qthen {o o' : Option (α × Nat)} {k k' : α → Option (β × Nat)}
    (ho : CLe o o') (hk : ∀ x, CLe (k x) (k' x)) : CLe (qthen o k) (qthen o' k') := by
  intro w h
  cases o with
  | none => cases h
  | some p =>
    obtain ⟨c, h1, h2⟩ := ho p rfl
    rw [h1]
    cases hq : k p.1 with
    | none => rw [qthen_some, hq] at h; cases h
    | some q =>
      rw [qthen_some, hq, addC_some] at h
      cases h
      obtain ⟨d, h3, h4⟩ := hk p.1 q hq
      rw [qthen_some, h3, addC_some]
      exact ⟨c + d, rfl, Nat.add_le_add h2 h4⟩

theorem cle_bind {γ : Type} (a : Option γ) {k k' : γ → Option (β × Nat)}
    (hk : ∀ x, CLe (k x) (k' x)) : CLe (a.bind k) (a.bind k') := by
  cases a with
  | none => exact cle_none _
  | some x => exact hk x

theorem cle_ite (c : Prop) [Decidable c] {a a' b b' : Option (α × Nat)} (ha : CLe a a') (hb : CLe b b') :
    CLe (if c then a else b) (if c then a' else b') := by
  split
  · exact ha
  · exact hb

theorem cle_qpop {o o' : Option (Out × Nat)} (ho : CLe o o') : CLe (qpop o) (qpop o') := by
  intro w h
  cases o with
  | none => cases h
  | some p =>
    obtain ⟨c, h1, h2⟩ := ho p rfl
    rw [h1]
    unfold qpop at h ⊢
    simp only [Option.map_some, Option.some.injEq] at h ⊢
    subst h
    exact ⟨c, rfl, h2⟩

theorem cle_qbinary (op : Core.BinaryOp) {a a' b b' : Option (Value × Nat)} (ha : CLe a a') (hb : CLe b b') :
    CLe (qbinary op a b) (qbinary op a' b') :=
  cle_qthen ha fun _ => cle_qthen hb fun _ => cle_refl _

theorem cle_qapplyOp (op : SrcOp) {a a' b b' : Option (Value × Nat)} (ha : CLe a a') (hb : CLe b b') :
    CLe (qapplyOp op a b) (qapplyOp op a' b') := by
  cases op with
  | logicalAnd =>
    exact cle_qthen ha fun l => cle_bind (asBool l) fun x => cle_ite (x = true) hb (cle_refl _)
  | logicalOr =>
    exact cle_qthen ha fun l => cle_bind (asBool l) fun x => cle_ite (x = true) (cle_refl _) hb
  | plus | minus | times | bitAnd | bitOr | bitXor | shiftLeft | shiftRight | less | lessEq | greater
  | greaterEq | equal | notEqual => exact cle_qbinary _ ha hb

theorem cle_outThen {rest rest' : Env → Option (Out × Nat)} (hr : ∀ e, CLe (rest e) (rest' e)) :
    ∀ o, CLe (Out.qthen rest o) (Out.qthen rest' o)
  | .next e => hr e
  | .brk _ => cle_refl _
  | .cont _ => cle_refl _
  | .ret _ => cle_refl _

theorem cle_qloop {test test' : Env → Option (Bool × Nat)} {body body' : Env → Option (Out × Nat)}
    (ht : ∀ e, CLe (test e) (test' e)) (hb : ∀ e, CLe (body e) (body' e)) :
    ∀ (n : Nat) (env : Env), CLe (qloop test body n env) (qloop test' body' n env)
  | 0, _ => cle_none _
  | n + 1, env => by
    rw [qloop, qloop]
    refine cle_qthen (ht env) fun b => cle_ite (b = true) (cle_qthen (hb env) fun o => ?_) (cle_refl _)
    cases o with
    | next e => exact cle_qloop ht hb n e
    | cont e => exact cle_qloop ht hb n e
    | brk e => exact cle_refl _
    | ret value => exact cle_refl _

end

/-! ## Bodies -/

section
variable {call call' : QCalls}

mutual
theorem qeff_cle (hc : ∀ c vs, CLe (call c vs) (call' c vs)) :
    ∀ (env : Env) (e : SrcEff), CLe (qeff call env e) (qeff call' env e)
  | _, .ePure _ => cle_refl _
  | env, .eCall callee args => by
    simp only [qeff]
    exact cle_qthen (qeffs_cle hc env args) fun vs => hc callee vs
  | env, .eApply op l r => by
    simp only [qeff]
    exact cle_qapplyOp op (qeff_cle hc env l) (qeff_cle hc env r)
  | env, .eNeg o => by
    simp only [qeff]
    exact cle_qthen (qeff_cle hc env o) fun _ => cle_refl _
  | env, .eNot o => by
    simp only [qeff]
    exact cle_qthen (qeff_cle hc env o) fun _ => cle_refl _
  | env, .eCast ty o => by
    simp only [qeff]
    exact cle_qthen (qeff_cle hc env o) fun _ => cle_refl _
  | _, .eIndex _ _ => cle_none _
  | env, .eStruct ty fields => by
    simp only [qeff]
    exact cle_qthen (qeffs_cle hc env fields) fun _ => cle_refl _
  | env, .eVariant ty variant payload => by
    simp only [qeff]
    exact cle_qthen (qeffs_cle hc env payload) fun _ => cle_refl _
  | env, .eMatch scrutinee ety rty binders values => by
    simp only [qeff]
    exact cle_qthen (qeff_cle hc env scrutinee) fun v => qarms_cle hc env v _ 0 binders values
  | env, .eDivide op l r => by
    simp only [qeff]
    exact cle_qbinary _ (qeff_cle hc env l) (qeff_cle hc env r)
  | _, .eStride _ => cle_none _
  | _, .arraySlice _ _ => cle_none _
  | env, .eIf c _ a b => by
    simp only [qeff]
    exact cle_qthen (qeff_cle hc env c) fun x => cle_bind (asBool x) fun bb =>
      cle_ite (bb = true) (qeff_cle hc env a) (qeff_cle hc env b)
  | env, .eLet id _ value _ body => by
    simp only [qeff]
    exact cle_qthen (qeff_cle hc env value) fun v => qeff_cle hc ((id, v) :: env) body
  | _, .eLen _ => cle_none _

theorem qeffs_cle (hc : ∀ c vs, CLe (call c vs) (call' c vs)) :
    ∀ (env : Env) (es : List SrcEff), CLe (qeffs call env es) (qeffs call' env es)
  | _, [] => cle_refl _
  | env, e :: es => by
    simp only [qeffs]
    exact cle_qthen (qeff_cle hc env e) fun _ => cle_qthen (qeffs_cle hc env es) fun _ => cle_refl _

theorem qarms_cle (hc : ∀ c vs, CLe (call c vs) (call' c vs)) :
    ∀ (env : Env) (v : Value) (id k : Nat) (binders : List (List Nat)) (values : List SrcEff),
      CLe (qarms call env v id k binders values) (qarms call' env v id k binders values)
  | _, _, _, _, [], _ => fun _ h => by simp [qarms] at h
  | _, _, _, _, _ :: _, [] => fun _ h => by simp [qarms] at h
  | env, v, id, k, bs :: rest, value :: values => by
    simp only [qarms]
    split
    · exact qarms_cle hc env v id (k + 1) rest values
    · exact qeff_cle hc _ value
end

theorem qstmt_cle (hc : ∀ c vs, CLe (call c vs) (call' c vs)) (fuel : Nat) (s : SrcStmt) :
    ∀ (env : Env), CLe (qstmt call fuel env s) (qstmt call' fuel env s) := by
  induction s with
  | nop => intro env; exact cle_refl _
  | «let» id ty value body ih =>
    intro env
    simp only [qstmt]
    exact cle_bind _ fun v => cle_qpop (ih _)
  | letStruct id ty fields body ih =>
    intro env
    simp only [qstmt]
    exact cle_bind _ fun v => cle_qpop (ih _)
  | letCall id ty callee args body ih =>
    intro env
    simp only [qstmt]
    exact cle_qthen (cle_bind _ fun vs => hc callee vs) fun v => cle_qpop (ih _)
  | letEnum id ty variant payload body ih =>
    intro env
    simp only [qstmt]
    exact cle_bind _ fun v => cle_qpop (ih _)
  | letMatch => intro env; exact cle_none _
  | set => intro env; exact cle_refl _
  | setField => intro env; exact cle_none _
  | setCall => intro env; exact cle_none _
  | «then» first second ih1 ih2 =>
    intro env
    simp only [qstmt]
    exact cle_qthen (ih1 env) (cle_outThen fun e => ih2 e)
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro env
    simp only [qstmt]
    exact cle_bind _ fun b => cle_ite (b = true) (ih1 env) (ih2 env)
  | «while» condition body ih =>
    intro env
    simp only [qstmt]
    exact cle_qloop (fun _ => cle_refl _) (fun e => ih e) fuel env
  | «return» => intro env; exact cle_refl _
  | letAlloc => intro env; exact cle_none _
  | letLoad => intro env; exact cle_none _
  | setByte => intro env; exact cle_none _
  | free => intro env; exact cle_none _
  | letSlice => intro env; exact cle_none _
  | letIndex => intro env; exact cle_none _
  | setIndex => intro env; exact cle_none _
  | letEval id ty value body ih =>
    intro env
    simp only [qstmt]
    exact cle_qthen (qeff_cle hc env value) fun v => cle_qpop (ih _)
  | setEval id value =>
    intro env
    simp only [qstmt]
    exact cle_qthen (qeff_cle hc env value) fun _ => cle_refl _
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro env
    simp only [qstmt]
    exact cle_qthen (qeff_cle hc env condition) fun c => cle_bind (asBool c) fun b =>
      cle_ite (b = true) (ih1 env) (ih2 env)
  | whileEval condition body ih =>
    intro env
    simp only [qstmt]
    exact cle_qloop (fun e => cle_qthen (qeff_cle hc e condition) fun _ => cle_refl _) (fun e => ih e) fuel env
  | returnEval value =>
    intro env
    simp only [qstmt]
    exact cle_qthen (qeff_cle hc env value) fun _ => cle_refl _
  | discard value =>
    intro env
    simp only [qstmt]
    exact cle_qthen (qeff_cle hc env value) fun _ => cle_refl _
  | setIndexEval => intro env; exact cle_none _
  | setFieldEval => intro env; exact cle_none _
  | returnUnit => intro env; exact cle_refl _
  | «assert» condition =>
    intro env
    simp only [qstmt]
    exact cle_qthen (qeff_cle hc env condition) fun c => cle_bind (asBool c) fun b =>
      cle_ite (b = true) (cle_refl _) (cle_none _)
  | «break» => intro env; exact cle_refl _
  | «continue» => intro env; exact cle_refl _
  | matchArm => intro env; exact cle_none _
  | unreachable => intro env; exact cle_none _

end

/-! ## Calls -/

/-- **A run costs at least as much where each `boxed` call does.** -/
theorem qcall_cle {sp : SrcProgram} {prims : Prims} {cost cost' : Nat → Nat}
    (le : ∀ c, prims.boxed.contains c = true → cost c ≤ cost' c) :
    ∀ n c vs, CLe (qcall sp prims cost n c vs) (qcall sp prims cost' n c vs)
  | 0 => fun _ _ => cle_none _
  | n + 1 => fun c vs => by
    simp only [qcall]
    by_cases prim : prims.isPrim c = true
    · rw [if_pos prim, if_pos prim]
      cases single vs with
      | none => exact cle_none _
      | some v =>
        intro x h
        simp only [Option.map_some, Option.some.injEq] at h
        subst h
        refine ⟨if prims.boxed.contains c then cost' c else 0, rfl, ?_⟩
        by_cases bx : prims.boxed.contains c = true
        · simp only [bx, if_true]
          exact le c bx
        · simp only [bx, Bool.false_eq_true, if_false, Nat.le_refl]
    · rw [if_neg prim, if_neg prim]
      cases sp.funcs[c]? with
      | none => exact cle_none _
      | some f =>
        simp only
        refine cle_ite _ ?_ (cle_none _)
        exact cle_qthen (qstmt_cle (qcall_cle le n) n f.body _) fun _ => cle_refl _

end Lanius.Faithful.Budget
