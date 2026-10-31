import Lanius.Mini.Reading.Effs

/-! # The reading, V8d: statements

`StmtsR env scope items m`: a statement list, a `let` scoping over the
statements after it. A statement is a return (of a raw slice, or of a
value), an `if` or `while`, or an expression statement: an assignment to a
local, a field of one or a slice element, a compound assignment, a
deallocation, an assertion, or a call whose value is discarded.

Each value is read once, as an effectful expression (`EffR`); a statement
over a value that reads as pure, a call with pure arguments, and so on
takes that statement's form (`returnEff`, `setEvalOf`, `evalHead`, ...),
so each statement has one reading. Only an allocation and a raw slice are
decided by their spelling. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Statement parts -/

theorem peel_postfix : ∀ {c pf : CTree}, Peel c pf → nodeProd pf = pPostfix
  | _, _, .wrap _ p => peel_postfix p
  | _, _, .bare _ _ p => peel_postfix p
  | _, _, .here e => e

/-- `path(args)` with no further postfix, the path a plain name. -/
def PathCallForm (pf : CTree) : Prop :=
  nodeProd (kid pf 0) = pIdent ∧ nodeProd (kid (kid pf 0) 1) = pIdentPlain ∧ nodeProd (kid pf 1) = pPostfixCall ∧
    nodeProd (kid (kid pf 1) 3) = pPostfixEnd

theorem isPathCall_sound {pf : CTree} (h : isPathCall pf = true) : PathCallForm pf := by
  simpa [isPathCall, PathCallForm, and_assoc] using h

/-- Field `j`'s type in the struct type `t`. -/
def FieldTyAt (decls : Decls) (t : Ty) (j : Nat) (ty : Ty) : Prop :=
  ∃ d args ts, t = .tyNamed d args ∧ FieldTys decls d args ts ∧ ts[j]? = some ty

theorem fieldTyAt_sound {fuel : Nat} {decls : Decls} {t : Ty} {j : Nat} :
    MaybeTy (FieldTyAt decls t j) (fieldTyAt fuel decls t j) := by
  intro ty h
  unfold fieldTyAt at h
  cases t with
  | tyNamed d args =>
    simp only [structFieldTys] at h
    cases hf : fieldTys fuel decls d args with
    | none => rw [hf] at h; cases h
    | some ts =>
      rw [hf] at h
      exact ⟨d, args, ts, rfl, fieldTys_sound hf, h⟩
  | tyI32 => cases h
  | tyBool => cases h
  | tyUint _ => cases h
  | tyPtr => cases h
  | tyIsize => cases h
  | tyChar => cases h
  | tyFloat ft => cases h
  | tySint _ => cases h
  | tySlice _ => cases h

theorem effPostfix_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected : Option Ty} {pf : CTree}
    {x : MEff} (pp : nodeProd pf = pPostfix) (h : effPostfix fuel env scope expected pf = some x) :
    EffR env scope expected pf x :=
  (effSound fuel).2.2.2.1 pp h

theorem effPathCall_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected : Option Ty}
    {path args : CTree} {x : MEff} (h : effPathCall fuel env scope expected path args = some x) :
    EffPathCall env scope expected path args x :=
  (effSound fuel).2.2.2.2.2.2.2.2.2.2.2.1 h

/-- `path(args)?` with no further postfix, the path a plain name. -/
def TryCallForm (pf : CTree) : Prop :=
  nodeProd (kid pf 0) = pIdent ∧ nodeProd (kid (kid pf 0) 1) = pIdentPlain ∧ nodeProd (kid pf 1) = pPostfixCall ∧
    nodeProd (kid (kid pf 1) 3) = pPostfixTry ∧ nodeProd (kid (kid (kid pf 1) 3) 1) = pPostfixEnd

theorem isTryCall_sound {pf : CTree} (h : isTryCall pf = true) : TryCallForm pf := by
  simpa [isTryCall, TryCallForm, and_assoc] using h

/-- `op?`: op's type st is a `core::result::Result` or `core::option::Option`
and the function returns the same enum with the same failure payload. -/
inductive TriedR (env : FrontEnv) (r : Nat) (call : Option MEff) (st : Ty) (w : Nat) : Tried → Prop
  | mk {n m : Inst} {rt : Ty} {t : TypeDecl} {ps qs : List (List Ty)} {tr : Tried} :
      namedParts st = some n → env.ret = some rt → namedParts rt = some m → env.decls.types[n.decl]? = some t →
      n.decl = m.decl → isTryEnum t = true → PayloadTys env.decls n.decl n.args ps →
      PayloadTys env.decls m.decl m.args qs → triedShape r call st w rt (some ps) (some qs) = some tr →
      TriedR env r call st w tr

/-- `path(args)?`: the call's value is bound to a local numbered by the `(`,
the failure binder is numbered by the `?`. -/
inductive TryCallR (env : FrontEnv) (scope : List Local) (pf : CTree) : Tried → Prop
  | mk {x : MEff} {st : Ty} {tr : Tried} : TryCallForm pf →
      FreshId scope ((kidToken (kid pf 1) 0).start - env.base) →
      FreshId scope ((kidToken (kid (kid pf 1) 3) 0).start - env.base) →
      (kidToken (kid pf 1) 0).start - env.base ≠ (kidToken (kid (kid pf 1) 3) 0).start - env.base →
      EffPathCall env scope none (kid (kid pf 0) 0) (kid (kid pf 1) 1) x → EffTy env.decls scope x st →
      TriedR env ((kidToken (kid pf 1) 0).start - env.base) (some x) st
        ((kidToken (kid (kid pf 1) 3) 0).start - env.base) tr →
      TryCallR env scope pf tr

/-- `x?`: the failure binder is numbered by the `?`. -/
inductive TryLocalR (env : FrontEnv) (scope : List Local) (pf : CTree) : Tried → Prop
  | mk {l : Local} {tr : Tried} : nodeProd (kid pf 1) = pPostfixTry → nodeProd (kid (kid pf 1) 1) = pPostfixEnd →
      FreshId scope ((kidToken (kid pf 1) 0).start - env.base) → LocalOf scope (kid pf 0) l →
      TriedR env l.id none l.ty ((kidToken (kid pf 1) 0).start - env.base) tr → TryLocalR env scope pf tr

