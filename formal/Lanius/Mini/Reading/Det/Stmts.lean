import Lanius.Mini.Reading.Det.Effs
import Lanius.Mini.Reading.Stmts

/-! # The reading is deterministic, F1: statements

`stmtsR_unique`: in a scope whose locals have distinct ids, a statement list
reads as at most one statement. A let's head (an `alloc` or
`slice_from_raw_parts` call) is never also an effectful expression, since no
function or variant is read at a reserved path (`peel_noEff`); a call
statement's `dealloc` and `assert` are told apart from a discarded call the
same way. The other forms are told apart by production. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Parts -/

theorem pow_two_inj {k k' : Nat} (hk : k < 31) (hk' : k' < 31)
    (h : BitVec.ofNat 64 (2 ^ k) = BitVec.ofNat 64 (2 ^ k')) : k = k' := by
  have e := congrArg BitVec.toNat h
  simp only [BitVec.toNat_ofNat] at e
  rw [Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by decide) (by omega)),
    Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by decide) (by omega))] at e
  rcases Nat.lt_trichotomy k k' with h | h | h
  · exact absurd e (Nat.ne_of_lt (Nat.pow_lt_pow_right (by decide) h))
  · exact h
  · exact absurd e.symm (Nat.ne_of_lt (Nat.pow_lt_pow_right (by decide) h))

theorem literalShift_unique {e : SrcExpr} {k k' : Nat} (h₁ : LiteralShift e k) (h₂ : LiteralShift e k') : k = k' := by
  cases h₁ with
  | int lt e₁ => cases h₂ with
    | int lt' e₂ => exact pow_two_inj lt lt' (e₁.symm.trans e₂)
  | unsigned lt e₁ => cases h₂ with
    | unsigned lt' e₂ => exact pow_two_inj lt lt' (e₁.symm.trans e₂)

theorem shiftOf_unique {e : SrcExpr} {k k' : Nat} (h₁ : ShiftOf e k) (h₂ : ShiftOf e k') : k = k' := by
  cases h₁ with
  | lit l => cases h₂ with
    | lit l' => exact literalShift_unique l l'
    | cast l' => cases l
  | cast l => cases h₂ with
    | lit l' => cases l'
    | cast l' => exact literalShift_unique l l'

theorem argsOfR_unique {env : FrontEnv} {scope : List Local} {args : CTree} {a b : List SrcExpr}
    (h₁ : ArgsOfR env scope args a) (h₂ : ArgsOfR env scope args b) : a = b := by
  obtain ⟨items, it, es⟩ := h₁
  obtain ⟨items', it', es'⟩ := h₂
  cases items_unique it it'
  exact listRel_unique (R := ExprR env scope) (fun _ _ _ x y => exprR_unique x y) es es'

theorem allocHeadR_unique {es : List SrcExpr} {a b : LetHead} (h₁ : AllocHeadR es a) (h₂ : AllocHeadR es b) :
    a = b := by
  obtain ⟨size, align, k, rfl, sh, rfl⟩ := h₁
  obtain ⟨size', align', k', e, sh', rfl⟩ := h₂
  cases e
  rw [shiftOf_unique sh sh']

theorem callPathHeadR_unique {env : FrontEnv} {scope : List Local} {path args : CTree} {a b : LetHead}
    (h₁ : CallPathHeadR env scope path args a) (h₂ : CallPathHeadR env scope path args b) : a = b := by
  cases h₁ with
  | alloc ps ar ah => cases h₂ with
    | alloc _ ar' ah' =>
      cases argsOfR_unique ar ar'
      exact allocHeadR_unique ah ah'
    | slice ps' _ => exact absurd (pathSpellings_unique ps ps') (by decide)
  | slice ps ar => cases h₂ with
    | alloc ps' _ _ => exact absurd (pathSpellings_unique ps ps') (by decide)
    | slice _ ar' => cases argsOfR_unique ar ar'; rfl

theorem letHeadR_unique {env : FrontEnv} {scope : List Local} {init : CTree} {a b : LetHead}
    (h₁ : LetHeadR env scope init a) (h₂ : LetHeadR env scope init b) : a = b := by
  cases h₁ with
  | callPath pe _ _ _ _ ch => cases h₂ with
    | callPath pe' _ _ _ _ ch' =>
      cases peel_unique pe pe'
      exact callPathHeadR_unique ch ch'

theorem fieldTyAt_unique {decls : Decls} {t : Ty} {j : Nat} {a b : Ty} (h₁ : FieldTyAt decls t j a)
    (h₂ : FieldTyAt decls t j b) : a = b := by
  obtain ⟨d, args, ts, rfl, f, g⟩ := h₁
  obtain ⟨d', args', ts', e, f', g'⟩ := h₂
  cases e
  rw [fieldTys_unique f f', g'] at g
  exact (Option.some.inj g).symm

/-! ## Reserved calls are not expressions -/

/-- A pure expression is never a call. -/
theorem peel_noExpr : ∀ {env : FrontEnv} {scope : List Local} {c pf : CTree} {e : SrcExpr},
    Peel c pf → nodeProd (kid pf 1) = pPostfixCall → ExprR env scope c e → False
  | _, _, _, _, _, .wrap _ p, pc, h => by
    cases h with
    | wrap _ r => exact peel_noExpr p pc r
    | _ => expr_clash
  | _, _, _, _, _, .bare _ _ p, pc, h => by
    cases h with
    | assign _ _ r => exact peel_noExpr p pc r
    | level _ r _ => exact peel_noExpr p pc r
    | cast _ r _ => exact peel_noExpr p pc r
    | _ => expr_clash
  | _, _, _, _, _, .here _, _, h => by
    cases h with
    | _ => expr_clash

