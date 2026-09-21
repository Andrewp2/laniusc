import Lanius.X86.Machine.Encoding
import Lanius.X86.Transport
import Lanius.Semantics.Rules

namespace Lanius.X86.LiteralReturn

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86.Transport Lanius.X86.Machine

/- A closed Core literal supported by this representative backend contract. -/
inductive Literal where
  | i32 (bits : BitVec 32)
  | bool (value : Bool)

def Literal.ty : Literal → Ty
  | .i32 _ => .scalar (.signed .i32)
  | .bool _ => .scalar .bool

def Literal.value : Literal → Value
  | .i32 bits => .signed .i32 bits.toInt
  | .bool value => .boolean value

def Literal.bits : Literal → BitVec 32
  | .i32 bits => bits
  | .bool value => BitVec.ofNat 32 (if value then 1 else 0)

def Literal.typeTag : Literal → Int
  | .i32 _ => 1
  | .bool _ => 2

def Literal.transportWord : Literal → Int
  | .i32 bits => bits.toInt
  | .bool value => if value then 1 else 0

theorem i32_transport_bounds (bits : BitVec 32) :
    -2147483648 ≤ bits.toInt ∧ bits.toInt < 2147483648 := by
  have lower := bits.le_toInt
  have upper := bits.toInt_lt
  have pow : (2 : Int) ^ 31 = 2147483648 := by decide
  simpa [pow] using And.intro lower upper

theorem i32_ofInt_toInt (value : Int)
    (lower : -2147483648 ≤ value) (upper : value < 2147483648) :
    (BitVec.ofInt 32 value).toInt = value := by
  rw [BitVec.toInt_ofInt, Int.bmod_eq_emod]
  have powNat : (2 ^ (32 : Nat) : Nat) = 4294967296 := by decide
  have pow : (2 ^ (32 : Nat) : Int) = 4294967296 := by omega
  have nonnegative : 0 ≤ value % (2 ^ (32 : Nat) : Int) :=
    Int.emod_nonneg _ (by omega)
  have below : value % (2 ^ (32 : Nat) : Int) < (2 ^ (32 : Nat) : Int) := by
    have h := Int.emod_lt value (by omega : (2 ^ (32 : Nat) : Int) ≠ 0)
    omega
  rw [pow] at nonnegative below
  simp only [powNat] at ⊢
  split <;> omega

theorem transport_word_bounds (literal : Literal) :
    -2147483648 ≤ literal.transportWord ∧ literal.transportWord < 2147483648 := by
  cases literal with
  | i32 bits => exact i32_transport_bounds bits
  | bool value => cases value <;> decide

def body (literal : Literal) : Stmt :=
  .returnValue (some (.value literal.value))

def trailingBody (literal : Literal) : Stmt :=
  .sequence (body literal) .skip

structure Supported (function : Function) where
  literal : Literal
  -- The backend transport buffer is a signed-i32 buffer; Core IDs are Nat.
  functionIdI32 : function.id < 2147483648
  zeroParameters : function.parameters = []
  resultType : function.returnType = literal.ty
  internal : function.external = none
  bodyExact : function.body = some (body literal)

/- A literal-return body does not inspect its locals, so the same machine
   preservation contract applies when the function has parameters.  This is
   intentionally separate from [Supported]: the transport theorem above is
   the closed, zero-parameter encoding, while this witness authenticates the
   executable function image after parameter lowering has already happened. -/
structure ParametersSupported (function : Function) where
  literal : Literal
  functionIdI32 : function.id < 2147483648
  resultType : function.returnType = literal.ty
  internal : function.external = none
  bodyExact : function.body = some (body literal)

structure ParametersTrailingSupported (function : Function) where
  literal : Literal
  functionIdI32 : function.id < 2147483648
  resultType : function.returnType = literal.ty
  internal : function.external = none
  bodyExact : function.body = some (trailingBody literal)

structure TrailingSupported (function : Function) where
  literal : Literal
  functionIdI32 : function.id < 2147483648
  zeroParameters : function.parameters = []
  resultType : function.returnType = literal.ty
  internal : function.external = none
  bodyExact : function.body = some (trailingBody literal)

theorem Supported.function_id_word_bounds (checked : Supported function) :
    -2147483648 ≤ Int.ofNat function.id ∧ Int.ofNat function.id < 2147483648 := by
  constructor
  · have nonnegative : 0 ≤ Int.ofNat function.id := Int.natCast_nonneg _
    omega
  · exact Int.ofNat_lt.mpr checked.functionIdI32

