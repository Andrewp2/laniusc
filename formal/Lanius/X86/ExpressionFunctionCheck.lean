import Lanius.X86.StatementCheck
import Lanius.X86.LocalExpressionCheck
import Lanius.Semantics.MutableLocal

namespace Lanius.X86.ExpressionFunctionCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck
open Lanius.X86.StatementCheck
open Lanius.X86.LocalExpressionCheck
open Lanius.X86.ScalarValidator

/- The frame protocol is independent of the source shape.  The same invariant
   is shared by the connected body certificate and its recursive suffix. -/
structure FunctionFrameInvariant (allocations : Nat) (bodyBytes : List UInt8)
    (before : Machine.State) where
  prologueDisjoint : ∀ index, index <
      (moveBytes .w64 rbpRegister rspRegister ++
        immediateBytes .w32 r11Register (frameSizeBits allocations) 0 ++
        aluBytes .w64 .subtract rspRegister r11Register).length →
    ∀ lane : Fin 8,
      before.rip + BitVec.ofNat 64 ((pushBytes rbpRegister).length + index) ≠
        before.registers rspRegister - 8 + BitVec.ofNat 64 lane.val
  body : FrameCodeInvariant (Machine.prologueState before allocations) 0 allocations bodyBytes
  savedFrameDisjoint : ∀ slot, slot < allocations → ∀ i : Fin 8, ∀ j : Fin 4,
    (Machine.prologueState before allocations).registers rbpRegister + BitVec.ofNat 64 i.val ≠
      frameSlotAddress ((Machine.prologueState before allocations).registers rbpRegister) slot +
        BitVec.ofNat 64 j.val
  returnAddressDisjoint : ∀ slot, slot < allocations → ∀ i : Fin 8, ∀ j : Fin 4,
    (Machine.prologueState before allocations).registers rbpRegister + 8 +
          BitVec.ofNat 64 i.val ≠
      frameSlotAddress ((Machine.prologueState before allocations).registers rbpRegister) slot +
        BitVec.ofNat 64 j.val

/- The uniform function-level result consumed by the caller certificate. -/
structure FunctionReturnedState {function : Function} {emitted : List UInt8}
    {certificate : Type} (checked : certificate) (allocations : Nat) (program : Program)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (returnAddress : Machine.Address) (coreAfter : Semantics.State)
    (body : Stmt) (value : Value)
    (after : Machine.State) (count : Nat) (valueExact : Prop) : Prop where
  bodyExact : function.body = some body
  coreValueExact : valueExact
  core : Executes program coreBefore body
    (.returned (some value)) coreAfter
  steps : Machine.Steps count machineBefore after
  rax : LiteralReturn.RaxMatches value ((after.registers resultRegister).setWidth 32)
  rip : after.rip = returnAddress
  stack : after.registers rspRegister = machineBefore.registers rspRegister + 8
  frame : after.registers rbpRegister = machineBefore.registers rbpRegister
  /-- Authenticated code remains intact across the saved-frame write and every
      dynamic expression spill.  The caller supplies only byte-level
      separation from those actual write locations. -/
  protectedCode : ∀ address bytes,
    CodeAt machineBefore.memory address bytes →
    (∀ index, index < bytes.length → ∀ lane : Fin 8,
      address + BitVec.ofNat 64 index ≠
        machineBefore.registers rspRegister - 8 + BitVec.ofNat 64 lane.val) →
    (∀ index, index < bytes.length → ∀ slot, slot < allocations →
      ∀ lane : Fin 4,
        address + BitVec.ofNat 64 index ≠
          frameSlotAddress
              ((Machine.prologueState machineBefore allocations).registers rbpRegister)
              slot +
            BitVec.ofNat 64 lane.val) →
    CodeAt after.memory address bytes
  /-- Reads outside the saved-RBP write and every allocated frame slot survive
      the complete function body.  These are the only writes in this suffix;
      no full-memory equality is claimed. -/
  preserveRead64Outside : ∀ address,
    (∀ i : Fin 8, ∀ j : Fin 8,
      address + BitVec.ofNat 64 i.val ≠
        machineBefore.registers rspRegister - 8 + BitVec.ofNat 64 j.val) →
    (∀ slot, slot < allocations → ∀ i : Fin 8, ∀ j : Fin 4,
      address + BitVec.ofNat 64 i.val ≠
        frameSlotAddress
            ((Machine.prologueState machineBefore allocations).registers rbpRegister)
            slot +
          BitVec.ofNat 64 j.val) →
    read64 after.memory address = read64 machineBefore.memory address

private theorem prologue_memory (before : Machine.State) (slots : Nat) :
    (Machine.prologueState before slots).memory =
      Machine.write64 before.memory
        (before.registers rspRegister - 8) (before.registers rbpRegister) := by
  rfl

private theorem prologue_rbp (before : Machine.State) (slots : Nat) :
    (Machine.prologueState before slots).registers rbpRegister =
      before.registers rspRegister - 8 := by
  simp [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
    Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
    rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes, Alu.result]

private theorem prologue_saved_frame (before : Machine.State) (slots : Nat) :
    read64 (Machine.prologueState before slots).memory
        ((Machine.prologueState before slots).registers rbpRegister) =
      before.registers rbpRegister := by
  rw [prologue_memory, prologue_rbp]
  exact read64_write64 _ _ _

private theorem prologue_return_address
    (before : Machine.State) (slots : Nat) (returnAddress : Machine.Address)
    (poppedReturn : read64 before.memory (before.registers rspRegister) = returnAddress) :
    read64 (Machine.prologueState before slots).memory
        ((Machine.prologueState before slots).registers rbpRegister + 8) = returnAddress := by
  rw [prologue_memory, prologue_rbp, BitVec.sub_add_cancel]
  calc
    read64 (Machine.write64 before.memory (before.registers rspRegister - 8)
        (before.registers rbpRegister)) (before.registers rspRegister) =
        read64 before.memory (before.registers rspRegister) := by
          apply read64_frame
          exact stackWindow_disjoint (by decide) (before.registers rspRegister)
    _ = returnAddress := poppedReturn

