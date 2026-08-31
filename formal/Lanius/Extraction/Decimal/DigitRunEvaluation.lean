import Lanius.Extraction.Decimal.DigitRunModel

namespace Lanius.Extraction.Decimal.DigitRunEvaluation

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Stateful
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.DigitRunModel

theorem startOutOfBounds_evaluates (source : List Byte) (start base : Nat) :
    Term.evaluate (Effectful.machine verifiedFrontendCore helperCallModel)
        world
        (environment source start base) DigitRunCommand.startOutOfBounds =
      .ok (.boolean (decide (source.length ≤ start)), world) := by
  calc
    _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
        world (environment source start base)
        DigitRunCommand.startOutOfBounds :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := verifiedFrontendCore) (calls := helperCallModel)
        DigitRunCommand.startOutOfBounds (by native_decide)
    _ = _ := by
      apply ReadOnly.Term.evaluate_i32_greaterEqual
      · rfl
      · rfl

theorem index_evaluates
    {arity : Nat} (currentEnvironment : Env arity)
    (sourceTerm positionTerm : Term signature arity)
    (source : List Byte) (position : Nat) (inBounds : position < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore helperCallModel) world
      currentEnvironment sourceTerm =
        .ok (sourceSlice source, world))
    (positionResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore helperCallModel) world
      currentEnvironment positionTerm =
        .ok (.signed .i32 position, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore helperCallModel)
        world currentEnvironment
        (DigitRunCommand.index sourceTerm positionTerm) =
      .ok (.signed .i32 (source.get ⟨position, inBounds⟩).val,
        world) := by
  apply Term.evaluate_apply2 sourceResult positionResult
  have operation := ReadOnly.evaluateOperation_i32_index
    (program := verifiedFrontendCore)
    (world := world) (cell := 0)
    (values := sourceIntegers source) (position := position)
    (baseType := DigitRunCommand.sliceType)
    (indexType := Program.i32Type) (elementType := Program.i32Type)
    sourceFound
    (by simpa using inBounds)
  simpa [Effectful.machine, Effectful.evaluateOperation,
    DigitRunCommand.index, DigitRunCommand.sliceType,
    DigitRunModel.sourceSlice,
    sourceIntegers, Program.i32Type] using
    operation

theorem isDigit_evaluates
    {arity : Nat} (world : World) (currentEnvironment : Env arity)
    (byteTerm baseTerm : Term signature arity) (byte : Byte) (base : Nat)
    (baseBound : base ≤ 2147483647)
    (byteResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore helperCallModel) world
      currentEnvironment byteTerm = .ok (.signed .i32 byte.val, world))
    (baseResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore helperCallModel) world
      currentEnvironment baseTerm = .ok (.signed .i32 base, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore helperCallModel)
        world currentEnvironment (DigitRunCommand.isDigit byteTerm baseTerm) =
      .ok (.boolean (isDigitForBase byte base), world) := by
  apply Term.evaluate_apply2 byteResult baseResult
  simpa [Effectful.machine, Effectful.evaluateOperation,
    DigitRunCommand.isDigit, DigitRunCommand.call] using
    helperCallModel_isDigit world byte base baseBound

theorem failed_evaluates
    {arity : Nat} (world : World) (currentEnvironment : Env arity)
    (offsetTerm : Term signature arity) (offset : Nat)
    (offsetBound : offset ≤ 2147483647)
    (offsetResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore helperCallModel) world
      currentEnvironment offsetTerm = .ok (.signed .i32 offset, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore helperCallModel)
        world currentEnvironment (DigitRunCommand.failed offsetTerm) =
      .ok (digitValue (.failure offset), world) := by
  apply Term.evaluate_apply1 offsetResult
  simpa [Effectful.machine, Effectful.evaluateOperation,
    DigitRunCommand.failed, DigitRunCommand.call] using
    helperCallModel_failed world offset offsetBound

theorem successful_evaluates
    {arity : Nat} (world : World) (currentEnvironment : Env arity)
    (offsetTerm : Term signature arity) (offset : Nat)
    (offsetBound : offset ≤ 2147483647)
    (offsetResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore helperCallModel) world
      currentEnvironment offsetTerm = .ok (.signed .i32 offset, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore helperCallModel)
        world currentEnvironment (DigitRunCommand.successful offsetTerm) =
      .ok (digitValue (.success offset), world) := by
  apply Term.evaluate_apply1 offsetResult
  simpa [Effectful.machine, Effectful.evaluateOperation,
    DigitRunCommand.successful, DigitRunCommand.call] using
    helperCallModel_successful world offset offsetBound

theorem loopCondition_evaluates (source : List Byte) (start base offset : Nat) :
    Term.evaluate termMachine world
        (loopEnvironment source start base offset)
        DigitRunCommand.loopCondition =
      .ok (.boolean (decide (offset < source.length)), world) := by
  calc
    _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
        world (loopEnvironment source start base offset)
        DigitRunCommand.loopCondition :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := verifiedFrontendCore) (calls := helperCallModel)
        DigitRunCommand.loopCondition (by native_decide)
    _ = _ := by
      apply ReadOnly.Term.evaluate_i32_less
      · rfl
      · rfl