def immediateBytes (literal : Literal) : List UInt8 :=
  Machine.immediateBytes .w32 0 (literal.bits) 0

def bytes (literal : Literal) : List UInt8 :=
  immediateBytes literal ++ Machine.returnBytes

theorem bytes_exact (literal : Literal) :
    bytes literal = [184] ++ displacementBytes literal.bits ++ [195] := by
  have noRex : Register.value .w32 0 0 false = 0 := by decide
  simp [bytes, immediateBytes, Machine.immediateBytes, Machine.returnBytes, noRex]

def RaxMatches (value : Value) (bits : BitVec 32) : Prop :=
  match value with
  | .signed .i32 number => bits.toInt = number
  | .boolean value => bits.toInt = if value then 1 else 0
  | _ => False

theorem literal_bits_match_core (literal : Literal) :
    RaxMatches literal.value literal.bits := by
  cases literal with
  | i32 bits => rfl
  | bool value => cases value <;> simp [RaxMatches, Literal.value, Literal.bits]

theorem Supported.transport (checked : Supported function) :
    encodeFunction function = some
      [1, 64, Int.ofNat function.id, checked.literal.typeTag, 0, 5,
        10, 1, 0, checked.literal.typeTag, checked.literal.transportWord] := by
  cases literal : checked.literal with
  | i32 bits =>
      simp [encodeFunction, encodeParameters, encodeStmt, encodeExpr, encodeValue,
        typeTag, body, Literal.ty, Literal.value, checked.bodyExact, checked.resultType, checked.internal,
        checked.zeroParameters, Literal.typeTag, Literal.transportWord, literal]
  | bool value =>
      simp [encodeFunction, encodeParameters, encodeStmt, encodeExpr, encodeValue,
        typeTag, body, Literal.ty, Literal.value, checked.bodyExact, checked.resultType, checked.internal,
        checked.zeroParameters, Literal.typeTag, Literal.transportWord, literal]

theorem core_executes (literal : Literal) (program : Program)
    (before : Lanius.Semantics.State) :
    Executes program before (body literal) (.returned (some literal.value)) before := by
  refine ⟨2, ?_⟩
  exact execStmt_return 1 program before (.value literal.value) literal.value before
    (evalExpr_value 0 program before literal.value)

theorem machine_returns (literal : Literal) (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip (bytes literal)) :
    ∃ middle after, Machine.Step before middle ∧ Machine.Step middle after ∧
      after.registers 0 = (literal.bits.setWidth 64) ∧
      (after.registers 0).setWidth 32 = literal.bits ∧
      RaxMatches literal.value ((after.registers 0).setWidth 32) ∧
      after.rip = Machine.read64 before.memory (before.registers 4) ∧
      after.registers 4 = before.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags := by
  let middle := before.immediate32 0 literal.bits (immediateBytes literal).length
  let after := middle.returnNear
  refine ⟨middle, after,
    .decoded (immediateBytes literal) loaded.prefix _ _
      (immediate_decodes .w32 0 literal.bits 0) rfl,
    .decoded Machine.returnBytes loaded.suffix .returnNear 1
      Machine.return_decodes rfl, ?_, ?_, ?_, ?_, ?_, ?_, rfl, rfl⟩
  · simp [after, middle, Machine.State.returnNear, Machine.State.immediate32]
  · simp [after, middle, Machine.State.returnNear, Machine.State.immediate32]
  · simpa [after, middle, Machine.State.returnNear, Machine.State.immediate32,
      RaxMatches] using literal_bits_match_core literal
  · simp [after, middle, Machine.State.returnNear, Machine.State.immediate32]
  · simp [after, middle, Machine.State.returnNear, Machine.State.immediate32]
  · intro register notResult notStack
    simp [after, middle, Machine.State.returnNear, Machine.State.immediate32,
      notResult, notStack]

/- This is the connected theorem. `bytesExact` authenticates bytes supplied by
   an external emitter; it intentionally makes no claim that the Lanius emitter
   produced them. -/