private theorem prologue_preserves_read64
    (before : Machine.State) (slots : Nat) (address : Machine.Address)
    (disjoint : ∀ i : Fin 8, ∀ j : Fin 8,
      address + BitVec.ofNat 64 i.val ≠
        before.registers rspRegister - 8 + BitVec.ofNat 64 j.val) :
    read64 (Machine.prologueState before slots).memory address =
      read64 before.memory address := by
  rw [prologue_memory]
  apply read64_frame
  exact disjoint

/-! A function-body shape composes the already checked next-completing
    statement fragment with one terminal return expression.  The terminal
    node owns the real frame epilogue; it is not represented as expression
    bytes alone.  This is the backend's first connected body boundary. -/

inductive BodyShape : Stmt → Type
  | terminal {source : Core.Expr}
      (expression : StatementCheck.ExpressionCertificate source) :
      BodyShape (.returnValue (some source))
  | sequence {first second : Stmt}
      (head : StatementCheck.StatementShape first)
      (tail : BodyShape second) :
      BodyShape (.sequence first second)
  | letLocal {id : VarId} {type : Ty} {initializer : Core.Expr}
      (initializerShape : StatementCheck.ExpressionCertificate initializer)
      (initializerI32 : ∃ value,
        initializerShape.checked.1.coreValue? = some (.signed .i32 value)) :
      BodyShape (.letLocal id type initializer
        (.returnValue (some (.local id))))

def BodyShape.coreValue? {source : Stmt} : BodyShape source → Option Value
  | .terminal expression => expression.checked.1.coreValue?
  | .sequence _ tail => tail.coreValue?
  | .letLocal initializer _ => initializer.checked.1.coreValue?

def BodyShape.allocations {source : Stmt} : BodyShape source → Nat
  | .terminal expression => expression.checked.1.allocations
  | .sequence head tail => max head.allocations tail.allocations
  | .letLocal initializerShape _ => max 1 initializerShape.checked.1.allocations

def BodyShape.bodyBytes {source : Stmt} (shape : BodyShape source) (base : Nat) : List UInt8 :=
  match shape with
  | .terminal expression => expression.checked.1.bodyBytes base ++ binaryEpilogueBytes
  | .sequence head tail => head.bodyBytes base ++ tail.bodyBytes base
  | .letLocal initializerShape _ =>
      initializerShape.checked.1.bodyBytes base ++ frameStoreBytes base ++
        frameLoadBytes base ++ binaryEpilogueBytes

/- A scalar let's body is checked in the existing statement fragment, with the
   one additional terminal local read made available by the binding.  The
   first milestone deliberately keeps the dynamic slot at the binding's base;
   nested lets will advance this environment in the next frame milestone. -/
def checkBodyShape? : (source : Stmt) → Option (BodyShape source)
  | .returnValue (some source) =>
      match StatementCheck.expressionCertificate? source with
      | none => none
      | some expression => some (.terminal expression)
  | .sequence first second =>
      match StatementCheck.checkShape? first, checkBodyShape? second with
      | some head, some tail => some (.sequence head tail)
      | none, _ => none
      | _, none => none
  | .letLocal id (.scalar (.signed .i32)) initializer
      (.returnValue (some (.local bodyId))) =>
      match StatementCheck.expressionCertificate? initializer with
      | some initializerShape =>
          match exact : initializerShape.checked.1.coreValue? with
          | some (.signed .i32 value) =>
              if same : bodyId = id then
                (by simpa [same] using
                  (some (BodyShape.letLocal (id := id) (type := _) (initializer := initializer)
                    initializerShape ⟨value, exact⟩)))
              else none
          | _ => none
      | none => none
  | _ => none

def bodyFunctionBytes {source : Stmt} (shape : BodyShape source) : List UInt8 :=
  framePrologueBytes shape.allocations ++ shape.bodyBytes 0 ++ ud2Bytes

structure BodySupported (function : Function) (emitted : List UInt8) where
  source : Stmt
  checkedShape : { shape : BodyShape source //
    emitted = bodyFunctionBytes shape }
  allocationsBound : checkedShape.1.allocations ≤ 2^28
  functionIdI32 : function.id < 2147483648
  zeroParameters : function.parameters = []
  resultType : function.returnType = .scalar (.signed .i32)
  internal : function.external = none
  bodyExact : function.body = some source

def BodySupported.resultValue? {function : Function} {emitted : List UInt8}
    (checked : BodySupported function emitted) : Option Value :=
  checked.checkedShape.1.coreValue?

def checkBody (function : Function) (emitted : List UInt8) :
    Option (BodySupported function emitted) :=
  match function with
  | ⟨id, parameters, returnType, some source, none⟩ =>
      if functionIdI32 : id < 2147483648 then
        if zeroParameters : parameters = [] then
          if resultType : returnType = .scalar (.signed .i32) then
            match checkBodyShape? source with
            | none => none
            | some shape =>
                if bytesExact : emitted = bodyFunctionBytes shape then
                  if allocationsBound : shape.allocations ≤ 2^28 then
                    some {
                      source := source
                      checkedShape := ⟨shape, bytesExact⟩
                      allocationsBound := allocationsBound
                      functionIdI32 := functionIdI32
                      zeroParameters := zeroParameters
                      resultType := resultType
                      internal := rfl
                      bodyExact := rfl }
                  else none
                else none
          else none
        else none
      else none
  | _ => none

def checkBodyValue? (function : Function) (emitted : List UInt8) : Option Value :=
  (checkBody function emitted).bind BodySupported.resultValue?

abbrev BodyFrameInvariant {source : Stmt} (shape : BodyShape source)
    (before : Machine.State) : Prop :=
  FunctionFrameInvariant shape.allocations (shape.bodyBytes 0 ++ ud2Bytes) before