/-- A call of a reserved path other than `slice_stride` is never an
effectful expression. -/
theorem peel_noEff : ∀ {env : FrontEnv} {scope : List Local} {E : Option Ty} {c pf : CTree} {ss : ModPath}
    {x : MEff}, Peel c pf → PathCallForm pf → PathSpellings (kid (kid (kid pf 0) 0) 0) (kid (kid (kid pf 0) 0) 1) ss →
    ss ∈ builtinPaths → ss ≠ [textSliceStride] → EffR env scope E c x → False
  | _, _, _, _, _, _, _, .wrap w p, cf, ps, mb, ns, h => by
    cases h with
    | pure r => exact peel_noExpr (.wrap w p) cf.2.2.1 r
    | wrap _ k => exact peel_noEff p cf ps mb ns k
    | _ => eff_clash
  | _, _, _, _, _, _, _, .bare w kn p, cf, ps, mb, ns, h => by
    cases h with
    | pure r => exact peel_noExpr (.bare w kn p) cf.2.2.1 r
    | bare _ _ k => exact peel_noEff p cf ps mb ns k
    | level _ kn' _ _ => exact kn' kn
    | cast _ kn' _ _ => exact kn' kn
    | _ => eff_clash
  | _, _, _, _, _, _, _, .here pp, cf, ps, mb, ns, h => by
    obtain ⟨p0, p01, p1, p13⟩ := cf
    cases h with
    | pure r => exact peel_noExpr (.here pp) p1 r
    | pathCall _ _ _ _ _ pc =>
      cases pc with
      | stride ps' _ _ _ _ _ => exact ns (pathSpellings_unique ps ps')
      | named pr nb _ _ _ => exact nb (by rw [pathRefR_spellings ps pr]; exact mb)
    | callChain _ _ _ _ ne _ _ => exact ne p13
    | chainLocal _ cf _ _ => exact cf.2.2.2 ⟨p0, p01, p1⟩
    | chain _ cf _ _ => exact cf.2.2.2 ⟨p0, p01, p1⟩
    | _ => eff_clash

theorem letHead_noEff {env : FrontEnv} {scope : List Local} {E : Option Ty} {init : CTree} {hd : LetHead}
    {x : MEff} (l : LetHeadR env scope init hd) (k : EffR env scope E init x) : False := by
  cases l with
  | callPath pe p0 p01 p1 p13 ch =>
    cases ch with
    | alloc ps _ _ => exact peel_noEff pe ⟨p0, p01, p1, p13⟩ ps (by simp [builtinPaths]) (by decide) k
    | slice ps _ => exact peel_noEff pe ⟨p0, p01, p1, p13⟩ ps (by simp [builtinPaths]) (by decide) k

/-! ## `?` -/

theorem peel_noExprTry : ∀ {env : FrontEnv} {scope : List Local} {c pf : CTree} {e : SrcExpr},
    Peel c pf → (nodeProd (kid pf 1) = pPostfixCall ∨ nodeProd (kid pf 1) = pPostfixTry) → ExprR env scope c e → False
  | _, _, _, _, _, .wrap _ p, pc, h => by
    cases h with
    | wrap _ r => exact peel_noExprTry p pc r
    | _ => expr_clash
  | _, _, _, _, _, .bare _ _ p, pc, h => by
    cases h with
    | assign _ _ r => exact peel_noExprTry p pc r
    | level _ r _ => exact peel_noExprTry p pc r
    | cast _ r _ => exact peel_noExprTry p pc r
    | _ => expr_clash
  | _, _, _, _, _, .here _, _, h => by
    cases h with
    | _ => expr_clash

theorem effChain_noTry {env : FrontEnv} {scope : List Local} {E : Option Ty} {a : MEff} {tail : CTree} {x : MEff}
    (t : nodeProd tail = pPostfixTry) (h : EffChain env scope E a tail x) : False := by
  cases h <;> prod_clash

theorem tryTail {pf : CTree} (tf : TryCallForm pf ∨ nodeProd (kid pf 1) = pPostfixTry) :
    nodeProd (kid pf 1) = pPostfixCall ∨ nodeProd (kid pf 1) = pPostfixTry :=
  tf.elim (fun t => .inl t.2.2.1) .inr

/-- `op?` is never an effectful expression: no rule reads a `?`. -/
theorem peel_noEffTry : ∀ {env : FrontEnv} {scope : List Local} {E : Option Ty} {c pf : CTree} {x : MEff},
    Peel c pf → (TryCallForm pf ∨ nodeProd (kid pf 1) = pPostfixTry) → EffR env scope E c x → False
  | _, _, _, _, _, _, .wrap w p, tf, h => by
    cases h with
    | pure r => exact peel_noExprTry (.wrap w p) (tryTail tf) r
    | wrap _ k => exact peel_noEffTry p tf k
    | _ => eff_clash
  | _, _, _, _, _, _, .bare w kn p, tf, h => by
    cases h with
    | pure r => exact peel_noExprTry (.bare w kn p) (tryTail tf) r
    | bare _ _ k => exact peel_noEffTry p tf k
    | level _ kn' _ _ => exact kn' kn
    | cast _ kn' _ _ => exact kn' kn
    | _ => eff_clash
  | _, _, _, _, _, _, .here pp, tf, h => by
    cases h with
    | pure r => exact peel_noExprTry (.here pp) (tryTail tf) r
    | callChain _ _ _ _ _ _ ch =>
      rcases tf with ⟨_, _, _, t, _⟩ | t
      · exact effChain_noTry t ch
      · prod_clash
    | chainLocal _ cf _ ch =>
      rcases tf with ⟨p0, p01, p1, _, _⟩ | t
      · exact cf.2.2.2 ⟨p0, p01, p1⟩
      · exact effChain_noTry t ch
    | chain _ cf _ ch =>
      rcases tf with ⟨p0, p01, p1, _, _⟩ | t
      · exact cf.2.2.2 ⟨p0, p01, p1⟩
      · exact effChain_noTry t ch
    | _ => rcases tf with ⟨_, _, _, _, _⟩ | _ <;> eff_clash

theorem triedR_unique {env : FrontEnv} {r : Nat} {call : Option MEff} {st : Ty} {w : Nat} {a b : Tried}
    (h₁ : TriedR env r call st w a) (h₂ : TriedR env r call st w b) : a = b := by
  cases h₁ with
  | mk hn hr hm _ _ _ hp hq hs => cases h₂ with
    | mk hn' hr' hm' _ _ _ hp' hq' hs' =>
      rw [hn] at hn'
      cases hn'
      rw [hr] at hr'
      cases hr'
      rw [hm] at hm'
      cases hm'
      cases payloadTys_unique hp hp'
      cases payloadTys_unique hq hq'
      rw [hs] at hs'
      exact Option.some.inj hs'

theorem tryCallR_unique {env : FrontEnv} {scope : List Local} {pf : CTree} {a b : Tried} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : TryCallR env scope pf a) (h₂ : TryCallR env scope pf b) : a = b := by
  cases h₁ with
  | mk _ _ _ _ pc ty tr => cases h₂ with
    | mk _ _ _ _ pc' ty' tr' =>
      cases effPathCall_unique pc nd vn pc'
      cases effTy_unique ty ty'
      exact triedR_unique tr tr'

