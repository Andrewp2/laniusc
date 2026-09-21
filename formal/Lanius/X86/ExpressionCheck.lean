import Lanius.X86.ScalarComposite
import Lanius.X86.Machine.ControlEncoding
import Lanius.Semantics.Rules

namespace Lanius.X86.ExpressionCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.LiteralReturn

/-!
  A suffix-level boundary for scalar expression lowering.

  `ScalarComposite` proves the one-slot machine protocol, while this file
  supplies the recursive byte/layout interface needed by a caller to compose
  child expressions.  It deliberately stops before a function prologue and
  RET: those belong to the function certificate.  A result carries both the
  authenticated code prefix/remainder and the state relation produced by the
  prefix, so a checker cannot replace execution with a claimed value.
-/

/- A typed witness indexed by the actual Core expression.  The index is the
   source expression that a function checker already received; this is not a
   second expression language.  Unsupported Core nodes have no constructor.
   In particular, this boundary rejects locals/parameters, division/remainder,
   memory, calls, and control flow until their actual backend protocols have
   matching machine proofs.  Multiplication is accepted only through the
   authenticated frame protocol below. -/
inductive BinaryMachineOp where
  | alu (operation : Alu)
  | multiply

def BinaryMachineOp.result : BinaryMachineOp → BitVec 32 → BitVec 32 → BitVec 32
  | .alu operation => operation.result
  | .multiply => (· * ·)

def BinaryMachineOp.bytes : BinaryMachineOp → Nat → List UInt8
  | .alu operation, slot => frameAluBytes slot operation
  | .multiply, slot => frameMultiplyBytes slot

def operation? : BinaryOp → Option BinaryMachineOp
  | .add => some (.alu .add)
  | .subtract => some (.alu .subtract)
  | .bitAnd => some (.alu .and)
  | .bitOr => some (.alu .or)
  | .bitXor => some (.alu .xor)
  | .multiply => some .multiply
  | _ => none

inductive Shape : Core.Expr → Type
  | lit (literal : LiteralReturn.Literal) (value : Value)
      (exact : literal.value = value) : Shape (.value value)
  | unary (coreOperation : UnaryOp)
      (operand : Core.Expr) (operandShape : Shape operand) :
      Shape (.unary coreOperation operand)
  | binary (coreOperation : BinaryOp) (operation : BinaryMachineOp)
      (left right : Core.Expr) (operationExact : operation? coreOperation = some operation)
      (leftShape : Shape left) (rightShape : Shape right) :
      Shape (.binary coreOperation left right)

def Shape.allocations {source : Core.Expr} : Shape source → Nat
  | Shape.lit _ _ _ => 0
  | Shape.unary _ _ operand => operand.allocations
  | Shape.binary _ _ _ _ _ left right => left.allocations + 1 + right.allocations

def unaryBytes : UnaryOp → List UInt8
  | .positive => []
  | .logicalNot => testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister ++
      [15, 148, 192] ++ zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister
  | .negate => negateBytes .w32 ScalarValidator.resultRegister

def Shape.bodyBytes {source : Core.Expr} : Shape source → Nat → List UInt8
  | Shape.lit literal _ _, _ => immediateBytes .w32 ScalarValidator.resultRegister literal.bits 0
  | Shape.unary operation _ operand, base =>
      operand.bodyBytes base ++ unaryBytes operation
  | Shape.binary _ operation _ _ _ left right, base =>
      left.bodyBytes base ++
        frameStoreBytes (base + left.allocations) ++
        right.bodyBytes (base + left.allocations + 1) ++
        BinaryMachineOp.bytes operation (base + left.allocations)

def Shape.coreValue? {source : Core.Expr} : Shape source → Option Value
  | Shape.lit literal _ _ => some literal.value
  | Shape.unary operation _ operand =>
      match operand.coreValue? with
      | some value => (evalUnaryValue Target.x86_64 operation value).toOption
      | none => none
  | Shape.binary coreOperation _ _ _ _ left right =>
      match left.coreValue?, right.coreValue? with
      | some left, some right =>
          match evalBinaryValue Target.x86_64 coreOperation left right with
          | .ok value => some value
          | .error _ => none
      | _, _ => none

def unarySupported (operation : UnaryOp) (operandValue result : Value) : Prop :=
  match operation, operandValue, result with
  | .positive, .signed .i32 _, .signed .i32 _ => True
  | .negate, .signed .i32 _, .signed .i32 _ => True
  | .logicalNot, .boolean _, .boolean _ => True
  | _, _, _ => False

inductive WellFormed : {source : Core.Expr} → Shape source → Prop
  | lit (literal : LiteralReturn.Literal) (value : Value) (exact : literal.value = value) :
      WellFormed (Shape.lit literal value exact)
  | unary (coreOperation : UnaryOp) (operand : Core.Expr)
      (operandShape : Shape operand) (operandWitness : WellFormed operandShape)
      (operandValue result : Value)
      (operandExact : operandShape.coreValue? = some operandValue)
      (resultExact : evalUnaryValue Target.x86_64 coreOperation operandValue = .ok result)
      (supported : unarySupported coreOperation operandValue result) :
      WellFormed (Shape.unary coreOperation operand operandShape)
  | binary (coreOperation : BinaryOp) (operation : BinaryMachineOp)
      (left right : Core.Expr) (operationExact : operation? coreOperation = some operation)
      (leftShape : Shape left) (rightShape : Shape right)
      (leftWitness : WellFormed leftShape) (rightWitness : WellFormed rightShape)
      (leftValue rightValue result : Int)
      (leftExact : leftShape.coreValue? = some (.signed .i32 leftValue))
      (rightExact : rightShape.coreValue? = some (.signed .i32 rightValue))
      (resultExact : evalBinaryValue Target.x86_64 coreOperation
        (.signed .i32 leftValue) (.signed .i32 rightValue) =
          .ok (.signed .i32 result)) :
      WellFormed (Shape.binary coreOperation operation left right operationExact leftShape rightShape)

def Shape.returnBytes {source : Core.Expr} (expression : Shape source) (slots : Nat) : List UInt8 :=
  framePrologueBytes slots ++ expression.bodyBytes 0 ++ ScalarValidator.binaryEpilogueBytes

/- Executable byte authentication for the recursive source shape.  The shape
   checker is intentionally fail-closed: callers must provide the exact
   canonical prefix generated from the authenticated Core expression. -/