theorem Supported.preserves (checked : Supported function) (program : Program)
    (coreBefore : Lanius.Semantics.State) (machineBefore : Machine.State)
    (emitted : List UInt8) (bytesExact : emitted = bytes checked.literal)
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip emitted)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) :
    function.body = some (body checked.literal) ∧
    Executes program coreBefore (body checked.literal)
      (.returned (some checked.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = checked.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = checked.literal.bits ∧
      RaxMatches checked.literal.value ((after.registers 0).setWidth 32) ∧
      after.rip = returnAddress ∧ after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  refine ⟨checked.bodyExact, core_executes checked.literal program coreBefore, ?_⟩
  rw [bytesExact] at loaded
  obtain ⟨middle, after, first, second, result, target, stack, frame, memory, flags⟩ :=
    machine_returns checked.literal machineBefore loaded
  exact ⟨middle, after, first, second, result, target, stack,
    frame.trans poppedReturn, memory, flags⟩

theorem TrailingSupported.preserves (checked : TrailingSupported function)
    (program : Program) (coreBefore : Lanius.Semantics.State)
    (machineBefore : Machine.State) (emitted : List UInt8)
    (bytesExact : emitted = bytes checked.literal)
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip emitted)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) :
    function.body = some (trailingBody checked.literal) ∧
    Executes program coreBefore (trailingBody checked.literal)
      (.returned (some checked.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = checked.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = checked.literal.bits ∧
      RaxMatches checked.literal.value ((after.registers 0).setWidth 32) ∧
      after.rip = returnAddress ∧ after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  refine ⟨checked.bodyExact, ?_, ?_⟩
  · refine ⟨3, ?_⟩
    apply execStmt_sequence_completed 2 program coreBefore
      (body checked.literal) .skip (.returned (some checked.literal.value)) coreBefore
    · exact execStmt_return 1 program coreBefore
        (.value checked.literal.value) checked.literal.value coreBefore
        (evalExpr_value 0 program coreBefore checked.literal.value)
    · simp
  · rw [bytesExact] at loaded
    obtain ⟨middle, after, first, second, result, target, stack, frame, memory, flags⟩ :=
      machine_returns checked.literal machineBefore loaded
    exact ⟨middle, after, first, second, result, target, stack,
      frame.trans poppedReturn, memory, flags⟩

theorem ParametersSupported.preserves (checked : ParametersSupported function)
    (program : Program) (coreBefore : Lanius.Semantics.State)
    (machineBefore : Machine.State) (emitted : List UInt8)
    (bytesExact : emitted = bytes checked.literal)
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip emitted)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) :
    function.body = some (body checked.literal) ∧
    Executes program coreBefore (body checked.literal)
      (.returned (some checked.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = checked.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = checked.literal.bits ∧
      RaxMatches checked.literal.value ((after.registers 0).setWidth 32) ∧
      after.rip = returnAddress ∧ after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  refine ⟨checked.bodyExact, core_executes checked.literal program coreBefore, ?_⟩
  rw [bytesExact] at loaded
  obtain ⟨middle, after, first, second, result, target, stack, frame, memory, flags⟩ :=
    machine_returns checked.literal machineBefore loaded
  exact ⟨middle, after, first, second, result, target,
    stack, frame.trans poppedReturn, memory, flags⟩

theorem ParametersTrailingSupported.preserves
    (checked : ParametersTrailingSupported function)
    (program : Program) (coreBefore : Lanius.Semantics.State)
    (machineBefore : Machine.State) (emitted : List UInt8)
    (bytesExact : emitted = bytes checked.literal)
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip emitted)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) :
    function.body = some (trailingBody checked.literal) ∧
    Executes program coreBefore (trailingBody checked.literal)
      (.returned (some checked.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = checked.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = checked.literal.bits ∧
      RaxMatches checked.literal.value ((after.registers 0).setWidth 32) ∧
      after.rip = returnAddress ∧ after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  refine ⟨checked.bodyExact, ?_, ?_⟩
  · refine ⟨3, ?_⟩
    apply execStmt_sequence_completed 2 program coreBefore
      (body checked.literal) .skip (.returned (some checked.literal.value)) coreBefore
    · exact execStmt_return 1 program coreBefore
        (.value checked.literal.value) checked.literal.value coreBefore
        (evalExpr_value 0 program coreBefore checked.literal.value)
    · simp
  · rw [bytesExact] at loaded
    obtain ⟨middle, after, first, second, result, target, stack, frame, memory, flags⟩ :=
      machine_returns checked.literal machineBefore loaded
    exact ⟨middle, after, first, second, result, target, stack,
      frame.trans poppedReturn, memory, flags⟩

end Lanius.X86.LiteralReturn