theorem tryR_unique {env : FrontEnv} {scope : List Local} {init : CTree} {a b : Tried} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : TryR env scope init a) (h₂ : TryR env scope init b) : a = b := by
  cases h₁ with
  | call p c => cases h₂ with
    | call p' c' =>
      cases peel_unique p p'
      exact tryCallR_unique nd vn c c'
    | «local» p' l' =>
      cases peel_unique p p'
      cases c with
      | mk f _ _ _ _ _ _ => cases l' with
        | mk t _ _ _ _ =>
          obtain ⟨_, _, f1, _⟩ := f
          prod_clash
  | «local» p l => cases h₂ with
    | call p' c' =>
      cases peel_unique p p'
      cases c' with
      | mk f _ _ _ _ _ _ => cases l with
        | mk t _ _ _ _ =>
          obtain ⟨_, _, f1, _⟩ := f
          prod_clash
    | «local» p' l' =>
      cases peel_unique p p'
      cases l with
      | mk _ _ _ lo tr => cases l' with
        | mk _ _ _ lo' tr' =>
          cases localOf_unique lo lo'
          exact triedR_unique tr tr'

theorem tryR_noHead {env : FrontEnv} {scope : List Local} {init : CTree} {tr : Tried} {hd : LetHead}
    (t : TryR env scope init tr) (l : LetHeadR env scope init hd) : False := by
  cases l with
  | callPath pe _ _ p1 p13 _ =>
    cases t with
    | call p c =>
      cases peel_unique pe p
      cases c with
      | mk f _ _ _ _ _ _ =>
        obtain ⟨_, _, _, f3, _⟩ := f
        prod_clash
    | «local» p l =>
      cases peel_unique pe p
      cases l with
      | mk t _ _ _ _ => prod_clash

theorem tryR_noEff {env : FrontEnv} {scope : List Local} {E : Option Ty} {init : CTree} {tr : Tried} {x : MEff}
    (t : TryR env scope init tr) (k : EffR env scope E init x) : False := by
  cases t with
  | call p c => cases c with
    | mk f _ _ _ _ _ _ => exact peel_noEffTry p (.inl f) k
  | «local» p l => cases l with
    | mk t _ _ _ _ => exact peel_noEffTry p (.inr t) k

theorem untypedR_unique {env : FrontEnv} {scope : List Local} {init : CTree} {t t' : Ty} {a b : LetHead}
    (nd : IdsFresh scope) (vn : VariantsNodup env.decls) (h₁ : UntypedR env scope init t a)
    (h₂ : UntypedR env scope init t' b) : t = t' ∧ a = b := by
  cases h₁ with
  | «try» k => cases h₂ with
    | «try» k' =>
      cases tryR_unique nd vn k k'
      exact ⟨rfl, rfl⟩
    | eval e _ _ => exact (tryR_noEff k e).elim
  | eval e _ ty => cases h₂ with
    | «try» k' => exact (tryR_noEff k' e).elim
    | eval e' _ ty' =>
      cases effR_unique e nd vn e'
      cases effTy_unique ty ty'
      exact ⟨rfl, rfl⟩

/-! ## Statements -/

section
variable {env : FrontEnv} {scope : List Local}

theorem letInitR_unique {ty : Ty} {init : CTree} {a b : LetHead} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : LetInitR env scope ty init a) (h₂ : LetInitR env scope ty init b) :
    a = b := by
  cases h₁ with
  | head l => cases h₂ with
    | head l' => exact letHeadR_unique l l'
    | «try» t => exact (tryR_noHead t l).elim
    | eval k _ => exact (letHead_noEff l k).elim
  | «try» t => cases h₂ with
    | head l' => exact (tryR_noHead t l').elim
    | «try» t' => rw [tryR_unique nd vn t t']
    | eval k _ => exact (tryR_noEff t k).elim
  | eval k e => cases h₂ with
    | head l' => exact (letHead_noEff l' k).elim
    | «try» t' => exact (tryR_noEff t' k).elim
    | eval k' e' =>
      rw [effR_unique k nd vn k', e'] at e
      exact (Option.some.inj e).symm

theorem returnR_unique {e : CTree} {a b : MStmt} (nd : IdsFresh scope) (vn : VariantsNodup env.decls)
    (h₁ : ReturnR env scope e a) (h₂ : ReturnR env scope e b) : a = b := by
  cases h₁ with
  | slice hr hl hh => cases h₂ with
    | slice hr' hl' hh' =>
      rw [hr] at hr'
      cases hr'
      rw [hl] at hl'
      cases hl'
      cases letHeadR_unique hh hh'
      rfl
    | eval k => exact (letHead_noEff hh k).elim
  | eval k => cases h₂ with
    | slice _ _ hh => exact (letHead_noEff hh k).elim
    | eval k' => rw [effR_unique k nd vn k']

theorem ifR_unique {c : CTree} {x y a b : MStmt} (nd : IdsFresh scope) (vn : VariantsNodup env.decls)
    (h₁ : IfR env scope c x y a) (h₂ : IfR env scope c x y b) : a = b := by
  cases h₁ with
  | eval k => cases h₂ with
    | eval k' => rw [effR_unique k nd vn k']

theorem whileR_unique {c : CTree} {body a b : MStmt} (nd : IdsFresh scope) (vn : VariantsNodup env.decls)
    (h₁ : WhileR env scope c body a) (h₂ : WhileR env scope c body b) : a = b := by
  cases h₁ with
  | eval k => cases h₂ with
    | eval k' => rw [effR_unique k nd vn k']