def checkShape? (source : Core.Expr) : Option { shape : Shape source // WellFormed shape } :=
  match source with
  | .value value =>
      match value with
      | .signed .i32 number =>
          if bounds : -2147483648 ≤ number ∧ number < 2147483648 then
            some ⟨.lit (.i32 (BitVec.ofInt 32 number))
              (.signed .i32 number) (by
                simp [LiteralReturn.Literal.value,
                  LiteralReturn.i32_ofInt_toInt number bounds.1 bounds.2]),
              .lit _ _ _⟩
          else none
      | .boolean value => some ⟨.lit (.bool value) (.boolean value) rfl,
              .lit _ _ rfl⟩
          | _ => none
  | .unary operation operand =>
      match checkShape? operand with
      | some ⟨operandShape, operandWitness⟩ =>
          match operandExact : operandShape.coreValue? with
          | some operandValue =>
              match operation, operandValue with
              | .positive, .signed .i32 value =>
                  some ⟨.unary .positive operand operandShape,
                    .unary .positive operand operandShape operandWitness
                      (.signed .i32 value) (.signed .i32 value) operandExact rfl
                        (by simp [unarySupported])⟩
              | .negate, .signed .i32 value =>
                  let result := .signed .i32
                    (wrapSigned Target.x86_64 .i32 (-value))
                  some ⟨.unary .negate operand operandShape,
                    .unary .negate operand operandShape operandWitness
                      (.signed .i32 value) result operandExact rfl
                      (by simp [unarySupported, result])⟩
              | .logicalNot, .boolean value =>
                  let result := .boolean (!value)
                  some ⟨.unary .logicalNot operand operandShape,
                    .unary .logicalNot operand operandShape operandWitness
                      (.boolean value) result operandExact rfl
                      (by simp [unarySupported, result])⟩
              | _, _ => none
          | none => none
      | none => none
  | .binary operation left right =>
      match exact : operation? operation with
      | some machineOperation =>
          match checkShape? left, checkShape? right with
          | some ⟨leftShape, leftWitness⟩, some ⟨rightShape, rightWitness⟩ =>
              match leftExact : leftShape.coreValue?, rightExact : rightShape.coreValue? with
              | some (.signed .i32 leftValue), some (.signed .i32 rightValue) =>
                  match resultExact : evalBinaryValue Target.x86_64 operation
                      (.signed .i32 leftValue) (.signed .i32 rightValue) with
                  | .ok (.signed .i32 result) =>
                      let shape := .binary operation machineOperation left right exact leftShape rightShape
                      some ⟨shape, .binary operation machineOperation left right exact leftShape rightShape
                        leftWitness rightWitness leftValue rightValue result leftExact rightExact resultExact⟩
                  | _ => none
              | _, _ => none
          | _, _ => none
      | none => none
  | _ => none
def checkBody? (source : Core.Expr) (emitted : List UInt8) :
    Option { shape : Shape source // emitted = shape.bodyBytes 0 ∧ WellFormed shape } :=
  match checkShape? source with
  | none => none
  | some ⟨shape, wellFormed⟩ =>
      if exact : emitted = shape.bodyBytes 0 then
        some ⟨shape, exact, wellFormed⟩
      else none

/- `checkBody?` is deliberately a byte certificate, not a claimed machine
   post-state.  The `Result` theorems below require authenticated `CodeAt`
   and child state relations; the dynamic frame invariant needed to derive
   those relations recursively is exposed by the two store lemmas below. -/

/- A dynamic value/frame contract.  `preserveBelow` is the frame allocator
   invariant: an expression entered with `base` free slots may write only at
   slots at or above that base.  This is exactly what a parent binary needs
   after it spills its left value and starts the right child at `base + 1`. -/
structure Result {source : Core.Expr} (expression : Shape source) (base : Nat)
    (before after : Machine.State) where
  bits : BitVec 32
  coreValue : Value
  consumed : List UInt8
  remainder : List UInt8
  steps : Nat
  run : Steps steps before after
  loaded : CodeAt before.memory before.rip (consumed ++ remainder)
  remainderLoaded : CodeAt after.memory after.rip remainder
  resultRegister : after.registers ScalarValidator.resultRegister = bits.setWidth 64
  frameStable : after.registers rbpRegister = before.registers rbpRegister
  /-- The authenticated prefix, rather than an asserted result, determines RIP. -/
  ripAdvance : after.rip = before.rip + BitVec.ofNat 64 consumed.length
  preserveBelow : ∀ slot, slot < base →
    read32 after.memory (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot)
  coreValueExact : expression.coreValue? = some coreValue
  representation : LiteralReturn.RaxMatches coreValue bits

/- This is the small memory lemma a recursive checker needs at each parent
   binary node.  It deliberately keeps the stack/code separation explicit;
   the flat machine model has no implicit memory map. -/
theorem codeAt_after_store
    (before stored : Machine.State) (slot : Nat) (bytes : List UInt8)
    (loaded : CodeAt before.memory
      (before.rip + BitVec.ofNat 64 (frameStoreBytes slot).length) bytes)
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (disjoint : ∀ index, index < bytes.length → ∀ lane : Fin 4,
      before.rip + BitVec.ofNat 64 (frameStoreBytes slot).length +
          BitVec.ofNat 64 index ≠
        frameSlotAddress (before.registers rbpRegister) slot +
          BitVec.ofNat 64 lane.val) :
    CodeAt stored.memory stored.rip bytes := by
  have preserved := loaded.write32
    ((before.registers ScalarValidator.resultRegister).setWidth 32)
    (address := frameSlotAddress (before.registers rbpRegister) slot)
    (by
      intro index bound lane
      simpa [frameSlotAddress, BitVec.add_assoc] using disjoint index bound lane)
  simpa [storeResult, Machine.State.store32, frameSlotAddress,
    ScalarValidator.resultRegister] using preserved

theorem lowerFrameSlot_after_store
    (before stored : Machine.State) (slot lower : Nat)
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (disjoint : ∀ i j : Fin 4,
      frameSlotAddress (before.registers rbpRegister) lower + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot + BitVec.ofNat 64 j.val) :
    read32 stored.memory (frameSlotAddress (before.registers rbpRegister) lower) =
      read32 before.memory (frameSlotAddress (before.registers rbpRegister) lower) := by
  rw [storeResult]
  simp only [Machine.State.store32]
  apply read32_frame
  exact disjoint

/- The recursive proof carries a finite frame window.  The window is a
   dynamic part of the caller's invariant: unlike a fixed stack bound, it can
   be enlarged by a parent while a child is running.  `separated` protects
   future instruction bytes from stores in that window; `slotsSeparated`
   supplies the corresponding stack-slot fact when a child finishes. -/
structure FrameCodeInvariant (before : Machine.State) (lower upper : Nat)
    (bytes : List UInt8) : Prop where
  loaded : CodeAt before.memory before.rip bytes
  separated : ∀ index, index < bytes.length → ∀ slot,
    lower ≤ slot → slot < upper → ∀ lane : Fin 4,
      before.rip + BitVec.ofNat 64 index ≠
        frameSlotAddress (before.registers rbpRegister) slot +
          BitVec.ofNat 64 lane.val
  slotsSeparated : ∀ left right,
    lower ≤ left → left < upper → lower ≤ right → right < upper → left ≠ right →
    ∀ i j : Fin 4,
      frameSlotAddress (before.registers rbpRegister) left +
          BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) right +
          BitVec.ofNat 64 j.val
  belowSlotsSeparated : ∀ left, left < lower → ∀ right,
    lower ≤ right → right < upper → left ≠ right → ∀ i j : Fin 4,
      frameSlotAddress (before.registers rbpRegister) left +
          BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) right +
          BitVec.ofNat 64 j.val

theorem FrameCodeInvariant.restrict
    {before : Machine.State} {lower upper lower' upper' : Nat}
    {bytes : List UInt8} (invariant : FrameCodeInvariant before lower upper bytes)
    (lowerBound : lower ≤ lower') (upperBound : upper' ≤ upper) :
    FrameCodeInvariant before lower' upper' bytes := by
  refine {
    loaded := invariant.loaded
    separated := ?_
    slotsSeparated := ?_
    belowSlotsSeparated := ?_ }
  · intro index bound slot lower'Bound upper'Bound lane
    exact invariant.separated index bound slot
      (by omega) (by omega) lane
  · intro left right leftLower leftUpper rightLower rightUpper different i j
    exact invariant.slotsSeparated left right (by omega) (by omega)
      (by omega) (by omega) different i j
  · intro left leftUpper' right rightLower' rightUpper' different i j
    by_cases oldBelow : left < lower
    · exact invariant.belowSlotsSeparated left oldBelow right
        (by omega) (by omega) different i j
    · exact invariant.slotsSeparated left right (by omega) (by omega)
        (by omega) (by omega) different i j

theorem FrameCodeInvariant.suffix
    {before after : Machine.State} {lower upper : Nat}
    {head rest : List UInt8}
    (invariant : FrameCodeInvariant before lower upper (head ++ rest))
    (loaded : CodeAt after.memory after.rip rest)
    (ripAdvance : after.rip = before.rip + BitVec.ofNat 64 head.length)
    (frameStable : after.registers rbpRegister = before.registers rbpRegister) :
    FrameCodeInvariant after lower upper rest := by
  refine {
    loaded := loaded
    separated := ?_
    slotsSeparated := ?_
    belowSlotsSeparated := by
      intro left leftUpper right rightLower rightUpper different i j
      simpa [frameStable] using invariant.belowSlotsSeparated left leftUpper right
        rightLower rightUpper different i j }
  · intro index bound slot lowerBound upperBound lane
    have original := invariant.separated (head.length + index) (by
      simp only [List.length_append]
      omega) slot lowerBound upperBound lane
    simpa [ripAdvance, BitVec.ofNat_add, BitVec.add_assoc, frameStable] using original
  · intro left right leftLower leftUpper rightLower rightUpper different i j
    simpa [frameStable] using invariant.slotsSeparated left right
      leftLower leftUpper rightLower rightUpper different i j

theorem FrameCodeInvariant.conditional_split_suffix
    {before thenState elseState : Machine.State} {lower upper : Nat}
    {thenBody elseBody suffix : List UInt8}
    (invariant : FrameCodeInvariant before lower upper
      (Machine.conditionalBytes thenBody elseBody ++ suffix))
    (thenBound : thenBody.length + 5 < 2 ^ 31)
    (elseBound : elseBody.length < 2 ^ 31)
    (thenMemory : thenState.memory = before.memory)
    (elseMemory : elseState.memory = before.memory)
    (thenRip : thenState.rip = before.rip + BitVec.ofNat 64
      (Machine.conditionalPrefix thenBody).length)
    (elseRip : elseState.rip = before.rip + BitVec.ofNat 64
      (Machine.conditionalPrefix thenBody).length +
      (BitVec.ofNat 32 (thenBody.length + 5)).signExtend 64)
    (thenFrame : thenState.registers rbpRegister = before.registers rbpRegister)
    (elseFrame : elseState.registers rbpRegister = before.registers rbpRegister) :
    FrameCodeInvariant thenState lower upper
      (thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix) ∧
    FrameCodeInvariant elseState lower upper (elseBody ++ suffix) := by
  have targets := Machine.conditional_code_targets_suffix thenBound elseBound invariant.loaded
  have thenLoaded : CodeAt thenState.memory thenState.rip
      (thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix) := by
    rw [thenMemory, thenRip]
    exact targets.1
  have elseLoaded : CodeAt elseState.memory elseState.rip (elseBody ++ suffix) := by
    rw [elseMemory, elseRip]
    exact targets.2
  have splitInvariant : FrameCodeInvariant before lower upper
      (Machine.conditionalPrefix thenBody ++
        (thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix)) := by
    simpa [Machine.conditionalBytes, List.append_assoc] using invariant
  have thenInvariant := FrameCodeInvariant.suffix splitInvariant thenLoaded thenRip thenFrame
  have elseSplit : FrameCodeInvariant before lower upper
      ((Machine.conditionalPrefix thenBody ++ thenBody ++
        Machine.jumpBytes (BitVec.ofNat 32 elseBody.length)) ++ (elseBody ++ suffix)) := by
    simpa [Machine.conditionalBytes, List.append_assoc] using invariant
  have elseRip' : elseState.rip = before.rip + BitVec.ofNat 64
      (Machine.conditionalPrefix thenBody ++ thenBody ++
        Machine.jumpBytes (BitVec.ofNat 32 elseBody.length)).length := by
    rw [elseRip, Machine.conditional_code_target_address thenBound]
  have elseInvariant := FrameCodeInvariant.suffix elseSplit elseLoaded elseRip' elseFrame
  exact ⟨thenInvariant, elseInvariant⟩

