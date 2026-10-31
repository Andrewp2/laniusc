import Lanius.Mini.Reading.Det.Stmts
import Lanius.Mini.Reading.Lits

/-! # The reading is deterministic, F1: closing and typing literals

Closing a function against the instance tables (`FuncClosed`) and typing
its literals (`LitFunc`) each give at most one result: the closed forms
follow the instance's constructors, a table index is the first match, and
each literal relation is the graph of its builder function (`litStmt_eq`).
`closedProgram_unique`: the closed program is unique. -/

namespace Lanius.Mini.Reading

open Lanius.Mini

/-! ## Closing -/

section
variable {decls : Decls} {fns types : List Inst}

mutual
theorem effClosed_unique : ∀ {x : MEff} {a b : SrcEff}, EffClosed decls fns types x a →
    EffClosed decls fns types x b → a = b
  | _, _, _, .pure, .pure => rfl
  | _, _, _, .call f as, .call f' as' => by rw [(firstWith_unique f f').1, effsClosed_unique as as']
  | _, _, _, .apply l r, .apply l' r' => by rw [effClosed_unique l l', effClosed_unique r r']
  | _, _, _, .neg h, .neg h' => by rw [effClosed_unique h h']
  | _, _, _, .not h, .not h' => by rw [effClosed_unique h h']
  | _, _, _, .cast h, .cast h' => by rw [effClosed_unique h h']
  | _, _, _, .index h, .index h' => by rw [effClosed_unique h h']
  | _, _, _, .struct lw fs, .struct lw' fs' => by rw [lowerR_unique lw lw', effsClosed_unique fs fs']
  | _, _, _, .variant lw ps, .variant lw' ps' => by rw [lowerR_unique lw lw', effsClosed_unique ps ps']
  | _, _, _, .match sc le lt vs, .match sc' le' lt' vs' => by
    rw [effClosed_unique sc sc', lowerR_unique le le', lowerR_unique lt lt', effsClosed_unique vs vs']
  | _, _, _, .divide l r, .divide l' r' => by rw [effClosed_unique l l', effClosed_unique r r']
  | _, _, _, .stride, .stride => rfl
  | _, _, _, .host as, .host as' => by rw [effsClosed_unique as as']
termination_by structural _ _ _ h _ => h

theorem effsClosed_unique : ∀ {xs : List MEff} {a b : List SrcEff}, EffsClosed decls fns types xs a →
    EffsClosed decls fns types xs b → a = b
  | _, _, _, .nil, .nil => rfl
  | _, _, _, .cons h hs, .cons h' hs' => by rw [effClosed_unique h h', effsClosed_unique hs hs']
termination_by structural _ _ _ h _ => h
end

