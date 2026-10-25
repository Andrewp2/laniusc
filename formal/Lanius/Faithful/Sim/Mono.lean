import Lanius.Faithful.Pure

/-! # More fuel, the same pure value

The pure semantics only looks at the values its calls give, so calls that
give the same values where they gave any (`CallsLe`) give bodies the same
values, and `pcall` keeps its value with more fuel (`pcall_mono`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)

/-- `call'` gives every value `call` gives. -/
def CallsLe (call call' : Calls) : Prop :=
  ∀ c vs w, call c vs = some w → call' c vs = some w

theorem bind_mono {α β : Type} {a a' : Option α} {f f' : α → Option β} {w : β}
    (ha : ∀ x, a = some x → a' = some x) (hf : ∀ x w, f x = some w → f' x = some w)
    (h : a.bind f = some w) : a'.bind f' = some w := by
  cases a with
  | none => simp at h
  | some x => rw [ha x rfl]; exact hf x w h

theorem applyOp_mono {op : SrcOp} {a a' b b' : Option Value} {v : Value}
    (ha : ∀ x, a = some x → a' = some x) (hb : ∀ x, b = some x → b' = some x)
    (h : applyOp op a b = some v) : applyOp op a' b' = some v := by
  cases a with
  | none => cases op <;> simp [applyOp, binary] at h
  | some x =>
    rw [ha x rfl]
    cases b with
    | some y => rw [hb y rfl]; exact h
    | none =>
      cases op <;> simp only [applyOp, binary, Option.bind_some, Option.bind_none] at h ⊢
      all_goals first
        | (simp at h; done)
        | (revert h
           cases asBool x with
           | none => simp
           | some bb => cases bb <;> simp)

section
variable {call call' : Calls}

mutual
theorem peff_mono (le : CallsLe call call') :
    ∀ {env : Env} {e : SrcEff} {v : Value}, peff call env e = some v → peff call' env e = some v
  | _, .ePure _, _, h => h
  | env, .eCall callee args, _, h => by
    simp only [peff] at h ⊢
    exact bind_mono (fun _ hx => peffs_mono le hx) (fun _ _ hc => le _ _ _ hc) h
  | env, .eApply op l r, _, h => by
    simp only [peff] at h ⊢
    exact applyOp_mono (fun _ hx => peff_mono le hx) (fun _ hx => peff_mono le hx) h
  | env, .eNeg o, _, h => by
    simp only [peff] at h ⊢
    exact bind_mono (fun _ hx => peff_mono le hx) (fun _ _ hx => hx) h
  | env, .eNot o, _, h => by
    simp only [peff] at h ⊢
    exact bind_mono (fun _ hx => peff_mono le hx) (fun _ _ hx => hx) h
  | env, .eCast ty o, _, h => by
    simp only [peff] at h ⊢
    exact bind_mono (fun _ hx => peff_mono le hx) (fun _ _ hx => hx) h
  | _, .eIndex _ _, _, h => by simp [peff] at h
  | env, .eStruct ty fields, _, h => by
    simp only [peff, Option.map_eq_some_iff] at h ⊢
    obtain ⟨vs, hvs, rfl⟩ := h
    exact ⟨vs, peffs_mono le hvs, rfl⟩
  | env, .eVariant ty variant payload, _, h => by
    simp only [peff, Option.map_eq_some_iff] at h ⊢
    obtain ⟨vs, hvs, rfl⟩ := h
    exact ⟨vs, peffs_mono le hvs, rfl⟩
  | env, .eMatch scrutinee ety rty binders values, _, h => by
    simp only [peff] at h ⊢
    exact bind_mono (fun _ hx => peff_mono le hx) (fun _ _ hx => parms_mono le hx) h
  | env, .eDivide op l r, _, h => by
    simp only [peff, binary] at h ⊢
    exact bind_mono (fun _ hx => peff_mono le hx)
      (fun _ _ hx => bind_mono (fun _ hy => peff_mono le hy) (fun _ _ hy => hy) hx) h
  | _, .eStride _, _, h => by simp [peff] at h

theorem peffs_mono (le : CallsLe call call') :
    ∀ {env : Env} {es : List SrcEff} {vs : List Value}, peffs call env es = some vs → peffs call' env es = some vs
  | _, [], _, h => h
  | env, e :: es, _, h => by
    simp only [peffs] at h ⊢
    exact bind_mono (fun _ hx => peff_mono le hx) (fun _ _ hx => by
      simp only [Option.map_eq_some_iff] at hx ⊢
      obtain ⟨rest, hr, rfl⟩ := hx
      exact ⟨rest, peffs_mono le hr, rfl⟩) h

theorem parms_mono (le : CallsLe call call') :
    ∀ {env : Env} {v : Value} {id k : Nat} {binders : List (List Nat)} {values : List SrcEff} {w : Value},
      parms call env v id k binders values = some w → parms call' env v id k binders values = some w
  | _, _, _, _, [], _, _, h => by simp [parms] at h
  | _, _, _, _, _ :: _, [], _, h => by simp [parms] at h
  | env, v, id, k, bs :: rest, value :: values, _, h => by
    simp only [parms] at h ⊢
    split at h
    · exact parms_mono le h
    · exact peff_mono le h
end

theorem pstmt_mono (le : CallsLe call call') (s : SrcStmt) :
    ∀ {env : Env} {d : Done}, pstmt call env s = some d → pstmt call' env s = some d := by
  induction s with
  | nop => exact fun h => h
  | «let» id ty value body ih =>
    intro env d h
    simp only [pstmt] at h ⊢
    exact bind_mono (fun _ hx => hx) (fun _ _ hx => ih hx) h
  | letStruct id ty fields body ih =>
    intro env d h
    simp only [pstmt] at h ⊢
    exact bind_mono (fun _ hx => hx) (fun _ _ hx => ih hx) h
  | letCall id ty callee args body ih =>
    intro env d h
    simp only [pstmt] at h ⊢
    exact bind_mono (fun _ hx => bind_mono (fun _ hy => hy) (fun _ _ hc => le _ _ _ hc) hx) (fun _ _ hx => ih hx) h
  | letEnum id ty variant payload body ih =>
    intro env d h
    simp only [pstmt] at h ⊢
    exact bind_mono (fun _ hx => hx) (fun _ _ hx => ih hx) h
  | letMatch => intro env d h; simp [pstmt] at h
  | set => intro env d h; simp [pstmt] at h
  | setField => intro env d h; simp [pstmt] at h
  | setCall => intro env d h; simp [pstmt] at h
  | «then» first second ih1 ih2 =>
    intro env d h
    simp only [pstmt] at h ⊢
    refine bind_mono (fun _ hx => ih1 hx) (fun x w hx => ?_) h
    cases x with
    | next => exact ih2 hx
    | ret value => exact hx
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro env d h
    simp only [pstmt] at h ⊢
    refine bind_mono (fun _ hx => hx) (fun b w hx => ?_) h
    cases b
    · exact ih2 hx
    · exact ih1 hx
  | «while» => intro env d h; simp [pstmt] at h
  | «return» => exact fun h => h
  | letAlloc => intro env d h; simp [pstmt] at h
  | letLoad => intro env d h; simp [pstmt] at h
  | setByte => intro env d h; simp [pstmt] at h
  | free => intro env d h; simp [pstmt] at h
  | letSlice => intro env d h; simp [pstmt] at h
  | letIndex => intro env d h; simp [pstmt] at h
  | setIndex => intro env d h; simp [pstmt] at h
  | letEval id ty value body ih =>
    intro env d h
    simp only [pstmt] at h ⊢
    exact bind_mono (fun _ hx => peff_mono le hx) (fun _ _ hx => ih hx) h
  | setEval => intro env d h; simp [pstmt] at h
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro env d h
    simp only [pstmt] at h ⊢
    refine bind_mono (fun _ hx => bind_mono (fun _ hy => peff_mono le hy) (fun _ _ hy => hy) hx)
      (fun b w hx => ?_) h
    cases b
    · exact ih2 hx
    · exact ih1 hx
  | whileEval => intro env d h; simp [pstmt] at h
  | returnEval value =>
    intro env d h
    simp only [pstmt, Option.map_eq_some_iff] at h ⊢
    obtain ⟨v, hv, rfl⟩ := h
    exact ⟨v, peff_mono le hv, rfl⟩
  | discard value =>
    intro env d h
    simp only [pstmt, Option.map_eq_some_iff] at h ⊢
    obtain ⟨v, hv, rfl⟩ := h
    exact ⟨v, peff_mono le hv, rfl⟩
  | setIndexEval => intro env d h; simp [pstmt] at h
  | setFieldEval => intro env d h; simp [pstmt] at h
  | returnUnit => exact fun h => h
  | «assert» condition =>
    intro env d h
    simp only [pstmt] at h ⊢
    exact bind_mono (fun _ hx => bind_mono (fun _ hy => peff_mono le hy) (fun _ _ hy => hy) hx)
      (fun _ _ hx => hx) h

end

/-- `pcall` keeps its value with more fuel. -/
theorem pcall_mono (sp : SrcProgram) (prims : Prims) :
    ∀ (n : Nat) {m c : Nat} {vs : List Value} {w : Value}, pcall sp prims n c vs = some w → n ≤ m →
      pcall sp prims m c vs = some w
  | 0, _, _, _, _, h, _ => by simp [pcall] at h
  | n + 1, m, c, vs, w, h, le => by
    obtain ⟨m, rfl⟩ : ∃ m', m = m' + 1 := ⟨m - 1, by omega⟩
    simp only [pcall] at h ⊢
    split at h
    · rename_i prim
      rw [if_pos prim]
      exact h
    · rename_i prim
      rw [if_neg prim]
      split at h
      · simp at h
      · split at h
        · rename_i len
          rw [if_pos len]
          exact bind_mono (fun _ hx => pstmt_mono (fun _ _ _ hc => pcall_mono sp prims n hc (by omega)) _ hx)
            (fun _ _ hx => hx) h
        · simp at h

end Lanius.Faithful
