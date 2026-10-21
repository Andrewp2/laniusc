import Lanius.Mini.Semantics

/-! The abstract target: an accumulator (eax) and frame slots. Each `Instr` is
one fixed byte sequence of the real backend (`Lanius.Mini.Bytes`), so the x86
proof is one lemma per constructor and this level carries the compiler logic. -/

namespace Lanius.Mini

inductive Instr where
  /-- `mov eax, imm32` -/
  | imm (value : BitVec 32)
  /-- `mov eax, [rbp - 8 * (slot + 1)]` -/
  | load (slot : Nat)
  /-- `mov [rbp - 8 * (slot + 1)], eax` -/
  | store (slot : Nat)
  /-- `neg eax` -/
  | neg
  /-- `mov ecx, eax; mov eax, [slot]; op eax, ecx`: eax := slot `op` eax -/
  | op (operation : BinOp) (slot : Nat)
  /-- frame epilogue and `ret`, returning eax -/
  | ret
  deriving DecidableEq, Repr

structure Machine where
  acc : BitVec 32
  slots : Nat → BitVec 32

def Machine.store (m : Machine) (slot : Nat) : Machine :=
  { m with slots := fun other => if other = slot then m.acc else m.slots other }

/-- Effect of a non-returning instruction; `ret` is handled by `Instr.run`. -/
def Instr.step : Instr → Machine → Machine
  | .imm value, m => { m with acc := value }
  | .load slot, m => { m with acc := m.slots slot }
  | .store slot, m => m.store slot
  | .neg, m => { m with acc := -m.acc }
  | .op operation slot, m => { m with acc := operation.apply (m.slots slot) m.acc }
  | .ret, m => m

/-- Straight-line execution of code that contains no `ret`. -/
def Instr.exec (code : List Instr) (m : Machine) : Machine := code.foldl (fun m i => i.step m) m

/-- The value the code returns at its first `ret`, or `none` if it has none. -/
def Instr.run : List Instr → Machine → Option (BitVec 32)
  | [], _ => none
  | .ret :: _, m => some m.acc
  | i :: rest, m => Instr.run rest (i.step m)

theorem Instr.run_cons (i : Instr) (rest : List Instr) (m : Machine) (notRet : i ≠ .ret) :
    Instr.run (i :: rest) m = Instr.run rest (i.step m) := by
  cases i <;> first | exact absurd rfl notRet | rfl

theorem Instr.exec_singleton (i : Instr) (m : Machine) : Instr.exec [i] m = i.step m := rfl

theorem Instr.exec_append (first second : List Instr) (m : Machine) :
    Instr.exec (first ++ second) m = Instr.exec second (Instr.exec first m) := by
  simp [Instr.exec, List.foldl_append]

/-- Running code with no `ret` prefix runs the rest from the prefix's result. -/
theorem Instr.run_append (first second : List Instr) (m : Machine)
    (noRet : Instr.ret ∉ first) :
    Instr.run (first ++ second) m = Instr.run second (Instr.exec first m) := by
  induction first generalizing m with
  | nil => rfl
  | cons i rest ih =>
    have notRet : i ≠ .ret := fun same => noRet (same ▸ List.mem_cons_self ..)
    have restNoRet : Instr.ret ∉ rest := fun mem => noRet (List.mem_cons_of_mem _ mem)
    cases i <;> first | exact absurd rfl notRet | exact ih _ restNoRet

end Lanius.Mini
