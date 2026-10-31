import Lanius.Mini.Reading.Det.Arms

/-! # The reading is deterministic, F1: effectful expressions

`effR_unique`: in a scope whose locals have distinct ids, a node reads as
at most one effectful expression at a given expected type. The pure
reading agrees with the others (`pure_agree`); the others are told apart by
production, by the exclusions the rules state, or by their parts' own
uniqueness. A match's arms are the same arms by `arms_unique`, which needs
an enum's variant names distinct (`VariantsNodup`, from `WellNamed`). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-- Each enum's variants have distinct names. -/
def VariantsNodup (decls : Decls) : Prop :=
  ∀ (d : Nat) (t : TypeDecl), decls.types[d]? = some t → t.isEnum = true → t.variants.Nodup

/-- Close a goal whose hypotheses give one node two different productions. -/
macro "eff_clash" : tactic => `(tactic| (exfalso; (try simp only [ChainForm, MethodForm, levelProds, List.mem_cons, List.not_mem_nil, or_false] at *); (try unfold_prods); omega))

theorem effArmsR_named {env : FrontEnv} : ∀ {scope : List Local} {expected : Option Ty} {owner : TypeDecl}
    {vs : List VariantTy} {os : List CTree} {eas : List EffArm}, EffArmsR env scope expected owner vs os eas →
    ListRel (ArmNames owner) os (vs.map (·.name))
  | _, _, _, _, _, _, .nil => .nil
  | _, _, _, _, _, _, .cons a rest => by
    refine .cons ?_ (effArmsR_named rest)
    cases a with
    | unit _ ps an _ _ _ _ => exact ⟨_, ps, an⟩
    | payload _ ps an _ _ _ _ _ _ => exact ⟨_, ps, an⟩

section
variable {env : FrontEnv}

set_option maxHeartbeats 4000000 in
mutual
theorem effR_unique : ∀ {scope : List Local} {expected : Option Ty} {c : CTree} {x : MEff},
    EffR env scope expected c x → IdsFresh scope → VariantsNodup env.decls →
    ∀ {y : MEff}, EffR env scope expected c y → x = y
  | _, _, _, _, .pure p, nd, _, _, h₂ => (pure_agree p nd h₂).symm
  | _, _, _, _, .wrap w k, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.wrap w k)
    | wrap _ k' => exact ih1 k'
    | _ => eff_clash
  | _, _, _, _, .bare w kids k, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.bare w kids k)
    | bare _ _ k' => exact ih1 k'
    | level _ kn _ _ => exact absurd kids kn
    | cast _ kn _ _ => exact absurd kids kn
    | _ => eff_clash
  | _, E, _, _, .level lp kn k fo, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    have ih2 := fun {y} k' => effFold_unique fo nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.level (expected := E) lp kn k fo)
    | bare _ kids _ => exact absurd kids kn
    | level _ _ k' fo' =>
      have e := ih1 k'
      subst e
      exact ih2 fo'
    | _ => eff_clash
  | _, E, _, _, .cast pc kn k cs, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.cast (expected := E) pc kn k cs)
    | bare _ kids _ => exact absurd kids kn
    | cast _ _ k' cs' =>
      have e := ih1 k'
      subst e
      exact effCasts_unique cs cs'
    | _ => eff_clash
  | _, _, _, _, .neg pn k xn, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.neg pn k xn)
    | neg _ k' xn' =>
      have e := ih1 k'
      subst e
      rw [xn] at xn'
      cases xn'
      rfl
    | _ => eff_clash
  | _, E, _, _, .not pn k xn, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.not (expected := E) pn k xn)
    | «not» _ k' xn' =>
      have e := ih1 k'
      subst e
      rw [xn] at xn'
      cases xn'
      rfl
    | _ => eff_clash
  | _, _, _, _, .group pg k, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.group pg k)
    | group _ k' => exact ih1 k'
    | _ => eff_clash
  | _, _, _, _, .primary pp pe k, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.primary pp pe k)
    | primary _ _ k' => exact ih1 k'
    | _ => eff_clash
  | _, _, _, _, .pathCall pp p0 p01 p1 p13 pc, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effPathCall_unique pc nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.pathCall pp p0 p01 p1 p13 pc)
    | pathCall _ _ _ _ _ pc' => exact ih1 pc'
    | _ => eff_clash
  | _, _, _, _, .method pp mf lo it mfor fd inf, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effInfer_unique inf nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.method pp mf lo it mfor fd inf)
    | method _ _ lo' it' mfor' fd' inf' =>
      have e := localOf_unique lo lo'
      subst e
      have e := items_unique it it'
      subst e
      have e := methodFor_unique mfor mfor'
      subst e
      rw [fd] at fd'
      cases fd'
      exact ih1 inf'
    | _ => eff_clash
  | _, E, _, _, .index pp p0 p01 p1 p13 lo k, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.index (expected := E) pp p0 p01 p1 p13 lo k)
    | index _ _ _ _ _ lo' k' =>
      have e := localOf_unique lo lo'
      subst e
      rw [ih1 k']
    | _ => eff_clash
  | _, _, _, _, .callChain pp p0 p01 p1 p13 pc ch, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effPathCall_unique pc nd vn (y := y) k'
    have ih2 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.callChain pp p0 p01 p1 p13 pc ch)
    | callChain _ _ _ _ _ pc' ch' =>
      have e := ih1 pc'
      subst e
      exact ih2 ch'
    | _ => eff_clash
  | _, _, _, _, .chainLocal pp cf lo ch, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    have ih2 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.chainLocal pp cf lo ch)
    | chainLocal _ _ lo' ch' =>
      have e := localOf_unique lo lo'
      subst e
      exact ih1 ch'
    | chain _ _ k' ch' =>
      have e := eff_local lo k'
      subst e
      exact ih2 ch'
    | _ => eff_clash
  | _, _, _, _, .chain pp cf k ch, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    have ih2 := fun {y} k' => effR_unique k nd vn (y := y) k'
    have ih3 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.chain pp cf k ch)
    | chainLocal _ _ lo' ch' =>
      have e := eff_local lo' k
      subst e
      exact ih1 ch'
    | chain _ _ k' ch' =>
      have e := ih2 k'
      subst e
      exact ih3 ch'
    | _ => eff_clash
  | _, _, _, _, .unitVariant pi pl ps e nl nk vb ev, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effVariant_unique ev nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.unitVariant pi pl ps e nl nk vb ev)
    | unitVariant _ _ ps' e' _ _ vb' ev' =>
      have es := pathSpellings_unique ps ps'
      subst es
      have ⟨ef, en⟩ := split_unique (e.symm.trans e')
      subst ef en
      have ev2 := variantByPath_unique vb vb'
      subst ev2
      exact ih1 ev'
    | _ => eff_clash
  | _, _, _, _, .literal pi pl ps it da td ne tf kn el di, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effList_unique el nd vn (ys := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.literal pi pl ps it da td ne tf kn el di)
    | literal _ _ ps' it' da' td' _ _ kn' el' di' =>
      have e := pathSpellings_unique ps ps'
      subst e
      have e := items_unique it it'
      subst e
      have e := declAt_unique da da'
      subst e
      rw [td] at td'
      cases td'
      have e := knownTys_unique (P := FieldTys _ _) (fun _ _ _ x y => fieldTys_unique x y) kn kn'
      subst e
      have e := ih1 el'
      subst e
      rw [declInst_unique di di']
    | _ => eff_clash
  | _, _, _, _, .match pm k et ee td en pt it len sub arms rt, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    have ih2 := fun {y} k' => effArmsR_unique arms nd vn (eas' := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.match pm k et ee td en pt it len sub arms rt)
    | «match» _ k' et' ee' td' _ pt' it' _ sub' arms' rt' =>
      have e := ih1 k'
      subst e
      have e := effTy_unique et et'
      subst e
      rw [ee] at ee'
      cases ee'
      rw [td] at td'
      cases td'
      have e := payloadTys_unique pt pt'
      subst e
      have e := items_unique it it'
      subst e
      have eo := by
        classical
        exact arms_unique armNames_fun ((vn _ _ td en).sublist (zipVariants_names _ _))
          (by rw [List.length_map]; exact len) (effArmsR_named arms) (effArmsR_named arms') sub sub'
      subst eo
      have ag := ih2 arms'
      rw [armsAgree_binders ag, armsAgree_values ag, armsAgree_resultTy ag rt rt']
    | _ => eff_clash
  | _, _, _, _, .array pa nr he it el len, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effList_unique el nd vn (ys := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.array pa nr he it el len)
    | array _ _ he' it' el' _ =>
      rw [he] at he'
      cases he'
      have e := items_unique it it'
      subst e
      rw [ih1 el']
    | arrayRepeat _ ps pr _ _ _ => exact (nr ⟨ps, pr⟩).elim
    | _ => eff_clash
  | _, _, _, _, .arrayRepeat pa ps pr he hw k, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | pure p => exact pure_agree p nd (.arrayRepeat pa ps pr he hw k)
    | array _ nr _ _ _ _ => exact (nr ⟨ps, pr⟩).elim
    | arrayRepeat _ _ _ he' _ k' =>
      rw [he] at he'
      cases he'
      have e := ih1 k'
      cases e
      rfl
    | _ => eff_clash
termination_by structural _ _ _ _ h _ _ _ _ => h

theorem effFold_unique : ∀ {scope : List Local} {a : MEff} {tail : CTree} {x : MEff},
    EffFold env scope a tail x → IdsFresh scope → VariantsNodup env.decls →
    ∀ {y : MEff}, EffFold env scope a tail y → x = y
  | _, _, _, _, .done kids, _, _, _, h₂ => by
    cases h₂ with
    | done _ => rfl
    | step kn _ _ _ => exact absurd kids kn
  | _, _, _, _, .step kn k eb fo, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    have ih2 := fun {y} k' => effFold_unique fo nd vn (y := y) k'
    cases h₂ with
    | done kids => exact absurd kids kn
    | step _ k' eb' fo' =>
      have e := ih1 k'
      subst e
      rw [eb] at eb'
      cases eb'
      exact ih2 fo'
termination_by structural _ _ _ _ h _ _ _ _ => h

theorem effChain_unique : ∀ {scope : List Local} {expected : Option Ty} {a : MEff} {tail : CTree}
    {x : MEff}, EffChain env scope expected a tail x → IdsFresh scope → VariantsNodup env.decls →
    ∀ {y : MEff}, EffChain env scope expected a tail y → x = y
  | _, _, _, _, _, .done pe, _, _, _, h₂ => by
    cases h₂ with
    | done _ => rfl
    | _ => eff_clash
  | _, _, _, _, _, .method pm pn pc it et mfor fd inf ch, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effInfer_unique inf nd vn (y := y) k'
    have ih2 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    cases h₂ with
    | method _ _ _ it' et' mfor' fd' inf' ch' =>
      have e := items_unique it it'
      subst e
      have e := effTy_unique et et'
      subst e
      have e := methodFor_unique mfor mfor'
      subst e
      rw [fd] at fd'
      cases fd'
      have e := ih1 inf'
      subst e
      exact ih2 ch'
    | _ => eff_clash
  | _, _, _, _, _, .field pm pn pnc et fi ch, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    cases h₂ with
    | field _ _ _ et' fi' ch' =>
      have e := effTy_unique et et'
      subst e
      have e := fieldIndex_unique fi fi'
      subst e
      exact ih1 ch'
    | _ => eff_clash
  | _, _, _, _, _, .index pi el lw k ch, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    have ih2 := fun {y} k' => effChain_unique ch nd vn (y := y) k'
    cases h₂ with
    | index _ el' lw' k' ch' =>
      rw [el] at el'
      cases el'
      have e := localWithId_unique lw lw'
      subst e
      have e := ih1 k'
      subst e
      exact ih2 ch'
    | _ => eff_clash
termination_by structural _ _ _ _ _ h _ _ _ _ => h

theorem effList_unique : ∀ {scope : List Local} {E : Option (List Ty)} {cs : List CTree}
    {xs : List MEff}, EffList env scope E cs xs → IdsFresh scope → VariantsNodup env.decls →
    ∀ {ys : List MEff}, EffList env scope E cs ys → xs = ys
  | _, _, _, _, .nil, _, _, _, h₂ => by cases h₂; rfl
  | _, _, _, _, .cons k rest, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    have ih2 := fun {y} k' => effList_unique rest nd vn (ys := y) k'
    cases h₂ with
    | cons k' rest' => rw [ih1 k', ih2 rest']
termination_by structural _ _ _ _ h _ _ _ _ => h

theorem effPathCall_unique : ∀ {scope : List Local} {expected : Option Ty} {path args : CTree}
    {x : MEff}, EffPathCall env scope expected path args x → IdsFresh scope → VariantsNodup env.decls →
    ∀ {y : MEff}, EffPathCall env scope expected path args y → x = y
  | _, _, _, _, _, .stride ps it pe pe1 lo lt, _, _, _, h₂ => by
    cases h₂ with
    | stride _ it' pe' _ lo' _ =>
      have e := items_unique it it'
      cases e
      have e := peel_unique pe pe'
      subst e
      rw [localOf_unique lo lo']
    | named pr nb _ _ _ =>
      exact (nb (by rw [pathRefR_spellings ps pr]; simp [builtinPaths])).elim
  | _, _, _, _, _, .named pr nb e it en, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effNamed_unique en nd vn (y := y) k'
    cases h₂ with
    | stride ps _ _ _ _ _ =>
      exact (nb (by rw [pathRefR_spellings ps pr]; simp [builtinPaths])).elim
    | named pr' _ e' it' en' =>
      have ep := pathRefR_unique pr pr'
      subst ep
      have ⟨ef, enm⟩ := split_unique (e.symm.trans e')
      subst ef enm
      have ei := items_unique it it'
      subst ei
      exact ih1 en'
termination_by structural _ _ _ _ _ h _ _ _ _ => h

theorem effNamed_unique : ∀ {scope : List Local} {expected : Option Ty} {front : ModPath}
    {name : Name} {targs items : List CTree} {x : MEff}, EffNamed env scope expected front name targs items x →
    IdsFresh scope → VariantsNodup env.decls → ∀ {y : MEff}, EffNamed env scope expected front name targs items y → x = y
  | _, _, _, _, _, _, _, .static to te ot mfor fd inf, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effInfer_unique inf nd vn (y := y) k'
    cases h₂ with
    | static to' _ ot' mfor' fd' inf' =>
      have e := bareTy_unique ot ot'
      subst e
      have e := methodFor_unique mfor mfor'
      subst e
      rw [fd] at fd'
      cases fd'
      exact ih1 inf'
    | infer nt _ _ _ _ => exact (nt ⟨to, te⟩).elim
    | explicit nt _ _ _ _ _ _ => exact (nt ⟨to, te⟩).elim
    | variant nf _ _ _ => exact (nf (.inl to)).elim
  | _, _, _, _, _, _, _, .infer nt fnm fd te inf, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effInfer_unique inf nd vn (y := y) k'
    cases h₂ with
    | static to te' _ _ _ _ => exact (nt ⟨to, te'⟩).elim
    | infer _ fnm' fd' _ inf' =>
      have e := fnNamed_unique fnm fnm'
      subst e
      rw [fd] at fd'
      cases fd'
      exact ih1 inf'
    | explicit _ _ _ tne _ _ _ => exact absurd te tne
    | variant nf _ _ _ => exact (nf (.inr ⟨_, fnm⟩)).elim
  | _, _, _, _, _, _, _, .explicit nt fnm fd tne ei pe el, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effList_unique el nd vn (ys := y) k'
    cases h₂ with
    | static to te _ _ _ _ => exact (nt ⟨to, te⟩).elim
    | infer _ _ _ te _ => exact absurd te tne
    | explicit _ fnm' fd' _ ei' pe' el' =>
      have e := fnNamed_unique fnm fnm'
      subst e
      rw [fd] at fd'
      cases fd'
      have e := explicitInst_unique ei ei'
      subst e
      have e := paramExpects_unique pe pe'
      subst e
      rw [ih1 el']
    | variant nf _ _ _ => exact (nf (.inr ⟨_, fnm⟩)).elim
  | _, _, _, _, _, _, _, .variant nf te vb ev, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effVariant_unique ev nd vn (y := y) k'
    cases h₂ with
    | static to _ _ _ _ _ => exact (nf (.inl to)).elim
    | infer _ fnm _ _ _ => exact (nf (.inr ⟨_, fnm⟩)).elim
    | explicit _ fnm _ _ _ _ _ => exact (nf (.inr ⟨_, fnm⟩)).elim
    | variant _ _ vb' ev' =>
      have e := variantByPath_unique vb vb'
      subst e
      exact ih1 ev'
termination_by structural _ _ _ _ _ _ _ h _ _ _ _ => h

theorem effInfer_unique : ∀ {scope : List Local} {expected : Option Ty} {d : Nat} {fd : FnDecl}
    {start : List Bind} {pre : List MEff} {items : List CTree} {x : MEff},
    EffInfer env scope expected d fd start pre items x → IdsFresh scope → VariantsNodup env.decls →
    ∀ {y : MEff}, EffInfer env scope expected d fd start pre items y → x = y
  | _, _, _, _, _, _, _, _, .plain e pe el, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effList_unique el nd vn (ys := y) k'
    cases h₂ with
    | plain _ pe' el' =>
      have es := paramExpects_unique pe pe'
      subst es
      rw [ih1 el']
    | infer ne _ _ _ _ => exact absurd e ne
  | _, _, _, _, _, _, _, _, .infer ne pp rb ea ib, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effArgs_unique ea nd vn (a' := y) k'
    cases h₂ with
    | plain e _ _ => exact absurd e ne
    | infer _ pp' rb' ea' ib' =>
      have e := paramPatterns_unique pp pp'
      subst e
      have e := retBinds_unique rb rb'
      subst e
      have e := ih1 ea'
      subst e
      rw [instBound_unique ib ib']
termination_by structural _ _ _ _ _ _ _ _ h _ _ _ _ => h

theorem effArgs_unique : ∀ {scope : List Local} {fd : FnDecl} {names : List Name} {ps : List CTree}
    {pre : List MEff} {items : List CTree} {b : List Bind} {a : ArgsBound},
    EffArgs env scope fd names ps pre items b a → IdsFresh scope → VariantsNodup env.decls →
    ∀ {a' : ArgsBound}, EffArgs env scope fd names ps pre items b a' → a = a'
  | _, _, _, _, _, _, _, _, .nil, _, _, _, h₂ => by cases h₂; rfl
  | _, _, _, _, _, _, _, _, .pre ba rest, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effArgs_unique rest nd vn (a' := y) k'
    cases h₂ with
    | pre ba' rest' =>
      have e := bindArg_unique ba ba'
      subst e
      rw [ih1 rest']
  | _, _, _, _, _, _, _, _, .arg ah k ba rest, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    have ih2 := fun {y} k' => effArgs_unique rest nd vn (a' := y) k'
    cases h₂ with
    | arg ah' k' ba' rest' =>
      have e := argHint_unique ah ah'
      subst e
      have e := ih1 k'
      subst e
      have e := bindArg_unique ba ba'
      subst e
      rw [ih2 rest']
termination_by structural _ _ _ _ _ _ _ _ h _ _ _ _ => h

theorem effVariant_unique : ∀ {scope : List Local} {expected : Option Ty} {v : VariantAt}
    {items : List CTree} {x : MEff}, EffVariant env scope expected v items x → IdsFresh scope →
    VariantsNodup env.decls → ∀ {y : MEff}, EffVariant env scope expected v items y → x = y
  | _, _, _, _, _, .mk td kn el di, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effList_unique el nd vn (ys := y) k'
    cases h₂ with
    | mk td' kn' el' di' =>
      rw [td] at td'
      cases td'
      have e := knownTys_unique (fun _ _ _ x y => by
        obtain ⟨vss, pv, gv⟩ := x
        obtain ⟨vss', pv', gv'⟩ := y
        rw [payloadTys_unique pv pv', gv'] at gv
        cases gv
        rfl) kn kn'
      subst e
      have e := ih1 el'
      subst e
      rw [declInst_unique di di']
termination_by structural _ _ _ _ _ h _ _ _ _ => h

theorem effArmsR_unique : ∀ {scope : List Local} {expected : Option Ty} {owner : TypeDecl}
    {vs : List VariantTy} {os : List CTree} {eas : List EffArm}, EffArmsR env scope expected owner vs os eas →
    IdsFresh scope → VariantsNodup env.decls →
    ∀ {eas' : List EffArm}, EffArmsR env scope expected owner vs os eas' → ListRel ArmAgree eas eas'
  | _, _, _, _, _, _, .nil, _, _, _, h₂ => by cases h₂; exact .nil
  | _, _, _, _, _, _, .cons a rest, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effArmR_unique a nd vn (ea' := y) k'
    have ih2 := fun {y} k' => effArmsR_unique rest nd vn (eas' := y) k'
    cases h₂ with
    | cons a' rest' => exact .cons (ih1 a') (ih2 rest')
termination_by structural _ _ _ _ _ _ h _ _ _ _ => h

theorem effArmR_unique : ∀ {scope : List Local} {expected : Option Ty} {owner : TypeDecl}
    {v : VariantTy} {arm : CTree} {ea : EffArm}, EffArmR env scope expected owner v arm ea →
    IdsFresh scope → VariantsNodup env.decls →
    ∀ {ea' : EffArm}, EffArmR env scope expected owner v arm ea' → ArmAgree ea ea'
  | _, _, _, _, _, _, .unit pi ps an pp k da mt, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k nd vn (y := y) k'
    cases h₂ with
    | unit _ _ _ _ k' da' mt' =>
      have e := ih1 k'
      subst e
      rw [da] at da'
      cases da'
      exact ⟨rfl, rfl, fun s t hs ht => effTy_unique (mt s hs) (mt' t ht)⟩
    | payload _ _ _ pnp _ _ _ _ _ => exact absurd pp pnp
  | _, _, _, _, _, _, .payload pi ps an pnp it br k da mt, nd, vn, _, h₂ => by
    have ih1 := fun {y} k' => effR_unique k (bindersR_fresh br nd) vn (y := y) k'
    cases h₂ with
    | unit _ _ _ pp _ _ _ => exact absurd pp pnp
    | payload _ _ _ _ it' br' k' da' mt' =>
      have e := items_unique it it'
      subst e
      have e := bindersR_unique br br'
      subst e
      have e := ih1 k'
      subst e
      rw [da] at da'
      cases da'
      exact ⟨rfl, rfl, fun s t hs ht => effTy_unique (mt s hs) (mt' t ht)⟩
termination_by structural _ _ _ _ _ _ h _ _ _ _ => h
end

end

end Lanius.Mini.Reading
