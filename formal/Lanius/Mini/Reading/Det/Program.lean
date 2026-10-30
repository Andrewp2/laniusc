import Lanius.Mini.Reading.Det.Close
import Lanius.Mini.Reading.Program

/-! # The reading is deterministic, F1: the program

`reading_unique`: the parse trees of a program's files read as at most one
source program. A function instance's parameters have distinct ids
(`paramsR_fresh`), so its body reads one way (`stmtsR_unique`); an enum's
variant names are distinct because `WellNamed` says so of each module's
enums and every type is declared in one of the files' modules
(`collected_home`). The instance tables and the closed program follow. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Each enum's variants are distinct -/

theorem typeDeclR_home {home : ModPath} {s : CTree} {t : TypeDecl} (h : TypeDeclR home s t) : t.home = home := by
  cases h <;> rfl

theorem itemDecls_home {home : ModPath} {item : CTree} {d : Decls} (h : ItemDecls home item d) :
    ∀ t ∈ d.types, t.home = home := by
  cases h with
  | type _ td =>
    intro t m
    simp only [onlyTypes, List.mem_singleton] at m
    subst m
    exact typeDeclR_home td
  | _ => intro t m; simp [onlyFns, onlyConsts, onlyImports, onlyAliases, noDecls] at m

theorem collect_home {home : ModPath} : ∀ {items : List CTree} {d : Decls}, Collect home items d →
    ∀ t ∈ d.types, t.home = home
  | _, _, .nil => by intro t m; simp [noDecls] at m
  | _, _, .cons i rest => by
    intro t m
    simp only [Decls.append, List.mem_append] at m
    rcases m with m | m
    · exact itemDecls_home i t m
    · exact collect_home rest t m

theorem collected_home : ∀ {roots : List CTree} {c : Collected}, CollectedR roots c →
    ∀ t ∈ c.decls.types, t.home ∈ c.modules
  | _, _, .nil => by intro t m; simp [noDecls] at m
  | _, _, .cons fd rest => by
    intro t m
    simp only [Decls.append, List.mem_append] at m
    rcases m with m | m
    · obtain ⟨_, _, _, _, co⟩ := fd
      exact List.mem_cons.2 (.inl (collect_home co t m))
    · exact List.mem_cons.2 (.inr (collected_home rest t m))

theorem variantsNodup_of {first : CTree} {rest : List CTree} {f : FileDecls} {r : Collected}
    (fd : FileDeclsR first f) (cr : CollectedR rest r)
    (wn : WellNamed { decls := f.decls.append r.decls, modules := f.home :: r.modules }) :
    VariantsNodup (f.decls.append r.decls) := by
  intro d t g en
  have m : t ∈ (f.decls.append r.decls).types := List.mem_of_getElem? g
  have hm : t.home ∈ f.home :: r.modules := collected_home (.cons fd cr) t m
  exact ((wn.2.1 t.home hm).2 t m en rfl).1

/-! ## Functions -/

theorem resultR_unique {env : FrontEnv} {ret : CTree} {a b : RetTy} (h₁ : ResultR env ret a)
    (h₂ : ResultR env ret b) : a = b := by
  cases h₁ with
  | void _ => cases h₂ with
    | void _ => rfl
    | _ => prod_clash
  | never _ q => cases h₂ with
    | never _ _ => rfl
    | ty _ q' _ => exact absurd q q'
    | _ => prod_clash
  | ty _ q t => cases h₂ with
    | ty _ _ t' => rw [tyR_unique t t']
    | never _ q' => exact absurd q' q
    | _ => prod_clash

section
variable {env : FrontEnv} {fd : FnDecl}