theorem FrameCodeInvariant.conditional_split
    {before thenState elseState : Machine.State} {lower upper : Nat}
    {thenBody elseBody : List UInt8}
    (invariant : FrameCodeInvariant before lower upper
      (Machine.conditionalBytes thenBody elseBody))
    (thenBound : thenBody.length + 5 < 2 ^ 31)
    (elseBound : elseBody.length < 2 ^ 31)
    (thenMemory : thenState.memory = before.memory)
    (elseMemory : elseState.memory = before.memory)
    (thenRip : thenState.rip = before.rip + BitVec.ofNat 64
      (Machine.conditionalPrefix thenBody).length)
    (elseRip : elseState.rip = before.rip + BitVec.ofNat 64
      (Machine.conditionalPrefix thenBody).length +
      (BitVec.ofNat 32 (thenBody.length + 5)).signExtend 64)
    (thenFrame : thenState.registers rbpRegister = before.registers rbpRegister)
    (elseFrame : elseState.registers rbpRegister = before.registers rbpRegister) :
    FrameCodeInvariant thenState lower upper
      (thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody) ∧
    FrameCodeInvariant elseState lower upper elseBody := by
  have invariant' : FrameCodeInvariant before lower upper
      (Machine.conditionalBytes thenBody elseBody ++ []) := by
    simpa using invariant
  simpa using FrameCodeInvariant.conditional_split_suffix
    (suffix := []) invariant' thenBound elseBound thenMemory elseMemory thenRip elseRip
      thenFrame elseFrame

theorem FrameCodeInvariant.after_store
    {before stored : Machine.State} {lower upper : Nat}
    {slot : Nat} {rest : List UInt8}
    (invariant : FrameCodeInvariant before lower upper
      (frameStoreBytes slot ++ rest))
    (slotLower : lower ≤ slot) (slotUpper : slot < upper)
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length) :
    FrameCodeInvariant stored lower upper rest := by
  have disjoint : ∀ index, index < rest.length → ∀ lane : Fin 4,
      before.rip + BitVec.ofNat 64 (frameStoreBytes slot).length +
          BitVec.ofNat 64 index ≠
        frameSlotAddress (before.registers rbpRegister) slot +
          BitVec.ofNat 64 lane.val := by
    intro index bound lane
    simpa [BitVec.ofNat_add, BitVec.add_assoc] using
      invariant.separated ((frameStoreBytes slot).length + index) (by
        simp only [List.length_append]
        omega) slot slotLower slotUpper lane
  refine {
    loaded := codeAt_after_store before stored slot rest
      invariant.loaded.suffix storeResult disjoint
    separated := ?_
    slotsSeparated := ?_
    belowSlotsSeparated := by
      intro left leftUpper right rightLower rightUpper different i j
      have original := invariant.belowSlotsSeparated left leftUpper right
        rightLower rightUpper different i j
      simpa [storeResult, Machine.State.store32] using original }
  · intro index bound other lowerBound upperBound lane
    have original := invariant.separated
      ((frameStoreBytes slot).length + index) (by
        simp only [List.length_append]
        omega) other lowerBound upperBound lane
    simpa [storeResult, Machine.State.store32, frameSlotAddress,
      BitVec.ofNat_add, BitVec.add_assoc] using original
  · intro left right leftLower leftUpper rightLower rightUpper different i j
    have original := invariant.slotsSeparated left right
      leftLower leftUpper rightLower rightUpper different i j
    simpa [storeResult, Machine.State.store32] using original

/- The recursive result adds only the bounded part of the frame contract that
   is needed by a parent spill.  The public `Result` remains the small suffix
   contract used by existing callers. -/
structure RecursiveResult {source : Core.Expr} (expression : Shape source)
    (base upper : Nat) (remainder : List UInt8) (before after : Machine.State) where
  result : Result expression base before after
  consumedExact : result.consumed = expression.bodyBytes base
  remainderExact : result.remainder = remainder
  preserveOutside : ∀ slot,
    base + expression.allocations ≤ slot → slot < upper →
    read32 after.memory (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot)
  /-- The recursive stores preserve any quadword outside the allocated slots.
      This is the memory boundary needed by a caller's epilogue. -/
  preserveRead64Outside : ∀ address,
    (∀ slot, base ≤ slot → slot < base + expression.allocations →
      ∀ i : Fin 8, ∀ j : Fin 4,
        address + BitVec.ofNat 64 i.val ≠
          frameSlotAddress (before.registers rbpRegister) slot +
            BitVec.ofNat 64 j.val) →
    read64 after.memory address = read64 before.memory address
  /-- Any authenticated code window disjoint from the allocated frame slots
      survives the recursive stores. -/
  preserveCodeAt : ∀ address bytes,
    CodeAt before.memory address bytes →
    (∀ index, index < bytes.length → ∀ slot,
      base ≤ slot → slot < base + expression.allocations → ∀ lane : Fin 4,
        address + BitVec.ofNat 64 index ≠
          frameSlotAddress (before.registers rbpRegister) slot +
            BitVec.ofNat 64 lane.val) →
    CodeAt after.memory address bytes