theorem stmtClosed_unique : ∀ {m : MStmt} {a b : SrcStmt}, StmtClosed decls fns types m a →
    StmtClosed decls fns types m b → a = b
  | _, _, _, .nop, .nop => rfl
  | _, _, _, .let lw b, .let lw' b' => by rw [lowerR_unique lw lw', stmtClosed_unique b b']
  | _, _, _, .letStruct lw b, .letStruct lw' b' => by rw [lowerR_unique lw lw', stmtClosed_unique b b']
  | _, _, _, .letCall lw f b, .letCall lw' f' b' => by
    rw [lowerR_unique lw lw', (firstWith_unique f f').1, stmtClosed_unique b b']
  | _, _, _, .letEnum lw b, .letEnum lw' b' => by rw [lowerR_unique lw lw', stmtClosed_unique b b']
  | _, _, _, .letMatch lw le b, .letMatch lw' le' b' => by
    rw [lowerR_unique lw lw', stmtClosed_unique b b']
    cases lowerR_unique le le'
    rfl
  | _, _, _, .set, .set => rfl
  | _, _, _, .setField, .setField => rfl
  | _, _, _, .setCall f, .setCall f' => by rw [(firstWith_unique f f').1]
  | _, _, _, .then a b, .then a' b' => by rw [stmtClosed_unique a a', stmtClosed_unique b b']
  | _, _, _, .if a b, .if a' b' => by rw [stmtClosed_unique a a', stmtClosed_unique b b']
  | _, _, _, .while b, .while b' => by rw [stmtClosed_unique b b']
  | _, _, _, .return, .return => rfl
  | _, _, _, .letAlloc b, .letAlloc b' => by rw [stmtClosed_unique b b']
  | _, _, _, .free, .free => rfl
  | _, _, _, .letSlice lw b, .letSlice lw' b' => by rw [lowerR_unique lw lw', stmtClosed_unique b b']
  | _, _, _, .letIndex lw b, .letIndex lw' b' => by rw [lowerR_unique lw lw', stmtClosed_unique b b']
  | _, _, _, .setIndex, .setIndex => rfl
  | _, _, _, .letEval lw x b, .letEval lw' x' b' => by
    rw [lowerR_unique lw lw', effClosed_unique x x', stmtClosed_unique b b']
  | _, _, _, .setEval x, .setEval x' => by rw [effClosed_unique x x']
  | _, _, _, .ifEval x a b, .ifEval x' a' b' => by
    rw [effClosed_unique x x', stmtClosed_unique a a', stmtClosed_unique b b']
  | _, _, _, .whileEval x b, .whileEval x' b' => by rw [effClosed_unique x x', stmtClosed_unique b b']
  | _, _, _, .returnEval x, .returnEval x' => by rw [effClosed_unique x x']
  | _, _, _, .discard x, .discard x' => by rw [effClosed_unique x x']
  | _, _, _, .setIndexEval i v, .setIndexEval i' v' => by rw [effClosed_unique i i', effClosed_unique v v']
  | _, _, _, .setFieldEval x, .setFieldEval x' => by rw [effClosed_unique x x']
  | _, _, _, .returnUnit, .returnUnit => rfl
  | _, _, _, .break, .break => rfl
  | _, _, _, .continue, .continue => rfl
  | _, _, _, .assert x, .assert x' => by rw [effClosed_unique x x']
termination_by structural _ _ _ h _ => h

theorem retClosed_unique {r : RetTy} {a b : SrcType} (h₁ : RetClosed decls types r a)
    (h₂ : RetClosed decls types r b) : a = b := by
  cases h₁ with
  | unit => cases h₂; rfl
  | ty lw => cases h₂ with
    | ty lw' => exact lowerR_unique lw lw'

theorem paramClosed_unique {p : MParam} {a b : SrcParam} (h₁ : ParamClosed decls types p a)
    (h₂ : ParamClosed decls types p b) : a = b := by
  obtain ⟨i₁, l₁⟩ := h₁
  obtain ⟨i₂, l₂⟩ := h₂
  have e := lowerR_unique l₁ l₂
  cases a
  cases b
  simp only at i₁ i₂ e
  rw [i₁, i₂, e]

theorem funcClosed_unique {f : MFunc} {a b : SrcFunc} (h₁ : FuncClosed decls fns types f a)
    (h₂ : FuncClosed decls fns types f b) : a = b := by
  obtain ⟨p₁, r₁, s₁⟩ := h₁
  obtain ⟨p₂, r₂, s₂⟩ := h₂
  have ep := listRel_unique (R := ParamClosed decls types) (fun _ _ _ x y => paramClosed_unique x y) p₁ p₂
  have er := retClosed_unique r₁ r₂
  have es := stmtClosed_unique s₁ s₂
  cases a
  cases b
  simp only at ep er es
  rw [ep, er, es]

end

/-! ## Typing literals -/

section
variable {locals : List LocalTy}