theorem paramsR_unique : ∀ {scope : List Local} {ps : List CTree} {a b : MParams}, ParamsR env fd scope ps a →
    ParamsR env fd scope ps b → a = b
  | _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, .cons _ _ _ pt ty rest, h₂ => by
    have ih := fun {y} k' => paramsR_unique rest (b := y) k'
    cases h₂ with
    | cons _ _ _ pt' ty' rest' =>
      cases patternOf_unique pt pt'
      cases tyR_unique ty ty'
      rw [ih rest']
termination_by structural _ _ _ _ h _ => h

theorem paramsR_fresh : ∀ {scope : List Local} {ps : List CTree} {r : MParams}, ParamsR env fd scope ps r →
    IdsFresh scope → IdsFresh r.scope
  | _, _, _, .nil, nd => nd
  | _, _, _, @ParamsR.cons _ _ _ p _ _ x _ _ _ fr _ _ rest, nd => by
    have h := paramsR_fresh rest
      (idsFresh_cons (l := { name := (kidToken p 0).text, id := (kidToken p 0).start - env.base, ty := x }) nd fr)
    exact h

end

theorem readFn_unique {decls : Decls} {fd : FnDecl} {args : List Ty} {a b : MFunc} (vn : VariantsNodup decls)
    (h₁ : ReadFn decls fd args a) (h₂ : ReadFn decls fd args b) : a = b := by
  obtain ⟨r, items, ps, body, _, _, rr, it, pr, br, rfl⟩ := h₁
  obtain ⟨r', items', ps', body', _, _, rr', it', pr', br', rfl⟩ := h₂
  cases resultR_unique rr rr'
  cases items_unique it it'
  cases paramsR_unique pr pr'
  cases blockR_unique br (paramsR_fresh pr List.nodup_nil) vn br'
  rfl

theorem readInst_unique {decls : Decls} {inst : Inst} {a b : MFunc} (vn : VariantsNodup decls)
    (h₁ : ReadInst decls inst a) (h₂ : ReadInst decls inst b) : a = b := by
  cases h₁ with
  | projection n ea ft => cases h₂ with
    | projection _ ea' ft' =>
      rw [ea] at ea'
      cases ea'
      rw [fieldTyAt_unique ft ft']
    | plain f _ _ => rw [n] at f; cases f
    | diverge f _ _ _ => rw [n] at f; cases f
  | plain f dv rf => cases h₂ with
    | projection n _ _ => rw [n] at f; cases f
    | plain f' _ rf' =>
      rw [f] at f'
      cases f'
      exact readFn_unique vn rf rf'
    | diverge f' dv' _ _ =>
      rw [f] at f'
      cases f'
      rw [dv] at dv'
      cases dv'
  | diverge f dv rg lt => cases h₂ with
    | projection n _ _ => rw [n] at f; cases f
    | plain f' dv' _ =>
      rw [f] at f'
      cases f'
      rw [dv] at dv'
      cases dv'
    | diverge f' _ rg' lt' =>
      rw [f] at f'
      cases f'
      cases readFn_unique vn rg rg'
      rw [lt] at lt'
      cases lt'
      rfl

/-! ## The tables and the program -/

section
variable {decls : Decls}

theorem monoR_unique (vn : VariantsNodup decls) : ∀ {table : List Inst} {done : List MFunc} {i : Nat}
    {a b : Mono}, MonoR decls table done i a → MonoR decls table done i b → a = b
  | _, _, _, _, _, .done _, .done _ => rfl
  | _, _, _, _, _, .done n, .step s _ _ => by rw [n] at s; cases s
  | _, _, _, _, _, .step s _ _, .done n => by rw [n] at s; cases s
  | _, _, _, _, _, .step s ri rest, h₂ => by
    have ih := fun {y} k' => monoR_unique vn rest (b := y) k'
    cases h₂ with
    | done n => rw [n] at s; cases s
    | step s' ri' rest' =>
      rw [s] at s'
      cases s'
      cases readInst_unique vn ri ri'
      exact ih rest'
termination_by structural _ _ _ _ _ h _ => h

theorem typeTable_unique : ∀ {table : List Inst} {ts : List Ty} {a b : List Inst}, TypeTable decls table ts a →
    TypeTable decls table ts b → a = b
  | _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, .cons x rest, h₂ => by
    have ih := fun {y} k' => typeTable_unique rest (b := y) k'
    cases h₂ with
    | cons x' rest' =>
      cases tyInsts_unique x x'
      exact ih rest'
termination_by structural _ _ _ _ h _ => h

theorem typeTableMore_unique : ∀ {table : List Inst} {ts : List Ty} {a b : List Inst},
    TypeTableMore decls table ts a → TypeTableMore decls table ts b → a = b
  | _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, .known k rest, h₂ => by
    have ih := fun {y} k' => typeTableMore_unique rest (b := y) k'
    cases h₂ with
    | known _ rest' => exact ih rest'
    | new k' _ _ => rw [k] at k'; cases k'
  | _, _, _, _, .new k t rest, h₂ => by
    have ih := fun {y} k' => typeTableMore_unique rest (b := y) k'
    cases h₂ with
    | known k' _ => rw [k] at k'; cases k'
    | new _ t' rest' =>
      cases typeTable_unique t t'
      exact ih rest'
termination_by structural _ _ _ _ h _ => h

end

/-- The parse trees of a program's files read as at most one program. -/
theorem reading_unique {roots : List CTree} {p q : SrcProgram} (h₁ : Reading roots p) (h₂ : Reading roots q) :
    p = q := by
  obtain ⟨first, rest, f, r, mono, seeded, types, e, fd, cr, wn, mr, tt, tm, cp⟩ := h₁
  obtain ⟨first', rest', f', r', mono', seeded', types', e', fd', cr', _, mr', tt', tm', cp'⟩ := h₂
  rw [e] at e'
  cases e'
  cases fileDeclsR_unique fd fd'
  cases collectedR_unique cr cr'
  have vn := variantsNodup_of fd cr wn
  cases monoR_unique vn mr mr'
  cases typeTable_unique tt tt'
  cases typeTableMore_unique tm tm'
  exact closedProgram_unique cp cp'

end Lanius.Mini.Reading
