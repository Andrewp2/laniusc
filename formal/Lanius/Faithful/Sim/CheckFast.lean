import Lanius.Faithful.Sim.Check

/-! # `stmtOk` with the callees' signatures looked up elsewhere

`stmtOk` finds each callee by indexing the program's function list, which the
kernel walks one function at a time. `stmtOkC` is `stmtOk` with the call
check `calls` a parameter (`stmtOkC_eq`: at `callTy sp outside` it is
`stmtOk`), so a concrete program's signatures can be looked up in blocks
(`blockGet`) instead: `sigCall (blockGet blocks)` is `callTy sp outside` when
the blocks are the program's signatures, `none` for those `outside`
(`callTy_eq_blocks`). -/

namespace Lanius.Faithful

open Lanius.Mini

section
variable (calls : Nat → List SrcType → Option SrcType) (boxes : Boxes)

mutual
def effTyC (tenv : TEnv) : SrcEff → Option SrcType
  | .ePure e => exprTy boxes tenv e
  | .eCall callee args => (effTysC tenv args).bind (calls callee)
  | .eApply op left right => (effTyC tenv left).bind fun l => (effTyC tenv right).bind (opTy op l)
  | .eNeg operand => (effTyC tenv operand).bind numOf
  | .eNot operand => (effTyC tenv operand).bind boolOf
  | .eCast ty operand => (effTyC tenv operand).bind (castTy ty)
  | .eIndex _ _ => none
  | .eStruct ty fields => (effTysC tenv fields).bind (structTy boxes ty)
  | .eVariant ty variant payload => (effTysC tenv payload).bind (variantTy ty variant)
  | .eMatch scrutinee ety rty binders values =>
    (effTyC tenv scrutinee).bind fun st =>
      match ety with
      | .enum _ variants => if st.same ety && armsOkC tenv rty variants binders values then some rty else none
      | .i32 | .bool | .uint _ | .struct _ _ | .ptr | .slice _ | .unit | .isize | .char | .float _ | .sint _ => none
  | .eDivide _ left right => (effTyC tenv left).bind fun l => (effTyC tenv right).bind (divTy l)
  | .eStride _ => none

def effTysC (tenv : TEnv) : List SrcEff → Option (List SrcType)
  | [] => some []
  | e :: es => (effTyC tenv e).bind fun t => (effTysC tenv es).map (t :: ·)

def armsOkC (tenv : TEnv) (rty : SrcType) : List (List SrcType) → List (List Nat) → List SrcEff → Bool
  | _, [], [] => true
  | _, [], _ :: _ => false
  | _, _ :: _, [] => false
  | [], _ :: _, _ :: _ => false
  | fs :: variants, binders :: rest, value :: values =>
    binders.length == fs.length &&
      (match effTyC (tenv.bindAll (binders.zip fs)) value with
       | some t => t.same rty
       | none => false) &&
      armsOkC tenv rty variants rest values
end

def stmtOkC (ret : SrcType) (tenv : TEnv) : SrcStmt → Bool
  | .nop => true
  | .let id _ value body =>
    match exprTy boxes tenv value with
    | some t => stmtOkC ret ((id, t) :: tenv) body
    | none => false
  | .letStruct id ty fields body =>
    match (exprTys boxes tenv fields).bind (structTy boxes ty) with
    | some t => stmtOkC ret ((id, t) :: tenv) body
    | none => false
  | .letCall id _ callee args body =>
    match (exprTys boxes tenv args).bind (calls callee) with
    | some t => stmtOkC ret ((id, t) :: tenv) body
    | none => false
  | .letEnum id ty variant payload body =>
    match (exprTys boxes tenv payload).bind (variantTy ty variant) with
    | some t => stmtOkC ret ((id, t) :: tenv) body
    | none => false
  | .letMatch _ _ _ _ _ _ => false
  | .set _ _ => false
  | .setField _ _ _ => false
  | .setCall _ _ _ => false
  | .then first second => stmtOkC ret tenv first && stmtOkC ret tenv second
  | .if condition thenBranch elseBranch =>
    isBoolTy (exprTy boxes tenv condition) && stmtOkC ret tenv thenBranch && stmtOkC ret tenv elseBranch
  | .while _ _ => false
  | .return value =>
    match exprTy boxes tenv value with
    | some t => t.same ret
    | none => false
  | .letAlloc _ _ _ _ => false
  | .letLoad _ _ _ _ => false
  | .setByte _ _ _ => false
  | .free _ _ _ => false
  | .letSlice _ _ _ _ _ => false
  | .letIndex _ _ _ _ _ => false
  | .setIndex _ _ _ => false
  | .letEval id _ value body =>
    match effTyC calls boxes tenv value with
    | some t => stmtOkC ret ((id, t) :: tenv) body
    | none => false
  | .setEval _ _ => false
  | .ifEval condition thenBranch elseBranch =>
    isBoolTy (effTyC calls boxes tenv condition) && stmtOkC ret tenv thenBranch && stmtOkC ret tenv elseBranch
  | .whileEval _ _ => false
  | .returnEval value =>
    match effTyC calls boxes tenv value with
    | some t => t.same ret
    | none => false
  | .discard value => (effTyC calls boxes tenv value).isSome
  | .setIndexEval _ _ _ => false
  | .setFieldEval _ _ _ => false
  | .returnUnit => true
  | .assert condition => isBoolTy (effTyC calls boxes tenv condition)