def RecursiveResult.restrict
    {source : Core.Expr} {expression : Shape source}
    {base upper upper' : Nat} {remainder : List UInt8} {before after : Machine.State}
    (result : RecursiveResult expression base upper remainder before after)
    (upperBound : upper' ≤ upper) :
    RecursiveResult expression base upper' remainder before after := by
  refine {
    result := result.result
    consumedExact := result.consumedExact
    remainderExact := result.remainderExact
    preserveOutside := ?_
    preserveRead64Outside := result.preserveRead64Outside
    preserveCodeAt := result.preserveCodeAt }
  intro slot shapeBound upper'Bound
  exact result.preserveOutside slot shapeBound (by omega)

private theorem binary_protocol (operation : BinaryMachineOp) (count slot : Nat)
    (leftValue rightValue : BitVec 32) (before stored rightState : Machine.State)
    (storeLoaded : CodeAt before.memory before.rip (frameStoreBytes slot))
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (leftValue_eq : (before.registers 0).setWidth 32 = leftValue)
    (rightSteps : Steps count stored rightState)
    (sameRbp : rightState.registers rbpRegister = before.registers rbpRegister)
    (sameSlot : read32 rightState.memory
      (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 stored.memory (frameSlotAddress (before.registers rbpRegister) slot))
    (rightResult : rightState.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt rightState.memory rightState.rip
      (BinaryMachineOp.bytes operation slot)) :
    ∃ after : Machine.State, Steps (count + 4) before after ∧
      after.registers 0 = (operation.result leftValue rightValue).setWidth 64 ∧
      after.registers rbpRegister = before.registers rbpRegister ∧
      after.memory = rightState.memory ∧
      after.rip = rightState.rip + BitVec.ofNat 64
        (BinaryMachineOp.bytes operation slot).length := by
  cases operation with
  | alu operation =>
      simpa [BinaryMachineOp.bytes, BinaryMachineOp.result] using
        frameStore_then_alu_protocol count slot operation leftValue rightValue before stored
          rightState storeLoaded storeResult leftValue_eq rightSteps sameRbp sameSlot rightResult
          loaded
  | multiply =>
      simpa [BinaryMachineOp.bytes, BinaryMachineOp.result] using
        frameStore_then_multiply_protocol count slot leftValue rightValue before stored rightState
          storeLoaded storeResult leftValue_eq rightSteps sameRbp sameSlot rightResult loaded

/- Machine-only part of the parent protocol.  Keeping this separate lets the
   recursive proof retain the exact memory equation needed for frame
   separation without duplicating the public recursive result contract. -/
private theorem binary_machine
    {leftSource rightSource : Core.Expr}
    (base slot : Nat) (operation : BinaryMachineOp)
    (left : Shape leftSource) (right : Shape rightSource)
    (before leftAfter stored rightAfter : Machine.State)
    (remainder : List UInt8)
    (leftResult : Result left base before leftAfter)
    (rightResult : Result right (slot + 1) stored rightAfter)
    (_slotExact : slot = base + left.allocations)
    (leftTail : leftResult.remainder =
      frameStoreBytes slot ++ rightResult.consumed ++
        BinaryMachineOp.bytes operation slot ++ remainder)
    (rightTail : rightResult.remainder =
      BinaryMachineOp.bytes operation slot ++ remainder)
    (storeResult : stored = leftAfter.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length) :
    ∃ after, Steps (leftResult.steps + (rightResult.steps + 4)) before after ∧
      after.registers ScalarValidator.resultRegister =
        (operation.result leftResult.bits rightResult.bits).setWidth 64 ∧
      after.registers rbpRegister = before.registers rbpRegister ∧
      after.memory = rightAfter.memory ∧
      after.rip = rightAfter.rip + BitVec.ofNat 64
        (BinaryMachineOp.bytes operation slot).length := by
  have storeLoaded : CodeAt leftAfter.memory leftAfter.rip
      (frameStoreBytes slot ++ rightResult.consumed ++
        BinaryMachineOp.bytes operation slot ++ remainder) := by
    simpa [leftTail] using leftResult.remainderLoaded
  have operationLoaded : CodeAt rightAfter.memory rightAfter.rip
      (BinaryMachineOp.bytes operation slot ++ remainder) := by
    simpa [rightTail] using rightResult.remainderLoaded
  have storeInstructionLoaded : CodeAt leftAfter.memory leftAfter.rip
      (frameStoreBytes slot) := by
    have source := storeLoaded
    rw [show frameStoreBytes slot ++ rightResult.consumed ++
        BinaryMachineOp.bytes operation slot ++ remainder =
        frameStoreBytes slot ++
          (rightResult.consumed ++ BinaryMachineOp.bytes operation slot ++ remainder) by
      simp [List.append_assoc]] at source
    exact source.prefix
  have leftValue : (leftAfter.registers ScalarValidator.resultRegister).setWidth 32 =
      leftResult.bits := by
    rw [leftResult.resultRegister]
    apply BitVec.eq_of_toNat_eq
    simp
  have sameRbp : rightAfter.registers rbpRegister = leftAfter.registers rbpRegister := by
    calc
      rightAfter.registers rbpRegister = stored.registers rbpRegister := rightResult.frameStable
      _ = leftAfter.registers rbpRegister := by simp [storeResult, Machine.State.store32]
  have sameSlot : read32 rightAfter.memory
      (frameSlotAddress (stored.registers rbpRegister) slot) =
      read32 stored.memory (frameSlotAddress (stored.registers rbpRegister) slot) := by
    exact rightResult.preserveBelow slot (by omega)
  have sameSlot' : read32 rightAfter.memory
      (frameSlotAddress (leftAfter.registers rbpRegister) slot) =
      read32 stored.memory (frameSlotAddress (leftAfter.registers rbpRegister) slot) := by
    calc
      read32 rightAfter.memory
          (frameSlotAddress (leftAfter.registers rbpRegister) slot) =
          read32 rightAfter.memory
            (frameSlotAddress (stored.registers rbpRegister) slot) := by
              simp [storeResult, Machine.State.store32]
      _ = read32 stored.memory (frameSlotAddress (stored.registers rbpRegister) slot) := sameSlot
      _ = read32 stored.memory (frameSlotAddress (leftAfter.registers rbpRegister) slot) := by
            simp [storeResult, Machine.State.store32]
  have rightResult' : rightAfter.registers 0 = rightResult.bits.setWidth 64 := by
    simpa [ScalarValidator.resultRegister] using rightResult.resultRegister
  obtain ⟨after, machineRun, machineResult, machineRbp, machineMemory, machineRip⟩ :=
    binary_protocol operation rightResult.steps slot leftResult.bits rightResult.bits
      leftAfter stored rightAfter storeInstructionLoaded storeResult leftValue rightResult.run
      sameRbp sameSlot' rightResult' operationLoaded.prefix
  refine ⟨after, ?_, machineResult, ?_, machineMemory, machineRip⟩
  · simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
      leftResult.run.trans machineRun
  · calc
      after.registers rbpRegister = leftAfter.registers rbpRegister := machineRbp
      _ = before.registers rbpRegister := leftResult.frameStable

def bitwiseNat (operation : BinaryOp) (left right : Nat) : Nat :=
  match operation with
  | .bitAnd => Nat.land left right
  | .bitOr => Nat.lor left right
  | .bitXor => Nat.xor left right
  | _ => 0

theorem wrapSigned_bmod (value : Int) :
    wrapSigned Target.x86_64 .i32 value = value.bmod (2 ^ 32) := by
  unfold wrapSigned signedModulus signedSignBit
  have bits : SignedIntTy.bits Target.x86_64 .i32 = 32 := by decide
  rw [bits, Int.bmod_eq_emod]
  dsimp
  change (if value % (4294967296 : Int) ≥ 2147483648 then
      value % (4294967296 : Int) - 4294967296 else value % (4294967296 : Int)) =
    value % (4294967296 : Int) -
      ↑(if value % (4294967296 : Int) ≥ 2147483648 then
        (4294967296 : Nat) else 0)
  by_cases h : value % (4294967296 : Int) ≥ 2147483648
  · simp [h]
  · simp [h]

theorem eval_bitwise
    (operation : BinaryOp) (leftValue rightValue : Int)
    (leftBits rightBits : BitVec 32)
    (leftExact : leftBits.toInt = leftValue)
    (rightExact : rightBits.toInt = rightValue)
    (operationExact : operation = .bitAnd ∨ operation = .bitOr ∨ operation = .bitXor) :
    evalSignedBinary Target.x86_64 operation .i32 leftValue rightValue =
      .ok (.signed .i32 (wrapSigned Target.x86_64 .i32
        (Int.ofNat (bitwiseNat operation leftBits.toNat rightBits.toNat)))) := by
  cases operation <;> simp_all [bitwiseNat, evalSignedBinary,
    signedBits_i32_bitvec_x86 leftBits leftValue leftExact,
    signedBits_i32_bitvec_x86 rightBits rightValue rightExact]

theorem alu_representation
    (coreOperation : BinaryOp) (operation : Alu)
    (leftValue rightValue result : Int) (leftBits rightBits : BitVec 32)
    (operationExact : operation? coreOperation = some (.alu operation))
    (leftRepresentation : RaxMatches (.signed .i32 leftValue) leftBits)
    (rightRepresentation : RaxMatches (.signed .i32 rightValue) rightBits)
    (resultExact : evalBinaryValue Target.x86_64 coreOperation
      (.signed .i32 leftValue) (.signed .i32 rightValue) =
        .ok (.signed .i32 result)) :
    RaxMatches (.signed .i32 result) (operation.result leftBits rightBits) := by
  cases coreOperation <;> cases operation <;> simp_all [operation?]
  case add.add =>
    simp_all [evalBinaryValue, evalSignedBinary, RaxMatches,
      Alu.result, wrapSigned_bmod, BitVec.toInt_add]
  case subtract.subtract =>
    simp_all [evalBinaryValue, evalSignedBinary, RaxMatches,
      Alu.result, wrapSigned_bmod, BitVec.toInt_sub]
  case bitAnd.and =>
    have evaluator : evalSignedBinary Target.x86_64 .bitAnd .i32 leftValue rightValue =
        .ok (.signed .i32 result) := by simpa [evalBinaryValue] using resultExact
    have bridge := eval_bitwise .bitAnd leftValue rightValue leftBits rightBits
      leftRepresentation rightRepresentation (Or.inl rfl)
    rw [evaluator] at bridge
    have valueExact : result = wrapSigned Target.x86_64 .i32
        (Int.ofNat (bitwiseNat .bitAnd leftBits.toNat rightBits.toNat)) := by
      injection bridge with valueEq
      injection valueEq with resultEq
    rw [RaxMatches, Alu.result, BitVec.toInt_and]
    rw [wrapSigned_bmod] at valueExact
    simpa [bitwiseNat] using valueExact.symm

  case bitOr.or =>
    have evaluator : evalSignedBinary Target.x86_64 .bitOr .i32 leftValue rightValue =
        .ok (.signed .i32 result) := by simpa [evalBinaryValue] using resultExact
    have bridge := eval_bitwise .bitOr leftValue rightValue leftBits rightBits
      leftRepresentation rightRepresentation (Or.inr (Or.inl rfl))
    rw [evaluator] at bridge
    have valueExact : result = wrapSigned Target.x86_64 .i32
        (Int.ofNat (bitwiseNat .bitOr leftBits.toNat rightBits.toNat)) := by
      injection bridge with valueEq
      injection valueEq with resultEq
    rw [RaxMatches, Alu.result, BitVec.toInt_or]
    rw [wrapSigned_bmod] at valueExact
    simpa [bitwiseNat] using valueExact.symm
  case bitXor.xor =>
    have evaluator : evalSignedBinary Target.x86_64 .bitXor .i32 leftValue rightValue =
        .ok (.signed .i32 result) := by simpa [evalBinaryValue] using resultExact
    have bridge := eval_bitwise .bitXor leftValue rightValue leftBits rightBits
      leftRepresentation rightRepresentation (Or.inr (Or.inr rfl))
    rw [evaluator] at bridge
    have valueExact : result = wrapSigned Target.x86_64 .i32
        (Int.ofNat (bitwiseNat .bitXor leftBits.toNat rightBits.toNat)) := by
      injection bridge with valueEq
      injection valueEq with resultEq
    rw [RaxMatches, Alu.result, BitVec.toInt_xor]
    rw [wrapSigned_bmod] at valueExact
    simpa [bitwiseNat] using valueExact.symm

theorem multiply_representation
    (coreOperation : BinaryOp)
    (leftValue rightValue result : Int) (leftBits rightBits : BitVec 32)
    (operationExact : operation? coreOperation = some .multiply)
    (leftRepresentation : RaxMatches (.signed .i32 leftValue) leftBits)
    (rightRepresentation : RaxMatches (.signed .i32 rightValue) rightBits)
    (resultExact : evalBinaryValue Target.x86_64 coreOperation
      (.signed .i32 leftValue) (.signed .i32 rightValue) =
        .ok (.signed .i32 result)) :
    RaxMatches (.signed .i32 result) (leftBits * rightBits) := by
  have coreExact : coreOperation = .multiply := by
    cases coreOperation <;> simp [operation?] at operationExact ⊢
  subst coreOperation
  rw [RaxMatches, BitVec.toInt_mul]
  rw [leftRepresentation, rightRepresentation]
  simp [evalBinaryValue, evalSignedBinary, wrapSigned_bmod] at resultExact ⊢
  exact resultExact

theorem binary_representation
    (coreOperation : BinaryOp) (operation : BinaryMachineOp)
    (leftValue rightValue result : Int) (leftBits rightBits : BitVec 32)
    (operationExact : operation? coreOperation = some operation)
    (leftRepresentation : RaxMatches (.signed .i32 leftValue) leftBits)
    (rightRepresentation : RaxMatches (.signed .i32 rightValue) rightBits)
    (resultExact : evalBinaryValue Target.x86_64 coreOperation
      (.signed .i32 leftValue) (.signed .i32 rightValue) =
        .ok (.signed .i32 result)) :
    RaxMatches (.signed .i32 result) (operation.result leftBits rightBits) := by
  cases operation with
  | alu operation =>
      exact alu_representation coreOperation operation leftValue rightValue result
        leftBits rightBits operationExact leftRepresentation rightRepresentation resultExact
  | multiply =>
      exact multiply_representation coreOperation leftValue rightValue result leftBits rightBits
        operationExact leftRepresentation rightRepresentation resultExact

def unarySteps : UnaryOp → Nat
  | .positive => 0
  | .logicalNot => 3
  | .negate => 1

def unaryMachineResult (operation : UnaryOp) (bits : BitVec 32) : BitVec 32 :=
  match operation with
  | .positive => bits
  | .negate => 0 - bits
  | .logicalNot => BitVec.ofNat 32 (if bits == 0 then 1 else 0)

private theorem bool_bits_eq (value : Bool) (bits : BitVec 32)
    (exact : RaxMatches (.boolean value) bits) :
    bits = BitVec.ofNat 32 (if value then 1 else 0) := by
  apply BitVec.eq_of_toInt_eq
  cases value <;> simp [RaxMatches] at exact ⊢ <;> exact exact

private theorem negate_representation (value : Int) (bits : BitVec 32)
    (exact : RaxMatches (.signed .i32 value) bits) :
    RaxMatches (.signed .i32 (wrapSigned Target.x86_64 .i32 (-value))) (0 - bits) := by
  rw [RaxMatches] at exact ⊢
  rw [wrapSigned_bmod]
  change (0 - bits).toInt = _
  rw [show (0 - bits : BitVec 32) = -bits by simp]
  rw [BitVec.toInt_neg, exact]

private theorem supported_operand
    (operation : UnaryOp) (operandValue result : Value)
    (supported : unarySupported operation operandValue result) :
    match operation with
    | .positive => ∃ value, operandValue = .signed .i32 value
    | .negate => ∃ value, operandValue = .signed .i32 value
    | .logicalNot => ∃ value, operandValue = .boolean value := by
  cases operandValue with
  | signed type value =>
      cases type <;> cases operation <;> cases result <;>
        simp [unarySupported] at supported ⊢
  | boolean value =>
      cases operation <;> cases result <;>
        simp [unarySupported] at supported ⊢
  | _ =>
      cases operation <;> cases result <;>
        simp [unarySupported] at supported ⊢

private theorem setEqual_decodes :
    decode [15, 148, 192] = some (.setCondition 4 0, 3) := by decide

private theorem logical32Flags_equal (before : BitVec 64) (result : BitVec 32)
    (auxiliary : Bool) :
    condition (logical32Flags before result auxiliary) 4 = (result == 0) := by
  change (logical32Flags before result auxiliary).getLsbD 6 = (result == 0)
  unfold logical32Flags logicalFlags
  generalize evenParity result = parity
  generalize (result == 0) = zero
  generalize result.msb = sign
  cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;>
    simp [arithmeticFlags]

private theorem setEqual_step (before after : Machine.State)
    (loaded : CodeAt before.memory before.rip [15, 148, 192])
    (result : after = before.setCondition 4 0 3) : Step before after := by
  exact Step.decoded [15, 148, 192] loaded (.setCondition 4 0) 3 setEqual_decodes result

private theorem unary_machine
    {source : Core.Expr} {expression : Shape source} (operation : UnaryOp)
    (base : Nat) (before childAfter : Machine.State) (remainder : List UInt8)
    (child : Result expression base before childAfter)
    (tail : child.remainder = unaryBytes operation ++ remainder) :
    ∃ after, Steps (child.steps + unarySteps operation) before after ∧
      after.registers rbpRegister = before.registers rbpRegister ∧
      after.memory = childAfter.memory ∧
      after.rip = childAfter.rip + BitVec.ofNat 64 (unaryBytes operation).length ∧
      after = match operation with
        | .positive => childAfter
        | .negate => childAfter.negate 32 ScalarValidator.resultRegister childAfter.flags
            (negateBytes .w32 ScalarValidator.resultRegister).length
        | .logicalNot =>
            let tested := childAfter.test32 ScalarValidator.resultRegister
              ScalarValidator.resultRegister (childAfter.flags.getLsbD 4)
              (testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister).length
            let conditioned := tested.setCondition 4 ScalarValidator.resultRegister 3
            conditioned.zeroExtendByte ScalarValidator.resultRegister
              ScalarValidator.resultRegister
              (zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister).length := by
  have loaded : CodeAt childAfter.memory childAfter.rip
      (unaryBytes operation ++ remainder) := by
    simpa [tail] using child.remainderLoaded
  cases operation with
  | positive =>
      refine ⟨childAfter, ?_, child.frameStable, rfl, ?_, rfl⟩
      · simpa [unarySteps] using child.run
      · simp [unaryBytes]
  | negate =>
      let after := childAfter.negate 32 ScalarValidator.resultRegister childAfter.flags
        (negateBytes .w32 ScalarValidator.resultRegister).length
      have step : Step childAfter after := by
        apply negate_step .w32 childAfter after ScalarValidator.resultRegister
          (by simpa [unaryBytes] using loaded.prefix) childAfter.flags
        rfl
      refine ⟨after, ?_, ?_, ?_, ?_, rfl⟩
      · simpa [after, unarySteps] using child.run.trans
          (Steps.cons step (Steps.refl after))
      · simpa [after, Machine.State.negate, rbpRegister, ScalarValidator.resultRegister] using
          child.frameStable
      · simp [after, Machine.State.negate]
      · simp [after, Machine.State.negate, unaryBytes]
  | logicalNot =>
      let tested := childAfter.test32 ScalarValidator.resultRegister
        ScalarValidator.resultRegister (childAfter.flags.getLsbD 4)
        (testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister).length
      let conditioned := tested.setCondition 4 ScalarValidator.resultRegister 3
      let after := conditioned.zeroExtendByte ScalarValidator.resultRegister
        ScalarValidator.resultRegister
        (zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister).length
      have loaded' : CodeAt childAfter.memory childAfter.rip
          (testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister ++
            ([15, 148, 192] ++
              (zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister ++ remainder))) := by
        simpa [unaryBytes, List.append_assoc] using loaded
      have first : Step childAfter tested := by
        apply test_step .w32 childAfter tested ScalarValidator.resultRegister
          ScalarValidator.resultRegister
          (by simpa using loaded'.prefix)
            (childAfter.flags.getLsbD 4)
        rfl
      have testTail : CodeAt tested.memory tested.rip
          ([15, 148, 192] ++
            zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister) := by
        have testTail0 : CodeAt childAfter.memory
            (childAfter.rip + BitVec.ofNat 64
              (testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister).length)
            (([15, 148, 192] ++
              zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister) ++ remainder) := by
          simpa [List.append_assoc] using loaded'.suffix
        simpa [tested, Machine.State.test32, Machine.State.test] using testTail0.prefix
      have second : Step tested conditioned := by
        apply setEqual_step tested conditioned
        exact testTail.prefix
        rfl
      have setTail : CodeAt conditioned.memory conditioned.rip
          (zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister) := by
        simpa [conditioned, Machine.State.setCondition] using testTail.suffix
      have third : Step conditioned after := by
        apply zeroExtendByte_step conditioned after ScalarValidator.resultRegister
          ScalarValidator.resultRegister
        exact setTail
        rfl
      refine ⟨after, ?_, ?_, ?_, ?_, rfl⟩
      · simpa [after, conditioned, tested, unarySteps] using child.run.trans
          (Steps.cons first (Steps.cons second (Steps.cons third (Steps.refl after))))
      · simpa [after, conditioned, tested, Machine.State.zeroExtendByte,
          Machine.State.setCondition, Machine.State.test32, Machine.State.test, rbpRegister,
          ScalarValidator.resultRegister] using child.frameStable
      · rfl
      · have testLen :
            (testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister).length = 2 := by decide
        have zeroLen :
            (zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister).length = 3 := by decide
        simp [after, conditioned, tested, Machine.State.zeroExtendByte,
          Machine.State.setCondition, Machine.State.test32, Machine.State.test, unaryBytes,
          testLen, zeroLen, BitVec.add_comm]
        rw [← BitVec.add_assoc]
        calc
          (3 : BitVec 64) + 3 + (childAfter.rip + 2) =
              childAfter.rip + ((3 : BitVec 64) + 3 + 2) := by ac_rfl
          _ = childAfter.rip + 8 := by
            have h : (3 : BitVec 64) + 3 + 2 = 8 := by decide
            rw [h]

/- Structural backend soundness for the accepted suffix language.  The only
   recursive hypotheses are the induction hypotheses for the two source
   children; child machine results are constructed here, not supplied by the
   caller. -/
theorem recursive_result
    {source : Core.Expr} (shape : Shape source)
    (wellFormed : WellFormed shape)
    (base upper : Nat) (before : Machine.State) (remainder : List UInt8)
    (window : base + shape.allocations ≤ upper)
    (invariant : FrameCodeInvariant before base upper
      (shape.bodyBytes base ++ remainder)) :
    Nonempty (Σ after : Machine.State,
      RecursiveResult shape base upper remainder before after) := by
  revert wellFormed base upper before remainder
  induction shape with
  | lit literal value exact =>
      intro wellFormed base upper before remainder window invariant
      cases exact
      change FrameCodeInvariant before base upper
        (immediateBytes .w32 ScalarValidator.resultRegister literal.bits 0 ++ remainder) at invariant
      let consumed := immediateBytes .w32 ScalarValidator.resultRegister literal.bits 0
      let after := before.immediate32 ScalarValidator.resultRegister literal.bits consumed.length
      have first : Step before after := by
        apply immediate_step before after .w32 ScalarValidator.resultRegister literal.bits 0
          (by simpa [Shape.bodyBytes] using invariant.loaded.prefix)
        rfl
      have tail : CodeAt after.memory after.rip remainder := by
        simpa [after, consumed, Machine.State.immediate32,
          ScalarValidator.resultRegister] using invariant.loaded.suffix
      refine ⟨⟨after, {
        result := {
          bits := literal.bits
          coreValue := literal.value
          consumed := consumed
          remainder := remainder
          steps := 1
          run := Steps.cons first (Steps.refl after)
          loaded := by simpa [consumed] using invariant.loaded
          remainderLoaded := tail
          resultRegister := by
            simp [after, Machine.State.immediate32, ScalarValidator.resultRegister]
          frameStable := by
            simp [after, Machine.State.immediate32, rbpRegister,
              ScalarValidator.resultRegister]
          ripAdvance := by
            simp [after, consumed, Machine.State.immediate32]
          preserveBelow := by
            intro slot _
            simp [after, Machine.State.immediate32]
          coreValueExact := by rfl
          representation := literal_bits_match_core literal }
        consumedExact := by rfl
        remainderExact := by rfl
        preserveOutside := ?_
        preserveRead64Outside := ?_
        preserveCodeAt := ?_ }⟩⟩
      intro slot _ _
      simp [after, Machine.State.immediate32]
      intro address _
      simp [after, Machine.State.immediate32]
      intro address bytes loaded _
      simpa [after, Machine.State.immediate32] using loaded
  | unary coreOperation operand operandShape ihOperand =>
      intro wellFormed base upper before remainder window invariant
      cases wellFormed with
      | unary _ _ _ operandWitness operandValue result operandExact resultExact supported =>
          have operandWindow : base + operandShape.allocations ≤ upper := by
            simpa [Shape.allocations] using window
          have operandInvariant : FrameCodeInvariant before base upper
              (operandShape.bodyBytes base ++ (unaryBytes coreOperation ++ remainder)) := by
            simpa [Shape.bodyBytes, List.append_assoc] using invariant
          obtain ⟨⟨childAfter, childResult⟩⟩ :=
            ihOperand operandWitness base upper before
              (unaryBytes coreOperation ++ remainder) operandWindow operandInvariant
          have childTail : childResult.result.remainder =
              unaryBytes coreOperation ++ remainder := childResult.remainderExact
          have childRip : childAfter.rip = before.rip +
              BitVec.ofNat 64 (operandShape.bodyBytes base).length := by
            simpa [childResult.consumedExact] using childResult.result.ripAdvance
          obtain ⟨after, machineRun, machineRbp, machineMemory, machineRip, machineAfter⟩ :=
            unary_machine coreOperation base before childAfter remainder
              childResult.result childTail
          have childCoreValue : childResult.result.coreValue = operandValue := by
            have exact := childResult.result.coreValueExact
            rw [operandExact] at exact
            injection exact with valueEq
            exact valueEq.symm
          have childRegister : childAfter.registers (0 : Register) =
              childResult.result.bits.setWidth 64 := by
            simpa [ScalarValidator.resultRegister] using childResult.result.resultRegister
          have childRegisterScalar : childAfter.registers ScalarValidator.resultRegister =
              childResult.result.bits.setWidth 64 := childResult.result.resultRegister
          have operandKind := supported_operand coreOperation operandValue result supported
          have machineResult :
              after.registers ScalarValidator.resultRegister =
                (unaryMachineResult coreOperation childResult.result.bits).setWidth 64 := by
            cases coreOperation with
            | positive =>
                simpa [machineAfter, unaryMachineResult] using childResult.result.resultRegister
            | negate =>
                rw [machineAfter]
                simp [unaryMachineResult, Machine.State.negate,
                  ScalarValidator.resultRegister]
                rw [childRegister]
                simp
            | logicalNot =>
                obtain ⟨value, rfl⟩ := operandKind
                have representation : RaxMatches (.boolean value)
                    childResult.result.bits := by
                  simpa [childCoreValue] using childResult.result.representation
                have bitsExact := bool_bits_eq value childResult.result.bits representation
                have childLowScalar :
                    (childAfter.registers ScalarValidator.resultRegister).setWidth 32 =
                      childResult.result.bits := by
                  rw [childRegisterScalar]
                  simp
                have conditionExact := logical32Flags_equal childAfter.flags
                  childResult.result.bits (childAfter.flags.getLsbD 4)
                let tested := childAfter.test32 ScalarValidator.resultRegister
                  ScalarValidator.resultRegister (childAfter.flags.getLsbD 4)
                  (testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister).length
                have testedCondition : condition tested.flags 4 =
                    (childResult.result.bits == 0) := by
                  simpa [tested, Machine.State.test32, Machine.State.test,
                    logical32Flags, childLowScalar, BitVec.and_self] using conditionExact
                cases value <;>
                  rw [machineAfter] <;>
                  simp only [Machine.State.zeroExtendByte, Machine.State.setCondition] <;>
                  rw [testedCondition] <;>
                  simp [unaryMachineResult, ScalarValidator.resultRegister, bitsExact,
                    childRegister,
                    Machine.State.test32, Machine.State.test, BitVec.and_self]
          let coreValue : Value := result
          have coreExact :
              (Shape.unary coreOperation operand operandShape).coreValue? = some coreValue := by
            simp [Shape.coreValue?, operandExact, resultExact, Except.toOption, coreValue]
          have representation : RaxMatches coreValue
              (unaryMachineResult coreOperation childResult.result.bits) := by
            have childRepresentation : RaxMatches operandValue childResult.result.bits := by
              simpa [childCoreValue] using childResult.result.representation
            cases coreOperation with
            | positive =>
                obtain ⟨value, rfl⟩ := operandKind
                have resultEq : (Except.ok (.signed .i32 value) : Except Trap Value) =
                    Except.ok result := by
                  simpa only [evalUnaryValue] using resultExact
                cases resultEq
                simpa [coreValue, unaryMachineResult] using childRepresentation
            | negate =>
                obtain ⟨value, rfl⟩ := operandKind
                have resultEq : (Except.ok (.signed .i32
                    (wrapSigned Target.x86_64 .i32 (-value))) : Except Trap Value) =
                    Except.ok result := by
                  simpa only [evalUnaryValue] using resultExact
                cases resultEq
                apply negate_representation value childResult.result.bits
                exact childRepresentation
            | logicalNot =>
                obtain ⟨value, rfl⟩ := operandKind
                have resultEq : (Except.ok (.boolean (!value)) : Except Trap Value) =
                    Except.ok result := by
                  simpa only [evalUnaryValue] using resultExact
                cases resultEq
                have bitsExact := bool_bits_eq value childResult.result.bits childRepresentation
                cases value <;> simp [coreValue, unaryMachineResult, RaxMatches, bitsExact]
          refine ⟨⟨after, {
            result := {
              bits := unaryMachineResult coreOperation childResult.result.bits
              coreValue := coreValue
              consumed := childResult.result.consumed ++ unaryBytes coreOperation
              remainder := remainder
              steps := childResult.result.steps + unarySteps coreOperation
              run := machineRun
              loaded := by
                simpa [childResult.consumedExact, childTail, List.append_assoc] using
                  childResult.result.loaded
              remainderLoaded := by
                have loaded : CodeAt childAfter.memory childAfter.rip
                    (unaryBytes coreOperation ++ remainder) := by
                  simpa [childTail] using childResult.result.remainderLoaded
                have suffix := loaded.suffix
                simpa [machineMemory, machineRip] using suffix
              resultRegister := machineResult
              frameStable := machineRbp
              ripAdvance := by
                simp [machineRip, childRip, childResult.consumedExact,
                  List.length_append, BitVec.ofNat_add, BitVec.add_assoc]
              preserveBelow := by
                simpa [machineMemory] using childResult.result.preserveBelow
              coreValueExact := coreExact
              representation := representation }
            consumedExact := by
              simp [Shape.bodyBytes, childResult.consumedExact]
            remainderExact := by rfl
            preserveOutside := by
              simpa [Shape.allocations, machineMemory] using childResult.preserveOutside
            preserveRead64Outside := by
              simpa [Shape.allocations, machineMemory] using childResult.preserveRead64Outside
            preserveCodeAt := by
              simpa [Shape.allocations, machineMemory] using childResult.preserveCodeAt }⟩⟩
  | binary coreOperation operation leftSource rightSource operationExact left right ihLeft ihRight =>
      intro wellFormed base upper before remainder window invariant
      cases wellFormed with
      | binary _ _ _ _ _ _ _ leftWitness rightWitness leftValue rightValue result
          leftExact rightExact resultExact =>
      let slot := base + left.allocations
      let continuation :=
        frameStoreBytes slot ++ right.bodyBytes (slot + 1) ++
          BinaryMachineOp.bytes operation slot ++ remainder
      have windowShape := window
      simp [Shape.allocations] at windowShape
      have leftInvariant : FrameCodeInvariant before base upper
          (left.bodyBytes base ++ continuation) := by
        simpa [Shape.bodyBytes, slot, continuation, List.append_assoc] using invariant
      have leftWindow : base + left.allocations ≤ upper := by
        omega
      obtain ⟨⟨leftAfter, leftResult⟩⟩ := ihLeft leftWitness base upper before continuation
        leftWindow leftInvariant
      have leftTail : leftResult.result.remainder = continuation :=
        leftResult.remainderExact
      have leftRip : leftAfter.rip = before.rip +
          BitVec.ofNat 64 (left.bodyBytes base).length := by
        simpa [leftResult.consumedExact] using leftResult.result.ripAdvance
      have leftFrameInvariant : FrameCodeInvariant leftAfter base upper continuation := by
        apply FrameCodeInvariant.suffix leftInvariant
          (by simpa [leftTail] using leftResult.result.remainderLoaded)
          leftRip leftResult.result.frameStable
      let stored := leftAfter.store32 0 rbpRegister
        (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length
      have slotLower : base ≤ slot := by simp [slot]
      have slotUpper : slot < upper := by
        dsimp [slot]
        omega
      have storedInvariant : FrameCodeInvariant stored base upper
          (right.bodyBytes (slot + 1) ++ BinaryMachineOp.bytes operation slot ++ remainder) := by
        have afterStore := FrameCodeInvariant.after_store leftFrameInvariant
          slotLower slotUpper (by rfl : stored = leftAfter.store32 0 rbpRegister
            (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
        simpa [continuation, stored] using afterStore
      have rightInvariant : FrameCodeInvariant stored (slot + 1) upper
          (right.bodyBytes (slot + 1) ++ BinaryMachineOp.bytes operation slot ++ remainder) := by
        apply FrameCodeInvariant.restrict storedInvariant
        · omega
        · omega
      have rightWindow : slot + 1 + right.allocations ≤ upper := by
        change base + left.allocations + 1 + right.allocations ≤ upper
        omega
      obtain ⟨⟨rightAfter, rightResult⟩⟩ := ihRight rightWitness (slot + 1) upper stored
        (BinaryMachineOp.bytes operation slot ++ remainder) rightWindow
        (by simpa [List.append_assoc] using rightInvariant)
      have leftTail' : leftResult.result.remainder =
          frameStoreBytes slot ++ rightResult.result.consumed ++
            BinaryMachineOp.bytes operation slot ++ remainder := by
        simpa [continuation, rightResult.consumedExact, List.append_assoc] using leftTail
      have rightTail' : rightResult.result.remainder =
          BinaryMachineOp.bytes operation slot ++ remainder := rightResult.remainderExact
      have storedRip : stored.rip = leftAfter.rip +
          BitVec.ofNat 64 (frameStoreBytes slot).length := by
        simp [stored, Machine.State.store32]
      have sameRbp : rightAfter.registers rbpRegister = before.registers rbpRegister := by
        calc
          rightAfter.registers rbpRegister = stored.registers rbpRegister :=
            rightResult.result.frameStable
          _ = leftAfter.registers rbpRegister := by
            simp [stored, Machine.State.store32]
          _ = before.registers rbpRegister := leftResult.result.frameStable
      have storeSlotStable : ∀ lower, lower < base →
          read32 stored.memory (frameSlotAddress (stored.registers rbpRegister) lower) =
            read32 leftAfter.memory (frameSlotAddress (leftAfter.registers rbpRegister) lower) := by
        intro lower lowerBound
        apply lowerFrameSlot_after_store leftAfter stored slot lower rfl
        intro i j
        exact leftFrameInvariant.belowSlotsSeparated lower (by omega) slot
          slotLower slotUpper (by omega) i j
      let coreValue : Value := .signed .i32 result
      have coreExact : (Shape.binary coreOperation operation leftSource rightSource
          operationExact left right).coreValue? = some coreValue := by
        simp [Shape.coreValue?, leftExact, rightExact, resultExact, coreValue]
      have leftResultValue : leftResult.result.coreValue = .signed .i32 leftValue := by
        have exact := leftResult.result.coreValueExact
        rw [leftExact] at exact
        injection exact with valueEq
        exact valueEq.symm
      have rightResultValue : rightResult.result.coreValue = .signed .i32 rightValue := by
        have exact := rightResult.result.coreValueExact
        rw [rightExact] at exact
        injection exact with valueEq
        exact valueEq.symm
      have representation : LiteralReturn.RaxMatches coreValue
          (operation.result leftResult.result.bits rightResult.result.bits) := by
        apply binary_representation coreOperation operation leftValue rightValue result
          leftResult.result.bits rightResult.result.bits operationExact
        · simpa [leftResultValue] using leftResult.result.representation
        · simpa [rightResultValue] using rightResult.result.representation
        · exact resultExact
      obtain ⟨after, machineRun, machineResult, machineRbp, machineMemory, machineRip⟩ :=
        binary_machine base slot operation left right before leftAfter stored rightAfter
          remainder leftResult.result rightResult.result (by rfl) leftTail' rightTail' (by rfl)
      have finalBelow : ∀ lower, lower < base →
          read32 after.memory (frameSlotAddress (before.registers rbpRegister) lower) =
            read32 before.memory (frameSlotAddress (before.registers rbpRegister) lower) := by
        intro lower lowerBound
        have rightBelow := rightResult.result.preserveBelow lower (by
          dsimp [slot]
          omega)
        have rightBelow' :
            read32 rightAfter.memory
                (frameSlotAddress (rightAfter.registers rbpRegister) lower) =
              read32 stored.memory
                (frameSlotAddress (stored.registers rbpRegister) lower) := by
          simpa [rightResult.result.frameStable] using rightBelow
        have leftBelow := leftResult.result.preserveBelow lower lowerBound
        calc
          read32 after.memory
              (frameSlotAddress (before.registers rbpRegister) lower) =
            read32 rightAfter.memory
              (frameSlotAddress (rightAfter.registers rbpRegister) lower) := by
                simp [machineMemory, sameRbp]
          _ = read32 stored.memory
              (frameSlotAddress (stored.registers rbpRegister) lower) := rightBelow'
          _ = read32 leftAfter.memory
              (frameSlotAddress (leftAfter.registers rbpRegister) lower) :=
                storeSlotStable lower lowerBound
          _ = read32 before.memory
              (frameSlotAddress (before.registers rbpRegister) lower) := by
                simpa [leftResult.result.frameStable] using leftBelow
      refine ⟨⟨after, {
        result := {
          bits := operation.result leftResult.result.bits rightResult.result.bits
          coreValue := coreValue
          consumed := leftResult.result.consumed ++ frameStoreBytes slot ++
            rightResult.result.consumed ++ BinaryMachineOp.bytes operation slot
          remainder := remainder
          steps := leftResult.result.steps + (rightResult.result.steps + 4)
          run := machineRun
          loaded := by
            simpa [leftResult.consumedExact, leftTail', List.append_assoc] using
              leftResult.result.loaded
          remainderLoaded := by
            have rightLoaded : CodeAt rightAfter.memory rightAfter.rip
                (BinaryMachineOp.bytes operation slot ++ remainder) := by
              simpa [rightResult.remainderExact] using rightResult.result.remainderLoaded
            simpa [machineMemory, machineRip] using rightLoaded.suffix
          resultRegister := machineResult
          frameStable := machineRbp
          ripAdvance := by
            simp [machineRip, rightResult.result.ripAdvance,
              leftResult.result.ripAdvance, List.length_append,
              BitVec.ofNat_add, BitVec.add_assoc, storedRip]
          preserveBelow := finalBelow
          coreValueExact := coreExact
          representation := representation }
        consumedExact := by simp [Shape.bodyBytes, slot, leftResult.consumedExact,
          rightResult.consumedExact, List.append_assoc]
        remainderExact := by rfl
        preserveOutside := ?_
        preserveRead64Outside := ?_
        preserveCodeAt := ?_ }⟩⟩
      intro target targetLower targetUpper
      have targetLeftUpper : base + left.allocations ≤ target := by
        simp [Shape.allocations] at targetLower
        omega
      have targetRightUpper : slot + 1 + right.allocations ≤ target := by
        simp [Shape.allocations] at targetLower
        dsimp [slot]
        omega
      have leftOutside :
          read32 leftAfter.memory
              (frameSlotAddress (before.registers rbpRegister) target) =
            read32 before.memory
              (frameSlotAddress (before.registers rbpRegister) target) :=
        leftResult.preserveOutside target targetLeftUpper targetUpper
      have leftOutside' :
          read32 leftAfter.memory
              (frameSlotAddress (leftAfter.registers rbpRegister) target) =
            read32 before.memory
              (frameSlotAddress (before.registers rbpRegister) target) := by
        simpa [leftResult.result.frameStable] using leftOutside
      have rightOutside :
          read32 rightAfter.memory
              (frameSlotAddress (stored.registers rbpRegister) target) =
            read32 stored.memory
              (frameSlotAddress (stored.registers rbpRegister) target) :=
        rightResult.preserveOutside target targetRightUpper targetUpper
      have storeStable : read32 stored.memory
          (frameSlotAddress (leftAfter.registers rbpRegister) target) =
          read32 leftAfter.memory
            (frameSlotAddress (leftAfter.registers rbpRegister) target) := by
        apply lowerFrameSlot_after_store leftAfter stored slot target rfl
        intro i j
        exact leftFrameInvariant.slotsSeparated target slot (by omega) targetUpper
          slotLower slotUpper (by omega) i j
      have storeStable' : read32 stored.memory
          (frameSlotAddress (stored.registers rbpRegister) target) =
          read32 leftAfter.memory
            (frameSlotAddress (leftAfter.registers rbpRegister) target) := by
        simpa [stored, Machine.State.store32] using storeStable
      have rightOutside' :
          read32 rightAfter.memory
              (frameSlotAddress (rightAfter.registers rbpRegister) target) =
            read32 stored.memory
              (frameSlotAddress (stored.registers rbpRegister) target) := by
        simpa [rightResult.result.frameStable] using rightOutside
      calc
        read32 after.memory
            (frameSlotAddress (before.registers rbpRegister) target) =
            read32 rightAfter.memory
              (frameSlotAddress (rightAfter.registers rbpRegister) target) := by
                simp [machineMemory, sameRbp]
        _ = read32 stored.memory
              (frameSlotAddress (stored.registers rbpRegister) target) := rightOutside'
        _ = read32 leftAfter.memory
              (frameSlotAddress (leftAfter.registers rbpRegister) target) := storeStable'
        _ = read32 before.memory
              (frameSlotAddress (before.registers rbpRegister) target) := leftOutside'
      intro address outside
      simp [Shape.allocations] at outside
      have leftOutside64 :
          read64 leftAfter.memory address = read64 before.memory address :=
        leftResult.preserveRead64Outside address (by
          intro childSlot childLower childUpper i j
          exact outside childSlot (by omega) (by omega) i j)
      have leftOutside64' :
          read64 leftAfter.memory address = read64 before.memory address := by
        simpa [leftResult.result.frameStable] using leftOutside64
      have storeOutside64 :
          read64 stored.memory address = read64 leftAfter.memory address := by
        rw [show stored.memory = Machine.write32 leftAfter.memory
          (frameSlotAddress (leftAfter.registers rbpRegister) slot)
          ((leftAfter.registers ScalarValidator.resultRegister).setWidth 32) by
            rfl]
        apply read64_write32_frame
        intro i j
        simpa only [leftResult.result.frameStable] using
          outside slot (by
            dsimp [slot]
            omega) (by
            dsimp [slot]
            omega) i j
      have rightOutside64 :
          read64 rightAfter.memory address = read64 stored.memory address :=
        rightResult.preserveRead64Outside address (by
          intro childSlot childLower childUpper i j
          simpa [stored, Machine.State.store32, leftResult.result.frameStable] using
            outside childSlot (by
              change base ≤ childSlot
              omega) (by
              omega) i j)
      have rightOutside64' :
          read64 rightAfter.memory address = read64 stored.memory address := by
        simpa [rightResult.result.frameStable] using rightOutside64
      calc
        read64 after.memory address = read64 rightAfter.memory address := by
          simp [machineMemory]
        _ = read64 stored.memory address := rightOutside64'
        _ = read64 leftAfter.memory address := storeOutside64
        _ = read64 before.memory address := leftOutside64'
      intro address bytes loaded outside
      have leftLoaded : CodeAt leftAfter.memory address bytes :=
        leftResult.preserveCodeAt address bytes loaded (by
          intro index bound childSlot childLower childUpper lane
          have childUpper' : childSlot < base +
              (Shape.binary coreOperation operation leftSource rightSource
                operationExact left right).allocations := by
            change childSlot < base + (left.allocations + 1 + right.allocations)
            change childSlot < base + left.allocations at childUpper
            omega
          exact outside index bound childSlot childLower childUpper' lane)
      have storedLoaded : CodeAt stored.memory address bytes := by
        apply CodeAt.write32 leftLoaded
        intro index bound lane
        simpa [frameSlotAddress, leftResult.result.frameStable] using
          outside index bound slot (by simp [slot]) (by
            change base + left.allocations <
              base + (left.allocations + 1 + right.allocations)
            omega) lane
      have rightLoaded : CodeAt rightAfter.memory address bytes :=
        rightResult.preserveCodeAt address bytes storedLoaded (by
          intro index bound childSlot childLower childUpper lane
          have childBase : base ≤ childSlot := by
            change base + left.allocations + 1 ≤ childSlot at childLower
            omega
          have childUpper' : childSlot < base +
              (Shape.binary coreOperation operation leftSource rightSource
                operationExact left right).allocations := by
            change childSlot < base + (left.allocations + 1 + right.allocations)
            change childSlot < base + left.allocations + 1 + right.allocations at childUpper
            omega
          simpa [stored, Machine.State.store32, leftResult.result.frameStable] using
            outside index bound childSlot childBase childUpper' lane)
      simpa [machineMemory] using rightLoaded

/- The dependent `checkedShape` already carries the exact body bytes and its
   `WellFormed` witness.  `_accepted` is retained in the public type to tie
   that witness to the actual checker output; the recursive proof consumes the
   embedded witness directly, avoiding brittle dependent elimination on the
   `Option` equality. -/
theorem checked_recursive_result
    {source : Core.Expr} {emitted : List UInt8}
    (checkedShape : { shape : Shape source //
      emitted = shape.bodyBytes 0 ∧ WellFormed shape })
    (_accepted : checkBody? source emitted = some checkedShape)
    (base upper : Nat) (before : Machine.State) (remainder : List UInt8)
    (window : base + checkedShape.1.allocations ≤ upper)
    (invariant : FrameCodeInvariant before base upper
      (checkedShape.1.bodyBytes base ++ remainder)) :
    Nonempty (Σ after : Machine.State,
      RecursiveResult checkedShape.1 base upper remainder before after) := by
  exact recursive_result checkedShape.1 checkedShape.2.2 base upper before remainder
    window invariant

end Lanius.X86.ExpressionCheck
