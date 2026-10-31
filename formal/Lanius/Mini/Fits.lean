import Lanius.Mini.CompileCorrect

/-! Static facts the x86 proof needs about compiled code: every slot is inside
the frame, every jump target is inside the function, every callee is in the
program. -/

namespace Lanius.Mini

def Instr.Fits (slots bound funcs : Nat) : Instr → Prop
  | .imm _ | .neg | .loadAt | .loadWordAt _ => True
  | .load slot | .store slot | .op _ _ slot | .cmp _ _ slot | .storeAt slot | .storeWordAt _ slot | .div _ _ slot =>
      slot < slots
  | .bump shift => shift < 32
  | .jmp target | .jz target => target ≤ bound
  | .call callee args target count => callee < funcs ∧ args.length ≤ slots ∧ (∀ slot ∈ args, slot < slots) ∧
      target + count ≤ slots ∧ 0 < count
  | .ret sources => ∀ slot ∈ sources, slot < slots ∧ sources.length ≤ slot
  | .sys _ slot => slot + 3 ≤ slots

theorem Instr.Fits.mono {i : Instr} {slots slots' bound bound' funcs : Nat} (fits : i.Fits slots bound funcs)
    (moreSlots : slots ≤ slots') (moreBound : bound ≤ bound') : i.Fits slots' bound' funcs := by
  cases i with
  | imm | neg | loadAt | loadWordAt => trivial
  | load | store | op | cmp | storeAt | storeWordAt | div => simp only [Instr.Fits] at fits ⊢; omega
  | bump => exact fits
  | jmp | jz => simp only [Instr.Fits] at fits ⊢; omega
  | call callee args target count =>
    exact ⟨fits.1, by have := fits.2.1; omega, fun slot inArgs => by have := fits.2.2.1 slot inArgs; omega,
      by have := fits.2.2.2.1; omega, fits.2.2.2.2⟩
  | ret sources =>
    exact fun slot mem => ⟨by have := (fits slot mem).1; omega, (fits slot mem).2⟩
  | sys => simp only [Instr.Fits] at fits ⊢; omega

theorem compileExpr_fits (base : Nat) (e : Expr) (depth : Nat) (within : e.within base = true)
    (bound funcs : Nat) : ∀ i ∈ compileExpr base e depth, i.Fits (base + depth + e.temps) bound funcs := by
  induction e generalizing depth with
  | lit => simp [compileExpr, Instr.Fits]
  | var index =>
    simp only [Expr.within, decide_eq_true_eq] at within
    simp only [compileExpr, List.mem_singleton, forall_eq, Instr.Fits]
    omega
  | neg operand ih =>
    simp only [compileExpr, List.mem_append, List.mem_singleton]
    rintro i (inner | rfl)
    · exact ih depth within i inner
    · trivial
  | binary _ _ left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    simp only [compileExpr, List.mem_append, List.mem_singleton, Expr.temps]
    rintro i (((inLeft | rfl) | inRight) | rfl)
    · exact (ihLeft depth within.1 i inLeft).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (ihRight (depth + 1) within.2 i inRight).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
  | compare _ _ left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    simp only [compileExpr, List.mem_append, List.mem_singleton, Expr.temps]
    rintro i (((inLeft | rfl) | inRight) | rfl)
    · exact (ihLeft depth within.1 i inLeft).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (ihRight (depth + 1) within.2 i inRight).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega

theorem argsTemps_head (arg : Expr) (rest : List Expr) (k : Nat) :
    k + 1 + arg.temps ≤ argsTemps (arg :: rest) k ∧ argsTemps rest (k + 1) ≤ argsTemps (arg :: rest) k := by
  simp only [argsTemps]; omega

theorem compileArgs_fits (base : Nat) (args : List Expr) (k : Nat) (within : allWithin base args = true)
    (bound funcs : Nat) : ∀ i ∈ compileArgs base args k, i.Fits (base + argsTemps args k) bound funcs := by
  induction args generalizing k with
  | nil => simp [compileArgs]
  | cons arg rest ih =>
    simp only [allWithin, Bool.and_eq_true] at within
    have bounds := argsTemps_head arg rest k
    simp only [compileArgs, List.mem_append, List.mem_singleton]
    rintro i ((inArg | rfl) | inRest)
    · exact (compileExpr_fits base arg (k + 1) within.1 bound funcs i inArg).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (ih (k + 1) within.2 i inRest).mono (by omega) (Nat.le_refl _)