end

section
variable {sp : SrcProgram} {outside : List Nat} {boxes : Boxes}

mutual
theorem effTyC_eq (tenv : TEnv) : ∀ e : SrcEff, effTyC (callTy sp outside) boxes tenv e = effTy sp outside boxes tenv e
  | .ePure e => by rw [effTyC, effTy]
  | .eCall callee args => by rw [effTyC, effTy, effTysC_eq tenv args]
  | .eApply op left right => by rw [effTyC, effTy, effTyC_eq tenv left, effTyC_eq tenv right]
  | .eNeg operand => by rw [effTyC, effTy, effTyC_eq tenv operand]
  | .eNot operand => by rw [effTyC, effTy, effTyC_eq tenv operand]
  | .eCast ty operand => by rw [effTyC, effTy, effTyC_eq tenv operand]
  | .eIndex _ _ => by rw [effTyC, effTy]
  | .eStruct ty fields => by rw [effTyC, effTy, effTysC_eq tenv fields]
  | .eVariant ty variant payload => by rw [effTyC, effTy, effTysC_eq tenv payload]
  | .eMatch scrutinee ety rty binders values => by
    rw [effTyC, effTy, effTyC_eq tenv scrutinee]
    cases ety with
    | enum _ variants => dsimp only; rw [armsOkC_eq tenv rty variants binders values]
    | i32 => rfl
    | bool => rfl
    | uint _ => rfl
    | struct _ _ => rfl
    | ptr => rfl
    | slice _ => rfl
    | unit => rfl
    | isize => rfl
    | char => rfl
    | float => rfl
    | sint _ => rfl
  | .eDivide _ left right => by rw [effTyC, effTy, effTyC_eq tenv left, effTyC_eq tenv right]
  | .eStride _ => by rw [effTyC, effTy]

theorem effTysC_eq (tenv : TEnv) : ∀ es : List SrcEff,
    effTysC (callTy sp outside) boxes tenv es = effTys sp outside boxes tenv es
  | [] => by rw [effTysC, effTys]
  | e :: es => by rw [effTysC, effTys, effTyC_eq tenv e, effTysC_eq tenv es]

theorem armsOkC_eq (tenv : TEnv) (rty : SrcType) : ∀ (variants : List (List SrcType)) (binders : List (List Nat))
    (values : List SrcEff),
    armsOkC (callTy sp outside) boxes tenv rty variants binders values =
      armsOk sp outside boxes tenv rty variants binders values
  | _, [], [] => by rw [armsOkC, armsOk]
  | _, [], _ :: _ => by rw [armsOkC, armsOk]
  | _, _ :: _, [] => by rw [armsOkC, armsOk]
  | [], _ :: _, _ :: _ => by rw [armsOkC, armsOk]
  | fs :: variants, binders :: rest, value :: values => by
    rw [armsOkC, armsOk, effTyC_eq _ value, armsOkC_eq tenv rty variants rest values] <;> rfl
end