theorem setR_unique {l : Local} {v : Nat} {value : CTree} {a b : MStmt} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : SetR env scope l v value a) (h₂ : SetR env scope l v value b) : a = b := by
  cases h₁ with
  | «try» t e => cases h₂ with
    | «try» t' e' =>
      cases tryR_unique nd vn t t'
      rw [e'] at e
      exact (Option.some.inj e).symm
    | eval k _ => exact (tryR_noEff t k).elim
  | eval k e => cases h₂ with
    | «try» t _ => exact (tryR_noEff t k).elim
    | eval k' e' =>
      rw [effR_unique k nd vn k', e'] at e
      exact (Option.some.inj e).symm

theorem assignTargetR_unique {target : CTree} {v : Nat} {value : CTree} {a b : MStmt} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : AssignTargetR env scope target v value a)
    (h₂ : AssignTargetR env scope target v value b) : a = b := by
  cases h₁ with
  | «local» _ lo s => cases h₂ with
    | «local» _ lo' s' =>
      cases localOf_unique lo lo'
      exact setR_unique nd vn s s'
    | _ => prod_clash
  | fieldEval _ _ _ lo fi ft k => cases h₂ with
    | fieldEval _ _ _ lo' fi' ft' k' =>
      cases localOf_unique lo lo'
      cases fieldIndex_unique fi fi'
      cases fieldTyAt_unique ft ft'
      rw [effR_unique k nd vn k']
    | _ => prod_clash
  | indexEval _ _ lo ki kv => cases h₂ with
    | indexEval _ _ lo' ki' kv' =>
      cases localOf_unique lo lo'
      rw [effR_unique ki nd vn ki', effR_unique kv nd vn kv']
    | _ => prod_clash

theorem compoundR_unique {target : CTree} {p : Nat} {value : CTree} {a b : MStmt} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : CompoundR env scope target p value a)
    (h₂ : CompoundR env scope target p value b) : a = b := by
  cases h₁ with
  | localEval _ lo k c s => cases h₂ with
    | localEval _ lo' k' c' s' =>
      cases localOf_unique lo lo'
      rw [effR_unique k nd vn k', c'] at c
      cases c
      rw [s'] at s
      exact (Option.some.inj s).symm
    | _ => prod_clash
  | fieldEval _ _ _ lo fi ft k c => cases h₂ with
    | fieldEval _ _ _ lo' fi' ft' k' c' =>
      cases localOf_unique lo lo'
      cases fieldIndex_unique fi fi'
      cases fieldTyAt_unique ft ft'
      rw [effR_unique k nd vn k', c'] at c
      cases c
      rfl
    | _ => prod_clash

theorem callStmtR_unique {pf : CTree} {a b : MStmt} (pp : nodeProd pf = pPostfix) (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : CallStmtR env scope pf a) (h₂ : CallStmtR env scope pf b) : a = b := by
  cases h₁ with
  | free cf ps ar sh => cases h₂ with
    | free _ _ ar' sh' =>
      cases argsOfR_unique ar ar'
      rw [shiftOf_unique sh sh']
    | assert _ ps' _ _ => exact absurd (pathSpellings_unique ps ps') (by decide)
    | discard _ k => exact (peel_noEff (.here pp) cf ps (by simp [builtinPaths]) (by decide) k).elim
    | «try» c => cases c with
      | mk f _ _ _ _ _ _ =>
        obtain ⟨_, _, _, f3, _⟩ := f
        obtain ⟨_, _, _, c3⟩ := cf
        prod_clash
  | assert cf ps it k => cases h₂ with
    | free _ ps' _ _ => exact absurd (pathSpellings_unique ps ps') (by decide)
    | assert _ _ it' k' =>
      cases items_unique it it'
      rw [effR_unique k nd vn k']
    | discard _ k' => exact (peel_noEff (.here pp) cf ps (by simp [builtinPaths]) (by decide) k').elim
    | «try» c => cases c with
      | mk f _ _ _ _ _ _ =>
        obtain ⟨_, _, _, f3, _⟩ := f
        obtain ⟨_, _, _, c3⟩ := cf
        prod_clash
  | discard d k => cases h₂ with
    | free cf ps _ _ => exact (peel_noEff (.here pp) cf ps (by simp [builtinPaths]) (by decide) k).elim
    | assert cf ps _ _ => exact (peel_noEff (.here pp) cf ps (by simp [builtinPaths]) (by decide) k).elim
    | discard _ k' => rw [effR_unique k nd vn k']
    | «try» c => cases c with
      | mk f _ _ _ _ _ _ =>
        obtain ⟨_, _, f1, f3, _⟩ := f
        rcases d with ⟨_, _, _, d3⟩ | ⟨_, d1, _⟩ <;> prod_clash
  | «try» c => cases h₂ with
    | free cf _ _ _ => cases c with
      | mk f _ _ _ _ _ _ =>
        obtain ⟨_, _, _, f3, _⟩ := f
        obtain ⟨_, _, _, c3⟩ := cf
        prod_clash
    | assert cf _ _ _ => cases c with
      | mk f _ _ _ _ _ _ =>
        obtain ⟨_, _, _, f3, _⟩ := f
        obtain ⟨_, _, _, c3⟩ := cf
        prod_clash
    | discard d _ => cases c with
      | mk f _ _ _ _ _ _ =>
        obtain ⟨_, _, f1, f3, _⟩ := f
        rcases d with ⟨_, _, _, d3⟩ | ⟨_, d1, _⟩ <;> prod_clash
    | «try» c' => rw [tryCallR_unique nd vn c c']

theorem assignR_unique {e : CTree} {a b : MStmt} (nd : IdsFresh scope) (vn : VariantsNodup env.decls)
    (h₁ : AssignR env scope e a) (h₂ : AssignR env scope e b) : a = b := by
  cases h₁ with
  | set _ _ ps pl t => cases h₂ with
    | set _ _ _ pl' t' =>
      cases peel_unique pl pl'
      exact assignTargetR_unique nd vn t t'
    | compound _ _ _ ns _ _ => exact absurd ps ns
    | call _ _ pe _ _ _ => prod_clash
  | compound _ _ kn ns pl c => cases h₂ with
    | set _ _ ps _ _ => exact absurd ps ns
    | compound _ _ _ _ pl' c' =>
      cases peel_unique pl pl'
      exact compoundR_unique nd vn c c'
    | call _ _ _ kn' _ _ => exact absurd kn' kn
  | call _ _ pe kn pl c => cases h₂ with
    | set _ _ ps _ _ => prod_clash
    | compound _ _ kn' _ _ _ => exact absurd kn kn'
    | call _ _ _ _ pl' c' =>
      cases peel_unique pl pl'
      exact callStmtR_unique (peel_postfix pl) nd vn c c'

/-! ## Match statements -/

theorem callStmtR_noEnd {pf : CTree} {a : MStmt} (c : CallStmtR env scope pf a) (pe : nodeProd (kid pf 1) = pPostfixEnd) :
    False := by
  cases c with
  | free f _ _ _ => obtain ⟨_, _, f3, _⟩ := f; prod_clash
  | assert f _ _ _ => obtain ⟨_, _, f3, _⟩ := f; prod_clash
  | discard f _ =>
    rcases f with ⟨_, _, f3, _⟩ | ⟨_, f2, _⟩
    · prod_clash
    · prod_clash
  | «try» t => cases t with
    | mk f _ _ _ _ _ _ => obtain ⟨_, _, f3, _⟩ := f; prod_clash

theorem assignR_noMatch {e m : CTree} {a : MStmt} (h : AssignR env scope e a) (mp : MatchPrimary e m) : False := by
  cases mp with
  | mk _ _ pn kn pl _ pe => cases h with
    | set _ _ ps _ _ => prod_clash
    | compound _ _ kn' _ _ _ => exact kn' kn
    | call _ _ _ _ pl' c =>
      cases peel_unique pl pl'
      exact callStmtR_noEnd c pe

