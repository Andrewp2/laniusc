import Lanius.X86.Machine.Block
import Lanius.X86.Machine.AluEncoding
import Lanius.X86.Machine.ScalarEncoding
import Lanius.X86.Machine.NonDivEncoding
import Lanius.X86.LiteralReturn

namespace Lanius.X86.ScalarValidator

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine

/-!
  A small, deliberately syntax-directed certificate for the scalar atom
  fragment.

  `Expr` is not another backend implementation.  It is the proof witness for
  the subset of Core expressions for which the current x86 emitter has a
  direct lowering covered by the existing machine proofs.  The checker below
  reconstructs this witness from a Core body, and authenticates the complete
  emitted byte string against its canonical lowering.

  Composite expression lowering is intentionally rejected here.  The actual
  backend evaluates the left operand first, saves it in a prologue-relative
  frame slot, evaluates the right operand, and then uses `RCX` plus
  `operation::from_slot`; it is not the tempting right-first register-only
  sequence.  A compositional checker must model that frame protocol and the
  patched prologue size before accepting composite bytes.  Division, remainder,
  shifts, comparisons, short-circuit booleans, calls, memory, and control flow
  are likewise outside this atom certificate.
-/

def resultRegister : Register := 0
def stackRegister : Register := 4

inductive Expr where
  | lit (literal : LiteralReturn.Literal)
  | var (id : VarId) (register : Register)

def Expr.ty : Expr → Ty
  | Expr.lit literal => literal.ty
  | Expr.var _ _ => .scalar (.signed .i32)

def Expr.core : Expr → Core.Expr
  | Expr.lit literal => .value literal.value
  | Expr.var id _ => .local id

def Expr.bytes : Expr → List UInt8
  | Expr.lit literal => Machine.immediateBytes .w32 resultRegister literal.bits 0
  | Expr.var _ register => Machine.moveBytes .w32 resultRegister register

def Expr.returnBytes (expression : Expr) : List UInt8 :=
  expression.bytes ++ Machine.returnBytes