structure BodySuffixResult {source : Stmt} (shape : BodyShape source)
    (program : Program) (coreBefore : Semantics.State)
    (coreAfter : Semantics.State) (before after : Machine.State)
    (savedFrame returnAddress : Machine.Address) where
  value : Value
  coreValueExact : shape.coreValue? = some value
  core : Executes program coreBefore source (.returned (some value)) coreAfter
  coreStable : ∃ threshold, StableStmt threshold program coreBefore source
    (.returned (some value)) coreAfter
  bits : BitVec 32
  representation : LiteralReturn.RaxMatches value bits
  steps : Nat
  run : Steps steps before after
  resultRegister : after.registers resultRegister = bits.setWidth 64
  rip : after.rip = returnAddress
  stack : after.registers rspRegister = before.registers rbpRegister + 16
  frameStable : after.registers rbpRegister = savedFrame
  preserveRead64Outside : ∀ address,
    (∀ slot, slot < shape.allocations → ∀ i : Fin 8, ∀ j : Fin 4,
      address + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot +
          BitVec.ofNat 64 j.val) →
    read64 after.memory address = read64 before.memory address
  preserveCodeAt : ∀ address bytes,
    CodeAt before.memory address bytes →
    (∀ index, index < bytes.length → ∀ slot, slot < shape.allocations →
      ∀ lane : Fin 4,
        address + BitVec.ofNat 64 index ≠
          frameSlotAddress (before.registers rbpRegister) slot +
            BitVec.ofNat 64 lane.val) →
    CodeAt after.memory address bytes

abbrev BodyResult {function : Function} {emitted : List UInt8}
    (checked : BodySupported function emitted) (program : Program)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (returnAddress : Machine.Address) (coreAfter : Semantics.State)
    (body : Stmt) (value : Value)
    (after : Machine.State) (count : Nat) : Prop :=
  FunctionReturnedState (function := function) (emitted := emitted)
    (certificate := BodySupported function emitted) checked
    checked.checkedShape.1.allocations program coreBefore machineBefore returnAddress coreAfter
    body value after count (checked.checkedShape.1.coreValue? = some value)

def BodySupported.result {function : Function} {emitted : List UInt8}
    (checked : BodySupported function emitted) (program : Program)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (returnAddress : Machine.Address) : Prop :=
  ∃ coreAfter body value after count,
    BodyResult checked program coreBefore machineBefore returnAddress coreAfter body value after count

theorem BodySupported.result_value
    {function : Function} {emitted : List UInt8}
    (checked : BodySupported function emitted)
    {program : Program} {coreBefore : Semantics.State}
    {machineBefore : Machine.State} {returnAddress : Machine.Address}
    (result : checked.result program coreBefore machineBefore returnAddress) :
    ∃ coreAfter body value after count,
      BodyResult checked program coreBefore machineBefore returnAddress
        coreAfter body value after count ∧
      checked.resultValue? = some value ∧
      LiteralReturn.RaxMatches value
        ((after.registers resultRegister).setWidth 32) := by
  rcases result with ⟨coreAfter, body, value, after, count, result⟩
  exact ⟨coreAfter, body, value, after, count, result,
    result.coreValueExact, result.rax⟩