/-- A let's `op?`. -/
inductive TryR (env : FrontEnv) (scope : List Local) (init : CTree) : Tried → Prop
  | call {pf : CTree} {tr : Tried} : Peel init pf → TryCallR env scope pf tr → TryR env scope init tr
  | «local» {pf : CTree} {tr : Tried} : Peel init pf → TryLocalR env scope pf tr → TryR env scope init tr

theorem triedOf_sound {fuel : Nat} {env : FrontEnv} {r : Nat} {call : Option MEff} {sty : Option Ty} {w : Nat}
    {tr : Tried} (h : triedOf fuel env r call sty w = some tr) : ∃ st, sty = some st ∧ TriedR env r call st w tr := by
  unfold triedOf at h
  cases sty with
  | none => cases h
  | some st =>
    simp only at h
    cases hn : namedParts st with
    | none => rw [hn] at h; cases h
    | some n =>
      rw [hn] at h
      simp only at h
      cases hr : env.ret with
      | none => rw [hr] at h; cases h
      | some rt =>
        rw [hr] at h
        simp only at h
        cases hm : namedParts rt with
        | none => rw [hm] at h; cases h
        | some m =>
          rw [hm] at h
          simp only at h
          cases ht : env.decls.types[n.decl]? with
          | none => rw [ht] at h; cases h
          | some t =>
            rw [ht] at h
            simp only [triedIf] at h
            split at h
            · rename_i c
              simp only [Bool.and_eq_true, decide_eq_true_eq] at c
              cases hp : payloadTys fuel env.decls n.decl n.args with
              | none => rw [hp] at h; simp [triedShape] at h
              | some ps =>
                cases hq : payloadTys fuel env.decls m.decl m.args with
                | none => rw [hp, hq] at h; simp [triedShape] at h
                | some qs =>
                  rw [hp, hq] at h
                  exact ⟨st, rfl, .mk hn hr hm ht c.1 c.2 (payloadTys_sound hp) (payloadTys_sound hq) h⟩
            · cases h

theorem tryCallOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {pf : CTree} {tr : Tried}
    (c : TryCallForm pf) (h : tryCallOf fuel env scope pf = some tr) : TryCallR env scope pf tr := by
  unfold tryCallOf at h
  simp only at h
  split at h
  · rename_i k
    simp only [Bool.and_eq_true, decide_eq_true_eq] at k
    obtain ⟨⟨f1, f2⟩, ne⟩ := k
    cases hx : effPathCall fuel env scope none (kid (kid pf 0) 0) (kid (kid pf 1) 1) with
    | none => rw [hx] at h; simp [triedCall] at h
    | some x =>
      rw [hx] at h
      simp only [triedCall] at h
      cases hty : effTy fuel env scope x with
      | none => rw [hty] at h; simp [triedOf] at h
      | some st =>
        rw [hty] at h
        obtain ⟨st', hst, tr'⟩ := triedOf_sound h
        cases hst
        exact .mk c ((freshId_iff _ _).1 f1) ((freshId_iff _ _).1 f2) ne (effPathCall_sound hx) (effTy_sound hty) tr'
  · cases h

theorem tryLocalOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {pf : CTree} {tr : Tried}
    (c : isTryLocal pf = true) (h : tryLocalOf fuel env scope pf = some tr) : TryLocalR env scope pf tr := by
  simp only [isTryLocal, Bool.and_eq_true, decide_eq_true_eq] at c
  unfold tryLocalOf at h
  simp only at h
  split at h
  · rename_i fw
    cases hl : localOf env scope (kid pf 0) with
    | none => rw [hl] at h; simp [triedLocal] at h
    | some l =>
      rw [hl] at h
      simp only [triedLocal] at h
      obtain ⟨st, hst, tr'⟩ := triedOf_sound h
      cases hst
      exact .mk c.1 c.2 ((freshId_iff _ _).1 fw) (localOf_sound hl) tr'
  · cases h

theorem tryOfInit_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {init : CTree} {tr : Tried}
    (h : tryOfInit fuel env scope init = some tr) : TryR env scope init tr := by
  unfold tryOfInit at h
  cases hp : peel fuel init with
  | none => rw [hp] at h; cases h
  | some pf =>
    rw [hp] at h
    simp only [tryPostfix] at h
    split at h
    · rename_i c
      exact .call (peel_sound hp) (tryCallOf_sound (isTryCall_sound c) h)
    · split at h
      · rename_i _ c
        exact .local (peel_sound hp) (tryLocalOf_sound c h)
      · cases h

theorem tryLetHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {init : CTree} {hd : LetHead}
    (h : tryLetHead fuel env scope init = some hd) : ∃ tr, hd = .tryOf tr ∧ TryR env scope init tr := by
  unfold tryLetHead at h
  cases ht : tryOfInit fuel env scope init with
  | none => rw [ht] at h; simp [tryHead] at h
  | some tr =>
    rw [ht] at h
    simp only [tryHead, Option.some.injEq] at h
    exact ⟨tr, h.symm, tryOfInit_sound ht⟩

/-- `let x = init;`: `op?` at its success payload's type, or else a value
with a type of its own (`inferred`). -/
inductive UntypedR (env : FrontEnv) (scope : List Local) (init : CTree) : Ty → LetHead → Prop
  | try {tr : Tried} : TryR env scope init tr → UntypedR env scope init tr.okTy (.tryOf tr)
  | eval {x : MEff} {t : Ty} : EffR env scope none init x → inferred x = true → EffTy env.decls scope x t →
      UntypedR env scope init t (evalLetHead t x)