theorem currentByte_evaluates (source : List Byte) (start base offset : Nat)
    (inBounds : offset < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    Term.evaluate termMachine world
        (loopEnvironment source start base offset)
        DigitRunCommand.currentByte =
      .ok (.signed .i32 (source.get ⟨offset, inBounds⟩).val,
        world) := by
  apply index_evaluates (source := source) (position := offset)
    (inBounds := inBounds) (sourceFound := sourceFound)
  · rfl
  · rfl

theorem currentValid_evaluates (source : List Byte) (start base offset : Nat)
    (byte : Byte) (baseBound : base ≤ 2147483647) :
    Term.evaluate termMachine world
        ((loopEnvironment source start base offset).push
          (.signed .i32 byte.val)) DigitRunCommand.currentValid =
      .ok (.boolean (isDigitForBase byte base), world) := by
  apply isDigit_evaluates (baseBound := baseBound)
  · rfl
  · rfl

theorem currentSeparator_evaluates
    (source : List Byte) (start base offset : Nat) (byte : Byte) :
    Term.evaluate termMachine world
        ((loopEnvironment source start base offset).push
          (.signed .i32 byte.val)) DigitRunCommand.currentSeparator =
      .ok (.boolean (decide (byte.val = 95)), world) := by
  calc
    _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
        world
        ((loopEnvironment source start base offset).push
          (.signed .i32 byte.val)) DigitRunCommand.currentSeparator :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := verifiedFrontendCore) (calls := helperCallModel)
        DigitRunCommand.currentSeparator (by native_decide)
    _ = _ := by
      apply ReadOnly.Term.evaluate_i32_equal
      · rfl
      · rfl

theorem addOne_evaluates
    {arity : Nat} (world : World) (currentEnvironment : Env arity)
    (left : Term signature arity) (value : Nat)
    (bound : value + 1 ≤ 2147483647)
    (leftResult : Term.evaluate termMachine world currentEnvironment left =
      .ok (.signed .i32 value, world)) :
    Term.evaluate termMachine world currentEnvironment
        (DigitRunCommand.add left (DigitRunCommand.i32 1)) =
      .ok (.signed .i32 (value + 1), world) := by
  apply Term.evaluate_apply2 leftResult (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.binary .add Program.i32Type Program.i32Type Program.i32Type)
    [.signed .i32 value, .signed .i32 1] = _
  exact ReadOnly.evaluateOperation_i32_add
    (program := verifiedFrontendCore) (world := world)
    (leftType := Program.i32Type) (rightType := Program.i32Type)
    (outputType := Program.i32Type) value 1 bound

theorem logicalNot_evaluates
    {arity : Nat} (world : World) (currentEnvironment : Env arity)
    (term : Term signature arity) (value : Bool)
    (termResult : Term.evaluate termMachine world currentEnvironment term =
      .ok (.boolean value, world)) :
    Term.evaluate termMachine world currentEnvironment
        (DigitRunCommand.unary .logicalNot term) =
      .ok (.boolean (!value), world) := by
  apply Term.evaluate_apply1 termResult
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.unary .logicalNot DigitRunCommand.boolType DigitRunCommand.boolType)
      [.boolean value] = _
  rfl

theorem requiredInitializer_evaluates
    (source : List Byte) (start base offset : Nat) (byte : Byte)
    (bound : offset + 1 ≤ 2147483647) :
    Term.evaluate termMachine world
        ((loopEnvironment source start base offset).push
          (.signed .i32 byte.val))
        DigitRunCommand.requiredInitializer =
      .ok (.signed .i32 (offset + 1), world) := by
  apply addOne_evaluates (value := offset) (bound := bound)
  rfl

theorem requiredOutOfBounds_evaluates
    (source : List Byte) (start base offset : Nat) (byte : Byte) :
    Term.evaluate termMachine world
        (((loopEnvironment source start base offset).push
          (.signed .i32 byte.val)).push (.signed .i32 (offset + 1)))
        DigitRunCommand.requiredOutOfBounds =
      .ok (.boolean (decide (source.length ≤ offset + 1)),
        world) := by
  calc
    _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
        world
        (((loopEnvironment source start base offset).push
          (.signed .i32 byte.val)).push (.signed .i32 (offset + 1)))
        DigitRunCommand.requiredOutOfBounds :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := verifiedFrontendCore) (calls := helperCallModel)
        DigitRunCommand.requiredOutOfBounds (by native_decide)
    _ = _ := by
      apply ReadOnly.Term.evaluate_i32_greaterEqual
      · rfl
      · rfl

