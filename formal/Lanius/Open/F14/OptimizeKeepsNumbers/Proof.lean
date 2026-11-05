module

public import Lanius.Open.F14.OptimizeKeepsNumbers.Stmt
public import Lanius.Mini.Validate
import all Lanius.Mini.Compiler.P.Expr_isAtom
import all Lanius.Mini.Compiler.P.Expr_mentions
import all Lanius.Mini.Compiler.P.Expr_subst
import all Lanius.Mini.Compiler.P.allocAgrees
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.divideAgrees
import all Lanius.Mini.Compiler.P.factValue
import all Lanius.Mini.Compiler.P.frameAgrees
import all Lanius.Mini.Compiler.P.loadByteAgrees
import all Lanius.Mini.Compiler.P.loadWordAgrees
import all Lanius.Mini.Compiler.P.retAgrees
import all Lanius.Mini.Compiler.P.staticAgrees
import all Lanius.Mini.Compiler.P.storeByteAgrees
import all Lanius.Mini.Compiler.P.storeWordAgrees
import all Lanius.Mini.Compiler.P.sysAgrees
import all Lanius.Mini.Compiler.P.Expr_temps
import all Lanius.Mini.Compiler.P.Expr_within
import all Lanius.Mini.Compiler.P.Stmt_temps
import all Lanius.Mini.Compiler.P.Stmt_within
import all Lanius.Mini.Compiler.P.allWithin
import all Lanius.Mini.Compiler.P.argSlots
import all Lanius.Mini.Compiler.P.argsRoom
import all Lanius.Mini.Compiler.P.argsTemps
import all Lanius.Mini.Compiler.P.arityIs
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileStmt
import all Lanius.Mini.Compiler.P.exprRoom
import all Lanius.Mini.Compiler.P.frameLimit
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.spend
import all Lanius.Mini.Compiler.P.stmtRoom
import all Lanius.Mini.Compiler.P.zeroLocals
import all Lanius.Mini.Compiler.P.firstFacts
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.Stmt_factsAfter
import all Lanius.Mini.Compiler.P.Stmt_ignores
import all Lanius.Mini.Compiler.P.Stmt_isBrk
import all Lanius.Mini.Compiler.P.Stmt_isCont
import all Lanius.Mini.Compiler.P.Stmt_isSkip
import all Lanius.Mini.Compiler.P.Stmt_jumps
import all Lanius.Mini.Compiler.P.assigned
import all Lanius.Mini.Compiler.P.longer
import all Lanius.Mini.Compiler.P.trimFacts
import all Lanius.Mini.Compiler.P.Stmt_deadBefore
import all Lanius.Mini.Compiler.P.Stmt_optimize
import all Lanius.Mini.Compiler.P.loopUnlessZero
import all Lanius.Mini.Compiler.P.optimizeFuncs
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.optimizeLoop
import all Lanius.Mini.Compiler.P.optimizeProgram
import all Lanius.Mini.Compiler.P.Expr_optimize
import all Lanius.Mini.Compiler.P.iteOrSkip
import all Lanius.Mini.Compiler.P.optimizeAll
import all Lanius.Mini.Compiler.P.optimizeAssign
import all Lanius.Mini.Compiler.P.optimizeBinary
import all Lanius.Mini.Compiler.P.optimizeBoth
import all Lanius.Mini.Compiler.P.optimizeCompare
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeRight
import all Lanius.Mini.Compiler.P.optimizeSeq
import all Lanius.Mini.Compiler.P.pickBranch
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects
import all Lanius.Mini.Compiler.P.factDies
import all Lanius.Mini.Compiler.P.kill
import all Lanius.Mini.Compiler.P.killTail
import all Lanius.Mini.Compiler.P.mentionsAny
import all Lanius.Mini.Compiler.P.noneDies
import all Lanius.Mini.Compiler.P.substAll

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

set_option linter.unusedSimpArgs false

namespace Lanius.Open.OptimizeKeepsNumbers

/-- Facts whose slots and values have numbers at most `B` and whose values are
atoms' (no temporaries). -/
def Good (B : Nat) (facts : List Fact) : Prop :=
  ∀ fact ∈ facts, fact.slot ≤ B ∧ nb fact.value ≤ B ∧ fact.value.temps = 0

theorem good_nil (B : Nat) : Good B [] := by
  intro fact m; simp at m

theorem good_sub {B : Nat} {facts others : List Fact} (good : Good B facts)
    (sub : ∀ fact ∈ others, fact ∈ facts) : Good B others :=
  fun fact m => good fact (sub fact m)