theorem untypedHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {init : CTree} {u : Untyped}
    (h : untypedHead fuel env scope init = some u) : UntypedR env scope init u.ty u.head := by
  unfold untypedHead at h
  cases ht : tryOfInit fuel env scope init with
  | some tr =>
    rw [ht] at h
    simp only [untypedTry, Option.some.injEq] at h
    subst h
    exact .try (tryOfInit_sound ht)
  | none =>
    rw [ht] at h
    simp only at h
    cases he : effOf fuel env scope none init with
    | none => rw [he] at h; simp [untypedEval] at h
    | some x =>
      rw [he] at h
      simp only [untypedEval] at h
      cases hty : effTy fuel env scope x with
      | none => rw [hty] at h; simp at h
      | some t =>
        rw [hty] at h
        simp only [untypedIf] at h
        split at h
        · rename_i c
          simp only [Option.some.injEq] at h
          subst h
          exact .eval (effOf_sound he) c (effTy_sound hty)
        · cases h

/-- What a let binds: a let head, `op?`, or else an effectful expression. -/
inductive LetInitR (env : FrontEnv) (scope : List Local) (ty : Ty) (init : CTree) : LetHead → Prop
  | head {hd : LetHead} : LetHeadR env scope init hd → LetInitR env scope ty init hd
  | try {tr : Tried} : TryR env scope init tr → LetInitR env scope ty init (.tryOf tr)
  | eval {x : MEff} {hd : LetHead} : EffR env scope (some ty) init x → evalHead ty (some x) = some hd →
      LetInitR env scope ty init hd

theorem letHeadOrEval_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {ty : Ty} {init : CTree}
    {hd : LetHead} (h : letHeadOrEval fuel env scope ty init = some hd) : LetInitR env scope ty init hd := by
  unfold letHeadOrEval at h
  cases hl : letHead fuel env scope init with
  | some h' =>
    rw [hl] at h
    simp only [Option.some.injEq] at h
    subst h
    exact .head (letHead_sound hl)
  | none =>
    rw [hl] at h
    simp only at h
    cases ht : tryLetHead fuel env scope init with
    | some t =>
      rw [ht] at h
      simp only [Option.some.injEq] at h
      subst h
      obtain ⟨tr, rfl, k⟩ := tryLetHead_sound ht
      exact .try k
    | none =>
      rw [ht] at h
      simp only at h
      cases he : effOf fuel env scope (some ty) init with
      | none => rw [he] at h; simp [evalHead] at h
      | some x =>
        rw [he] at h
        exact .eval (effOf_sound he) h

