import Lanius.Faithful.Cost
import Lanius.Faithful.Sim.Mono

/-! # The cost semantics is monotone in its calls

`Sim/Mono.lean` for `qcall`: calls that give the same value and cost where
they gave any (`QCallsLe`) give bodies the same value and cost. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)

/-- `call'` gives every value and cost `call` gives. -/
def QCallsLe (call call' : QCalls) : Prop :=
  ∀ c vs w, call c vs = some w → call' c vs = some w

theorem qthen_mono {α β : Type} {o o' : Option (α × Nat)} {k k' : α → Option (β × Nat)} {w : β × Nat}
    (ho : ∀ x, o = some x → o' = some x) (hk : ∀ x w, k x = some w → k' x = some w)
    (h : qthen o k = some w) : qthen o' k' = some w := by
  unfold qthen at h ⊢
  refine bind_mono ho (fun p w hp => ?_) h
  unfold addC at hp ⊢
  simp only [Option.map_eq_some_iff] at hp ⊢
  obtain ⟨q, hq, rfl⟩ := hp
  exact ⟨q, hk _ _ hq, rfl⟩

theorem qapplyOp_mono {op : SrcOp} {a a' b b' : Option (Value × Nat)} {v : Value × Nat}
    (ha : ∀ x, a = some x → a' = some x) (hb : ∀ x, b = some x → b' = some x)
    (h : qapplyOp op a b = some v) : qapplyOp op a' b' = some v := by
  cases a with
  | none => cases op <;> simp [qapplyOp, qbinary, qthen] at h
  | some x =>
    rw [ha x rfl]
    cases b with
    | some y => rw [hb y rfl]; exact h
    | none =>
      cases op <;> simp only [qapplyOp, qbinary, qthen, Option.bind_some, Option.bind_none] at h ⊢
      all_goals first
        | (simp [addC] at h; done)
        | (revert h
           cases asBool x.1 with
           | none => simp [addC]
           | some bb => cases bb <;> simp [addC])

section
variable {call call' : QCalls}

mutual
theorem qeff_mono (le : QCallsLe call call') :
    ∀ {env : Env} {e : SrcEff} {v : Value × Nat}, qeff call env e = some v → qeff call' env e = some v
  | _, .ePure _, _, h => h
  | env, .eCall callee args, _, h => by
    simp only [qeff] at h ⊢
    exact qthen_mono (fun _ hx => qeffs_mono le hx) (fun _ _ hc => le _ _ _ hc) h
  | env, .eApply op l r, _, h => by
    simp only [qeff] at h ⊢
    exact qapplyOp_mono (fun _ hx => qeff_mono le hx) (fun _ hx => qeff_mono le hx) h
  | env, .eNeg o, _, h => by
    simp only [qeff] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => hx) h
  | env, .eNot o, _, h => by
    simp only [qeff] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => hx) h
  | env, .eCast ty o, _, h => by
    simp only [qeff] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => hx) h
  | _, .eIndex _ _, _, h => by simp [qeff] at h
  | env, .eStruct ty fields, _, h => by
    simp only [qeff] at h ⊢
    exact qthen_mono (fun _ hx => qeffs_mono le hx) (fun _ _ hx => hx) h
  | env, .eVariant ty variant payload, _, h => by
    simp only [qeff] at h ⊢
    exact qthen_mono (fun _ hx => qeffs_mono le hx) (fun _ _ hx => hx) h
  | env, .eMatch scrutinee ety rty binders values, _, h => by
    simp only [qeff] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => qarms_mono le hx) h
  | env, .eDivide op l r, _, h => by
    simp only [qeff, qbinary] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx)
      (fun _ _ hx => qthen_mono (fun _ hy => qeff_mono le hy) (fun _ _ hy => hy) hx) h
  | _, .eStride _, _, h => by simp [qeff] at h

theorem qeffs_mono (le : QCallsLe call call') :
    ∀ {env : Env} {es : List SrcEff} {vs : List Value × Nat}, qeffs call env es = some vs →
      qeffs call' env es = some vs
  | _, [], _, h => h
  | env, e :: es, _, h => by
    simp only [qeffs] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx)
      (fun _ _ hx => qthen_mono (fun _ hy => qeffs_mono le hy) (fun _ _ hy => hy) hx) h