theorem good_killShared {B : Nat} {facts : List Fact} (good : Good B facts) (index : Nat) :
    Good B (killShared facts index) :=
  good_sub good fun _ m => by unfold killShared at m; exact (mem_killPrefix m).1

theorem factValue_good {B : Nat} : ∀ {facts : List Fact}, Good B facts → ∀ index : Nat,
    nb (factValue facts index) ≤ max B index ∧ (factValue facts index).temps = 0
  | [], _, index => ⟨Nat.le_max_right B index, rfl⟩
  | fact :: rest, good, index => by
    simp only [factValue]
    split
    · have := good fact (List.mem_cons_self ..)
      exact ⟨by omega, this.2.2⟩
    · exact factValue_good (good_sub good fun _ m => List.mem_cons_of_mem _ m) index

theorem subst_good {B : Nat} {facts : List Fact} (good : Good B facts) : ∀ e : Expr,
    nb (e.subst facts) ≤ max B (nb e) ∧ (e.subst facts).temps ≤ e.temps
  | .lit v => by simp [Expr.subst, Expr.temps]
  | .var index => by
    have := factValue_good good index
    simp only [Expr.subst, nb_Expr_var, nb_nat, Expr.temps]; omega
  | .neg a => by
    have := subst_good good a
    simp only [Expr.subst, nb_Expr_neg, Expr.temps]; omega
  | .binary w o a b => by
    have := subst_good good a; have := subst_good good b
    simp only [Expr.subst, nb_Expr_binary, Expr.temps]; omega
  | .compare w o a b => by
    have := subst_good good a; have := subst_good good b
    simp only [Expr.subst, nb_Expr_compare, Expr.temps]; omega
  | .fp o a b => by
    have := subst_good good a; have := subst_good good b
    simp only [Expr.subst, nb_Expr_fp, Expr.temps]; omega

theorem optimizeNeg_le (a : Expr) :
    nb (optimizeNeg a) ≤ nb a ∧ (optimizeNeg a).temps ≤ a.temps := by
  unfold optimizeNeg
  split <;> simp [Expr.temps]

theorem optimizeBinary_le (w : Word) (o : BinOp) (a b : Expr) :
    nb (optimizeBinary w o a b) ≤ max (nb a) (nb b) ∧
      (optimizeBinary w o a b).temps ≤ max a.temps (b.temps + 1) := by
  unfold optimizeBinary
  split
  · split
    · unfold optimizeBoth; split <;> simp [Expr.temps]
    · unfold optimizeLeft
      split
      · simp [Expr.temps]
      · split
        · omega
        · simp [Expr.temps]
  · split
    · unfold optimizeRight
      split
      · simp [Expr.temps]
      · split
        · omega
        · simp [Expr.temps]
    · simp [Expr.temps]

theorem optimizeCompare_le (w : Word) (o : CmpOp) (a b : Expr) :
    nb (optimizeCompare w o a b) ≤ max (nb a) (nb b) ∧
      (optimizeCompare w o a b).temps ≤ max a.temps (b.temps + 1) := by
  unfold optimizeCompare
  split
  · split <;> simp [Expr.temps]
  · simp [Expr.temps]

theorem optimize_le : ∀ e : Expr, nb e.optimize ≤ nb e ∧ e.optimize.temps ≤ e.temps
  | .lit v => by simp [Expr.optimize, Expr.temps]
  | .var index => by simp [Expr.optimize, Expr.temps]
  | .neg a => by
    have := optimize_le a; have := optimizeNeg_le a.optimize
    simp only [Expr.optimize, nb_Expr_neg, Expr.temps]; omega
  | .binary w o a b => by
    have := optimize_le a; have := optimize_le b
    have := optimizeBinary_le w o a.optimize b.optimize
    simp only [Expr.optimize, nb_Expr_binary, Expr.temps]; omega
  | .compare w o a b => by
    have := optimize_le a; have := optimize_le b
    have := optimizeCompare_le w o a.optimize b.optimize
    simp only [Expr.optimize, nb_Expr_compare, Expr.temps]; omega
  | .fp o a b => by
    have := optimize_le a; have := optimize_le b
    simp only [Expr.optimize, nb_Expr_fp, Expr.temps]; omega

/-- An expression read with the facts and folded. -/
theorem read_le {B : Nat} {facts : List Fact} (good : Good B facts) (e : Expr) :
    nb (e.subst facts).optimize ≤ max B (nb e) ∧ (e.subst facts).optimize.temps ≤ e.temps := by
  have := subst_good good e; have := optimize_le (e.subst facts); omega