private def literalOfValue? (value : Value) :
    Option { literal : LiteralReturn.Literal // literal.value = value } :=
  match value with
  | .signed .i32 number =>
      if bounds : -2147483648 ≤ number ∧ number < 2147483648 then
        some ⟨.i32 (BitVec.ofInt 32 number), by
          simp [LiteralReturn.Literal.value,
            LiteralReturn.i32_ofInt_toInt number bounds.1 bounds.2]⟩
      else none
  | .boolean value => some ⟨.bool value, by simp [LiteralReturn.Literal.value]⟩
  | _ => none

mutual
  def fromCore? (registerOf : VarId → Option Register)
      (source : Core.Expr) : Option { expression : Expr // expression.core = source } :=
    match source with
    | .value value => (literalOfValue? value).map fun literal =>
        ⟨Expr.lit literal.1, by simp [Expr.core, literal.2]⟩
    | .local id => do
        let register ← registerOf id
        if register = resultRegister || register = stackRegister || register ∈ [10, 11, 12, 13, 14, 15]
        then none else some ⟨Expr.var id register, rfl⟩
    | .unary _ _ => none
    | .binary _ _ _ => none
    | _ => none
end

structure Supported (function : Function) where
  expression : Expr
  bodyExact : function.body = some (.returnValue (some expression.core))
  resultType : function.returnType = expression.ty
  internal : function.external = none
  parametersI32 : ∀ parameter ∈ function.parameters,
    parameter.2 = .scalar (.signed .i32)

private def shape? (function : Function) (registerOf : VarId → Option Register) :
    Option (Supported function) :=
  match function with
  | ⟨_, parameters, returnType, some (.returnValue (some expression)), none⟩ =>
      match fromCore? registerOf expression with
      | some expression' =>
          if resultType : returnType = expression'.1.ty then
            if parametersI32 : ∀ parameter ∈ parameters,
                parameter.2 = .scalar (.signed .i32) then
              some ⟨expression'.1, by simp [expression'.2], resultType, rfl,
                parametersI32⟩
            else none
          else none
      | none => none
  | _ => none

structure Checked (function : Function) (emitted : List UInt8) where
  supported : Supported function
  bytesExact : emitted = supported.expression.returnBytes

def check (function : Function) (registerOf : VarId → Option Register)
    (emitted : List UInt8) : Option (Checked function emitted) :=
  match shape? function registerOf with
  | none => none
  | some supported =>
      if bytesExact : emitted = supported.expression.returnBytes then
        some ⟨supported, bytesExact⟩
      else none

theorem check_sound {function : Function} {registerOf : VarId → Option Register}
    {emitted : List UInt8} {checked : Checked function emitted}
    (accepted : check function registerOf emitted = some checked) :
    emitted = checked.supported.expression.returnBytes := by
  unfold check at accepted
  split at accepted
  next _ => simp at accepted
  next supported =>
    split at accepted
    next bytesExact => cases accepted; exact bytesExact
    next _ => simp at accepted

def Represented (before : Machine.State) (register : Register) (bits : BitVec 32) : Prop :=
  (before.registers register).setWidth 32 = bits

/- The connected preservation theorem for the closed scalar subset.  It is
   derived from the authenticated bytes and the existing immediate/return
   decode and machine-step lemmas; no post-state result is assumed. -/
theorem literalPreserves (literal : LiteralReturn.Literal) (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip
      (Expr.returnBytes (.lit literal)))
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 before.memory (before.registers 4) = returnAddress) :
    ∃ middle after, Machine.Step before middle ∧ Machine.Step middle after ∧
      after.registers resultRegister = literal.bits.setWidth 64 ∧
      (after.registers resultRegister).setWidth 32 = literal.bits ∧
      LiteralReturn.RaxMatches literal.value
        ((after.registers resultRegister).setWidth 32) ∧
      after.rip = returnAddress ∧ after.registers 4 = before.registers 4 + 8 ∧
      (∀ register, register ≠ resultRegister → register ≠ 4 →
        after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags := by
  have exactBytes : Expr.returnBytes (.lit literal) = LiteralReturn.bytes literal := rfl
  rw [exactBytes] at loaded
  obtain ⟨middle, after, first, second, result, target, stack, frame, memory, flags⟩ :=
    LiteralReturn.machine_returns literal before loaded
  obtain ⟨frameRegs, memoryState, flagsState⟩ := flags
  refine ⟨middle, after, first, second, result, ?_, ?_, frame.trans poppedReturn, memory,
    frameRegs, memoryState, flagsState⟩
  · simpa [resultRegister] using target
  · simpa [resultRegister] using stack

/- A parameter/local atom has the same fully-derived machine theorem.  This
   keeps the register representation an initial-state premise, rather than a
   claimed result in a certificate.  Composite expressions are rejected by
   `fromCore?` until the actual backend frame-slot protocol is modeled. -/
theorem localPreserves (id : VarId) (register : Register) (bits : BitVec 32)
    (before : Machine.State)
    (represented : Represented before register bits)
    (loaded : Machine.CodeAt before.memory before.rip
      (Expr.returnBytes (.var id register)))
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 before.memory (before.registers 4) = returnAddress) :
    ∃ middle after, Machine.Step before middle ∧ Machine.Step middle after ∧
      after.registers resultRegister = bits.setWidth 64 ∧
      after.rip = returnAddress ∧ after.registers 4 = before.registers 4 + 8 ∧
      (∀ other, other ≠ resultRegister → other ≠ 4 →
        after.registers other = before.registers other) ∧
      after.memory = before.memory ∧ after.flags = before.flags := by
  let move := Machine.moveBytes .w32 resultRegister register
  let middle := before.move32 resultRegister register move.length
  let after := middle.returnNear
  have moveLoaded : Machine.CodeAt before.memory before.rip move := by
    simpa [Expr.returnBytes, Expr.bytes, move] using loaded.prefix
  have first := Machine.move_step before middle .w32 resultRegister register moveLoaded (by rfl)
  have returnLoaded : Machine.CodeAt middle.memory middle.rip Machine.returnBytes := by
    simpa [middle, move, Expr.returnBytes, Expr.bytes, Machine.State.move32,
      resultRegister] using loaded.suffix
  have second := Machine.return_step middle after returnLoaded (by rfl)
  refine ⟨middle, after, first, second, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · have movedValue : middle.registers resultRegister = bits.setWidth 64 := by
      simpa [middle, Machine.State.move32, resultRegister] using
        congrArg (fun value : BitVec 32 => value.setWidth 64) represented
    simpa [after, middle, Machine.State.returnNear, Machine.State.move32,
      resultRegister] using movedValue
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32,
      resultRegister, poppedReturn]
  · simp [after, middle, Machine.State.returnNear, Machine.State.move32,
      resultRegister]
  · intro other notResult notStack
    have notResult' : other ≠ 0 := by simpa [resultRegister] using notResult
    simp [after, middle, Machine.State.returnNear, Machine.State.move32, resultRegister,
      notResult', notStack]
  · rfl
  · rfl

end Lanius.X86.ScalarValidator