theorem stmtOkC_eq (ret : SrcType) (s : SrcStmt) : ∀ tenv : TEnv,
    stmtOkC (callTy sp outside) boxes ret tenv s = stmtOk sp outside boxes ret tenv s := by
  induction s with
  | nop => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | «let» id _ value body ih => intro tenv; simp only [stmtOkC, stmtOk, ih] <;> rfl
  | letStruct id ty fields body ih => intro tenv; simp only [stmtOkC, stmtOk, ih] <;> rfl
  | letCall id _ callee args body ih => intro tenv; simp only [stmtOkC, stmtOk, ih] <;> rfl
  | letEnum id ty variant payload body ih => intro tenv; simp only [stmtOkC, stmtOk, ih] <;> rfl
  | letMatch => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | set => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | setField => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | setCall => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | «then» first second ih1 ih2 => intro tenv; rw [stmtOkC, stmtOk, ih1, ih2] <;> rfl
  | «if» condition thenBranch elseBranch ih1 ih2 => intro tenv; rw [stmtOkC, stmtOk, ih1, ih2] <;> rfl
  | «while» => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | «return» value => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | letAlloc => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | letLoad => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | setByte => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | free => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | letSlice => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | letIndex => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | setIndex => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | letEval id _ value body ih => intro tenv; simp only [stmtOkC, stmtOk, effTyC_eq, ih] <;> rfl
  | setEval => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro tenv; rw [stmtOkC, stmtOk, effTyC_eq, ih1, ih2] <;> rfl
  | whileEval => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | returnEval value => intro tenv; rw [stmtOkC, stmtOk, effTyC_eq] <;> rfl
  | discard value => intro tenv; rw [stmtOkC, stmtOk, effTyC_eq] <;> rfl
  | setIndexEval => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | setFieldEval => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | returnUnit => intro tenv; rw [stmtOkC, stmtOk] <;> rfl
  | «assert» condition => intro tenv; rw [stmtOkC, stmtOk, effTyC_eq] <;> rfl

end

/-! ## Signatures in blocks

The table has an entry per function: `none` for one `outside`, else what
`callTy` reads of it (`sigOf`). It is checked against the program in one walk
(`entriesFit`), and its `none`s against `outside` (`noneAt`), so no lookup in
`outside` is done per function. -/

/-- What `callTy` reads of a function. -/
def sigOf (f : SrcFunc) : List SrcType × SrcType := (f.params.map SrcParam.ty, f.ret)

abbrev SigEntry := Option (List SrcType × SrcType)

/-- `callTy`, with the callees' entries from `sig`. -/
def sigCall (sig : Nat → Option SigEntry) (callee : Nat) (ts : List SrcType) : Option SrcType :=
  match sig callee with
  | some (some s) => if typesSame ts s.1 then some s.2 else none
  | some none => none
  | none => none

/-- Each entry is `none` or its function's `sigOf`. -/
def entriesFit : List SrcFunc → List SigEntry → Bool
  | [], [] => true
  | [], _ :: _ => false
  | _ :: _, [] => false
  | _ :: fs, none :: es => entriesFit fs es
  | f :: fs, some (ps, r) :: es => typesSame (f.params.map SrcParam.ty) ps && f.ret.same r && entriesFit fs es

/-- The positions, from `n`, of the `none` entries. -/
def noneAt : Nat → List SigEntry → List Nat
  | _, [] => []
  | n, none :: es => n :: noneAt (n + 1) es
  | n, some _ :: es => noneAt (n + 1) es