theorem matchPrimary_unique {e a b : CTree} (h₁ : MatchPrimary e a) (h₂ : MatchPrimary e b) : a = b := by
  cases h₁ with
  | mk _ _ _ _ pl _ _ => cases h₂ with
    | mk _ _ _ _ pl' _ _ => cases peel_unique pl pl'; rfl

theorem matchStmtHead_parts {scope : List Local} {id closer : Nat} {x : MEff} {ety : Ty} {t : TypeDecl}
    {vs : List VariantTy} {rt : Ty} {h : MatchStmt} (hh : matchStmtHead scope id closer x ety t vs rt = some h) :
    h.owner = t ∧ h.variants = vs := by
  unfold matchStmtHead at hh
  cases hl : effLocal x with
  | some l =>
    rw [hl] at hh
    simp only [matchStmtIf] at hh
    split at hh
    · simp only [Option.some.injEq] at hh; subst hh; exact ⟨rfl, rfl⟩
    · cases hh
  | none =>
    rw [hl] at hh
    simp only [matchStmtIf] at hh
    split at hh
    · simp only [Option.some.injEq] at hh; subst hh; exact ⟨rfl, rfl⟩
    · cases hh

theorem matchStmtR_unique {m : CTree} {a b : MatchStmt} (nd : IdsFresh scope) (vn : VariantsNodup env.decls)
    (h₁ : MatchStmtR env scope m a) (h₂ : MatchStmtR env scope m b) : a = b := by
  cases h₁ with
  | mk k et hn ht _ pt hr hh => cases h₂ with
    | mk k' et' hn' ht' _ pt' hr' hh' =>
      have e := effR_unique k nd vn k'
      subst e
      have e := effTy_unique et et'
      subst e
      rw [hn] at hn'
      cases hn'
      rw [ht] at ht'
      cases ht'
      have e := payloadTys_unique pt pt'
      subst e
      rw [hr] at hr'
      cases hr'
      rw [hh] at hh'
      exact Option.some.inj hh'

theorem armBindR_unique {owner : TypeDecl} {v : VariantTy} {arm : CTree} {a b : Bound}
    (h₁ : ArmBindR env scope owner v arm a) (h₂ : ArmBindR env scope owner v arm b) : a = b := by
  cases h₁ with
  | plain _ _ _ pl => cases h₂ with
    | plain _ _ _ _ => rfl
    | payload _ _ _ pl' _ _ => exact absurd pl pl'
  | payload _ _ _ pl it br => cases h₂ with
    | plain _ _ _ pl' => exact absurd pl' pl
    | payload _ _ _ _ it' br' =>
      cases items_unique it it'
      exact bindersR_unique br br'

theorem armBindR_names {owner : TypeDecl} {v : VariantTy} {arm : CTree} {b : Bound}
    (h : ArmBindR env scope owner v arm b) : ArmNames owner arm v.name := by
  cases h with
  | plain _ ps an _ => exact ⟨_, ps, an⟩
  | payload _ ps an _ _ _ => exact ⟨_, ps, an⟩

theorem armBindR_fresh {owner : TypeDecl} {v : VariantTy} {arm : CTree} {b : Bound}
    (h : ArmBindR env scope owner v arm b) (nd : IdsFresh scope) : IdsFresh b.scope := by
  cases h with
  | plain _ _ _ _ => exact nd
  | payload _ _ _ _ _ br => exact bindersR_fresh br nd

theorem armBlockR_unique {arm a b : CTree} (h₁ : ArmBlockR arm a) (h₂ : ArmBlockR arm b) : a = b := by
  cases h₁ with
  | mk pl _ _ => cases h₂ with
    | mk pl' _ _ => cases peel_unique pl pl'; rfl

theorem armsStmtR_named {h : MatchStmt} : ∀ {os : List CTree} {k : Nat} {vs : List VariantTy} {c : MStmt},
    ArmsStmtR env scope h k vs os c → ListRel (ArmNames h.owner) os (vs.map (·.name))
  | [], _, _, _, r => by cases r; exact .nil
  | _ :: _, _, _, _, r => by
    cases r with
    | cons ab _ _ rest _ => exact .cons (armBindR_names ab) (armsStmtR_named rest)

theorem letArmsR_named {h : MatchStmt} {x : Local} {rest : MStmt} : ∀ {os : List CTree} {k : Nat}
    {vs : List VariantTy} {c : MStmt}, LetArmsR env scope h x rest k vs os c → ListRel (ArmNames h.owner) os (vs.map (·.name))
  | [], _, _, _, r => by cases r; exact .nil
  | _ :: _, _, _, _, r => by
    cases r with
    | block ab _ _ rest _ => exact .cons (armBindR_names ab) (letArmsR_named rest)
    | value ab _ _ rest _ => exact .cons (armBindR_names ab) (letArmsR_named rest)

theorem matchInit_unique {init a b : CTree} (h₁ : MatchInit init a) (h₂ : MatchInit init b) : a = b := by
  cases h₁ with
  | mk pl _ _ => cases h₂ with
    | mk pl' _ _ => cases peel_unique pl pl'; rfl

end

/-! ## Block arms: no expression reads one -/

theorem exprR_noPrim {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr}
    (p : nodeProd c = pMatchExpr ∨ nodeProd c = pArmBlock) (h : ExprR env scope c e) : False := by
  rcases p with p | p <;> cases h <;> expr_clash

theorem peel_noExprPrim : ∀ {env : FrontEnv} {scope : List Local} {c pf : CTree} {e : SrcExpr},
    Peel c pf → (nodeProd (kid pf 0) = pMatchExpr ∨ nodeProd (kid pf 0) = pArmBlock) →
    nodeProd (kid pf 1) = pPostfixEnd → ExprR env scope c e → False
  | _, _, _, _, _, .wrap _ p, pc, pe, h => by
    cases h with
    | wrap _ r => exact peel_noExprPrim p pc pe r
    | _ => expr_clash
  | _, _, _, _, _, .bare _ _ p, pc, pe, h => by
    cases h with
    | assign _ _ r => exact peel_noExprPrim p pc pe r
    | level _ r _ => exact peel_noExprPrim p pc pe r
    | cast _ r _ => exact peel_noExprPrim p pc pe r
    | _ => expr_clash
  | _, _, _, _, _, .here _, pc, pe, h => by
    cases h with
    | «postfix» _ _ r => exact exprR_noPrim pc r
    | _ => expr_clash

theorem effR_noArmBlock {env : FrontEnv} {scope : List Local} {E : Option Ty} {c : CTree} {x : MEff}
    (p : nodeProd c = pArmBlock) (h : EffR env scope E c x) : False := by
  cases h with
  | pure r => exact exprR_noPrim (.inr p) r
  | _ => eff_clash