/-- `return e;`: a raw slice in a function returning a slice (a slice local
numbered by the value's first token, then its return), or else the value,
read at the result type. -/
inductive ReturnR (env : FrontEnv) (scope : List Local) (e : CTree) : MStmt → Prop
  | slice {el : Ty} {first : Token} {rest : List Token} {p l : SrcExpr} : env.ret = some (.tySlice el) →
      e.leaves = first :: rest → LetHeadR env scope e (.sliceOf p l) →
      ReturnR env scope e (.mLetSlice (first.start - env.base) el p l (.mReturn (.local (first.start - env.base))))
  | eval {x : MEff} : EffR env scope env.ret e x → ReturnR env scope e (returnEff x)

theorem returnOrEval_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {e : CTree} {m : MStmt}
    (h : returnOrEval fuel env scope e = some m) : ReturnR env scope e m := by
  unfold returnOrEval at h
  cases hs : returnSlice fuel env scope e with
  | some m' =>
    rw [hs] at h
    simp only [Option.some.injEq] at h
    subst h
    unfold returnSlice at hs
    cases hr : env.ret with
    | none => rw [hr] at hs; cases hs
    | some t =>
      rw [hr] at hs
      simp only at hs
      cases he : sliceElem t with
      | none => rw [he] at hs; cases hs
      | some el =>
        rw [he] at hs
        simp only at hs
        rw [sliceElem_eq he] at hr
        cases ht : treeTokens e with
        | nil => rw [ht] at hs; cases hs
        | cons first rest =>
          rw [ht] at hs
          simp only [sliceReturned] at hs
          cases hl : letHead fuel env scope e with
          | none => rw [hl] at hs; cases hs
          | some hd =>
            rw [hl] at hs
            cases hd with
            | sliceOf p l =>
              simp only [Option.some.injEq] at hs
              subst hs
              exact .slice hr (by rw [← treeTokens_eq]; exact ht) (letHead_sound hl)
            | plain _ => cases hs
            | callOf _ => cases hs
            | variantOf _ _ => cases hs
            | literalOf _ => cases hs
            | matchOf _ _ _ => cases hs
            | allocOf _ _ => cases hs
            | indexOf _ _ => cases hs
            | evalOf _ => cases hs
            | tryOf _ => cases hs
  | none =>
    rw [hs] at h
    simp only at h
    cases he : effOf fuel env scope env.ret e with
    | none => rw [he] at h; simp [returnEvalOf] at h
    | some x =>
      rw [he] at h
      simp only [returnEvalOf, Option.some.injEq] at h
      subst h
      exact .eval (effOf_sound he)

/-- `if (c) { a } else { b }`. -/
inductive IfR (env : FrontEnv) (scope : List Local) (c : CTree) (a b : MStmt) : MStmt → Prop
  | eval {x : MEff} : EffR env scope (some .tyBool) c x → IfR env scope c a b (ifEff x a b)

theorem ifOrEval_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {c : CTree} {a b : Option MStmt}
    {m : MStmt} (h : ifOrEval fuel env scope c a b = some m) :
    ∃ x y, a = some x ∧ b = some y ∧ IfR env scope c x y m := by
  unfold ifOrEval at h
  simp only [ifEvalOf] at h
  cases he : effOf fuel env scope (some .tyBool) c with
  | none => rw [he] at h; cases h
  | some e =>
    rw [he] at h
    cases a with
    | none => cases h
    | some x =>
      cases b with
      | none => cases h
      | some y =>
        simp only [Option.some.injEq] at h
        subst h
        exact ⟨x, y, rfl, rfl, .eval (effOf_sound he)⟩

/-- `while (c) { body }`. -/
inductive WhileR (env : FrontEnv) (scope : List Local) (c : CTree) (body : MStmt) : MStmt → Prop
  | eval {x : MEff} : EffR env scope (some .tyBool) c x → WhileR env scope c body (whileEff x body)

theorem whileOrEval_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {c : CTree} {body : Option MStmt}
    {m : MStmt} (h : whileOrEval fuel env scope c body = some m) :
    ∃ x, body = some x ∧ WhileR env scope c x m := by
  unfold whileOrEval at h
  simp only [whileEvalOf] at h
  cases he : effOf fuel env scope (some .tyBool) c with
  | none => rw [he] at h; cases h
  | some e =>
    rw [he] at h
    cases body with
    | none => cases h
    | some x =>
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨x, rfl, .eval (effOf_sound he)⟩

/-! ## Assignments -/

/-- `x = value;` for the local `l`: the value read at the local's type. -/
inductive SetR (env : FrontEnv) (scope : List Local) (l : Local) (value : CTree) : MStmt → Prop
  | eval {x : MEff} {m : MStmt} : EffR env scope (some l.ty) value x → setEvalOf l.id (some x) = some m →
      SetR env scope l value m

theorem setOrEval_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {l : Local} {value : CTree} {m : MStmt}
    (h : setOrEval fuel env scope l value = some m) : SetR env scope l value m := by
  unfold setOrEval at h
  cases he : effOf fuel env scope (some l.ty) value with
  | none => rw [he] at h; simp [setEvalOf] at h
  | some x =>
    rw [he] at h
    exact .eval (effOf_sound he) h

/-- `target = value;`: a local, a field of a local, or an element of a
slice local. -/
inductive AssignTargetR (env : FrontEnv) (scope : List Local) (target value : CTree) : MStmt → Prop
  | «local» {l : Local} {m : MStmt} : nodeProd (kid target 1) = pPostfixEnd → LocalOf scope (kid target 0) l →
      SetR env scope l value m → AssignTargetR env scope target value m
  | fieldEval {l : Local} {j : Nat} {t : Ty} {x : MEff} : nodeProd (kid target 1) = pPostfixMember →
      nodeProd (kid (kid target 1) 2) = pMemberTypeArgsNone → nodeProd (kid (kid target 1) 3) = pPostfixEnd →
      LocalOf scope (kid target 0) l → FieldIndex env.decls l.ty (kidToken (kid target 1) 1).text j →
      FieldTyAt env.decls l.ty j t → EffR env scope (some t) value x →
      AssignTargetR env scope target value (setFieldEff l.id j x)
  | indexEval {l : Local} {i v : MEff} : nodeProd (kid target 1) = pPostfixIndex →
      nodeProd (kid (kid target 1) 3) = pPostfixEnd → LocalOf scope (kid target 0) l →
      EffR env scope none (kid (kid target 1) 1) i → EffR env scope (sliceElem l.ty) value v →
      AssignTargetR env scope target value (setIndexEff l.id i v)

theorem assignTarget_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {target value : CTree} {m : MStmt}
    (h : assignTarget fuel env scope target value = some m) : AssignTargetR env scope target value m := by
  unfold assignTarget at h
  simp only at h
  split at h
  · rename_i pe
    cases hl : localOf env scope (kid target 0) with
    | none => rw [hl] at h; cases h
    | some l =>
      rw [hl] at h
      exact .local pe (localOf_sound hl) (setOrEval_sound h)
  split at h
  · rename_i _ c
    simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
    cases hl : localOf env scope (kid target 0) with
    | none => rw [hl] at h; cases h
    | some l =>
      rw [hl] at h
      simp only [setFieldOrEval] at h
      cases hj : fieldIndex env l.ty (kidToken (kid target 1) 1).text with
      | none => rw [hj] at h; cases h
      | some j =>
        rw [hj] at h
        simp only at h
        cases ht : fieldTyAt fuel env.decls l.ty j with
        | none => simp [ht, checkedStmt, hasTy] at h
        | some t =>
          simp only [ht, checkedStmt, hasTy, ↓reduceIte] at h
          cases he : effOf fuel env scope (some t) value with
          | none => rw [he] at h; cases h
          | some x =>
            rw [he] at h
            simp only [fieldEvalStmt, Option.some.injEq] at h
            subst h
            exact .fieldEval c.1 c.2.1 c.2.2 (localOf_sound hl) (fieldIndex_sound hj) (fieldTyAt_sound t ht)
              (effOf_sound he)
  split at h
  · rename_i _ _ c
    simp only [Bool.and_eq_true, decide_eq_true_eq] at c
    cases hl : localOf env scope (kid target 0) with
    | none => rw [hl] at h; cases h
    | some l =>
      rw [hl] at h
      simp only [setIndexOrEval, setIndexEvalOf] at h
      cases hi : effOf fuel env scope none (kid (kid target 1) 1) with
      | none => rw [hi] at h; cases h
      | some i =>
        rw [hi] at h
        cases hv : effOf fuel env scope (sliceElem l.ty) value with
        | none => rw [hv] at h; cases h
        | some v =>
          rw [hv] at h
          simp only [Option.some.injEq] at h
          subst h
          exact .indexEval c.1 c.2 (localOf_sound hl) (effOf_sound hi) (effOf_sound hv)
  cases h

/-- `target op= value;`: `x = x op value` or `x.f = x.f op value`, also for
`/=` and `%=`. -/
inductive CompoundR (env : FrontEnv) (scope : List Local) (target : CTree) (p : Nat) (value : CTree) : MStmt → Prop
  | localEval {l : Local} {x y : MEff} {m : MStmt} : nodeProd (kid target 1) = pPostfixEnd →
      LocalOf scope (kid target 0) l → EffR env scope (some l.ty) value x →
      compoundEff p (.xPure (.local l.id)) (some x) = some y → setEvalOf l.id (some y) = some m →
      CompoundR env scope target p value m
  | fieldEval {l : Local} {j : Nat} {t : Ty} {x y : MEff} : nodeProd (kid target 1) = pPostfixMember →
      nodeProd (kid (kid target 1) 2) = pMemberTypeArgsNone → nodeProd (kid (kid target 1) 3) = pPostfixEnd →
      LocalOf scope (kid target 0) l → FieldIndex env.decls l.ty (kidToken (kid target 1) 1).text j →
      FieldTyAt env.decls l.ty j t → EffR env scope (some t) value x →
      compoundEff p (.xPure (.field l.id j)) (some x) = some y →
      CompoundR env scope target p value (setFieldEff l.id j y)

theorem compoundEff_some {p : Nat} {left : MEff} {right : Option MEff} {y : MEff}
    (h : compoundEff p left right = some y) : ∃ x, right = some x ∧ compoundEff p left (some x) = some y := by
  cases right with
  | some x => exact ⟨x, rfl, h⟩
  | none =>
    unfold compoundEff at h
    repeat' split at h
    all_goals simp [xDivideOf, xApplyOf] at h

theorem compoundOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {target : CTree} {p : Nat} {value : CTree}
    {m : MStmt} (h : compoundOf fuel env scope (some target) p value = some m) : CompoundR env scope target p value m := by
  simp only [compoundOf] at h
  simp only [compoundEval] at h
  split at h
  · rename_i pe
    cases hl : localOf env scope (kid target 0) with
    | none => rw [hl] at h; cases h
    | some l =>
      rw [hl] at h
      simp only at h
      cases hy : compoundEff p (.xPure (.local l.id)) (effOf fuel env scope (some l.ty) value) with
      | none => rw [hy] at h; simp [setEvalOf] at h
      | some y =>
        rw [hy] at h
        obtain ⟨x, hx, hy'⟩ := compoundEff_some hy
        exact .localEval pe (localOf_sound hl) (effOf_sound hx) hy' h
  split at h
  · rename_i _ c
    simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
    cases hl : localOf env scope (kid target 0) with
    | none => rw [hl] at h; cases h
    | some l =>
      rw [hl] at h
      simp only [compoundFieldEval] at h
      cases hj : fieldIndex env l.ty (kidToken (kid target 1) 1).text with
      | none => rw [hj] at h; cases h
      | some j =>
        rw [hj] at h
        simp only at h
        cases ht : fieldTyAt fuel env.decls l.ty j with
        | none => simp [ht, checkedStmt, hasTy] at h
        | some t =>
          simp only [ht, checkedStmt, hasTy, ↓reduceIte] at h
          cases hy : compoundEff p (.xPure (.field l.id j)) (effOf fuel env scope (some t) value) with
          | none => rw [hy] at h; simp [fieldEvalStmt] at h
          | some y =>
            rw [hy] at h
            simp only [fieldEvalStmt, Option.some.injEq] at h
            subst h
            obtain ⟨x, hx, hy'⟩ := compoundEff_some hy
            exact .fieldEval c.1 c.2.1 c.2.2 (localOf_sound hl) (fieldIndex_sound hj) (fieldTyAt_sound t ht)
              (effOf_sound hx) hy'
  cases h

/-- A call statement: `dealloc(pointer, size, align)`, `assert(c)`, or a
call whose value is discarded. -/
inductive CallStmtR (env : FrontEnv) (scope : List Local) (pf : CTree) : MStmt → Prop
  | free {pointer size align : SrcExpr} {k : Nat} : PathCallForm pf →
      PathSpellings (kid (kid (kid pf 0) 0) 0) (kid (kid (kid pf 0) 0) 1) deallocPath →
      ArgsOfR env scope (kid (kid pf 1) 1) [pointer, size, align] → ShiftOf align k →
      CallStmtR env scope pf (.mFree pointer size k)
  | assert {c : CTree} {x : MEff} : PathCallForm pf →
      PathSpellings (kid (kid (kid pf 0) 0) 0) (kid (kid (kid pf 0) 0) 1) [textAssert] →
      Items (kid (kid pf 1) 1) [c] → EffR env scope (some .tyBool) c x → CallStmtR env scope pf (.mAssert x)
  | discard {x : MEff} : (PathCallForm pf ∨ MethodForm pf) → EffR env scope none pf x →
      CallStmtR env scope pf (.mDiscard x)
  | try {tr : Tried} : TryCallR env scope pf tr → CallStmtR env scope pf (tryRest tr .mNop)

theorem freeOf_sound {es : List SrcExpr} {m : MStmt} (h : freeOf (some es) = some m) :
    ∃ pointer size align k, es = [pointer, size, align] ∧ ShiftOf align k ∧ m = .mFree pointer size k := by
  match es, h with
  | [], h => simp [freeOf] at h
  | [_], h => simp [freeOf] at h
  | [_, _], h => simp [freeOf] at h
  | pointer :: size :: align :: more, h =>
    simp only [freeOf] at h
    cases hs : shiftOf align with
    | none => rw [hs] at h; simp [freeShifted] at h
    | some k =>
      rw [hs] at h
      cases more with
      | nil =>
        simp only [freeShifted, Option.some.injEq] at h
        exact ⟨pointer, size, align, k, rfl, shiftOf_sound hs, h.symm⟩
      | cons _ _ => simp [freeShifted] at h

theorem callStmt_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {pf : CTree} {m : MStmt}
    (pp : nodeProd pf = pPostfix) (h : callStmt fuel env scope pf = some m) : CallStmtR env scope pf m := by
  unfold callStmt at h
  simp only at h
  split at h
  · rename_i c
    simp only [Bool.and_eq_true] at c
    cases ha : argsOf fuel env scope (kid (kid pf 1) 1) with
    | none => rw [ha] at h; simp [freeOf] at h
    | some es =>
      rw [ha] at h
      obtain ⟨pointer, size, align, k, rfl, sh, rfl⟩ := freeOf_sound h
      exact .free (isPathCall_sound c.1) (pathSpellings_sound (isPath_eq c.2)) (argsOf_sound ha) sh
  split at h
  · rename_i _ c
    simp only [Bool.and_eq_true] at c
    cases hi : listItems fuel (kid (kid pf 1) 1) with
    | none => rw [hi] at h; simp [assertArg] at h
    | some items =>
      rw [hi] at h
      match items, h, hi with
      | [], h, _ => simp [assertArg] at h
      | _ :: _ :: _, h, _ => simp [assertArg] at h
      | [a], h, hi =>
        simp only [assertArg] at h
        cases he : effOf fuel env scope (some .tyBool) a with
        | none => rw [he] at h; simp [assertOf] at h
        | some x =>
          rw [he] at h
          simp only [assertOf, Option.some.injEq] at h
          subst h
          exact .assert (isPathCall_sound c.1) (pathSpellings_sound (isPath_eq c.2)) (listItems_sound hi)
            (effOf_sound he)
  split at h
  · rename_i _ _ c
    simp only [Bool.or_eq_true] at c
    cases he : effPostfix fuel env scope none pf with
    | none => rw [he] at h; simp [discardOf] at h
    | some x =>
      rw [he] at h
      simp only [discardOf, Option.some.injEq] at h
      subst h
      refine .discard ?_ (effPostfix_sound pp he)
      rcases c with c | c
      · exact .inl (isPathCall_sound c)
      · exact .inr (isMethodForm_sound c)
  split at h
  · rename_i _ _ _ c
    cases ht : tryCallOf fuel env scope pf with
    | none => rw [ht] at h; simp [tryStmt] at h
    | some tr =>
      rw [ht] at h
      simp only [tryStmt, Option.some.injEq] at h
      subst h
      exact .try (tryCallOf_sound (isTryCall_sound c) ht)
  cases h

/-- An expression statement: `target = value;`, `target op= value;`, or a
call statement. -/
inductive AssignR (env : FrontEnv) (scope : List Local) (e : CTree) : MStmt → Prop
  | set {target : CTree} {m : MStmt} : nodeProd e = pExpr → nodeProd (kid e 0) = pAssign →
      nodeProd (kid (kid e 0) 1) = pAssignSet → Peel (kid (kid e 0) 0) target →
      AssignTargetR env scope target (kid (kid (kid e 0) 1) 1) m → AssignR env scope e m
  | compound {target : CTree} {m : MStmt} : nodeProd e = pExpr → nodeProd (kid e 0) = pAssign →
      kidsOf (kid (kid e 0) 1) ≠ [] → nodeProd (kid (kid e 0) 1) ≠ pAssignSet → Peel (kid (kid e 0) 0) target →
      CompoundR env scope target (nodeProd (kid (kid e 0) 1)) (kid (kid (kid e 0) 1) 1) m → AssignR env scope e m
  | call {pf : CTree} {m : MStmt} : nodeProd e = pExpr → nodeProd (kid e 0) = pAssign →
      nodeProd (kid (kid e 0) 1) = pAssignEnd → kidsOf (kid (kid e 0) 1) = [] → Peel (kid (kid e 0) 0) pf →
      CallStmtR env scope pf m →
      AssignR env scope e m

theorem assignment_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {e : CTree} {m : MStmt}
    (h : assignment fuel env scope e = some m) : AssignR env scope e m := by
  unfold assignment at h
  simp only at h
  split at h
  · rename_i c
    simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
    cases hp : peel fuel (kid (kid e 0) 0) with
    | none => rw [hp] at h; cases h
    | some target =>
      rw [hp] at h
      exact .set c.1 c.2.1 c.2.2 (peel_sound hp) (assignTarget_sound h)
  split at h
  · rename_i _ c
    simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
    cases hp : peel fuel (kid (kid e 0) 0) with
    | none => rw [hp] at h; simp [compoundOf] at h
    | some target =>
      rw [hp] at h
      exact .compound c.1 c.2.1 ((hasKids_iff _).1 c.2.2.1) c.2.2.2 (peel_sound hp) (compoundOf_sound h)
  split at h
  · rename_i _ c2 c
    simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
    have kn : kidsOf (kid (kid e 0) 1) = [] := Classical.byContradiction fun hne => c2 (by
      simp only [Bool.and_eq_true, decide_eq_true_eq]
      exact ⟨⟨⟨c.1, c.2.1⟩, (hasKids_iff _).2 hne⟩, by rw [c.2.2]; decide⟩)
    cases hp : peel fuel (kid (kid e 0) 0) with
    | none => rw [hp] at h; cases h
    | some pf =>
      rw [hp] at h
      have pe := peel_sound hp
      exact .call c.1 c.2.1 c.2.2 kn pe (callStmt_sound (peel_postfix pe) h)
  cases h

/-! ## Statement lists -/

mutual
/-- A block's statement list. -/
inductive BlockR (env : FrontEnv) : List Local → CTree → MStmt → Prop
  | mk {scope : List Local} {list : CTree} {items : List CTree} {m : MStmt} : Items list items →
      StmtsR env scope items m → BlockR env scope list m

/-- A statement list: a let scopes over the statements after it. -/
inductive StmtsR (env : FrontEnv) : List Local → List CTree → MStmt → Prop
  | nil {scope : List Local} : StmtsR env scope [] .mNop
  | «let» {scope : List Local} {s : CTree} {rest : List CTree} {t : Ty} {hd : LetHead} {body m : MStmt} :
      nodeProd s = pLetStmt → nodeProd (kid s 2) = pLetType → nodeProd (kid s 3) = pLetInit →
      (kidToken s 1).text ∉ env.globals → FreshId scope ((kidToken s 1).start - env.base) →
      TyR env (kid (kid s 2) 1) t →
      LetInitR env scope t (kid (kid s 3) 1) hd →
      StmtsR env ({ name := (kidToken s 1).text, id := (kidToken s 1).start - env.base, ty := t } :: scope) rest body →
      letStmt ((kidToken s 1).start - env.base) t hd body = some m → StmtsR env scope (s :: rest) m
  /-- `let x = init;`, x at init's own type. -/
  | letUntyped {scope : List Local} {s : CTree} {rest : List CTree} {t : Ty} {hd : LetHead} {body m : MStmt} :
      nodeProd s = pLetStmt → nodeProd (kid s 2) = pLetTypeNone → nodeProd (kid s 3) = pLetInit →
      (kidToken s 1).text ∉ env.globals → FreshId scope ((kidToken s 1).start - env.base) →
      UntypedR env scope (kid (kid s 3) 1) t hd →
      StmtsR env ({ name := (kidToken s 1).text, id := (kidToken s 1).start - env.base, ty := t } :: scope) rest body →
      letStmt ((kidToken s 1).start - env.base) t hd body = some m → StmtsR env scope (s :: rest) m
  | last {scope : List Local} {s : CTree} {m : MStmt} : nodeProd s ≠ pLetStmt → StmtR env scope s m →
      StmtsR env scope [s] m
  | seq {scope : List Local} {s next : CTree} {more : List CTree} {a b : MStmt} : nodeProd s ≠ pLetStmt →
      StmtR env scope s a → StmtsR env scope (next :: more) b → StmtsR env scope (s :: next :: more) (.mThen a b)

/-- A statement other than a let. -/
inductive StmtR (env : FrontEnv) : List Local → CTree → MStmt → Prop
  | ret {scope : List Local} {s : CTree} {m : MStmt} : nodeProd s = pReturnStmt → nodeProd (kid s 1) = pReturnValue →
      ReturnR env scope (kid (kid s 1) 0) m → StmtR env scope s m
  | retUnit {scope : List Local} {s : CTree} : nodeProd s = pReturnStmt → nodeProd (kid s 1) = pReturnVoid →
      StmtR env scope s .mReturnUnit
  | brk {scope : List Local} {s : CTree} : nodeProd s = pBreakStmt → StmtR env scope s .mBreak
  | cont {scope : List Local} {s : CTree} : nodeProd s = pContinueStmt → StmtR env scope s .mContinue
  | ifElse {scope : List Local} {s : CTree} {a b m : MStmt} : nodeProd s = pIfStmt → nodeProd (kid s 5) = pElseStmt →
      BlockR env scope (kid (kid s 4) 1) a → BlockR env scope (kid (kid (kid s 5) 1) 1) b →
      IfR env scope (kid s 2) a b m → StmtR env scope s m
  | ifOnly {scope : List Local} {s : CTree} {a m : MStmt} : nodeProd s = pIfStmt → nodeProd (kid s 5) = pElseNone →
      BlockR env scope (kid (kid s 4) 1) a → IfR env scope (kid s 2) a .mNop m → StmtR env scope s m
  | «while» {scope : List Local} {s : CTree} {body m : MStmt} : nodeProd s = pWhileStmt →
      BlockR env scope (kid (kid s 4) 1) body → WhileR env scope (kid s 2) body m → StmtR env scope s m
  | assign {scope : List Local} {s : CTree} {m : MStmt} : nodeProd s = pExprStmt → AssignR env scope (kid s 0) m →
      StmtR env scope s m
  /-- `for x in a..n { body }`: `let c = a; let e = n; while (c < e) { let x = c;
  c = c + 1; body }`, c, e and x numbered by the `for`, x's and the `in` token. -/
  | forRange {scope : List Local} {s : CTree} {n : Local} {a : SrcExpr} {body m : MStmt} :
      nodeProd s = pForStmt → nodeProd (kid s 3) = pForIterRangeFromStart →
      nodeProd (kid (kid s 3) 0) = pRangeStartInt → nodeProd (kid (kid s 3) 1) = pRangeExclusive →
      nodeProd (kid (kid (kid s 3) 1) 1) = pRangeBound →
      nodeProd (kid (kid (kid (kid s 3) 1) 1) 0) = pRangeBoundName →
      nodeProd (kid (kid (kid (kid (kid s 3) 1) 1) 0) 1) = pPostfixEnd →
      (kidToken s 1).text ∉ env.globals → FreshId scope ((kidToken s 1).start - env.base) →
      FreshId scope ((kidToken s 0).start - env.base) → FreshId scope ((kidToken s 2).start - env.base) →
      LocalNamed scope (kidToken (kid (kid (kid (kid (kid s 3) 1) 1) 0) 0) 0).text n →
      IntLiteral (kidToken (kid (kid s 3) 0) 0).text a →
      BlockR env ({ name := (kidToken s 1).text, id := (kidToken s 2).start - env.base, ty := n.ty } :: scope)
        (kid (kid s 4) 1) body →
      forRange ((kidToken s 0).start - env.base) ((kidToken s 1).start - env.base) ((kidToken s 2).start - env.base)
        n.ty a n.id (some body) = some m →
      StmtR env scope s m
  /-- `{ ... }`: its lets scope over the block only. -/
  | block {scope : List Local} {s : CTree} {m : MStmt} : nodeProd s = pBlockStmt →
      BlockR env scope (kid (kid s 0) 1) m → StmtR env scope s m
end

def StmtSound (fuel : Nat) : Prop :=
  (∀ {env scope list m}, blockOf fuel env scope list = some m → BlockR env scope list m) ∧
  (∀ {env scope items m}, stmtsOf fuel env scope items = some m → StmtsR env scope items m) ∧
  (∀ {env scope s rest m}, stmtFirst fuel env scope s rest = some m → StmtsR env scope (s :: rest) m) ∧
  (∀ {env scope s rest m}, nodeProd s = pLetStmt → letFirst fuel env scope s rest = some m →
    StmtsR env scope (s :: rest) m) ∧
  (∀ {env scope s m}, stmtOf fuel env scope s = some m → StmtR env scope s m) ∧
  (∀ {env scope s m}, nestedOf fuel env scope s = some m → StmtR env scope s m)

theorem stmtSound : ∀ fuel, StmtSound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
    all_goals intros
    all_goals rename_i h
    · rw [blockOf.eq_def] at h; simp at h
    · rw [stmtsOf.eq_def] at h; simp at h
    · rw [stmtFirst.eq_def] at h; simp at h
    · rw [letFirst.eq_def] at h; simp at h
    · rw [stmtOf.eq_def] at h; simp at h
    · rw [nestedOf.eq_def] at h; simp at h
  | f + 1 => by
    obtain ⟨ihBlock, ihStmts, ihFirst, ihLet, ihStmt, ihNested⟩ := stmtSound f
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro env scope list m h
      rw [blockOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases hi : listItems (f + 1) list with
      | none => rw [hi] at h; cases h
      | some items =>
        rw [hi] at h
        exact .mk (listItems_sound hi) (ihStmts h)
    · intro env scope items m h
      rw [stmtsOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases items with
      | nil =>
        simp only [Option.some.injEq] at h
        subst h
        exact .nil
      | cons s rest =>
        exact ihFirst h
    · intro env scope s rest m h
      rw [stmtFirst.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i pl
        exact ihLet pl h
      · rename_i pl
        cases rest with
        | nil => exact .last pl (ihStmt h)
        | cons next more =>
          simp only [thenOf] at h
          cases ha : stmtOf f env scope s with
          | none => rw [ha] at h; cases h
          | some a =>
            rw [ha] at h
            simp only [thenRest] at h
            cases hb : stmtsOf f env scope (next :: more) with
            | none => rw [hb] at h; cases h
            | some b =>
              rw [hb] at h
              simp only [Option.some.injEq] at h
              subst h
              exact .seq pl (ihStmt ha) (ihStmts hb)
    · intro env scope s rest m pl h
      rw [letFirst.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i c
        simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at c
        obtain ⟨⟨⟨lt, li⟩, ng⟩, fr⟩ := c
        cases ht : tyOf (f + 1) env (kid (kid s 2) 1) with
        | none => rw [ht] at h; cases h
        | some t =>
          rw [ht] at h
          simp only [letOf] at h
          cases hh : letHeadOrEval f env scope t (kid (kid s 3) 1) with
          | none => rw [hh] at h; cases h
          | some hd =>
            rw [hh] at h
            simp only [letBody] at h
            cases hb : stmtsOf f env ({ name := (kidToken s 1).text, id := (kidToken s 1).start - env.base, ty := t } ::
                scope) rest with
            | none => rw [hb] at h; cases h
            | some body =>
              rw [hb] at h
              refine .let pl lt li (fun mem => ?_) ((freshId_iff _ _).1 fr) (tyOf_sound ht) (letHeadOrEval_sound hh)
                (ihStmts hb) h
              rw [(member_iff _ _).2 mem] at ng
              cases ng
      · split at h
        · rename_i _ c
          simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at c
          obtain ⟨⟨⟨lt, li⟩, ng⟩, fr⟩ := c
          cases hu : untypedHead f env scope (kid (kid s 3) 1) with
          | none => rw [hu] at h; cases h
          | some u =>
            rw [hu] at h
            simp only [letBody] at h
            cases hb : stmtsOf f env
                ({ name := (kidToken s 1).text, id := (kidToken s 1).start - env.base, ty := u.ty } :: scope) rest with
            | none => rw [hb] at h; cases h
            | some body =>
              rw [hb] at h
              refine .letUntyped pl lt li (fun mem => ?_) ((freshId_iff _ _).1 fr) (untypedHead_sound hu)
                (ihStmts hb) h
              rw [(member_iff _ _).2 mem] at ng
              cases ng
        · cases h
    · intro env scope s m h
      rw [stmtOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i c
        simp only [Bool.and_eq_true, decide_eq_true_eq] at c
        exact .ret c.1 c.2 (returnOrEval_sound h)
      split at h
      · rename_i _ c
        simp only [Bool.and_eq_true, decide_eq_true_eq] at c
        simp only [Option.some.injEq] at h
        subst h
        exact .retUnit c.1 c.2
      split at h
      · rename_i _ _ c
        simp only [Option.some.injEq] at h
        subst h
        exact .brk (by simpa using c)
      split at h
      · rename_i _ _ _ c
        simp only [Option.some.injEq] at h
        subst h
        exact .cont (by simpa using c)
      split at h
      · rename_i _ _ _ _ c
        simp only [Bool.and_eq_true, decide_eq_true_eq] at c
        obtain ⟨a, b, ha, hb, ir⟩ := ifOrEval_sound h
        exact .ifElse c.1 c.2 (ihBlock ha) (ihBlock hb) ir
      split at h
      · rename_i _ _ _ _ _ c
        simp only [Bool.and_eq_true, decide_eq_true_eq] at c
        obtain ⟨a, b, ha, hb, ir⟩ := ifOrEval_sound h
        simp only [Option.some.injEq] at hb
        subst hb
        exact .ifOnly c.1 c.2 (ihBlock ha) ir
      split at h
      · rename_i _ _ _ _ _ _ pw
        obtain ⟨body, hb, wr⟩ := whileOrEval_sound h
        exact .while pw (ihBlock hb) wr
      split at h
      · exact ihNested h
      split at h
      · rename_i _ _ _ _ _ _ _ _ pa
        exact .assign pa (assignment_sound h)
      cases h
    · intro env scope s m h
      rw [nestedOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i pf
        try dsimp only at h
        split at h
        · rename_i c
          simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at c
          obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨pi, ps⟩, pe⟩, pb⟩, pn⟩, pp⟩, ng⟩, fx⟩, fc⟩, fe⟩ := c
          cases hn : findLocal scope (kidToken (kid (kid (kid (kid (kid s 3) 1) 1) 0) 0) 0).text with
          | none => rw [hn] at h; cases h
          | some n =>
            rw [hn] at h
            try dsimp only at h
            cases ha : intLiteral (kidToken (kid (kid s 3) 0) 0).text with
            | none => rw [ha] at h; cases h
            | some a =>
              rw [ha] at h
              try dsimp only at h
              cases hb : blockOf f env (⟨(kidToken s 1).text, (kidToken s 2).start - env.base, n.ty⟩ :: scope)
                  (kid (kid s 4) 1) with
              | none => rw [hb] at h; simp [forRange] at h
              | some body =>
                rw [hb] at h
                refine .forRange pf pi ps pe pb pn pp (fun mem => ?_) ((freshId_iff _ _).1 fx)
                  ((freshId_iff _ _).1 fc) ((freshId_iff _ _).1 fe) (findLocal_sound hn) (intLiteral_sound ha)
                  (ihBlock hb) h
                rw [(member_iff _ _).2 mem] at ng
                cases ng
        · cases h
      split at h
      · rename_i _ pb
        exact .block pb (ihBlock h)
      cases h

theorem blockOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {list : CTree} {m : MStmt}
    (h : blockOf fuel env scope list = some m) : BlockR env scope list m :=
  (stmtSound fuel).1 h

end Lanius.Mini.Reading