theorem body_suffix_result
    {source : Stmt} (shape : BodyShape source)
    (program : Program) (coreBefore : Semantics.State)
    (upper : Nat) (before : Machine.State)
    (savedFrame returnAddress : Machine.Address)
    (savedRead : read64 before.memory (before.registers rbpRegister) = savedFrame)
    (returnRead : read64 before.memory (before.registers rbpRegister + 8) = returnAddress)
    (savedDisjoint : ∀ slot, slot < shape.allocations → ∀ i : Fin 8, ∀ j : Fin 4,
      before.registers rbpRegister + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot + BitVec.ofNat 64 j.val)
    (returnDisjoint : ∀ slot, slot < shape.allocations → ∀ i : Fin 8, ∀ j : Fin 4,
      before.registers rbpRegister + 8 + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot + BitVec.ofNat 64 j.val)
    (coreFormed : coreBefore.CellsWellFormed)
    (window : shape.allocations ≤ upper)
    (suffix : List UInt8)
    (invariant : FrameCodeInvariant before 0 upper
      (shape.bodyBytes 0 ++ suffix)) :
    Nonempty (Σ coreAfter : Semantics.State, Σ after : Machine.State,
      BodySuffixResult shape program coreBefore coreAfter before after
        savedFrame returnAddress) := by
  revert program coreBefore upper before savedFrame returnAddress savedRead returnRead
    savedDisjoint returnDisjoint coreFormed suffix
  induction shape with
  | terminal expression =>
      intro program coreBefore upper before savedFrame returnAddress savedRead returnRead
        savedDisjoint returnDisjoint coreFormed window suffix invariant
      let remainder := binaryEpilogueBytes ++ suffix
      have expressionInvariant : FrameCodeInvariant before 0 upper
          (expression.checked.1.bodyBytes 0 ++ remainder) := by
        simpa [remainder, BodyShape.bodyBytes, List.append_assoc] using invariant
      obtain ⟨⟨bodyAfter, expressionResult⟩⟩ :=
        checked_recursive_result expression.checked expression.accepted 0 upper before remainder
          (by simpa [BodyShape.allocations] using window) expressionInvariant
      have loadedTail : CodeAt bodyAfter.memory bodyAfter.rip remainder := by
        simpa [expressionResult.remainderExact] using expressionResult.result.remainderLoaded
      have loadedEpilogue : CodeAt bodyAfter.memory bodyAfter.rip binaryEpilogueBytes := by
        simpa [remainder] using loadedTail.prefix
      have savedRead' : read64 bodyAfter.memory (bodyAfter.registers rbpRegister) = savedFrame := by
        rw [expressionResult.result.frameStable]
        exact (expressionResult.preserveRead64Outside _ (by
          intro slot _ slotUpper i j
          exact savedDisjoint slot
            (by simpa [BodyShape.allocations] using slotUpper) i j)).trans savedRead
      have returnRead' : read64 bodyAfter.memory (bodyAfter.registers rbpRegister + 8) = returnAddress := by
        rw [expressionResult.result.frameStable]
        exact (expressionResult.preserveRead64Outside _ (by
          intro slot _ slotUpper i j
          exact returnDisjoint slot
            (by simpa [BodyShape.allocations] using slotUpper) i j)).trans returnRead
      obtain ⟨after, epilogueRun, finalResult, finalFrame, _finalStack, _finalRip,
          finalMemory, _flags⟩ :=
        binaryEpilogue_machine bodyAfter (expressionResult.result.bits.setWidth 64)
          loadedEpilogue savedFrame returnAddress savedRead' returnRead'
          expressionResult.result.resultRegister
      obtain ⟨value, valueExact, coreRun⟩ :=
        shape_return_executes (program := program) (state := coreBefore)
          expression.checked.1 expression.checked.2.2
      obtain ⟨stableValue, stableExact, coreStable⟩ :=
        shape_return_stable (program := program) (state := coreBefore)
          expression.checked.1 expression.checked.2.2
      have stableValueEq : stableValue = value :=
        Option.some.inj (stableExact.symm.trans valueExact)
      subst stableValue
      have valueEq : value = expressionResult.result.coreValue :=
        Option.some.inj (valueExact.symm.trans expressionResult.result.coreValueExact)
      refine ⟨⟨coreBefore, after, {
        value := value
        coreValueExact := by simpa [BodyShape.coreValue?] using valueExact
        core := coreRun
        coreStable := ⟨_, coreStable⟩
        bits := expressionResult.result.bits
        representation := by simpa [valueEq] using expressionResult.result.representation
        steps := expressionResult.result.steps + 3
        run := expressionResult.result.run.trans epilogueRun
        resultRegister := by simpa [finalResult] using finalResult
        rip := _finalRip
        stack := by
          calc
            after.registers rspRegister = bodyAfter.registers rbpRegister + 16 := _finalStack
            _ = before.registers rbpRegister + 16 := by
              rw [expressionResult.result.frameStable]
        frameStable := finalFrame
        preserveRead64Outside := by
          intro address outside
          simpa [finalMemory] using
            expressionResult.preserveRead64Outside address (by
              intro slot lowerBound upperBound i j
              exact outside slot
                (by simpa [BodyShape.allocations] using upperBound) i j)
        preserveCodeAt := by
          intro address bytes loaded outside
          have bodyCode := expressionResult.preserveCodeAt address bytes loaded (by
            intro index bound slot lowerBound slotUpper lane
            exact outside index bound slot
              (by simpa [BodyShape.allocations] using slotUpper) lane)
          simpa [finalMemory] using bodyCode }⟩⟩
  | sequence head tail ihTail =>
      intro program coreBefore upper before savedFrame returnAddress savedRead returnRead
        savedDisjoint returnDisjoint coreFormed window suffix invariant
      have sequenceWindow : (BodyShape.sequence head tail).allocations ≤ upper := window
      have fullInvariant : FrameCodeInvariant before 0 upper
          (head.bodyBytes 0 ++ (tail.bodyBytes 0 ++ suffix)) := by
        simpa [BodyShape.bodyBytes, List.append_assoc] using invariant
      have sequenceInvariant : FrameCodeInvariant before 0
          (BodyShape.sequence head tail).allocations
          (head.bodyBytes 0 ++ (tail.bodyBytes 0 ++ suffix)) := by
        exact FrameCodeInvariant.restrict fullInvariant (Nat.le_refl _) sequenceWindow
      have headWindow : head.allocations ≤ (BodyShape.sequence head tail).allocations := by
        simpa [BodyShape.allocations] using (Nat.le_max_left head.allocations tail.allocations)
      have headInvariant : FrameCodeInvariant before 0
          (BodyShape.sequence head tail).allocations
          (head.bodyBytes 0 ++ (tail.bodyBytes 0 ++ suffix)) := by
        simpa [BodyShape.bodyBytes, List.append_assoc] using sequenceInvariant
      obtain ⟨middle, headExact⟩ := checked_shape_result head program coreBefore
        0 (BodyShape.sequence head tail).allocations before
        (tail.bodyBytes 0 ++ suffix)
        (by simpa using headWindow) sequenceInvariant
      have middleInvariant : FrameCodeInvariant middle 0
          (BodyShape.sequence head tail).allocations
          (tail.bodyBytes 0 ++ suffix) := by
        have headRip : middle.rip = before.rip +
            BitVec.ofNat 64 (head.bodyBytes 0).length := by
          simpa [headExact.consumedExact] using headExact.result.ripAdvance
        have remainderLoaded : CodeAt middle.memory middle.rip
          (tail.bodyBytes 0 ++ suffix) := by
          simpa [headExact.remainderExact] using headExact.result.remainderLoaded
        exact FrameCodeInvariant.suffix headInvariant remainderLoaded headRip
          headExact.result.frameStable
      have savedReadMiddle :
          read64 middle.memory (middle.registers rbpRegister) = savedFrame := by
        rw [headExact.result.frameStable]
        exact (headExact.result.preserveRead64Outside _ (by
          intro slot lowerBound upperBound i j
          exact savedDisjoint slot
            (by simpa [BodyShape.allocations] using upperBound) i j)).trans savedRead
      have returnReadMiddle :
          read64 middle.memory (middle.registers rbpRegister + 8) = returnAddress := by
        rw [headExact.result.frameStable]
        exact (headExact.result.preserveRead64Outside _ (by
          intro slot lowerBound upperBound i j
          exact returnDisjoint slot
            (by simpa [BodyShape.allocations] using upperBound) i j)).trans returnRead
      have tailSavedDisjoint : ∀ slot, slot < tail.allocations → ∀ i : Fin 8, ∀ j : Fin 4,
          middle.registers rbpRegister + BitVec.ofNat 64 i.val ≠
            frameSlotAddress (middle.registers rbpRegister) slot + BitVec.ofNat 64 j.val := by
        intro slot slotUpper i j
        simpa [headExact.result.frameStable] using savedDisjoint slot
          ((Nat.lt_of_lt_of_le slotUpper (Nat.le_max_right _ _))) i j
      have tailReturnDisjoint : ∀ slot, slot < tail.allocations → ∀ i : Fin 8, ∀ j : Fin 4,
          middle.registers rbpRegister + 8 + BitVec.ofNat 64 i.val ≠
            frameSlotAddress (middle.registers rbpRegister) slot + BitVec.ofNat 64 j.val := by
        intro slot slotUpper i j
        simpa [headExact.result.frameStable] using returnDisjoint slot
          ((Nat.lt_of_lt_of_le slotUpper (Nat.le_max_right _ _))) i j
      obtain ⟨⟨tailCoreAfter, after, tailResult⟩⟩ := ihTail program coreBefore
        (BodyShape.sequence head tail).allocations middle savedFrame
        returnAddress savedReadMiddle returnReadMiddle tailSavedDisjoint tailReturnDisjoint
        coreFormed
        (by simpa [BodyShape.allocations] using
          (Nat.le_max_right head.allocations tail.allocations))
        suffix
        middleInvariant
      refine ⟨⟨tailCoreAfter, after, {
        value := tailResult.value
        coreValueExact := by simpa [BodyShape.coreValue?] using tailResult.coreValueExact
        core := by
          obtain ⟨headFuel, headContract⟩ := headExact.result.coreStable
          obtain ⟨tailFuel, tailContract⟩ := tailResult.coreStable
          have sequenceContract := StableStmt.sequence_next headContract tailContract
          exact ⟨max headFuel tailFuel + 1,
            sequenceContract _ (Nat.le_refl _)⟩
        coreStable := by
          obtain ⟨headFuel, headContract⟩ := headExact.result.coreStable
          obtain ⟨tailFuel, tailContract⟩ := tailResult.coreStable
          exact ⟨max headFuel tailFuel + 1,
            StableStmt.sequence_next headContract tailContract⟩
        bits := tailResult.bits
        representation := tailResult.representation
        steps := headExact.result.steps + tailResult.steps
        run := headExact.result.run.trans tailResult.run
        resultRegister := tailResult.resultRegister
        rip := tailResult.rip
        stack := by
          calc
            after.registers rspRegister = middle.registers rbpRegister + 16 := tailResult.stack
            _ = before.registers rbpRegister + 16 := by
              rw [headExact.result.frameStable]
        frameStable := tailResult.frameStable
        preserveRead64Outside := by
          intro address outside
          have headOutside := headExact.result.preserveRead64Outside address (by
            intro slot lowerBound upperBound i j
            exact outside slot upperBound i j)
          have tailOutside := tailResult.preserveRead64Outside address (by
            intro slot slotUpper i j
            have slotShape : slot < (BodyShape.sequence head tail).allocations := by
              exact Nat.lt_of_lt_of_le slotUpper (Nat.le_max_right _ _)
            simpa [headExact.result.frameStable] using outside slot slotShape i j)
          exact tailOutside.trans headOutside
        preserveCodeAt := by
          intro address bytes loaded outside
          have middleLoaded := headExact.result.preserveCodeAt address bytes loaded (by
            intro index bound slot lowerBound upperBound lane
            exact outside index bound slot upperBound lane)
          exact tailResult.preserveCodeAt address bytes middleLoaded (by
            intro index bound slot slotUpper lane
            have slotShape : slot < (BodyShape.sequence head tail).allocations := by
              exact Nat.lt_of_lt_of_le slotUpper (Nat.le_max_right _ _)
            simpa [headExact.result.frameStable] using outside index bound slot
              slotShape lane) }⟩⟩
  | @letLocal id type initializer initializerShape initializerI32 =>
      intro program coreBefore upper before savedFrame returnAddress savedRead returnRead
        savedDisjoint returnDisjoint coreFormed window suffix invariant
      let remainder := frameStoreBytes 0 ++ frameLoadBytes 0 ++
        (binaryEpilogueBytes ++ suffix)
      have initializerInvariant : FrameCodeInvariant before 0 upper
          (initializerShape.checked.1.bodyBytes 0 ++ remainder) := by
        simpa [remainder, BodyShape.bodyBytes, List.append_assoc] using invariant
      have initializerWindow : initializerShape.checked.1.allocations ≤ upper := by
        simp [BodyShape.allocations] at window ⊢
        omega
      let initializerI32Witness := initializerI32
      have zeroSlot : 0 <
          (BodyShape.letLocal (id := id) (type := type) (initializer := initializer)
            initializerShape initializerI32Witness).allocations := by
        simpa [BodyShape.allocations] using
          (Nat.lt_of_lt_of_le Nat.zero_lt_one
            (Nat.le_max_left 1 initializerShape.checked.1.allocations))
      have upperPositive : 0 < upper := Nat.lt_of_lt_of_le zeroSlot window
      have savedDisjointMax : ∀ slot,
          slot < max 1 initializerShape.checked.1.allocations → ∀ i : Fin 8, ∀ j : Fin 4,
            before.registers rbpRegister + BitVec.ofNat 64 i.val ≠
              frameSlotAddress (before.registers rbpRegister) slot +
                BitVec.ofNat 64 j.val := by
        intro slot bound i j
        exact savedDisjoint slot (by
          change slot < max 1 initializerShape.checked.1.allocations
          exact bound) i j
      have returnDisjointMax : ∀ slot,
          slot < max 1 initializerShape.checked.1.allocations → ∀ i : Fin 8, ∀ j : Fin 4,
            before.registers rbpRegister + 8 + BitVec.ofNat 64 i.val ≠
              frameSlotAddress (before.registers rbpRegister) slot +
                BitVec.ofNat 64 j.val := by
        intro slot bound i j
        exact returnDisjoint slot (by
          change slot < max 1 initializerShape.checked.1.allocations
          exact bound) i j
      obtain ⟨⟨initializerAfter, initializerResult⟩⟩ :=
        checked_recursive_result initializerShape.checked initializerShape.accepted
          0 upper before remainder (by simpa using initializerWindow) initializerInvariant
      have initializerTailLoaded : CodeAt initializerAfter.memory initializerAfter.rip
          remainder := by
        simpa [initializerResult.remainderExact] using initializerResult.result.remainderLoaded
      have initializerRip : initializerAfter.rip = before.rip +
          BitVec.ofNat 64 (initializerShape.checked.1.bodyBytes 0).length := by
        simpa [initializerResult.consumedExact] using initializerResult.result.ripAdvance
      have initializerAfterInvariant : FrameCodeInvariant initializerAfter 0 upper remainder := by
        exact FrameCodeInvariant.suffix initializerInvariant initializerTailLoaded initializerRip
          initializerResult.result.frameStable
      obtain ⟨initializerValue, initializerValueExact, initializerEvaluates⟩ :=
        shape_evaluates_at initializerShape.checked.1 initializerShape.checked.2.2
          (shapeFuel initializerShape.checked.1) (Nat.le_refl _)
          program coreBefore
      have initializerValueEq : initializerValue = initializerResult.result.coreValue :=
        Option.some.inj (initializerValueExact.symm.trans
          initializerResult.result.coreValueExact)
      obtain ⟨initializerInt, initializerI32Exact⟩ := initializerI32Witness
      have initializerSigned : initializerValue = .signed .i32 initializerInt := by
        have resultExact := initializerResult.result.coreValueExact
        have staticExact : initializerResult.result.coreValue =
            .signed .i32 initializerInt := by
          exact Option.some.inj (resultExact.symm.trans initializerI32Exact)
        exact initializerValueEq.trans staticExact
      have initializerStable : StableExpr (shapeFuel initializerShape.checked.1)
          program coreBefore initializer initializerValue coreBefore := by
        intro fuel enough
        obtain ⟨value, valueExact, evaluates⟩ :=
          shape_evaluates_at initializerShape.checked.1 initializerShape.checked.2.2 fuel
            (by omega) program coreBefore
        have valueEq : value = initializerValue :=
          Option.some.inj (valueExact.symm.trans initializerValueExact)
        subst value
        exact evaluates
      let stored := initializerAfter.store32 0 rbpRegister
        (BitVec.ofInt 32 (frameDisplacement 0)) (frameStoreBytes 0).length
      have storeLoaded : CodeAt initializerAfter.memory initializerAfter.rip
          (frameStoreBytes 0) := by
        exact initializerTailLoaded.prefix.prefix
      have storeResult : stored = initializerAfter.store32 0 rbpRegister
          (BitVec.ofInt 32 (frameDisplacement 0)) (frameStoreBytes 0).length := by
        rfl
      have storeStep : Step initializerAfter stored :=
        frameStore_step initializerAfter stored 0 storeLoaded storeResult
      have bodyInvariant : FrameCodeInvariant stored 0 upper
          (frameLoadBytes 0 ++ (binaryEpilogueBytes ++ suffix)) := by
        apply FrameCodeInvariant.after_store initializerAfterInvariant
        · omega
        · exact upperPositive
        · exact storeResult
      have savedReadInit : read64 initializerAfter.memory
          (initializerAfter.registers rbpRegister) = savedFrame := by
        rw [initializerResult.result.frameStable]
        exact (initializerResult.preserveRead64Outside _ (by
          intro slot _ slotUpper i j
          exact savedDisjoint slot (by
            change slot < max 1 initializerShape.checked.1.allocations
            exact Nat.lt_of_lt_of_le (by simpa only [Nat.zero_add] using slotUpper)
              (Nat.le_max_right _ _)) i j)).trans savedRead
      have returnReadInit : read64 initializerAfter.memory
          (initializerAfter.registers rbpRegister + 8) = returnAddress := by
        rw [initializerResult.result.frameStable]
        exact (initializerResult.preserveRead64Outside _ (by
          intro slot _ slotUpper i j
          exact returnDisjoint slot (by
            change slot < max 1 initializerShape.checked.1.allocations
            exact Nat.lt_of_lt_of_le (by simpa only [Nat.zero_add] using slotUpper)
              (Nat.le_max_right _ _)) i j)).trans returnRead
      have savedReadStored : read64 stored.memory
          (stored.registers rbpRegister) = savedFrame := by
        rw [storeResult]
        rw [show stored.registers rbpRegister = initializerAfter.registers rbpRegister by rfl]
        exact (read64_write32_frame initializerAfter.memory
          (frameSlotAddress (initializerAfter.registers rbpRegister) 0)
          (initializerAfter.registers rbpRegister) _ (by
            intro i j
            simpa [initializerResult.result.frameStable] using
              savedDisjointMax 0 (Nat.lt_of_lt_of_le Nat.zero_lt_one
                (Nat.le_max_left _ _)) i j
          )).trans savedReadInit
      have returnReadStored : read64 stored.memory
          (stored.registers rbpRegister + 8) = returnAddress := by
        rw [storeResult]
        rw [show stored.registers rbpRegister = initializerAfter.registers rbpRegister by rfl]
        exact (read64_write32_frame initializerAfter.memory
          (frameSlotAddress (initializerAfter.registers rbpRegister) 0)
          (initializerAfter.registers rbpRegister + 8) _ (by
            intro i j
            simpa [initializerResult.result.frameStable] using
              returnDisjointMax 0 (Nat.lt_of_lt_of_le Nat.zero_lt_one
                (Nat.le_max_left _ _)) i j
          )).trans returnReadInit
      have localValue : (coreBefore.bindLocal id initializerValue).local? id =
          some (.signed .i32 initializerInt) := by
        simpa [initializerSigned] using
          State.bindLocal_local? coreBefore coreFormed id (.signed .i32 initializerInt)
      let environment : BodyEnvironment (coreBefore.bindLocal id initializerValue) stored := {
        id := id
        location := .frame 0
        value := initializerInt
        localValue := localValue
        frameSlots := upper
        frameBound := by
          intro slot h
          cases h
          omega
        registerSafe := by
          intro register h
          cases h
        representedRegister := by
          intro register h
          cases h
        representedFrame := by
          intro slot h
          cases h
          change (read32 (initializerAfter.store32 0 rbpRegister
            (BitVec.ofInt 32 (frameDisplacement 0)) (frameStoreBytes 0).length).memory
            (frameSlotAddress (initializerAfter.registers rbpRegister) 0)).toInt = initializerInt
          rw [frameStore_slot_value]
          change (BitVec.setWidth 32 (initializerAfter.registers resultRegister)).toInt = initializerInt
          rw [initializerResult.result.resultRegister]
          have staticCore : initializerResult.result.coreValue =
              .signed .i32 initializerInt := by
            exact Option.some.inj (initializerResult.result.coreValueExact.symm.trans
              initializerI32Exact)
          simpa [LiteralReturn.RaxMatches, staticCore] using
            initializerResult.result.representation
          }
      let localChecked : LocalExpressionCheck.Supported environment
          (.local id) (frameLoadBytes 0) := {
        id := id
        location := .frame 0
        idExact := rfl
        locationExact := rfl
        sourceExact := rfl
        bytesExact := rfl }
      have localLoaded : CodeAt stored.memory stored.rip (frameLoadBytes 0) :=
        bodyInvariant.loaded.prefix
      obtain ⟨localAfter, localCore, localStep, localResult, localRip,
          localRsp, localPreserved, localMemory, localFlags⟩ :=
        LocalExpressionCheck.preserves localChecked program localLoaded
      let localBits : BitVec 32 := BitVec.ofInt 32 environment.value
      have epilogueLoaded : CodeAt localAfter.memory localAfter.rip
          binaryEpilogueBytes := by
        have suffix := bodyInvariant.loaded.suffix
        have localRip' : localAfter.rip = stored.rip +
            BitVec.ofNat 64 (frameLoadBytes 0).length := by
          simpa [LocalExpressionCheck.Location.bodyBytes] using localRip
        rw [localMemory, localRip']
        simpa using suffix.prefix
      have localRbp : localAfter.registers rbpRegister = stored.registers rbpRegister :=
        localPreserved rbpRegister (by decide) (by decide)
      have savedReadLocal : read64 localAfter.memory
          (localAfter.registers rbpRegister) = savedFrame := by
        rw [localMemory, localRbp]
        exact savedReadStored
      have returnReadLocal : read64 localAfter.memory
          (localAfter.registers rbpRegister + 8) = returnAddress := by
        rw [localMemory, localRbp]
        exact returnReadStored
      obtain ⟨after, epilogueRun, finalResult, finalFrame, _finalStack, _finalRip,
          finalMemory, _finalFlags⟩ :=
        binaryEpilogue_machine localAfter (localBits.setWidth 64)
          epilogueLoaded savedFrame returnAddress savedReadLocal returnReadLocal
          (by simpa [localBits] using localResult)
      let coreBeforeBound : Semantics.State := coreBefore.bindLocal id initializerValue
      have bodyStable : StableStmt 2 program coreBeforeBound
          (.returnValue (some (.local id)))
          (.returned (some (.signed .i32 initializerInt))) coreBeforeBound := by
        intro fuel enough
        have localEval := evalExpr_local_of_local? (fuel - 2) program coreBeforeBound id
          (.signed .i32 initializerInt) (by simpa [coreBeforeBound] using localValue)
        have localEval' : evalExpr (fuel - 1) program coreBeforeBound (.local id) =
            .done (.signed .i32 initializerInt) coreBeforeBound := by
          simpa [show fuel - 2 + 1 = fuel - 1 by omega] using localEval
        simpa [show fuel - 1 + 1 = fuel by omega] using
          execStmt_return (fuel - 1) program coreBeforeBound (.local id)
            (.signed .i32 initializerInt) coreBeforeBound localEval'
      let finalCore : Semantics.State := restoreLocals coreBefore coreBeforeBound
      have coreRun : Executes program coreBefore
          (.letLocal id type initializer
            (.returnValue (some (.local id))))
          (.returned (some (.signed .i32 initializerInt))) finalCore := by
        let fuel := max (shapeFuel initializerShape.checked.1) 2
        refine ⟨fuel + 1, ?_⟩
        apply execStmt_letLocal fuel program coreBefore
          id type initializer
          (.returnValue (some (.local id))) initializerValue coreBefore coreBeforeBound
          (.returned (some (.signed .i32 initializerInt)))
        · exact initializerStable fuel (Nat.le_max_left _ _)
        · exact bodyStable fuel (Nat.le_max_right _ _)
      have coreStable : StableStmt (max (shapeFuel initializerShape.checked.1) 2 + 1)
          program coreBefore
          (.letLocal id type initializer
            (.returnValue (some (.local id))))
          (.returned (some (.signed .i32 initializerInt))) finalCore := by
        exact StableStmt.letLocal program coreBefore id type
          initializer (.returnValue (some (.local id)))
          initializerValue coreBefore coreBeforeBound
          (.returned (some (.signed .i32 initializerInt))) initializerStable bodyStable
      refine ⟨⟨finalCore, after, {
        value := .signed .i32 initializerInt
        coreValueExact := by simpa [BodyShape.coreValue?] using initializerI32Exact
        core := coreRun
        coreStable := ⟨_, coreStable⟩
        bits := localBits
        representation := by
          simp only [LiteralReturn.RaxMatches, localBits]
          exact environment.value_toInt
        steps := initializerResult.result.steps + 1 + 1 + 3
        run := initializerResult.result.run.trans
          (Steps.cons storeStep (Steps.cons localStep epilogueRun))
        resultRegister := by simpa [finalResult] using finalResult
        rip := _finalRip
        stack := by
          calc
            after.registers rspRegister = localAfter.registers rbpRegister + 16 := _finalStack
            _ = before.registers rbpRegister + 16 := by
              rw [localRbp]
              rw [show stored.registers rbpRegister = initializerAfter.registers rbpRegister by rfl]
              rw [initializerResult.result.frameStable]
        frameStable := by
          exact finalFrame
        preserveRead64Outside := by
          intro address outside
          have storedOutside : read64 stored.memory address =
              read64 initializerAfter.memory address := by
            rw [storeResult]
            exact read64_write32_frame initializerAfter.memory
              (frameSlotAddress (initializerAfter.registers rbpRegister) 0) address _ (by
                intro i j
                simpa [initializerResult.result.frameStable] using
                  outside 0 (by
                    change 0 < max 1 initializerShape.checked.1.allocations
                    exact Nat.lt_of_lt_of_le Nat.zero_lt_one (Nat.le_max_left _ _)) i j
              )
          have initializerOutside := initializerResult.preserveRead64Outside address (by
            intro slot lowerBound upperBound i j
            simpa [initializerResult.result.frameStable] using
              outside slot (by
                change slot < max 1 initializerShape.checked.1.allocations
                exact Nat.lt_of_lt_of_le (by simpa only [Nat.zero_add] using upperBound)
                  (Nat.le_max_right _ _)) i j
          )
          calc
            read64 after.memory address = read64 localAfter.memory address := by rw [finalMemory]
            _ = read64 stored.memory address := by rw [localMemory]
            _ = read64 initializerAfter.memory address := storedOutside
            _ = read64 before.memory address := initializerOutside
        preserveCodeAt := by
          intro address bytes loaded outside
          have initializerCode := initializerResult.preserveCodeAt address bytes loaded (by
            intro index bound slot lowerBound upperBound lane
            exact outside index bound slot (by
              change slot < max 1 initializerShape.checked.1.allocations
              exact Nat.lt_of_lt_of_le (by simpa only [Nat.zero_add] using upperBound)
                (Nat.le_max_right _ _)) lane)
          have storedCode : CodeAt stored.memory address bytes := by
            rw [storeResult]
            apply initializerCode.write32
            intro index bound lane
            simpa [initializerResult.result.frameStable, frameSlotAddress] using
              outside index bound 0
                (by
                  change 0 < max 1 initializerShape.checked.1.allocations
                  exact Nat.lt_of_lt_of_le Nat.zero_lt_one (Nat.le_max_left _ _)) lane
          simpa [finalMemory, localMemory] using storedCode }
      ⟩⟩
theorem BodySupported.preserves {function : Function} {emitted : List UInt8}
    (checked : BodySupported function emitted) (program : Program)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (loaded : CodeAt machineBefore.memory machineBefore.rip emitted)
    (frame : BodyFrameInvariant checked.checkedShape.1 machineBefore)
    (coreFormed : coreBefore.CellsWellFormed)
    (returnAddress : Machine.Address)
    (poppedReturn : read64 machineBefore.memory
      (machineBefore.registers rspRegister) = returnAddress) :
    BodySupported.result checked program coreBefore machineBefore returnAddress := by
  have loadedFull : CodeAt machineBefore.memory machineBefore.rip
      (bodyFunctionBytes checked.checkedShape.1) := by
    simpa [checked.checkedShape.2] using loaded
  have loadedFunction : CodeAt machineBefore.memory machineBefore.rip
      (framePrologueBytes checked.checkedShape.1.allocations ++
        (checked.checkedShape.1.bodyBytes 0 ++ ud2Bytes)) := by
    simpa [bodyFunctionBytes, List.append_assoc] using loadedFull
  have loadedPrologue := loadedFunction.prefix
  have prologueRun := framePrologue_steps checked.checkedShape.1.allocations machineBefore
    loadedPrologue (by
      intro index bound lane
      simpa [BitVec.add_zero] using frame.prologueDisjoint index bound lane)
  have savedRead : read64 (Machine.prologueState machineBefore
      checked.checkedShape.1.allocations).memory
      ((Machine.prologueState machineBefore checked.checkedShape.1.allocations).registers rbpRegister) =
      machineBefore.registers rbpRegister :=
    prologue_saved_frame machineBefore checked.checkedShape.1.allocations
  have returnRead : read64 (Machine.prologueState machineBefore
      checked.checkedShape.1.allocations).memory
      ((Machine.prologueState machineBefore checked.checkedShape.1.allocations).registers rbpRegister + 8) =
      returnAddress :=
    prologue_return_address machineBefore checked.checkedShape.1.allocations returnAddress poppedReturn
  obtain ⟨⟨bodyCoreAfter, bodyAfter, bodyResult⟩⟩ := body_suffix_result checked.checkedShape.1 program
    coreBefore checked.checkedShape.1.allocations
    (Machine.prologueState machineBefore checked.checkedShape.1.allocations)
    (machineBefore.registers rbpRegister) returnAddress savedRead returnRead
    frame.savedFrameDisjoint frame.returnAddressDisjoint coreFormed (Nat.le_refl _)
    ud2Bytes
    (by simpa [bodyFunctionBytes, List.append_assoc] using frame.body)
  change ∃ coreAfter body value after count,
    BodyResult checked program coreBefore machineBefore returnAddress coreAfter body value after count
  refine ⟨bodyCoreAfter, checked.source, bodyResult.value, bodyAfter, 4 + bodyResult.steps, {
    bodyExact := checked.bodyExact
    coreValueExact := by simpa [BodyShape.coreValue?] using bodyResult.coreValueExact
    core := bodyResult.core
    steps := prologueRun.trans bodyResult.run
    rax := by simpa [bodyResult.resultRegister] using bodyResult.representation
    rip := bodyResult.rip
    stack := by
      calc
        bodyAfter.registers rspRegister =
            (Machine.prologueState machineBefore checked.checkedShape.1.allocations).registers rbpRegister + 16 :=
          bodyResult.stack
        _ = machineBefore.registers rspRegister + 8 := by
          simp [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
            Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
            rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
            Alu.result, BitVec.sub_eq_add_neg, BitVec.add_assoc]
    frame := bodyResult.frameStable
    protectedCode := by
      intro address bytes loaded savedDisjoint slotsDisjoint
      exact bodyResult.preserveCodeAt address bytes (by
        rw [prologue_memory]
        exact loaded.write64 _ (by
          intro index bound lane
          exact savedDisjoint index bound lane)) (by
        intro index bound slot slotUpper lane
        exact slotsDisjoint index bound slot (by omega) lane)
    preserveRead64Outside := by
      intro address savedDisjoint slotsDisjoint
      have bodyOutside := bodyResult.preserveRead64Outside address (by
        intro slot slotUpper i j
        exact slotsDisjoint slot slotUpper i j)
      have prologueOutside := prologue_preserves_read64 machineBefore
        checked.checkedShape.1.allocations address savedDisjoint
      calc
        read64 bodyAfter.memory address =
            read64 (Machine.prologueState machineBefore
              checked.checkedShape.1.allocations).memory address := bodyOutside
        _ = read64 machineBefore.memory address := prologueOutside
  }⟩

end Lanius.X86.ExpressionFunctionCheck