theorem readAll_le {B : Nat} {facts : List Fact} (good : Good B facts) : ∀ (args : List Expr) (k : Nat),
    nb (optimizeAll (substAll args facts)) ≤ max B (nb args) ∧
      argsTemps (optimizeAll (substAll args facts)) k ≤ argsTemps args k
  | [], k => by simp [substAll, optimizeAll, argsTemps]
  | a :: rest, k => by
    have := read_le good a; have := readAll_le good rest (k + 1)
    simp only [substAll, optimizeAll, nb_cons, argsTemps]; omega

theorem assigned_good {B : Nat} {facts : List Fact} (good : Good B facts) {index : Nat} {value : Expr}
    (hi : index ≤ B) (hv : nb value ≤ B) : Good B (assigned facts index value) := by
  unfold assigned
  dsimp only
  split
  · rename_i atom
    simp only [Bool.and_eq_true] at atom
    intro fact m
    rcases List.mem_cons.mp m with same | m
    · subst same
      have := subst_good good value
      refine ⟨hi, by simp only; omega, ?_⟩
      have := atom.1
      simp only
      generalize value.subst facts = known at this
      cases known <;> simp_all [Expr.isAtom, Expr.temps]
    · exact good_killShared good index fact (mem_trimFacts m)
  · exact good_killShared good index

theorem factsAfter_good {B : Nat} : ∀ (s : Stmt) {facts : List Fact}, Good B facts → nb s ≤ B →
    Good B (s.factsAfter facts)
  | .skip, _, good, _ => good
  | .assign index value, _, good, h => by
    simp only [nb_Stmt_assign, nb_nat] at h
    exact assigned_good good (by omega) (by omega)
  | .seq a b, _, good, h => by
    simp only [nb_Stmt_seq] at h
    exact factsAfter_good b (factsAfter_good a good (by omega)) (by omega)
  | .ite c t e, _, _, _ => good_nil B
  | .loop c b, _, _, _ => good_nil B
  | .call t n f a, _, _, _ => good_nil B
  | .ret v, _, _, _ => good_nil B
  | .brk, _, _, _ => good_nil B
  | .cont, _, _, _ => good_nil B
  | .alloc t sh sz, _, good, _ => good_killShared good t
  | .loadByte t a, _, good, _ => good_killShared good t
  | .storeByte a v, _, good, _ => good
  | .loadWord w t a, _, good, _ => good_killShared good t
  | .storeWord w a v, _, good, _ => good
  | .divide w o t l r, _, good, _ => good_killShared good t
  | .sys c t a, _, _, _ => good_nil B
  | .frame t b, _, good, _ => good_killShared good t
  | .static t o, _, good, _ => good_killShared good t

theorem optimizeSeq_le (a b : Stmt) :
    nb (optimizeSeq a b) ≤ max (nb a) (nb b) ∧ (optimizeSeq a b).temps ≤ max a.temps b.temps := by
  unfold optimizeSeq
  split
  · omega
  · split
    · omega
    · simp [Stmt.temps]

theorem optimizeIte_le (c : Expr) (t e : Stmt) :
    nb (optimizeIte c t e) ≤ max (nb c) (max (nb t) (nb e)) ∧
      (optimizeIte c t e).temps ≤ max c.temps (max t.temps e.temps) := by
  unfold optimizeIte
  split
  · unfold pickBranch; split <;> omega
  · unfold iteOrSkip; split <;> simp [Stmt.temps]

theorem optimizeLoop_le (c : Expr) (b : Stmt) :
    nb (optimizeLoop c b) ≤ max (nb c) (nb b) ∧ (optimizeLoop c b).temps ≤ max c.temps b.temps := by
  unfold optimizeLoop
  split
  · unfold loopUnlessZero; split <;> simp [Stmt.temps]
  · simp [Stmt.temps]

theorem optimizeAssign_le (index : Nat) (v : Expr) :
    nb (optimizeAssign index v) ≤ max index (nb v) ∧ (optimizeAssign index v).temps ≤ v.temps := by
  unfold optimizeAssign
  split <;> simp [Stmt.temps]