theorem entriesFit_get : ∀ {fs : List SrcFunc} {es : List SigEntry}, entriesFit fs es = true → ∀ c : Nat,
    (es[c]? = none ↔ fs[c]? = none) ∧ ∀ f s, fs[c]? = some f → es[c]? = some (some s) → s = sigOf f
  | [], [], _, c => by simp
  | [], _ :: _, h, _ => nomatch h
  | _ :: _, [], h, _ => nomatch h
  | _ :: fs, none :: es, h, 0 => by simp
  | _ :: fs, none :: es, h, c + 1 => by
    rw [List.getElem?_cons_succ, List.getElem?_cons_succ]
    exact entriesFit_get (fs := fs) (es := es) h c
  | f :: fs, some (ps, r) :: es, h, 0 => by
    simp only [entriesFit, Bool.and_eq_true] at h
    obtain ⟨⟨same, same'⟩, _⟩ := h
    refine ⟨by simp, fun g s hg hs => ?_⟩
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hg hs
    subst hg hs
    rw [sigOf, typesSame_eq _ same, SrcType.same_eq same']
  | f :: fs, some (ps, r) :: es, h, c + 1 => by
    simp only [entriesFit, Bool.and_eq_true] at h
    rw [List.getElem?_cons_succ, List.getElem?_cons_succ]
    exact entriesFit_get h.2 c

theorem noneAt_ge : ∀ (n : Nat) (es : List SigEntry) (x : Nat), x ∈ noneAt n es → n ≤ x
  | _, [], _, h => nomatch h
  | n, none :: es, x, h => by
    rw [noneAt, List.mem_cons] at h
    rcases h with rfl | h
    · exact Nat.le_refl _
    · exact Nat.le_of_succ_le (noneAt_ge (n + 1) es x h)
  | n, some _ :: es, x, h => by
    rw [noneAt] at h
    exact Nat.le_of_succ_le (noneAt_ge (n + 1) es x h)

theorem mem_noneAt : ∀ (n : Nat) (es : List SigEntry) (c : Nat), n + c ∈ noneAt n es ↔ es[c]? = some none
  | _, [], c => by simp [noneAt]
  | n, none :: es, 0 => by simp [noneAt]
  | n, some _ :: es, 0 => by
    simp only [noneAt, Nat.add_zero, List.getElem?_cons_zero, Option.some.injEq, reduceCtorEq, iff_false]
    intro h
    exact Nat.not_succ_le_self n (noneAt_ge (n + 1) es n h)
  | n, none :: es, c + 1 => by
    rw [noneAt, List.mem_cons, List.getElem?_cons_succ, ← mem_noneAt (n + 1) es c,
      Nat.add_assoc, Nat.add_comm 1 c]
    constructor
    · rintro (h | h)
      · exact absurd h (by omega)
      · exact h
    · exact Or.inr
  | n, some _ :: es, c + 1 => by
    rw [noneAt, List.getElem?_cons_succ, ← mem_noneAt (n + 1) es c, Nat.add_assoc, Nat.add_comm 1 c]

theorem callTy_eq_entries {sp : SrcProgram} {outside : List Nat} {es : List SigEntry}
    (fit : entriesFit sp.funcs es = true) (outs : noneAt 0 es = outside) :
    callTy sp outside = sigCall fun c => es[c]? := by
  funext c ts
  have mem : outside.contains c = true ↔ es[c]? = some none := by
    rw [← outs, List.contains_iff_mem, ← mem_noneAt 0 es c, Nat.zero_add]
  obtain ⟨len, sig⟩ := entriesFit_get fit c
  unfold callTy sigCall
  dsimp only
  cases h : es[c]? with
  | none =>
    rw [len.1 h, if_neg (by rw [mem, h]; exact fun e => nomatch e)]
  | some e =>
    cases e with
    | none => rw [if_pos (mem.2 h)]
    | some s =>
      rw [if_neg (by rw [mem, h]; exact fun e => nomatch e)]
      cases hf : sp.funcs[c]? with
      | none => exact absurd (len.2 hf) (by rw [h]; exact fun e => nomatch e)
      | some f => rw [sig f s hf h]; rfl

/-- Element `i` of the blocks put together; each block has its length. -/
def blockGet {α : Type} : List (Nat × List α) → Nat → Option α
  | [], _ => none
  | (n, b) :: bs, i => if i < n then b[i]? else blockGet bs (i - n)

def blocksLen {α : Type} : List (Nat × List α) → Bool
  | [] => true
  | (n, b) :: bs => decide (n = b.length) && blocksLen bs

theorem blockGet_eq {α : Type} : ∀ (bs : List (Nat × List α)) (i : Nat), blocksLen bs = true →
    blockGet bs i = (bs.map Prod.snd).flatten[i]?
  | [], i, _ => by simp [blockGet]
  | (n, b) :: bs, i, h => by
    simp only [blocksLen, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨rfl, h⟩ := h
    simp only [blockGet, List.map_cons, List.flatten_cons]
    by_cases lt : i < b.length
    · rw [if_pos lt, List.getElem?_append_left lt]
    · rw [if_neg lt, List.getElem?_append_right (Nat.le_of_not_lt lt), blockGet_eq bs _ h]

theorem callTy_eq_blocks {sp : SrcProgram} {outside : List Nat} {blocks : List (Nat × List SigEntry)}
    (len : blocksLen blocks = true) (fit : entriesFit sp.funcs (blocks.map Prod.snd).flatten = true)
    (outs : noneAt 0 (blocks.map Prod.snd).flatten = outside) :
    callTy sp outside = sigCall (blockGet blocks) := by
  rw [callTy_eq_entries fit outs]
  congr
  funext c
  rw [blockGet_eq _ _ len]

theorem pureFunc_fast {sp : SrcProgram} {prims : Prims} {outside : List Nat} {boxes : Boxes}
    {calls : Nat → List SrcType → Option SrcType} {f : SrcFunc} (hb : boxElem sp prims = boxes)
    (hc : callTy sp outside = calls) (ok : stmtOkC calls boxes f.ret (paramTEnv f.params) f.body = true) :
    PureFunc sp prims outside f = true := by
  unfold PureFunc
  rw [hb, ← stmtOkC_eq, hc]
  exact ok

end Lanius.Faithful