theorem peel_noEffArmBlock : ∀ {env : FrontEnv} {scope : List Local} {E : Option Ty} {c pf : CTree} {x : MEff},
    Peel c pf → nodeProd (kid pf 0) = pArmBlock → nodeProd (kid pf 1) = pPostfixEnd → EffR env scope E c x → False
  | _, _, _, _, _, _, .wrap w p, pc, pe, h => by
    cases h with
    | pure r => exact peel_noExprPrim (.wrap w p) (.inr pc) pe r
    | wrap _ k => exact peel_noEffArmBlock p pc pe k
    | _ => eff_clash
  | _, _, _, _, _, _, .bare w kn p, pc, pe, h => by
    cases h with
    | pure r => exact peel_noExprPrim (.bare w kn p) (.inr pc) pe r
    | bare _ _ k => exact peel_noEffArmBlock p pc pe k
    | level _ kn' _ _ => exact kn' kn
    | cast _ kn' _ _ => exact kn' kn
    | _ => eff_clash
  | _, _, _, _, _, _, .here pp, pc, pe, h => by
    cases h with
    | pure r => exact peel_noExprPrim (.here pp) (.inr pc) pe r
    | primary _ _ k => exact effR_noArmBlock pc k
    | _ => eff_clash

/-- A match's value read effectfully is read from its primary. -/
theorem peel_effPrim : ∀ {env : FrontEnv} {scope : List Local} {E : Option Ty} {c pf : CTree} {x : MEff},
    Peel c pf → nodeProd (kid pf 0) = pMatchExpr → nodeProd (kid pf 1) = pPostfixEnd → EffR env scope E c x →
    ∃ E' x', EffR env scope E' (kid pf 0) x'
  | _, _, _, _, _, _, .wrap w p, pc, pe, h => by
    cases h with
    | pure r => exact (peel_noExprPrim (.wrap w p) (.inl pc) pe r).elim
    | wrap _ k => exact peel_effPrim p pc pe k
    | _ => eff_clash
  | _, _, _, _, _, _, .bare w kn p, pc, pe, h => by
    cases h with
    | pure r => exact (peel_noExprPrim (.bare w kn p) (.inl pc) pe r).elim
    | bare _ _ k => exact peel_effPrim p pc pe k
    | level _ kn' _ _ => exact (kn' kn).elim
    | cast _ kn' _ _ => exact (kn' kn).elim
    | _ => eff_clash
  | _, _, _, _, _, _, .here pp, pc, pe, h => by
    cases h with
    | pure r => exact (peel_noExprPrim (.here pp) (.inl pc) pe r).elim
    | primary _ _ k => exact ⟨_, _, k⟩
    | _ => eff_clash

theorem effArmsR_mem {env : FrontEnv} : ∀ {scope : List Local} {E : Option Ty} {owner : TypeDecl}
    {vs : List VariantTy} {os : List CTree} {eas : List EffArm}, EffArmsR env scope E owner vs os eas →
    ∀ {a : CTree}, a ∈ os → ∃ v ea, EffArmR env scope E owner v a ea
  | _, _, _, _, _, _, .nil, _, m => by cases m
  | _, _, _, _, _, _, .cons r rest, _, m => by
    rcases List.mem_cons.1 m with rfl | m
    · exact ⟨_, _, r⟩
    · exact effArmsR_mem rest m

theorem armBlockR_noEff {env : FrontEnv} {scope : List Local} {E : Option Ty} {a list : CTree} {x : MEff}
    (ab : ArmBlockR a list) (h : EffR env scope E (kid a 2) x) : False := by
  cases ab with
  | mk pl pc pe => exact peel_noEffArmBlock pl pc pe h

/-- No match with a block arm has an effectful reading. -/
theorem matchR_noBlock {env : FrontEnv} {scope : List Local} {E : Option Ty} {m a list : CTree} {x : MEff}
    {arms : List CTree} (vn : VariantsNodup env.decls) (it : Items (kid m 5) arms) (ma : a ∈ arms)
    (ab : ArmBlockR a list) (h : EffR env scope E m x) (pm : nodeProd m = pMatchExpr) : False := by
  cases h with
  | pure r => exact exprR_noPrim (.inl pm) r
  | «match» _ _ _ _ td en _ it' len sub ar _ =>
    cases items_unique it it'
    have nd := listRel_nodup armNames_fun (effArmsR_named ar) ((vn _ _ td en).sublist (zipVariants_names _ _))
    have all := by
      classical
      exact subset_of_nodup_length nd sub (by rw [listRel_length (effArmsR_named ar), List.length_map, len])
    obtain ⟨v, ea, r⟩ := effArmsR_mem ar (all ma)
    cases r with
    | unit _ _ _ _ k _ _ => exact armBlockR_noEff ab k
    | payload _ _ _ _ _ _ k _ _ => exact armBlockR_noEff ab k
  | _ => eff_clash

theorem letInitR_noArmBlock {env : FrontEnv} {scope : List Local} {ty : Ty} {a list : CTree} {hd : LetHead}
    (ab : ArmBlockR a list) (h : LetInitR env scope ty (kid a 2) hd) : False := by
  cases ab with
  | mk pl pc pe => cases h with
    | head l => cases l with
      | callPath pe' p0 _ _ _ _ => cases peel_unique pe' pl; prod_clash
    | «try» t => cases t with
      | call p c =>
        cases peel_unique p pl
        cases c with
        | mk f _ _ _ _ _ _ => obtain ⟨f0, _⟩ := f; prod_clash
      | «local» p l =>
        cases peel_unique p pl
        cases l with
        | mk t _ _ _ _ => prod_clash
    | eval k _ => exact peel_noEffArmBlock pl pc pe k

/-- A let of a match with a block arm has no other reading. -/
theorem letInitR_noBlockMatch {env : FrontEnv} {scope : List Local} {ty : Ty} {init m a list : CTree}
    {arms : List CTree} {hd : LetHead} (vn : VariantsNodup env.decls) (mi : MatchInit init m)
    (it : Items (kid m 5) arms) (ma : a ∈ arms) (ab : ArmBlockR a list) (h : LetInitR env scope ty init hd) : False := by
  cases mi with
  | mk pl pc pe => cases h with
    | head l => cases l with
      | callPath pe' p0 _ _ _ _ => cases peel_unique pe' pl; prod_clash
    | «try» t => cases t with
      | call p c =>
        cases peel_unique p pl
        cases c with
        | mk f _ _ _ _ _ _ => obtain ⟨f0, _⟩ := f; prod_clash
      | «local» p l =>
        cases peel_unique p pl
        cases l with
        | mk t _ _ _ _ => prod_clash
    | eval k _ =>
      obtain ⟨_, _, k'⟩ := peel_effPrim pl pc pe k
      exact matchR_noBlock vn it ma ab k' pc