theorem litExpr_eq : ∀ {want : Option SrcType} {e e' : SrcExpr}, LitExpr locals want e e' →
    e' = litExpr locals want e
  | _, _, _, .int => by simp only [litExpr]
  | _, _, _, .boolean => by simp only [litExpr]
  | _, _, _, .unsigned => by simp only [litExpr]
  | _, _, _, .local => by simp only [litExpr]
  | _, _, _, .field => by simp only [litExpr]
  | _, _, _, .negate hw h => by rw [litExpr_eq h]; simp only [litExpr, hw]
  | _, _, _, .negWide hw => by simp only [litExpr, hw]
  | _, _, _, .not h => by rw [litExpr_eq h]; simp only [litExpr]
  | _, _, _, .apply ha hb => by rw [litExpr_eq ha, litExpr_eq hb]; simp only [litExpr]
  | _, _, _, .cast hw h => by rw [litExpr_eq h]; simp only [litExpr, hw]
  | _, _, _, .wide hw => by simp only [litExpr, hw]
  | _, _, _, .null => by simp only [litExpr]
  | _, _, _, .char => by simp only [litExpr]

theorem litExprs_eq : ∀ {wants : Option (List SrcType)} {es es' : List SrcExpr}, LitExprs locals wants es es' →
    es' = litExprs locals wants es
  | _, _, _, .nil => by simp only [litExprs]
  | _, _, _, .cons h hs => by rw [litExpr_eq h, litExprs_eq hs]; simp only [litExprs]

theorem litArms_eq {t : SrcType} : ∀ {ps : Option (List (List SrcType))} {arms arms' : List SrcArm},
    LitArms locals ps t arms arms' → arms' = litSrcArms locals ps t arms
  | _, _, _, .nil => by simp only [litSrcArms]
  | _, _, _, .cons h hs => by rw [litExpr_eq h, litArms_eq hs]; simp only [litSrcArms]

end

section
variable {funcs : List SrcFunc}

mutual
theorem litEff_eq : ∀ {locals : List LocalTy} {want : Option SrcType} {x x' : SrcEff},
    LitEff funcs locals want x x' → x' = litEff funcs locals want x
  | _, _, _, _, .pure h => by rw [litExpr_eq h]; simp only [litEff]
  | _, _, _, _, .call hs => by rw [litEffs_eq hs]; simp only [litEff]
  | _, _, _, _, .apply ha hb => by rw [litEff_eq ha, litEff_eq hb]; simp only [litEff]
  | _, _, _, _, .neg h => by rw [litEff_eq h]; simp only [litEff]
  | _, _, _, _, .not h => by rw [litEff_eq h]; simp only [litEff]
  | _, _, _, _, .cast h => by rw [litEff_eq h]; simp only [litEff]
  | _, _, _, _, .index h => by rw [litEff_eq h]; simp only [litEff]
  | _, _, _, _, .struct hs => by rw [litEffs_eq hs]; simp only [litEff]
  | _, _, _, _, .variant hs => by rw [litEffs_eq hs]; simp only [litEff]
  | _, _, _, _, .match h hs => by rw [litEff_eq h, litArmEffs_eq hs]; simp only [litEff]
  | _, _, _, _, .divide ha hb => by rw [litEff_eq ha, litEff_eq hb]; simp only [litEff]
  | _, _, _, _, .stride => by simp only [litEff]
termination_by structural _ _ _ _ h => h

theorem litEffs_eq : ∀ {locals : List LocalTy} {wants : Option (List SrcType)} {xs xs' : List SrcEff},
    LitEffs funcs locals wants xs xs' → xs' = litEffs funcs locals wants xs
  | _, _, _, _, .nil => by simp only [litEffs]
  | _, _, _, _, .cons h hs => by rw [litEff_eq h, litEffs_eq hs]; simp only [litEffs]
termination_by structural _ _ _ _ h => h

theorem litArmEffs_eq : ∀ {locals : List LocalTy} {ps : Option (List (List SrcType))} {t : SrcType}
    {bs : List (List Nat)} {vs vs' : List SrcEff}, LitArmEffs funcs locals ps t bs vs vs' →
    vs' = litArmEffs funcs locals ps t bs vs
  | _, _, _, _, _, _, .nil => by simp only [litArmEffs]
  | _, _, _, _, _, _, .cons h hs => by rw [litEff_eq h, litArmEffs_eq hs]; simp only [litArmEffs]
termination_by structural _ _ _ _ _ _ h => h
end

theorem litStmt_eq {ret : SrcType} : ∀ {locals : List LocalTy} {s s' : SrcStmt},
    LitStmt funcs ret locals s s' → s' = litStmt funcs ret locals s
  | _, _, _, .nop => by simp only [litStmt]
  | _, _, _, .let h b => by rw [litExpr_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .letStruct h b => by rw [litExprs_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .letCall h b => by rw [litExprs_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .letEnum h b => by rw [litExprs_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .letMatch h b => by rw [litArms_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .set h => by rw [litExpr_eq h]; simp only [litStmt]
  | _, _, _, .setField h => by rw [litExpr_eq h]; simp only [litStmt]
  | _, _, _, .setCall h => by rw [litExprs_eq h]; simp only [litStmt]
  | _, _, _, .then a b => by rw [litStmt_eq a, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .if c a b => by rw [litExpr_eq c, litStmt_eq a, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .while c b => by rw [litExpr_eq c, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .return h => by rw [litExpr_eq h]; simp only [litStmt]
  | _, _, _, .letAlloc h b => by rw [litExpr_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .letLoad hp ho b => by rw [litExpr_eq hp, litExpr_eq ho, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .setByte hp ho hv => by rw [litExpr_eq hp, litExpr_eq ho, litExpr_eq hv]; simp only [litStmt]
  | _, _, _, .free hp hs => by rw [litExpr_eq hp, litExpr_eq hs]; simp only [litStmt]
  | _, _, _, .letSlice hp hn b => by rw [litExpr_eq hp, litExpr_eq hn, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .letIndex h b => by rw [litExpr_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .setIndex hi hv => by rw [litExpr_eq hi, litExpr_eq hv]; simp only [litStmt]
  | _, _, _, .letEval h b => by rw [litEff_eq h, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .setEval h => by rw [litEff_eq h]; simp only [litStmt]
  | _, _, _, .ifEval c a b => by rw [litEff_eq c, litStmt_eq a, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .whileEval c b => by rw [litEff_eq c, litStmt_eq b]; simp only [litStmt]
  | _, _, _, .returnEval h => by rw [litEff_eq h]; simp only [litStmt]
  | _, _, _, .discard h => by rw [litEff_eq h]; simp only [litStmt]
  | _, _, _, .setIndexEval hi hv => by rw [litEff_eq hi, litEff_eq hv]; simp only [litStmt]
  | _, _, _, .setFieldEval h => by rw [litEff_eq h]; simp only [litStmt]
  | _, _, _, .returnUnit => by simp only [litStmt]
  | _, _, _, .break => by simp only [litStmt]
  | _, _, _, .continue => by simp only [litStmt]
  | _, _, _, .matchArm b r => by rw [litStmt_eq b, litStmt_eq r]; simp only [litStmt]
  | _, _, _, .unreachable => by simp only [litStmt]
  | _, _, _, .assert h => by rw [litEff_eq h]; simp only [litStmt]

theorem litFunc_unique {g a b : SrcFunc} (h₁ : LitFunc funcs g a) (h₂ : LitFunc funcs g b) : a = b := by
  obtain ⟨p₁, r₁, s₁⟩ := h₁
  obtain ⟨p₂, r₂, s₂⟩ := h₂
  have e₁ := litStmt_eq s₁
  have e₂ := litStmt_eq s₂
  cases a
  cases b
  simp only at p₁ r₁ e₁ p₂ r₂ e₂
  rw [p₁, r₁, e₁, p₂, r₂, e₂]

end

theorem closedProgram_unique {decls : Decls} {fns types : List Inst} {funcs : List MFunc} {p q : SrcProgram}
    (h₁ : ClosedProgram decls fns types funcs p) (h₂ : ClosedProgram decls fns types funcs q) : p = q := by
  obtain ⟨fs, c₁, l₁, _⟩ := h₁
  obtain ⟨fs', c₂, l₂, _⟩ := h₂
  cases listRel_unique (R := FuncClosed decls fns types) (fun _ _ _ x y => funcClosed_unique x y) c₁ c₂
  have e := listRel_unique (R := LitFunc fs) (fun _ _ _ x y => litFunc_unique x y) l₁ l₂
  cases p
  cases q
  simp only at e
  rw [e]

end Lanius.Mini.Reading
