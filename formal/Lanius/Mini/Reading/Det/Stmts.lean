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

/-! ## Statements -/

section
variable {env : FrontEnv} {scope : List Local}

theorem letInitR_unique {ty : Ty} {init : CTree} {a b : LetHead} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : LetInitR env scope ty init a) (h₂ : LetInitR env scope ty init b) :
    a = b := by
  cases h₁ with
  | head l => cases h₂ with
    | head l' => exact letHeadR_unique l l'
    | eval k _ => exact (letHead_noEff l k).elim
  | eval k e => cases h₂ with
    | head l' => exact (letHead_noEff l' k).elim
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

theorem setR_unique {l : Local} {value : CTree} {a b : MStmt} (nd : IdsFresh scope) (vn : VariantsNodup env.decls)
    (h₁ : SetR env scope l value a) (h₂ : SetR env scope l value b) : a = b := by
  cases h₁ with
  | eval k e => cases h₂ with
    | eval k' e' =>
      rw [effR_unique k nd vn k', e'] at e
      exact (Option.some.inj e).symm

theorem assignTargetR_unique {target value : CTree} {a b : MStmt} (nd : IdsFresh scope)
    (vn : VariantsNodup env.decls) (h₁ : AssignTargetR env scope target value a)
    (h₂ : AssignTargetR env scope target value b) : a = b := by
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
  | assert cf ps it k => cases h₂ with
    | free _ ps' _ _ => exact absurd (pathSpellings_unique ps ps') (by decide)
    | assert _ _ it' k' =>
      cases items_unique it it'
      rw [effR_unique k nd vn k']
    | discard _ k' => exact (peel_noEff (.here pp) cf ps (by simp [builtinPaths]) (by decide) k').elim
  | discard _ k => cases h₂ with
    | free cf ps _ _ => exact (peel_noEff (.here pp) cf ps (by simp [builtinPaths]) (by decide) k).elim
    | assert cf ps _ _ => exact (peel_noEff (.here pp) cf ps (by simp [builtinPaths]) (by decide) k).elim
    | discard _ k' => rw [effR_unique k nd vn k']

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

end

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
  | _, _, _, .let ps _ _ _ fr ty li body ls, nd, vn, _, h₂ => by
    have ih := fun {y} k' => stmtsR_unique body (idsFresh_cons nd fr) vn (b := y) k'
    cases h₂ with
    | «let» _ _ _ _ _ ty' li' body' ls' =>
      cases tyR_unique ty ty'
      cases letInitR_unique nd vn li li'
      cases ih body'
      rw [ls'] at ls
      exact (Option.some.inj ls).symm
    | last np _ => exact absurd ps np
    | seq np _ _ => exact absurd ps np
  | _, _, _, .last np s, nd, vn, _, h₂ => by
    have ih := fun {y} k' => stmtR_unique s nd vn (b := y) k'
    cases h₂ with
    | «let» ps _ _ _ _ _ _ _ _ => exact absurd ps np
    | last _ s' => exact ih s'
  | _, _, _, .seq np s rest, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => stmtR_unique s nd vn (b := y) k'
    have ih2 := fun {y} k' => stmtsR_unique rest nd vn (b := y) k'
    cases h₂ with
    | «let» ps _ _ _ _ _ _ _ _ => exact absurd ps np
    | seq _ s' rest' => rw [ih1 s', ih2 rest']
termination_by structural _ _ _ h _ _ _ _ => h

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
termination_by structural _ _ _ h _ _ _ _ => h
end

end

end Lanius.Mini.Reading