theorem stmt_le {B : Nat} : ∀ (s : Stmt) {facts : List Fact}, Good B facts → nb s ≤ B →
    nb (s.optimize facts) ≤ B ∧ (s.optimize facts).temps ≤ s.temps
  | .skip, _, _, _ => by simp [Stmt.optimize, Stmt.temps]
  | .assign index value, facts, good, h => by
    have := read_le good value
    have := optimizeAssign_le index (value.subst facts).optimize
    simp only [nb_Stmt_assign, nb_nat] at h
    simp only [Stmt.optimize, Stmt.temps]; omega
  | .seq a b, facts, good, h => by
    simp only [nb_Stmt_seq] at h
    have ha := stmt_le a good (by omega)
    have hb := stmt_le b (factsAfter_good a good (by omega)) (by omega)
    have := optimizeSeq_le (a.optimize facts) (b.optimize (a.factsAfter facts))
    simp only [Stmt.optimize, Stmt.temps]
    split <;> omega
  | .ite c t e, facts, good, h => by
    simp only [nb_Stmt_ite] at h
    have := read_le good c
    have := stmt_le t good (by omega)
    have := stmt_le e good (by omega)
    have := optimizeIte_le (c.subst facts).optimize (t.optimize facts) (e.optimize facts)
    simp only [Stmt.optimize, Stmt.temps]; omega
  | .loop c b, _, _, h => by
    simp only [nb_Stmt_loop] at h
    have := optimize_le c
    have := stmt_le b (good_nil B) (by omega)
    have := optimizeLoop_le c.optimize (b.optimize [])
    simp only [Stmt.optimize, Stmt.temps]; omega
  | .call t n f a, _, good, h => by
    have := readAll_le good a 0
    simp only [nb_Stmt_call, nb_nat] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_call, nb_nat]; omega
  | .ret v, _, good, h => by
    have := readAll_le good v 0
    simp only [nb_Stmt_ret] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_ret]; omega
  | .brk, _, _, _ => by simp [Stmt.optimize, Stmt.temps]
  | .cont, _, _, _ => by simp [Stmt.optimize, Stmt.temps]
  | .alloc t sh sz, _, good, h => by
    have := read_le good sz
    simp only [nb_Stmt_alloc, nb_nat] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_alloc, nb_nat]; omega
  | .loadByte t a, _, good, h => by
    have := read_le good a
    simp only [nb_Stmt_loadByte, nb_nat] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_loadByte, nb_nat]; omega
  | .storeByte a v, _, good, h => by
    have := read_le good a; have := read_le good v
    simp only [nb_Stmt_storeByte] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_storeByte]; omega
  | .loadWord w t a, _, good, h => by
    have := read_le good a
    simp only [nb_Stmt_loadWord, nb_nat] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_loadWord, nb_nat]; omega
  | .storeWord w a v, _, good, h => by
    have := read_le good a; have := read_le good v
    simp only [nb_Stmt_storeWord] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_storeWord]; omega
  | .divide w o t l r, _, good, h => by
    have := read_le good l; have := read_le good r
    simp only [nb_Stmt_divide, nb_nat] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_divide, nb_nat]; omega
  | .sys c t a, _, good, h => by
    have := readAll_le good a 0
    simp only [nb_Stmt_sys, nb_nat] at h
    simp only [Stmt.optimize, Stmt.temps, nb_Stmt_sys, nb_nat]; omega
  | .frame t b, _, _, h => by
    simp only [Stmt.optimize, Stmt.temps]; exact ⟨h, Nat.le_refl _⟩
  | .static t o, _, _, h => by
    simp only [Stmt.optimize, Stmt.temps]; exact ⟨h, Nat.le_refl _⟩

theorem funcs_le : ∀ funcs : List Func,
    nb (optimizeFuncs funcs) ≤ nb funcs ∧ funcsTemps (optimizeFuncs funcs) ≤ funcsTemps funcs
  | [] => by simp [optimizeFuncs, funcsTemps]
  | f :: rest => by
    have := funcs_le rest
    have := stmt_le f.body (good_nil (nb f.body)) (Nat.le_refl _)
    have := nb_le_Func_body f; have := nb_le_Func_params f
    have := nb_le_Func_results f; have := nb_le_Func_locals f
    have nf : nb f = max (nb f.params) (max (nb f.results) (max (nb f.locals) (nb f.body))) := rfl
    simp only [optimizeFuncs, funcsTemps, nb_cons, nb_Func_mk]; omega

end Lanius.Open.OptimizeKeepsNumbers

theorem Lanius.Open.OptimizeKeepsNumbers.proof : Lanius.Open.OptimizeKeepsNumbers := by
  intro p
  exact Lanius.Open.OptimizeKeepsNumbers.funcs_le p.funcs