theorem requiredInvalid_evaluates
    (source : List Byte) (start base offset : Nat) (byte : Byte)
    (baseBound : base ≤ 2147483647)
    (nextInBounds : offset + 1 < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    Term.evaluate termMachine world
        (((loopEnvironment source start base offset).push
          (.signed .i32 byte.val)).push (.signed .i32 (offset + 1)))
        DigitRunCommand.requiredInvalid =
      .ok (.boolean (!(isDigitForBase
        (source.get ⟨offset + 1, nextInBounds⟩) base)), world) := by
  apply logicalNot_evaluates
  apply isDigit_evaluates (baseBound := baseBound)
  · apply index_evaluates (source := source) (position := offset + 1)
      (inBounds := nextInBounds) (sourceFound := sourceFound)
    · rfl
    · rfl
  · rfl

theorem offsetAfterRequired_evaluates
    (source : List Byte) (start base offset : Nat) (byte : Byte)
    (bound : offset + 2 ≤ 2147483647) :
    Term.evaluate termMachine world
        (((loopEnvironment source start base offset).push
          (.signed .i32 byte.val)).push (.signed .i32 (offset + 1)))
        DigitRunCommand.offsetAfterRequired =
      .ok (.signed .i32 (offset + 2), world) := by
  have oneBound : offset + 1 + 1 ≤ 2147483647 := by omega
  have evaluated := addOne_evaluates
    (world := world)
    (currentEnvironment :=
      ((loopEnvironment source start base offset).push
        (.signed .i32 byte.val)).push (.signed .i32 (offset + 1)))
    (left := DigitRunCommand.slot 6) (value := offset + 1)
    (bound := oneBound) (leftResult := by rfl)
  have addition : ((offset + 1 : Nat) : Int) + 1 =
      (offset : Int) + 2 := by omega
  rw [addition] at evaluated
  simpa only [DigitRunCommand.offsetAfterRequired] using evaluated

@[simp] theorem loopEnvironment_set_offset
    (source : List Byte) (start base oldOffset newOffset : Nat) :
    Env.set (loopEnvironment source start base oldOffset) ⟨4, by omega⟩
        (.signed .i32 newOffset) =
      loopEnvironment source start base newOffset := by
  funext index
  simp only [Env.set]
  split
  next same =>
    have last : index.val = 4 := congrArg Fin.val same
    simp [loopEnvironment, Env.push, last]
  next different =>
    have before : index.val < 4 := by
      by_cases isBefore : index.val < 4
      · exact isBefore
      · have last : index.val = 4 := by omega
        exact False.elim (different (Fin.ext last))
    simp [loopEnvironment, Env.push, before]

theorem loopBody_accepted_evaluates
    (source : List Byte) (start base offset : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (inBounds : offset < source.length)
    (accepted : isDigitForBase (source.get ⟨offset, inBounds⟩) base = true)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    Command.Evaluates termMachine commandMachine world
      (loopEnvironment source start base offset) DigitRunCommand.loopBody
      .next world
      (loopEnvironment source start base (offset + 1)) := by
  let byte := source.get ⟨offset, inBounds⟩
  have byteResult := currentByte_evaluates (world := world)
    source start base offset inBounds sourceFound
  have validResult := currentValid_evaluates (world := world)
    source start base offset byte baseBound
  rw [show isDigitForBase byte base = true by simpa [byte] using accepted]
    at validResult
  have oneResult : Term.evaluate termMachine world
      ((loopEnvironment source start base offset).push
        (.signed .i32 byte.val)) (DigitRunCommand.i32 1) =
      .ok (.signed .i32 1, world) := by rfl
  have updateResult : commandMachine.evalLocalUpdate .add
      (((loopEnvironment source start base offset).push
        (.signed .i32 byte.val)) ⟨4, by omega⟩)
      (.signed .i32 1) = .ok (.signed .i32 (offset + 1)) := by
    have bound : offset + 1 ≤ 2147483647 :=
      Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
    simp only [commandMachine, Stateful.machineWith]
    change Lanius.Semantics.evalAssignValue verifiedFrontendCore.target .add
      (some (.signed .i32 offset)) (.signed .i32 1) = _
    simp only [Lanius.Semantics.evalAssignValue,
      Lanius.Semantics.assignOpBinary?, Lanius.Semantics.evalBinaryValue,
      beq_self_eq_true, if_true, Lanius.Semantics.evalSignedBinary]
    have addition : (offset : Int) + 1 = (offset + 1 : Nat) := by omega
    rw [addition]
    have wrapped := Lanius.Semantics.wrapSigned_i32_ofNat
      verifiedFrontendCore.target (offset + 1) bound
    congr 3
  have updated : Command.Evaluates termMachine commandMachine
      world
      ((loopEnvironment source start base offset).push
        (.signed .i32 byte.val))
      (.updateLocal .add 4 (DigitRunCommand.i32 1)) .next
      world
      (Env.set ((loopEnvironment source start base offset).push
        (.signed .i32 byte.val)) ⟨4, by omega⟩
        (.signed .i32 (offset + 1))) :=
    .updateLocal oneResult updateResult
  have updatedStatement := Command.Evaluates.sequenceNext updated
    (Command.Evaluates.skip (termMachine := termMachine)
      (machine := commandMachine))
  have popped : Env.pop
      (Env.set ((loopEnvironment source start base offset).push
        (.signed .i32 byte.val)) ⟨4, by omega⟩
        (.signed .i32 (offset + 1))) =
      loopEnvironment source start base (offset + 1) := by
    funext index
    simp only [Env.pop, Env.set]
    split
    next same =>
      have last : index.val = 4 := congrArg Fin.val same
      simp [loopEnvironment, Env.push, last]
    next different =>
      have before : index.val < 4 := by
        by_cases isBefore : index.val < 4
        · exact isBefore
        · have last : index.val = 4 := by omega
          exact False.elim (different (Fin.ext last))
      simp [loopEnvironment, Env.push, before]
  rw [← popped]
  unfold DigitRunCommand.loopBody
  apply Command.Evaluates.letValue (by simpa [byte] using byteResult)
  apply Command.Evaluates.sequenceNext
  · exact Command.Evaluates.ifTrue validResult updatedStatement
  · exact .skip

theorem loopBody_boundary_evaluates
    (source : List Byte) (start base offset : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (inBounds : offset < source.length)
    (rejected : isDigitForBase (source.get ⟨offset, inBounds⟩) base = false)
    (notSeparator : (source.get ⟨offset, inBounds⟩).val ≠ 95)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    ∃ afterEnvironment : Env 5,
      Command.Evaluates termMachine commandMachine world
        (loopEnvironment source start base offset) DigitRunCommand.loopBody
        (.returned (some (digitValue (.success offset))))
        world afterEnvironment := by
  let byte := source.get ⟨offset, inBounds⟩
  have byteResult := currentByte_evaluates (world := world)
    source start base offset inBounds sourceFound
  have validResult := currentValid_evaluates (world := world)
    source start base offset byte baseBound
  rw [show isDigitForBase byte base = false by
    simpa [byte] using rejected] at validResult
  have separatorResult := currentSeparator_evaluates (world := world)
    source start base offset byte
  have separatorFalse : decide (byte.val = 95) = false := by
    simp [show byte.val ≠ 95 by simpa [byte] using notSeparator]
  rw [separatorFalse] at separatorResult
  have successResult : Term.evaluate termMachine world
      ((loopEnvironment source start base offset).push
        (.signed .i32 byte.val))
      (DigitRunCommand.successful (DigitRunCommand.slot 4)) =
      .ok (digitValue (.success offset), world) := by
    apply successful_evaluates
      (offsetBound := Nat.le_trans (Nat.le_of_lt inBounds) sourceBound)
    rfl
  refine ⟨Env.pop ((loopEnvironment source start base offset).push
    (.signed .i32 byte.val)), ?_⟩
  unfold DigitRunCommand.loopBody
  apply Command.Evaluates.letValue (by simpa [byte] using byteResult)
  apply Command.Evaluates.sequenceStop
  · apply Command.Evaluates.ifFalse validResult
    apply Command.Evaluates.sequenceStop
    · apply Command.Evaluates.ifFalse separatorResult
      apply Command.Evaluates.sequenceStop
      · exact Command.Evaluates.returnSome successResult
      · simp
    · simp
  · simp

theorem loopBody_separatorAtEnd_evaluates
    (source : List Byte) (start base offset : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (inBounds : offset < source.length)
    (rejected : isDigitForBase (source.get ⟨offset, inBounds⟩) base = false)
    (separator : (source.get ⟨offset, inBounds⟩).val = 95)
    (requiredAtEnd : offset + 1 = source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    ∃ afterEnvironment : Env 5,
      Command.Evaluates termMachine commandMachine world
        (loopEnvironment source start base offset) DigitRunCommand.loopBody
        (.returned (some (digitValue (.failure (offset + 1)))))
        world afterEnvironment := by
  let byte := source.get ⟨offset, inBounds⟩
  let byteEnvironment := (loopEnvironment source start base offset).push
    (.signed .i32 byte.val)
  let requiredEnvironment := byteEnvironment.push (.signed .i32 (offset + 1))
  have byteResult := currentByte_evaluates (world := world)
    source start base offset inBounds sourceFound
  have validResult := currentValid_evaluates (world := world)
    source start base offset byte baseBound
  rw [show isDigitForBase byte base = false by simpa [byte] using rejected]
    at validResult
  have separatorResult := currentSeparator_evaluates (world := world)
    source start base offset byte
  rw [show decide (byte.val = 95) = true by
    simp [show byte.val = 95 by simpa [byte] using separator]] at separatorResult
  have requiredBound : offset + 1 ≤ 2147483647 := by
    rw [requiredAtEnd]
    exact sourceBound
  have initializer := requiredInitializer_evaluates (world := world)
    source start base offset byte requiredBound
  have atEnd := requiredOutOfBounds_evaluates (world := world)
    source start base offset byte
  rw [show decide (source.length ≤ offset + 1) = true by
    simp [requiredAtEnd]] at atEnd
  have failureResult : Term.evaluate termMachine world
      requiredEnvironment (DigitRunCommand.failed (DigitRunCommand.slot 6)) =
      .ok (digitValue (.failure (offset + 1)), world) := by
    apply failed_evaluates (offsetBound := requiredBound)
    rfl
  refine ⟨Env.pop (Env.pop requiredEnvironment), ?_⟩
  unfold DigitRunCommand.loopBody
  apply Command.Evaluates.letValue (by simpa [byte] using byteResult)
  apply Command.Evaluates.sequenceStop
  · apply Command.Evaluates.ifFalse (by
      simpa [byteEnvironment, byte] using validResult)
    apply Command.Evaluates.sequenceStop
    · apply Command.Evaluates.ifTrue
        (by simpa [byteEnvironment, byte] using separatorResult)
      apply Command.Evaluates.letValue
        (by simpa [byteEnvironment, byte] using initializer)
      apply Command.Evaluates.sequenceStop
      · apply Command.Evaluates.ifTrue
          (by simpa [requiredEnvironment, byteEnvironment, byte] using atEnd)
        apply Command.Evaluates.sequenceStop
        · exact Command.Evaluates.returnSome (by
            simpa [requiredEnvironment, byteEnvironment, byte] using failureResult)
        · simp
      · simp
    · simp
  · simp

theorem loopBody_separatorInvalid_evaluates
    (source : List Byte) (start base offset : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (inBounds : offset < source.length)
    (rejected : isDigitForBase (source.get ⟨offset, inBounds⟩) base = false)
    (separator : (source.get ⟨offset, inBounds⟩).val = 95)
    (nextInBounds : offset + 1 < source.length)
    (nextRejected : isDigitForBase
      (source.get ⟨offset + 1, nextInBounds⟩) base = false)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    ∃ afterEnvironment : Env 5,
      Command.Evaluates termMachine commandMachine world
        (loopEnvironment source start base offset) DigitRunCommand.loopBody
        (.returned (some (digitValue (.failure (offset + 1)))))
        world afterEnvironment := by
  let byte := source.get ⟨offset, inBounds⟩
  let byteEnvironment := (loopEnvironment source start base offset).push
    (.signed .i32 byte.val)
  let requiredEnvironment := byteEnvironment.push (.signed .i32 (offset + 1))
  have byteResult := currentByte_evaluates (world := world)
    source start base offset inBounds sourceFound
  have validResult := currentValid_evaluates (world := world)
    source start base offset byte baseBound
  rw [show isDigitForBase byte base = false by simpa [byte] using rejected]
    at validResult
  have separatorResult := currentSeparator_evaluates (world := world)
    source start base offset byte
  rw [show decide (byte.val = 95) = true by
    simp [show byte.val = 95 by simpa [byte] using separator]] at separatorResult
  have requiredBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
  have initializer := requiredInitializer_evaluates (world := world)
    source start base offset byte requiredBound
  have atEnd := requiredOutOfBounds_evaluates (world := world)
    source start base offset byte
  rw [show decide (source.length ≤ offset + 1) = false by
    simp [Nat.not_le.mpr nextInBounds]] at atEnd
  have invalid := requiredInvalid_evaluates (world := world)
    source start base offset byte baseBound nextInBounds sourceFound
  rw [nextRejected] at invalid
  have failureResult : Term.evaluate termMachine world
      requiredEnvironment (DigitRunCommand.failed (DigitRunCommand.slot 6)) =
      .ok (digitValue (.failure (offset + 1)), world) := by
    apply failed_evaluates (offsetBound := requiredBound)
    rfl
  refine ⟨Env.pop (Env.pop requiredEnvironment), ?_⟩
  unfold DigitRunCommand.loopBody
  apply Command.Evaluates.letValue (by simpa [byte] using byteResult)
  apply Command.Evaluates.sequenceStop
  · apply Command.Evaluates.ifFalse (by
      simpa [byteEnvironment, byte] using validResult)
    apply Command.Evaluates.sequenceStop
    · apply Command.Evaluates.ifTrue
        (by simpa [byteEnvironment, byte] using separatorResult)
      apply Command.Evaluates.letValue
        (by simpa [byteEnvironment, byte] using initializer)
      apply Command.Evaluates.sequenceNext
      · exact Command.Evaluates.ifFalse
          (by simpa [requiredEnvironment, byteEnvironment, byte] using atEnd) .skip
      · apply Command.Evaluates.sequenceStop
        · apply Command.Evaluates.ifTrue
            (by simpa [requiredEnvironment, byteEnvironment, byte] using invalid)
          apply Command.Evaluates.sequenceStop
          · exact Command.Evaluates.returnSome (by
              simpa [requiredEnvironment, byteEnvironment, byte] using failureResult)
          · simp
        · simp
    · simp
  · simp

theorem popPopSetOffset_eq_loopEnvironment
    (source : List Byte) (start base oldOffset newOffset : Nat)
    (byte : Byte) :
    Env.pop (Env.pop
      (Env.set (((loopEnvironment source start base oldOffset).push
        (.signed .i32 byte.val)).push (.signed .i32 (oldOffset + 1)))
        ⟨4, by omega⟩ (.signed .i32 newOffset))) =
      loopEnvironment source start base newOffset := by
  funext index
  simp only [Env.pop, Env.set]
  split
  next same =>
    have last : index.val = 4 := congrArg Fin.val same
    simp [loopEnvironment, Env.push, last]
  next different =>
    have before : index.val < 4 := by
      by_cases isBefore : index.val < 4
      · exact isBefore
      · have last : index.val = 4 := by omega
        exact False.elim (different (Fin.ext last))
    have beforeFive : index.val < 5 := by omega
    have beforeSix : index.val < 6 := by omega
    simp [loopEnvironment, Env.push, before, beforeFive, beforeSix]

theorem loopBody_separatorAccepted_evaluates
    (source : List Byte) (start base offset : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (inBounds : offset < source.length)
    (rejected : isDigitForBase (source.get ⟨offset, inBounds⟩) base = false)
    (separator : (source.get ⟨offset, inBounds⟩).val = 95)
    (nextInBounds : offset + 1 < source.length)
    (nextAccepted : isDigitForBase
      (source.get ⟨offset + 1, nextInBounds⟩) base = true)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    Command.Evaluates termMachine commandMachine world
      (loopEnvironment source start base offset) DigitRunCommand.loopBody
      .next world
      (loopEnvironment source start base (offset + 2)) := by
  let byte := source.get ⟨offset, inBounds⟩
  let byteEnvironment := (loopEnvironment source start base offset).push
    (.signed .i32 byte.val)
  let requiredEnvironment := byteEnvironment.push (.signed .i32 (offset + 1))
  have byteResult := currentByte_evaluates (world := world)
    source start base offset inBounds sourceFound
  have validResult := currentValid_evaluates (world := world)
    source start base offset byte baseBound
  rw [show isDigitForBase byte base = false by simpa [byte] using rejected]
    at validResult
  have separatorResult := currentSeparator_evaluates (world := world)
    source start base offset byte
  rw [show decide (byte.val = 95) = true by
    simp [show byte.val = 95 by simpa [byte] using separator]] at separatorResult
  have requiredBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
  have initializer := requiredInitializer_evaluates (world := world)
    source start base offset byte requiredBound
  have atEnd := requiredOutOfBounds_evaluates (world := world)
    source start base offset byte
  rw [show decide (source.length ≤ offset + 1) = false by
    simp [Nat.not_le.mpr nextInBounds]] at atEnd
  have invalid := requiredInvalid_evaluates (world := world)
    source start base offset byte baseBound nextInBounds sourceFound
  rw [nextAccepted] at invalid
  have nextBound : offset + 2 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt nextInBounds) sourceBound
  have assignmentValue := offsetAfterRequired_evaluates (world := world)
    source start base offset byte nextBound
  have assigned := Command.Evaluates.setLocal
    (machine := commandMachine) (target := (⟨4, by omega⟩ : Fin 7))
    assignmentValue
  have assignedStatement := Command.Evaluates.sequenceNext assigned
    (Command.Evaluates.skip (termMachine := termMachine)
      (machine := commandMachine))
  have popped := popPopSetOffset_eq_loopEnvironment
    source start base offset (offset + 2) byte
  rw [← popped]
  unfold DigitRunCommand.loopBody
  apply Command.Evaluates.letValue (by simpa [byte] using byteResult)
  apply Command.Evaluates.sequenceNext
  · apply Command.Evaluates.ifFalse (by
      simpa [byteEnvironment, byte] using validResult)
    apply Command.Evaluates.sequenceNext
    · apply Command.Evaluates.ifTrue
        (by simpa [byteEnvironment, byte] using separatorResult)
      apply Command.Evaluates.letValue
        (by simpa [byteEnvironment, byte] using initializer)
      apply Command.Evaluates.sequenceNext
      · exact Command.Evaluates.ifFalse
          (by simpa [requiredEnvironment, byteEnvironment, byte] using atEnd) .skip
      · apply Command.Evaluates.sequenceNext
        · exact Command.Evaluates.ifFalse
            (by simpa [requiredEnvironment, byteEnvironment, byte] using invalid) .skip
        · exact assignedStatement
    · exact .skip
  · exact .skip

theorem loop_evaluates
    (source : List Byte) (start base offset : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (offsetBound : offset ≤ source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (scanDigitTail base (source.drop offset) offset = .success source.length ∧
      Command.Evaluates termMachine commandMachine world
        (loopEnvironment source start base offset)
        (.whileLoop DigitRunCommand.loopCondition DigitRunCommand.loopBody)
        .next world
        (loopEnvironment source start base source.length)) ∨
    (∃ afterEnvironment : Env 5,
      Command.Evaluates termMachine commandMachine world
        (loopEnvironment source start base offset)
        (.whileLoop DigitRunCommand.loopCondition DigitRunCommand.loopBody)
        (.returned (some (digitValue
          (scanDigitTail base (source.drop offset) offset))))
        world afterEnvironment) := by
  by_cases inBounds : offset < source.length
  · have condition := loopCondition_evaluates (world := world)
      source start base offset
    rw [show decide (offset < source.length) = true by simp [inBounds]] at condition
    let byte := source.get ⟨offset, inBounds⟩
    have dropped : source.drop offset = byte :: source.drop (offset + 1) := by
      simpa [byte] using List.drop_eq_getElem_cons inBounds
    by_cases accepted : isDigitForBase byte base = true
    · have body := loopBody_accepted_evaluates source start base offset
        sourceBound baseBound inBounds (by simpa [byte] using accepted)
        sourceFound
      have step : scanDigitTail base (source.drop offset) offset =
          scanDigitTail base (source.drop (offset + 1)) (offset + 1) := by
        rw [dropped, scanDigitTail.eq_def]
        simp [accepted]
      rcases loop_evaluates source start base (offset + 1) sourceBound
          baseBound (Nat.succ_le_of_lt inBounds) sourceFound with left | right
      · left
        exact ⟨step.trans left.1,
          Command.Evaluates.whileNext condition body left.2⟩
      · right
        obtain ⟨afterEnvironment, rest⟩ := right
        refine ⟨afterEnvironment, ?_⟩
        rw [step]
        exact Command.Evaluates.whileNext condition body rest
    · have rejected : isDigitForBase byte base = false := by
        cases result : isDigitForBase byte base with
        | false => rfl
        | true => exact False.elim (accepted result)
      by_cases separator : byte.val = 95
      · by_cases nextInBounds : offset + 1 < source.length
        · let nextByte := source.get ⟨offset + 1, nextInBounds⟩
          have nextDropped : source.drop (offset + 1) =
              nextByte :: source.drop (offset + 2) := by
            have baseDrop := List.drop_eq_getElem_cons nextInBounds
            simpa [nextByte, Nat.add_assoc] using baseDrop
          by_cases nextAccepted : isDigitForBase nextByte base = true
          · have body := loopBody_separatorAccepted_evaluates source start base
                offset sourceBound baseBound inBounds
                (by simpa [byte] using rejected)
                (by simpa [byte] using separator) nextInBounds
                (by simpa [nextByte] using nextAccepted) sourceFound
            have step : scanDigitTail base (source.drop offset) offset =
                scanDigitTail base (source.drop (offset + 2)) (offset + 2) := by
              rw [dropped, nextDropped, scanDigitTail.eq_def]
              simp [rejected, separator, nextAccepted]
            rcases loop_evaluates source start base (offset + 2) sourceBound
                baseBound (Nat.succ_le_of_lt nextInBounds) sourceFound with left | right
            · left
              exact ⟨step.trans left.1,
                Command.Evaluates.whileNext condition body left.2⟩
            · right
              obtain ⟨afterEnvironment, rest⟩ := right
              refine ⟨afterEnvironment, ?_⟩
              rw [step]
              exact Command.Evaluates.whileNext condition body rest
          · have nextRejected : isDigitForBase nextByte base = false := by
              cases result : isDigitForBase nextByte base with
              | false => rfl
              | true => exact False.elim (nextAccepted result)
            obtain ⟨afterEnvironment, body⟩ :=
              loopBody_separatorInvalid_evaluates source start base offset
                sourceBound baseBound inBounds (by simpa [byte] using rejected)
                (by simpa [byte] using separator) nextInBounds
                (by simpa [nextByte] using nextRejected) sourceFound
            have resultEq : scanDigitTail base (source.drop offset) offset =
                .failure (offset + 1) := by
              rw [dropped, nextDropped, scanDigitTail.eq_def]
              simp [rejected, separator, nextRejected]
            right
            refine ⟨afterEnvironment, ?_⟩
            rw [resultEq]
            exact Command.Evaluates.whileReturn condition body
        · have requiredAtEnd : offset + 1 = source.length := by omega
          have nextDropped : source.drop (offset + 1) = [] :=
            List.drop_eq_nil_of_le (Nat.le_of_not_gt nextInBounds)
          obtain ⟨afterEnvironment, body⟩ :=
            loopBody_separatorAtEnd_evaluates source start base offset
              sourceBound baseBound inBounds (by simpa [byte] using rejected)
              (by simpa [byte] using separator) requiredAtEnd sourceFound
          have resultEq : scanDigitTail base (source.drop offset) offset =
              .failure (offset + 1) := by
            rw [dropped, nextDropped, scanDigitTail.eq_def]
            simp [rejected, separator]
          right
          refine ⟨afterEnvironment, ?_⟩
          rw [resultEq]
          exact Command.Evaluates.whileReturn condition body
      · obtain ⟨afterEnvironment, body⟩ :=
          loopBody_boundary_evaluates source start base offset sourceBound
            baseBound inBounds
            (by simpa [byte] using rejected) (by simpa [byte] using separator)
            sourceFound
        have resultEq : scanDigitTail base (source.drop offset) offset =
            .success offset := by
          rw [dropped, scanDigitTail.eq_def]
          simp [rejected, separator]
        right
        refine ⟨afterEnvironment, ?_⟩
        rw [resultEq]
        exact Command.Evaluates.whileReturn condition body
  · have atEnd : offset = source.length :=
      Nat.le_antisymm offsetBound (Nat.le_of_not_gt inBounds)
    have condition := loopCondition_evaluates (world := world)
      source start base offset
    rw [show decide (offset < source.length) = false by simp [inBounds]] at condition
    left
    constructor
    · simp [atEnd, scanDigitTail]
    · simpa [atEnd] using Command.Evaluates.whileFalse
        (body := DigitRunCommand.loopBody) condition
termination_by source.length - offset
decreasing_by all_goals omega

theorem initialInvalid_evaluates
    (source : List Byte) (start base : Nat)
    (baseBound : base ≤ 2147483647)
    (inBounds : start < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    Term.evaluate termMachine world
        (environment source start base) DigitRunCommand.initialInvalid =
      .ok (.boolean (!(isDigitForBase
        (source.get ⟨start, inBounds⟩) base)), world) := by
  apply logicalNot_evaluates
  apply isDigit_evaluates (baseBound := baseBound)
  · apply index_evaluates (source := source) (position := start)
      (inBounds := inBounds) (sourceFound := sourceFound)
    · rfl
    · rfl
  · rfl

theorem offsetInitializer_evaluates
    (source : List Byte) (start base : Nat)
    (bound : start + 1 ≤ 2147483647) :
    Term.evaluate termMachine world
        (environment source start base) DigitRunCommand.offsetInitializer =
      .ok (.signed .i32 (start + 1), world) := by
  apply addOne_evaluates (value := start) (bound := bound)
  rfl

theorem command_evaluates
    (world : World) (source : List Byte) (start base : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (_startBound : start ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    ∃ afterEnvironment : Env 4,
      Command.Evaluates termMachine commandMachine world
        (environment source start base) DigitRunCommand.command
        (.returned (some (digitValue (scanDigitRun source start base))))
        world afterEnvironment := by
  have startCondition := startOutOfBounds_evaluates (world := world)
    source start base
  by_cases inBounds : start < source.length
  · rw [show decide (source.length ≤ start) = false by
      simp [Nat.not_le.mpr inBounds]] at startCondition
    let first := source.get ⟨start, inBounds⟩
    have invalid := initialInvalid_evaluates (world := world)
      source start base baseBound inBounds sourceFound
    by_cases accepted : isDigitForBase first base = true
    · rw [show isDigitForBase (source.get ⟨start, inBounds⟩) base = true by
        simpa [first] using accepted] at invalid
      simp at invalid
      have initializerBound : start + 1 ≤ 2147483647 :=
        Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
      have initializer := offsetInitializer_evaluates (world := world)
        source start base initializerBound
      have loopResult := loop_evaluates source start base (start + 1)
        sourceBound baseBound (Nat.succ_le_of_lt inBounds) sourceFound
      have letBody : ∃ afterEnvironment : Env 5,
          Command.Evaluates termMachine commandMachine world
            (loopEnvironment source start base (start + 1))
            (.sequence
              (.whileLoop DigitRunCommand.loopCondition DigitRunCommand.loopBody)
              (DigitRunCommand.returned
                (DigitRunCommand.successful (DigitRunCommand.slot 4))))
            (.returned (some (digitValue
              (scanDigitTail base (source.drop (start + 1)) (start + 1)))))
            world afterEnvironment := by
        rcases loopResult with left | right
        · have successResult : Term.evaluate termMachine world
              (loopEnvironment source start base source.length)
              (DigitRunCommand.successful (DigitRunCommand.slot 4)) =
              .ok (digitValue (.success source.length), world) := by
            apply successful_evaluates (offsetBound := sourceBound)
            rfl
          refine ⟨loopEnvironment source start base source.length, ?_⟩
          rw [left.1]
          apply Command.Evaluates.sequenceNext left.2
          apply Command.Evaluates.sequenceStop
          · exact Command.Evaluates.returnSome successResult
          · simp
        · obtain ⟨afterEnvironment, loopExecution⟩ := right
          exact ⟨afterEnvironment,
            Command.Evaluates.sequenceStop loopExecution (by simp)⟩
      obtain ⟨afterLetEnvironment, letBodyExecution⟩ := letBody
      have letExecution := Command.Evaluates.letValue
        (type := Program.i32Type) initializer (by
          change Command.Evaluates termMachine commandMachine
            world
            (loopEnvironment source start base (start + 1)) _ _ _ _
          exact letBodyExecution)
      have dropped : source.drop start =
          first :: source.drop (start + 1) := by
        simpa [first] using List.drop_eq_getElem_cons inBounds
      have resultEq : scanDigitRun source start base =
          scanDigitTail base (source.drop (start + 1)) (start + 1) := by
        simp [scanDigitRun, dropped, accepted]
      refine ⟨Env.pop afterLetEnvironment, ?_⟩
      rw [resultEq]
      unfold DigitRunCommand.command
      apply Command.Evaluates.sequenceNext
      · exact Command.Evaluates.ifFalse startCondition .skip
      · apply Command.Evaluates.sequenceNext
        · exact Command.Evaluates.ifFalse (by simpa [first] using invalid) .skip
        · exact letExecution
    · have rejected : isDigitForBase first base = false := by
        cases result : isDigitForBase first base with
        | false => rfl
        | true => exact False.elim (accepted result)
      rw [show isDigitForBase (source.get ⟨start, inBounds⟩) base = false by
        simpa [first] using rejected] at invalid
      simp at invalid
      have failureResult : Term.evaluate termMachine world
          (environment source start base)
          (DigitRunCommand.failed (DigitRunCommand.slot 2)) =
          .ok (digitValue (.failure start), world) := by
        apply failed_evaluates
          (offsetBound := Nat.le_trans (Nat.le_of_lt inBounds) sourceBound)
        rfl
      have dropped : source.drop start =
          first :: source.drop (start + 1) := by
        simpa [first] using List.drop_eq_getElem_cons inBounds
      have resultEq : scanDigitRun source start base = .failure start := by
        simp [scanDigitRun, dropped, rejected]
      refine ⟨environment source start base, ?_⟩
      rw [resultEq]
      unfold DigitRunCommand.command
      apply Command.Evaluates.sequenceNext
      · exact Command.Evaluates.ifFalse startCondition .skip
      · apply Command.Evaluates.sequenceStop
        · apply Command.Evaluates.ifTrue (by simpa [first] using invalid)
          apply Command.Evaluates.sequenceStop
          · exact Command.Evaluates.returnSome failureResult
          · simp
        · simp
  · have atOrAfter : source.length ≤ start := Nat.le_of_not_gt inBounds
    rw [show decide (source.length ≤ start) = true by simp [atOrAfter]]
      at startCondition
    have failureResult : Term.evaluate termMachine world
        (environment source start base)
        (DigitRunCommand.failed (DigitRunCommand.slot 2)) =
        .ok (digitValue (.failure start), world) := by
      apply failed_evaluates (offsetBound := _startBound)
      rfl
    have droppedEmpty : source.drop start = [] :=
      List.drop_eq_nil_of_le atOrAfter
    have resultEq : scanDigitRun source start base = .failure start := by
      simp [scanDigitRun, droppedEmpty]
    refine ⟨environment source start base, ?_⟩
    rw [resultEq]
    unfold DigitRunCommand.command
    apply Command.Evaluates.sequenceStop
    · apply Command.Evaluates.ifTrue startCondition
      apply Command.Evaluates.sequenceStop
      · exact Command.Evaluates.returnSome failureResult
      · simp
    · simp

end Lanius.Extraction.Decimal.DigitRunEvaluation