section
variable {env : FrontEnv}

mutual
theorem blockR_unique : ∀ {scope : List Local} {list : CTree} {a : MStmt}, BlockR env scope list a →
    IdsFresh scope → VariantsNodup env.decls → ∀ {b : MStmt}, BlockR env scope list b → a = b
  | _, _, _, .mk it ss, nd, vn, _, h₂ => by
    have ih := fun {y} k' => stmtsR_unique ss nd vn (b := y) k'
    cases h₂ with
    | mk it' ss' =>
      cases items_unique it it'
      exact ih ss'
termination_by structural _ _ _ h _ _ _ _ => h

theorem stmtsR_unique : ∀ {scope : List Local} {items : List CTree} {a : MStmt}, StmtsR env scope items a →
    IdsFresh scope → VariantsNodup env.decls → ∀ {b : MStmt}, StmtsR env scope items b → a = b
  | _, _, _, .nil, _, _, _, h₂ => by cases h₂; rfl
  | _, _, _, .let ps lt _ _ fr ty li body ls, nd, vn, _, h₂ => by
    have ih := fun {y} k' => stmtsR_unique body (idsFresh_cons nd fr) vn (b := y) k'
    cases h₂ with
    | «let» _ _ _ _ _ ty' li' body' ls' =>
      cases tyR_unique ty ty'
      cases letInitR_unique nd vn li li'
      cases ih body'
      rw [ls'] at ls
      exact (Option.some.inj ls).symm
    | letUntyped _ lt' _ _ _ _ _ _ => prod_clash
    | letMatch _ _ _ _ _ _ bm _ _ _ _ _ _ =>
      obtain ⟨_, _, _, _, mi, it, ma, ab⟩ := bm
      exact (letInitR_noBlockMatch vn mi it ma ab li).elim
    | last np _ => exact absurd ps np
    | seq np _ _ => exact absurd ps np
  | _, _, _, .letMatch ps lt _ _ fr ty bm mi mr mo body la mv, nd, vn, _, h₂ => by
    have ih := fun {y} k' => stmtsR_unique body (idsFresh_cons nd fr) vn (b := y) k'
    cases h₂ with
    | «let» _ _ _ _ _ _ li' _ _ =>
      obtain ⟨_, _, _, _, mi', it, ma, ab⟩ := bm
      exact (letInitR_noBlockMatch vn mi' it ma ab li').elim
    | letUntyped _ lt' _ _ _ _ _ _ => prod_clash
    | letMatch _ _ _ _ _ ty' _ mi' mr' mo' body' la' mv' =>
      cases tyR_unique ty ty'
      have e := matchInit_unique mi mi'
      subst e
      have e := matchStmtR_unique nd vn mr mr'
      subst e
      have e := ih body'
      subst e
      obtain ⟨arms, it, len, sub⟩ := mo
      obtain ⟨arms', it', _, sub'⟩ := mo'
      have e := items_unique it it'
      subst e
      cases mr with
      | mk _ _ _ td en _ _ hh =>
        obtain ⟨ho, hv⟩ := matchStmtHead_parts hh
        have eo := by
          classical
          exact arms_unique armNames_fun
            ((vn _ _ td en).sublist (by rw [hv, zipVariants_eq, ← ho]; exact zipVariants_names _ _))
            (by rw [List.length_map]; exact len) (letArmsR_named la) (letArmsR_named la') sub sub'
        subst eo
        have e := letArmsR_unique la nd vn la'
        subst e
        rw [mv'] at mv
        exact (Option.some.inj mv).symm
    | last np _ => exact absurd ps np
    | seq np _ _ => exact absurd ps np
  | _, _, _, .letUntyped ps lt _ _ fr un body ls, nd, vn, _, h₂ => by
    have ih := fun {y} k' => stmtsR_unique body (idsFresh_cons nd fr) vn (b := y) k'
    cases h₂ with
    | «let» _ lt' _ _ _ _ _ _ _ => prod_clash
    | letUntyped _ _ _ _ _ un' body' ls' =>
      obtain ⟨rfl, rfl⟩ := untypedR_unique nd vn un un'
      cases ih body'
      rw [ls'] at ls
      exact (Option.some.inj ls).symm
    | letMatch _ lt' _ _ _ _ _ _ _ _ _ _ _ => prod_clash
    | last np _ => exact absurd ps np
    | seq np _ _ => exact absurd ps np
  | _, _, _, .last np s, nd, vn, _, h₂ => by
    have ih := fun {y} k' => stmtR_unique s nd vn (b := y) k'
    cases h₂ with
    | «let» ps _ _ _ _ _ _ _ _ => exact absurd ps np
    | letUntyped ps _ _ _ _ _ _ _ => exact absurd ps np
    | letMatch ps _ _ _ _ _ _ _ _ _ _ _ _ => exact absurd ps np
    | last _ s' => exact ih s'
  | _, _, _, .seq np s rest, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => stmtR_unique s nd vn (b := y) k'
    have ih2 := fun {y} k' => stmtsR_unique rest nd vn (b := y) k'
    cases h₂ with
    | «let» ps _ _ _ _ _ _ _ _ => exact absurd ps np
    | letUntyped ps _ _ _ _ _ _ _ => exact absurd ps np
    | letMatch ps _ _ _ _ _ _ _ _ _ _ _ _ => exact absurd ps np
    | seq _ s' rest' => rw [ih1 s', ih2 rest']
termination_by structural _ _ _ h _ _ _ _ => h

theorem armsStmtR_unique : ∀ {scope : List Local} {h : MatchStmt} {k : Nat} {vs : List VariantTy} {os : List CTree}
    {a : MStmt}, ArmsStmtR env scope h k vs os a → IdsFresh scope → VariantsNodup env.decls →
    ∀ {b : MStmt}, ArmsStmtR env scope h k vs os b → a = b
  | _, _, _, _, _, _, .nil, _, _, _, h₂ => by cases h₂; rfl
  | _, _, _, _, _, _, .cons ab al bb rest hb, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => blockR_unique bb (armBindR_fresh ab nd) vn (b := y) k'
    have ih2 := fun {y} k' => armsStmtR_unique rest nd vn (b := y) k'
    cases h₂ with
    | cons ab' al' bb' rest' hb' =>
      have e := armBindR_unique ab ab'
      subst e
      have e := armBlockR_unique al al'
      subst e
      have e := ih1 bb'
      subst e
      have e := ih2 rest'
      subst e
      rw [hb'] at hb
      exact (Option.some.inj hb).symm
termination_by structural _ _ _ _ _ _ h _ _ _ _ => h

theorem letArmsR_unique : ∀ {scope : List Local} {h : MatchStmt} {x : Local} {rest : MStmt} {k : Nat}
    {vs : List VariantTy} {os : List CTree} {a : MStmt}, LetArmsR env scope h x rest k vs os a → IdsFresh scope →
    VariantsNodup env.decls → ∀ {b : MStmt}, LetArmsR env scope h x rest k vs os b → a = b
  | _, _, _, _, _, _, _, _, .nil, _, _, _, h₂ => by cases h₂; rfl
  | _, _, _, _, _, _, _, _, .block ab al bb rest hb, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => blockR_unique bb (armBindR_fresh ab nd) vn (b := y) k'
    have ih2 := fun {y} k' => letArmsR_unique rest nd vn (b := y) k'
    cases h₂ with
    | block ab' al' bb' rest' hb' =>
      have e := armBindR_unique ab ab'
      subst e
      have e := armBlockR_unique al al'
      subst e
      have e := ih1 bb'
      subst e
      have e := ih2 rest'
      subst e
      rw [hb'] at hb
      exact (Option.some.inj hb).symm
    | value _ li' _ _ _ => exact (letInitR_noArmBlock al li').elim
  | _, _, _, _, _, _, _, _, .value ab li ls rest hb, nd, vn, _, h₂ => by
    have ih2 := fun {y} k' => letArmsR_unique rest nd vn (b := y) k'
    cases h₂ with
    | block _ al' _ _ _ => exact (letInitR_noArmBlock al' li).elim
    | value ab' li' ls' rest' hb' =>
      have e := armBindR_unique ab ab'
      subst e
      have e := letInitR_unique (armBindR_fresh ab nd) vn li li'
      subst e
      rw [ls'] at ls
      cases ls
      have e := ih2 rest'
      subst e
      rw [hb'] at hb
      exact (Option.some.inj hb).symm
termination_by structural _ _ _ _ _ _ _ _ h _ _ _ _ => h

theorem stmtR_unique : ∀ {scope : List Local} {s : CTree} {a : MStmt}, StmtR env scope s a →
    IdsFresh scope → VariantsNodup env.decls → ∀ {b : MStmt}, StmtR env scope s b → a = b
  | _, _, _, .ret _ _ r, nd, vn, _, h₂ => by
    cases h₂ with
    | ret _ _ r' => exact returnR_unique nd vn r r'
    | _ => prod_clash
  | _, _, _, .retUnit _ _, _, _, _, h₂ => by
    cases h₂ with
    | retUnit _ _ => rfl
    | _ => prod_clash
  | _, _, _, .brk _, _, _, _, h₂ => by
    cases h₂ with
    | brk _ => rfl
    | _ => prod_clash
  | _, _, _, .cont _, _, _, _, h₂ => by
    cases h₂ with
    | cont _ => rfl
    | _ => prod_clash
  | _, _, _, .ifElse _ _ ba bb i, nd, vn, _, h₂ => by
    have iha := fun {y} k' => blockR_unique ba nd vn (b := y) k'
    have ihb := fun {y} k' => blockR_unique bb nd vn (b := y) k'
    cases h₂ with
    | ifElse _ _ ba' bb' i' =>
      cases iha ba'
      cases ihb bb'
      exact ifR_unique nd vn i i'
    | _ => prod_clash
  | _, _, _, .ifOnly _ _ ba i, nd, vn, _, h₂ => by
    have iha := fun {y} k' => blockR_unique ba nd vn (b := y) k'
    cases h₂ with
    | ifOnly _ _ ba' i' =>
      cases iha ba'
      exact ifR_unique nd vn i i'
    | _ => prod_clash
  | _, _, _, .while _ bb w, nd, vn, _, h₂ => by
    have ih := fun {y} k' => blockR_unique bb nd vn (b := y) k'
    cases h₂ with
    | «while» _ bb' w' =>
      cases ih bb'
      exact whileR_unique nd vn w w'
    | _ => prod_clash
  | _, _, _, .assign _ a, nd, vn, _, h₂ => by
    cases h₂ with
    | assign _ a' => exact assignR_unique nd vn a a'
    | «match» _ mp _ _ _ _ => exact (assignR_noMatch a mp).elim
    | _ => prod_clash
  | _, _, _, .match _ mp mr mo ar mv, nd, vn, _, h₂ => by
    have ih := fun {y} k' => armsStmtR_unique ar nd vn (b := y) k'
    cases h₂ with
    | «match» _ mp' mr' mo' ar' mv' =>
      have e := matchPrimary_unique mp mp'
      subst e
      have e := matchStmtR_unique nd vn mr mr'
      subst e
      obtain ⟨arms, it, len, sub⟩ := mo
      obtain ⟨arms', it', _, sub'⟩ := mo'
      have e := items_unique it it'
      subst e
      cases mr with
      | mk _ _ _ td en _ _ hh =>
        obtain ⟨ho, hv⟩ := matchStmtHead_parts hh
        have eo := by
          classical
          exact arms_unique armNames_fun
            ((vn _ _ td en).sublist (by rw [hv, zipVariants_eq, ← ho]; exact zipVariants_names _ _))
            (by rw [List.length_map]; exact len) (armsStmtR_named ar) (armsStmtR_named ar') sub sub'
        subst eo
        have e := ih ar'
        subst e
        rw [mv'] at mv
        exact (Option.some.inj mv).symm
    | assign _ a' => exact (assignR_noMatch a' mp).elim
    | _ => prod_clash
  | _, _, _, .forRange _ _ _ _ _ _ _ _ _ _ fx ln il bb fr, nd, vn, _, h₂ => by
    have ih := fun {y} k' => blockR_unique bb (idsFresh_cons nd fx) vn (b := y) k'
    cases h₂ with
    | forRange _ _ _ _ _ _ _ _ _ _ _ ln' il' bb' fr' =>
      obtain ⟨_, f⟩ := ln
      obtain ⟨_, f'⟩ := ln'
      cases (firstWith_unique f f').2
      cases intLiteral_unique il il'
      cases ih bb'
      rw [fr'] at fr
      exact (Option.some.inj fr).symm
    | _ => prod_clash
  | _, _, _, .block _ bb, nd, vn, _, h₂ => by
    have ih := fun {y} k' => blockR_unique bb nd vn (b := y) k'
    cases h₂ with
    | block _ bb' => exact ih bb'
    | _ => prod_clash
termination_by structural _ _ _ h _ _ _ _ => h
end

end

end Lanius.Mini.Reading
