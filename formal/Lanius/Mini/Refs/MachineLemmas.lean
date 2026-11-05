module

public import Lanius.Mini.Refs.Machine
public import Lanius.Mini.Stops
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

@[expose] public section

/-! # References: the code templates are within the locals (F5) -/

namespace Lanius.Mini

theorem addOff_within {r base : Nat} (off : Nat) (lt : r < base) :
    (addOff r off).within base = true ∧ (addOff r off).temps = 1 := by
  simp [addOff, Expr.within, Expr.temps, lt]

theorem SrcType.loadsFrom_within (ty : SrcType) {r target base : Nat} {arities : List Arity} {results : Nat}
    (lt : r < base) : ∀ (count s : Nat), (∀ i, s ≤ i → i < s + count → target + i < base) →
      (ty.loadsFrom r target s count).within base arities results = true ∧ (ty.loadsFrom r target s count).temps ≤ 1
  | 0, s, _ => by simp [SrcType.loadsFrom, Stmt.within, Stmt.temps]
  | count + 1, s, fits => by
    obtain ⟨w, t⟩ := addOff_within (ty.refSlotAt s).1 lt
    obtain ⟨ih1, ih2⟩ := SrcType.loadsFrom_within ty (arities := arities) (results := results) lt count (s + 1) fun i lo hi => fits i (by omega) (by omega)
    have here := fits s (Nat.le_refl _) (by omega)
    simp only [SrcType.loadsFrom, Stmt.within, Stmt.temps]
    refine ⟨?_, Nat.max_le.mpr ⟨?_, ih2⟩⟩
    · cases (ty.refSlotAt s).2 <;> simp [Access.load, Stmt.within, w, here, ih1]
    · cases (ty.refSlotAt s).2 <;> simp [Access.load, Stmt.temps, t]

theorem SrcType.storesFrom_within (ty : SrcType) {r slot base : Nat} {arities : List Arity} {results : Nat}
    (lt : r < base) : ∀ (count s : Nat), (∀ i, s ≤ i → i < s + count → slot + i < base) →
      (ty.storesFrom r slot s count).within base arities results = true ∧ (ty.storesFrom r slot s count).temps ≤ 1
  | 0, s, _ => by simp [SrcType.storesFrom, Stmt.within, Stmt.temps]
  | count + 1, s, fits => by
    obtain ⟨w, t⟩ := addOff_within (ty.refSlotAt s).1 lt
    obtain ⟨ih1, ih2⟩ := SrcType.storesFrom_within ty (arities := arities) (results := results) lt count (s + 1) fun i lo hi => fits i (by omega) (by omega)
    have here := fits s (Nat.le_refl _) (by omega)
    simp only [SrcType.storesFrom, Stmt.within, Stmt.temps]
    refine ⟨?_, Nat.max_le.mpr ⟨?_, ih2⟩⟩
    · cases (ty.refSlotAt s).2 <;> simp [Access.store, Stmt.within, Expr.within, w, here, ih1]
    · cases (ty.refSlotAt s).2 <;> simp [Access.store, Stmt.temps, Expr.temps, t]

theorem SrcType.loadSlots_within (ty : SrcType) {r target base : Nat} {arities : List Arity} {results : Nat}
    (lt : r < base) (fits : target + ty.size ≤ base) :
    (ty.loadSlots r target).within base arities results = true ∧ (ty.loadSlots r target).temps ≤ 1 :=
  ty.loadsFrom_within lt ty.size 0 fun i _ hi => by omega

theorem SrcType.storeSlots_within (ty : SrcType) {r slot base : Nat} {arities : List Arity} {results : Nat}
    (lt : r < base) (fits : slot + ty.size ≤ base) :
    (ty.storeSlots r slot).within base arities results = true ∧ (ty.storeSlots r slot).temps ≤ 1 :=
  ty.storesFrom_within lt ty.size 0 fun i _ hi => by omega

theorem RPlace.code_within {c : RCtx} {t base : Nat} {arities : List Arity} {results : Nat} (tlt : t < base) :
    ∀ (p : RPlace) {code : Stmt} {ty : SrcType}, p.code c t = some (code, ty) → (∀ k ∈ p.slots c, k < base) →
      p.IndexesWithin base arities results →
      code.within base arities results = true ∧ code.temps ≤ max 2 p.indexTemps
  | .home id, code, ty, hcode, slots, _ => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    have := slots c.frame (by simp [RPlace.slots])
    refine ⟨by simp [Stmt.within, addOff, Expr.within, tlt, this], ?_⟩
    simp only [Stmt.temps, addOff, Expr.temps, RPlace.indexTemps]
    omega
  | .deref id, code, ty, hcode, slots, _ => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    have := slots (c.slotOf id) (by simp [RPlace.slots])
    refine ⟨by simp [Stmt.within, Expr.within, tlt, this], ?_⟩
    simp [Stmt.temps, Expr.temps]
  | .field base' f, code, ty, hcode, slots, idx => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i codeB tyB hb
    split at hcode
    · cases hcode
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    obtain ⟨w, tm⟩ := RPlace.code_within tlt base' hb (by simpa [RPlace.slots] using slots) idx
    refine ⟨by simp [Stmt.within, addOff, Expr.within, w, tlt], ?_⟩
    simp only [RPlace.indexTemps] at tm ⊢
    simp only [Stmt.temps, addOff, Expr.temps]
    omega
  | .index base' ie indexCode slot, code, ty, hcode, slots, idx => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i codeB tyB hb
    split at hcode
    · cases hcode
    rename_i length element hinfo
    split at hcode
    · cases hcode
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    obtain ⟨idxB, idxCode, slotLt⟩ := idx
    obtain ⟨w, tm⟩ := RPlace.code_within tlt base' hb (by simpa [RPlace.slots] using slots) idxB
    have ea : (elementAddr t slot length element).within base arities results = true ∧
        (elementAddr t slot length element).temps ≤ 2 := by
      unfold elementAddr
      split
      all_goals
        refine ⟨by simp [Stmt.within, Expr.within, tlt, slotLt], ?_⟩
        simp only [Stmt.temps, Expr.temps]
        omega
    obtain ⟨ea1, ea2⟩ := ea
    refine ⟨by simp [Stmt.within, refTrap, Expr.within, w, idxCode, ea1, tlt, slotLt], ?_⟩
    simp only [RPlace.indexTemps] at tm ⊢
    simp only [Stmt.temps, refTrap, Expr.temps]
    omega

end Lanius.Mini