theorem argSlots_fit (base : Nat) (args : List Expr) (k : Nat) :
    ∀ slot ∈ argSlots base args k, slot < base + argsTemps args k := by
  induction args generalizing k with
  | nil => simp [argSlots]
  | cons arg rest ih =>
    have bounds := argsTemps_head arg rest k
    simp only [argSlots, List.mem_cons]
    rintro slot (rfl | inRest)
    · omega
    · have := ih (k + 1) slot inRest; omega

theorem argsTemps_length (args : List Expr) (k : Nat) (nonempty : args ≠ []) :
    k + args.length ≤ argsTemps args k := by
  induction args generalizing k with
  | nil => contradiction
  | cons arg rest ih =>
    simp only [argsTemps, List.length_cons]
    cases rest with
    | nil => simp [argsTemps]
    | cons next more =>
      have := ih (k + 1) (by simp)
      simp only [List.length_cons] at this ⊢
      omega

theorem argSlots_count (base : Nat) (args : List Expr) : (argSlots base args 0).length ≤ base + argsTemps args 0 := by
  rw [argSlots_length]
  cases args with
  | nil => simp
  | cons arg rest => have := argsTemps_length (arg :: rest) 0 (by simp); omega

theorem argSlots_ge (base : Nat) (args : List Expr) (k : Nat) :
    ∀ slot ∈ argSlots base args k, base + k ≤ slot := by
  induction args generalizing k with
  | nil => simp [argSlots]
  | cons arg rest ih =>
    simp only [argSlots, List.mem_cons]
    rintro slot (rfl | inRest)
    · omega
    · have := ih (k + 1) slot inRest; omega