theorem qarms_mono (le : QCallsLe call call') :
    ∀ {env : Env} {v : Value} {id k : Nat} {binders : List (List Nat)} {values : List SrcEff} {w : Value × Nat},
      qarms call env v id k binders values = some w → qarms call' env v id k binders values = some w
  | _, _, _, _, [], _, _, h => by simp [qarms] at h
  | _, _, _, _, _ :: _, [], _, h => by simp [qarms] at h
  | env, v, id, k, bs :: rest, value :: values, _, h => by
    simp only [qarms] at h ⊢
    split at h
    · exact qarms_mono le h
    · exact qeff_mono le h
end

theorem qstmt_mono (le : QCallsLe call call') (s : SrcStmt) :
    ∀ {env : Env} {d : Done × Nat}, qstmt call env s = some d → qstmt call' env s = some d := by
  induction s with
  | nop => exact fun h => h
  | «let» id ty value body ih =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact bind_mono (fun _ hx => hx) (fun _ _ hx => ih hx) h
  | letStruct id ty fields body ih =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact bind_mono (fun _ hx => hx) (fun _ _ hx => ih hx) h
  | letCall id ty callee args body ih =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact qthen_mono (fun _ hx => bind_mono (fun _ hy => hy) (fun _ _ hc => le _ _ _ hc) hx) (fun _ _ hx => ih hx) h
  | letEnum id ty variant payload body ih =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact bind_mono (fun _ hx => hx) (fun _ _ hx => ih hx) h
  | letMatch => intro env d h; simp [qstmt] at h
  | set => intro env d h; simp [qstmt] at h
  | setField => intro env d h; simp [qstmt] at h
  | setCall => intro env d h; simp [qstmt] at h
  | «then» first second ih1 ih2 =>
    intro env d h
    simp only [qstmt] at h ⊢
    refine qthen_mono (fun _ hx => ih1 hx) (fun x w hx => ?_) h
    cases x with
    | next => exact ih2 hx
    | ret value => exact hx
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro env d h
    simp only [qstmt] at h ⊢
    refine bind_mono (fun _ hx => hx) (fun b w hx => ?_) h
    cases b
    · exact ih2 hx
    · exact ih1 hx
  | «while» => intro env d h; simp [qstmt] at h
  | «return» => exact fun h => h
  | letAlloc => intro env d h; simp [qstmt] at h
  | letLoad => intro env d h; simp [qstmt] at h
  | setByte => intro env d h; simp [qstmt] at h
  | free => intro env d h; simp [qstmt] at h
  | letSlice => intro env d h; simp [qstmt] at h
  | letIndex => intro env d h; simp [qstmt] at h
  | setIndex => intro env d h; simp [qstmt] at h
  | letEval id ty value body ih =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => ih hx) h
  | setEval => intro env d h; simp [qstmt] at h
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro env d h
    simp only [qstmt] at h ⊢
    refine qthen_mono (fun _ hx => qeff_mono le hx) (fun c w hx => ?_) h
    refine bind_mono (fun _ hy => hy) (fun b w hy => ?_) hx
    cases b
    · exact ih2 hy
    · exact ih1 hy
  | whileEval => intro env d h; simp [qstmt] at h
  | returnEval value =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => hx) h
  | discard value =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => hx) h
  | setIndexEval => intro env d h; simp [qstmt] at h
  | setFieldEval => intro env d h; simp [qstmt] at h
  | returnUnit => exact fun h => h
  | «assert» condition =>
    intro env d h
    simp only [qstmt] at h ⊢
    exact qthen_mono (fun _ hx => qeff_mono le hx) (fun _ _ hx => hx) h
  | «break» => intro env d h; simp [qstmt] at h
  | «continue» => intro env d h; simp [qstmt] at h
  | matchArm => intro env d h; simp [qstmt] at h
  | unreachable => intro env d h; simp [qstmt] at h

end

end Lanius.Faithful