theorem compileStmt_fits (base : Nat) (arities : List Arity) {results : Nat} (resultsFit : results ≤ base)
    (stmt : Stmt) (pos : Nat) (within : stmt.within base arities results = true) :
    ∀ i ∈ compileStmt base pos stmt,
      i.Fits (base + stmt.temps) (pos + codeSize (compileStmt base pos stmt)) arities.length := by
  induction stmt generalizing pos with
  | skip => simp [compileStmt]
  | assign index value =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt, List.mem_append, List.mem_singleton, Stmt.temps]
    rintro i (inValue | rfl)
    · exact (compileExpr_fits base value 0 within.2 _ _ i inValue).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
  | seq first second ihFirst ihSecond =>
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt, List.mem_append, Stmt.temps, codeSize_append]
    rintro i (inFirst | inSecond)
    · exact (ihFirst pos within.1 i inFirst).mono (by omega) (by omega)
    · exact (ihSecond _ within.2 i inSecond).mono (by omega) (by omega)
  | ite condition thenBranch elseBranch ihThen ihElse =>
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt, List.mem_append, List.mem_singleton, Stmt.temps, codeSize_append, codeSize,
      Instr.size]
    rintro i ((((inCondition | rfl) | inThen) | rfl) | inElse)
    · exact (compileExpr_fits base condition 0 within.1.1 _ _ i inCondition).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (ihThen _ within.1.2 i inThen).mono (by omega) (by omega)
    · simp only [Instr.Fits]; omega
    · exact (ihElse _ within.2 i inElse).mono (by omega) (by omega)
  | loop condition body ihBody =>
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt, List.mem_append, List.mem_singleton, Stmt.temps, codeSize_append, codeSize,
      Instr.size]
    rintro i (((inCondition | rfl) | inBody) | rfl)
    · exact (compileExpr_fits base condition 0 within.1 _ _ i inCondition).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (ihBody _ within.2 i inBody).mono (by omega) (by omega)
    · simp only [Instr.Fits]; omega
  | call target count callee args =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq, arityIs_eq] at within
    obtain ⟨⟨⟨fit, positive⟩, ⟨arity, found, -, -⟩⟩, argsWithin⟩ := within
    have calleeBound : callee < arities.length := (List.getElem?_eq_some_iff.mp found).1
    simp only [compileStmt, List.mem_append, List.mem_cons, List.not_mem_nil, or_false, Stmt.temps]
    rintro i (inArgs | rfl)
    · exact compileArgs_fits base args 0 argsWithin _ _ i inArgs
    · exact ⟨calleeBound, argSlots_count base args, argSlots_fit base args 0, by omega, positive⟩
  | ret values =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt, List.mem_append, List.mem_singleton, Stmt.temps]
    rintro i (inValues | rfl)
    · exact compileArgs_fits base values 0 within.2 _ _ i inValues
    · intro slot mem
      refine ⟨argSlots_fit base values 0 slot mem, ?_⟩
      have := argSlots_ge base values 0 slot mem
      rw [argSlots_length]
      omega
  | alloc target shift size =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt, List.mem_append, List.mem_cons, List.not_mem_nil, or_false, Stmt.temps]
    rintro i (inSize | rfl | rfl)
    · exact (compileExpr_fits base size 0 within.2 _ _ i inSize).mono (by omega) (Nat.le_refl _)
    · exact within.1.2
    · simp only [Instr.Fits]; omega
  | loadByte target address =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt, List.mem_append, List.mem_cons, List.not_mem_nil, or_false, Stmt.temps]
    rintro i (inAddress | rfl | rfl)
    · exact (compileExpr_fits base address 0 within.2 _ _ i inAddress).mono (by omega) (Nat.le_refl _)
    · trivial
    · simp only [Instr.Fits]; omega
  | storeByte address value =>
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt, List.mem_append, List.mem_singleton, Stmt.temps]
    rintro i ((inAddress | rfl) | inValue | rfl)
    · exact (compileExpr_fits base address 0 within.1 _ _ i inAddress).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (compileExpr_fits base value 1 within.2 _ _ i inValue).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
  | loadWord width target address =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt, List.mem_append, List.mem_cons, List.not_mem_nil, or_false, Stmt.temps]
    rintro i (inAddress | rfl | rfl)
    · exact (compileExpr_fits base address 0 within.2 _ _ i inAddress).mono (by omega) (Nat.le_refl _)
    · trivial
    · simp only [Instr.Fits]; omega
  | storeWord width address value =>
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt, List.mem_append, List.mem_singleton, Stmt.temps]
    rintro i ((inAddress | rfl) | inValue | rfl)
    · exact (compileExpr_fits base address 0 within.1 _ _ i inAddress).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (compileExpr_fits base value 1 within.2 _ _ i inValue).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
  | divide word operation target left right =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt, List.mem_append, List.mem_cons, List.mem_singleton, List.not_mem_nil, or_false,
      Stmt.temps]
    rintro i (((inLeft | rfl) | inRight) | rfl | rfl)
    · exact (compileExpr_fits base left 0 within.1.2 _ _ i inLeft).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · exact (compileExpr_fits base right 1 within.2 _ _ i inRight).mono (by omega) (Nat.le_refl _)
    · simp only [Instr.Fits]; omega
    · simp only [Instr.Fits]; omega
  | sys kind target args =>
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    obtain ⟨⟨below, len⟩, argsWithin⟩ := within
    have three := argsTemps_length args 0 (by intro empty; rw [empty] at len; simp at len)
    simp only [compileStmt, List.mem_append, List.mem_cons, List.not_mem_nil, or_false, Stmt.temps]
    rintro i (inArgs | rfl | rfl)
    · exact compileArgs_fits base args 0 argsWithin _ _ i inArgs
    · simp only [Instr.Fits]; omega
    · simp only [Instr.Fits]; omega

theorem zeroLocals_fits (first count : Nat) (bound funcs : Nat) :
    ∀ i ∈ zeroLocals first count, i.Fits (first + count) bound funcs := by
  induction count generalizing first with
  | zero => simp [zeroLocals_zero]
  | succ count ih =>
    simp only [zeroLocals_succ, List.mem_cons]
    rintro i (rfl | inRest)
    · simp only [Instr.Fits]; omega
    · exact (ih (first + 1) i inRest).mono (by omega) (Nat.le_refl _)

theorem compileFunc_fits {arities : List Arity} {func : Func} {code : Code}
    (compiled : compileFunc arities func = some code) :
    ∀ i ∈ code.instrs, i.Fits code.slots (codeSize code.instrs) arities.length := by
  obtain ⟨paramsFit, within, slots, -, instrs, -, resultsFit⟩ := compileFunc_spec compiled
  rw [instrs, slots]
  simp only [List.mem_append, List.mem_cons]
  rintro i ((rfl | inInit) | inBody)
  · trivial
  · exact (zeroLocals_fits _ _ _ _ i inInit).mono (by omega) (Nat.le_refl _)
  · exact (compileStmt_fits _ _ resultsFit _ _ within i inBody).mono (Nat.le_refl _)
      (by rw [codeSize_append]; omega)

end Lanius.Mini
