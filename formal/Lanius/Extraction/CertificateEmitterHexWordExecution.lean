import Lanius.Extraction.CertificateEmitterOutputBuffer
import Lanius.Extraction.CertificateEmitterHexWord
import Lanius.Extraction.CertificateEmitterCall

namespace Lanius.Extraction.CertificateEmitterHexWordExecution

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.CertificateEmitterFrame Lanius.Extraction.CertificateEmitterCall
open Lanius.Extraction.CertificateEmitterHexWord Lanius.Extraction.CertificateEmitterOutputBuffer
open Lanius.Extraction.CertificateEmitterCall

structure SourceHexWordStep (program : Program) (hexWord : FunctionId)
    (caller : State) (root : CellId) (elements : List Value)
    (capacity position : Nat) (value : Int) (arguments : List Expr) where
  threshold : Nat
  after : State
  stable : StableExpr threshold program caller (.call hexWord arguments)
    (.signed .i32 (Int.ofNat (position + 8))) after
  memory : after.cellEntry? root = some { id := root, value := some (.array (hexWordElements elements position value)) }
  frame : WriteFrame caller after root (.array (hexWordElements elements position value))

structure SourceHexByteStep (program : Program) (hexByte : FunctionId)
    (caller : State) (root : CellId) (elements : List Value)
    (capacity position value nextValue : Nat) (arguments : List Expr) where
  threshold : Nat
  after : State
  stable : StableExpr threshold program caller (.call hexByte arguments)
    (.signed .i32 (Int.ofNat (position + 2))) after
  memory : after.cellEntry? root = some { id := root, value := some (.array (hexByteElements elements position value)) }
  frame : WriteFrame caller after root (.array (hexByteElements elements position value))
  nextBuffer : OutputBuffer after root (hexByteElements elements position value)
    capacity (position + 2) nextValue

structure SourceHexWordBody (program : Program) (hexByte : FunctionId)
    (callee : State) (bodyFuel : Nat) (body : Stmt) (result : Value)
    (root : CellId) (elements : List Value) (capacity position : Nat) (value : Int)
    (b0 b1 b2 b3 b4 : Nat) (arguments0 arguments1 arguments2 arguments3 : List Expr) where
  buffer : OutputBuffer callee root elements capacity position b0
  step0 : SourceHexByteStep program hexByte callee root elements capacity position b0 b1 arguments0
  step1 : SourceHexByteStep program hexByte step0.after root (hexByteElements elements position b0) capacity (position + 2) b1 b2 arguments1
  step2 : SourceHexByteStep program hexByte step1.after root (hexByteElements (hexByteElements elements position b0) (position + 2) b1) capacity (position + 4) b2 b3 arguments2
  step3 : SourceHexByteStep program hexByte step2.after root (hexByteElements (hexByteElements (hexByteElements elements position b0) (position + 2) b1) (position + 4) b2) capacity (position + 6) b3 b4 arguments3
  bodyContract : StableStmt bodyFuel program callee body (.returned (some result)) step3.after
  resultEq : result = .signed .i32 (Int.ofNat (position + 8))
  b0_eq : b0 = hexWordByte value 24
  b1_eq : b1 = hexWordByte value 16
  b2_eq : b2 = hexWordByte value 8
  b3_eq : b3 = hexWordByte value 0

inductive SourceHexByteTrace (program : Program) (hexByte : FunctionId)
    (root : CellId) (capacity : Nat) : State → List Value → Nat → List Nat → Nat → State → Type
  | nil :
      SourceHexByteTrace program hexByte root capacity caller elements position [] position caller
  | cons {value nextValue : Nat} {rest : List Nat} {finish : Nat} {after : State} {arguments : List Expr}
      (step : SourceHexByteStep program hexByte caller root elements capacity position value nextValue arguments)
      (tail : SourceHexByteTrace program hexByte root capacity step.after
        (hexByteElements elements position value) (position + 2) rest finish after) :
      SourceHexByteTrace program hexByte root capacity caller elements position
        (value :: rest) finish after

inductive SourceHexWordTrace (program : Program) (hexWord : FunctionId)
    (root : CellId) (capacity : Nat) : State → List Value → Nat → List Int → Nat → State → Type
  | nil :
      SourceHexWordTrace program hexWord root capacity caller elements position [] position caller
  | cons {value : Int} {rest : List Int} {finish : Nat} {after : State} {arguments : List Expr}
      (step : SourceHexWordStep program hexWord caller root elements capacity position value arguments)
      (tail : SourceHexWordTrace program hexWord root capacity step.after
        (hexWordElements elements position value) (position + 8) rest finish after) :
      SourceHexWordTrace program hexWord root capacity caller elements position
        (value :: rest) finish after

def sourceHexWordElements : List Value → Nat → List Int → List Value
  | elements, _, [] => elements
  | elements, position, value :: values =>
      sourceHexWordElements (hexWordElements elements position value) (position + 8) values

def sourceHexByteElements : List Value → Nat → List Nat → List Value
  | elements, _, [] => elements
  | elements, position, value :: values =>
      sourceHexByteElements (hexByteElements elements position value) (position + 2) values

def sourceEmitTransportElements (elements : List Value) (position count : Nat)
    (values : List Int) : List Value :=
  sourceHexWordElements (hexWordElements elements position (Int.ofNat count))
    (position + 8) values

structure SourceEmitTransportTrace (program : Program) (hexWord : FunctionId)
    (root : CellId) (capacity : Nat) (caller : State) (elements : List Value)
    (position : Nat) (words : List Int) (wordsLength count : Nat)
    (countArguments : List Expr) (finish : Nat) (after : State) where
  guard : count ≤ wordsLength
  wordsLengthEq : wordsLength = words.length
  countStep : SourceHexWordStep program hexWord caller root elements capacity position
    (Int.ofNat count) countArguments
  values : List Int
  selected : values = words.take count
  trace : SourceHexWordTrace program hexWord root capacity countStep.after
    (hexWordElements elements position (Int.ofNat count)) (position + 8)
    values finish after

def sourceEmitImageElements (elements : List Value) (position imageLength : Nat)
    (image : List Nat) : List Value :=
  sourceHexByteElements (hexWordElements elements position (Int.ofNat imageLength))
    (position + 8) image

def sourceFunctionHeader : Nat := 16
def sourceFunctionEnd : Nat := 14

def sourceFunctionSpans : List Int → Int → List (Int × Int)
  | [], _ => []
  | start :: next :: starts, finalEnd =>
      (start, next - start) :: sourceFunctionSpans (next :: starts) finalEnd
  | [start], finalEnd => [(start, finalEnd - start)]

def sourceFunctionValid : List Int → Int → Prop
  | [], _ => True
  | start :: next :: starts, finalEnd =>
      start ≥ 0 ∧ next > start ∧ sourceFunctionValid (next :: starts) finalEnd
  | [start], finalEnd => start ≥ 0 ∧ finalEnd > start

def sourceFunctionWords (starts : List Int) (finalEnd : Int) : List Int :=
  (sourceFunctionSpans starts finalEnd).flatMap fun span => [span.1, span.2]

theorem sourceFunctionSpans_length (starts : List Int) (finalEnd : Int) :
    (sourceFunctionSpans starts finalEnd).length = starts.length := by
  induction starts with
  | nil => rfl
  | cons start rest ih =>
      cases rest with
      | nil => simp [sourceFunctionSpans]
      | cons next rest =>
          simp [sourceFunctionSpans, ih]

theorem sourceFunctionWords_length (starts : List Int) (finalEnd : Int) :
    (sourceFunctionWords starts finalEnd).length = 2 * starts.length := by
  have flatMapLength : ∀ spans : List (Int × Int),
      (spans.flatMap fun span => [span.1, span.2]).length = 2 * spans.length := by
    intro spans
    induction spans with
    | nil => simp
    | cons span spans ih => simp [ih]; omega
  calc
    (sourceFunctionWords starts finalEnd).length =
        2 * (sourceFunctionSpans starts finalEnd).length := flatMapLength _
    _ = 2 * starts.length := by rw [sourceFunctionSpans_length]

structure SourceFunctionTable (work : List Int) (workLength stride count : Nat)
    (starts : List Int) (finalEnd : Int) where
  workLengthEq : workLength = work.length
  bounds : sourceFunctionHeader + stride * 8 ≤ workLength ∧
    count ≤ stride ∧ sourceFunctionHeader + stride * 7 + count ≤ workLength
  countEq : starts.length = count
  startIndex : ∀ index, index < count →
    work[sourceFunctionHeader + stride * 7 + index]? = starts[index]?
  endIndex : work[sourceFunctionEnd]? = some finalEnd
  endNonnegative : 0 ≤ finalEnd
  valid : sourceFunctionValid starts finalEnd

def sourceEmitFunctionsElements (elements : List Value) (position count : Nat)
    (starts : List Int) (finalEnd : Int) : List Value :=
  sourceHexWordElements (hexWordElements elements position (Int.ofNat count))
    (position + 8) (sourceFunctionWords starts finalEnd)

structure SourceEmitFunctionsTrace (program : Program) (hexWord : FunctionId)
    (root : CellId) (capacity : Nat) (caller : State) (elements : List Value)
    (position : Nat) (work : List Int) (workLength stride count : Nat)
    (starts : List Int) (finalEnd : Int) (countArguments : List Expr)
    (finish : Nat) (after : State) where
  table : SourceFunctionTable work workLength stride count starts finalEnd
  countStep : SourceHexWordStep program hexWord caller root elements capacity position
    (Int.ofNat count) countArguments
  trace : SourceHexWordTrace program hexWord root capacity countStep.after
    (hexWordElements elements position (Int.ofNat count)) (position + 8)
    (sourceFunctionWords starts finalEnd) finish after

structure SourceEmitImageTrace (program : Program) (hexWord hexByte : FunctionId)
    (root : CellId) (capacity : Nat) (caller : State) (elements : List Value)
    (position : Nat) (image : List Nat) (imageLength : Nat) (countArguments : List Expr)
    (finish : Nat) (after : State) where
  guard : imageLength ≤ image.length
  countStep : SourceHexWordStep program hexWord caller root elements capacity position
    (Int.ofNat imageLength) countArguments
  values : List Nat
  selected : values = image.take imageLength
  trace : SourceHexByteTrace program hexByte root capacity countStep.after
    (hexWordElements elements position (Int.ofNat imageLength)) (position + 8)
    values finish after

private theorem writeFrame_rootBound {before after : State} {root : CellId} {value : Value}
    (frame : WriteFrame before after root value) (bound : root < before.nextCell) :
    root < after.nextCell := by
  rcases frame with ⟨middle, caller, _, next, _, _, _, _⟩
  rcases caller.cells with ⟨_, _, frontier, _⟩
  rw [next]
  exact Nat.lt_of_lt_of_le bound frontier

theorem sourceHexWordTrace_result
    (trace : SourceHexWordTrace program hexWord root capacity caller elements position values finish after)
    (bound : root < caller.nextCell)
    (baseMemory : caller.cellEntry? root =
      some { id := root, value := some (.array elements) }) :
    finish = position + 8 * values.length ∧
      after.cellEntry? root = some { id := root, value := some (.array (sourceHexWordElements elements position values)) } ∧
      (values = [] ∧ after = caller ∨
        WriteFrame caller after root (.array (sourceHexWordElements elements position values))) := by
  induction trace with
  | nil => exact ⟨by rfl, by simpa, Or.inl ⟨by rfl, by rfl⟩⟩
  | cons step tail ih =>
      have tailBound := writeFrame_rootBound step.frame bound
      rcases ih tailBound step.memory with ⟨finishEq, memory, outcome⟩
      refine ⟨by simp_all [Nat.add_assoc, Nat.mul_succ]; omega, memory, ?_⟩
      rcases outcome with ⟨empty, same⟩ | frame
      · exact Or.inr (by simpa [sourceHexWordElements, empty, same] using step.frame)
      · exact Or.inr (by simpa [sourceHexWordElements] using WriteFrame.trans step.frame frame bound)

theorem sourceHexByteTrace_result
    (trace : SourceHexByteTrace program hexByte root capacity caller elements position values finish after)
    (bound : root < caller.nextCell)
    (baseMemory : caller.cellEntry? root = some { id := root, value := some (.array elements) }) :
    finish = position + 2 * values.length ∧
      after.cellEntry? root = some { id := root, value := some (.array (sourceHexByteElements elements position values)) } ∧
      (values = [] ∧ after = caller ∨
        WriteFrame caller after root (.array (sourceHexByteElements elements position values))) := by
  induction trace with
  | nil => exact ⟨by rfl, by simpa, Or.inl ⟨by rfl, by rfl⟩⟩
  | cons step tail ih =>
      have tailBound := writeFrame_rootBound step.frame bound
      rcases ih tailBound step.memory with ⟨finishEq, memory, outcome⟩
      refine ⟨by simp_all [Nat.add_assoc, Nat.mul_succ]; omega, memory, ?_⟩
      rcases outcome with ⟨empty, same⟩ | frame
      · exact Or.inr (by simpa [sourceHexByteElements, empty, same] using step.frame)
      · exact Or.inr (by simpa [sourceHexByteElements] using WriteFrame.trans step.frame frame bound)

theorem sourceEmitTransport_result
    (trace : SourceEmitTransportTrace program hexWord root capacity caller elements position
      words wordsLength count countArguments finish after)
    (bound : root < caller.nextCell) :
    finish = position + 8 * (trace.values.length + 1) ∧
      after.cellEntry? root = some
        { id := root, value := some (.array
          (sourceEmitTransportElements elements position count (words.take count))) } ∧
      WriteFrame caller after root (.array
        (sourceEmitTransportElements elements position count (words.take count))) := by
  have tailBound := writeFrame_rootBound trace.countStep.frame bound
  rcases sourceHexWordTrace_result trace.trace tailBound trace.countStep.memory with
    ⟨finishEq, memory, outcome⟩
  rcases outcome with ⟨empty, same⟩ | frame
  · have selectedEmpty : words.take count = [] := by rw [← trace.selected, empty]
    refine ⟨by omega, ?_, ?_⟩
    · simpa [sourceEmitTransportElements, trace.selected, empty, same] using memory
    · simpa [sourceEmitTransportElements, sourceHexWordElements, selectedEmpty, same] using trace.countStep.frame
  · refine ⟨by omega, ?_, ?_⟩
    · simpa [sourceEmitTransportElements, trace.selected] using memory
    · simpa [sourceEmitTransportElements, trace.selected] using
        WriteFrame.trans trace.countStep.frame frame bound

theorem sourceEmitImage_result
    (trace : SourceEmitImageTrace program hexWord hexByte root capacity caller elements position
      image imageLength countArguments finish after)
    (bound : root < caller.nextCell) :
    finish = position + 8 + 2 * trace.values.length ∧
      after.cellEntry? root = some
        { id := root, value := some (.array
          (sourceEmitImageElements elements position imageLength (image.take imageLength))) } ∧
      WriteFrame caller after root (.array
        (sourceEmitImageElements elements position imageLength (image.take imageLength))) := by
  have tailBound := writeFrame_rootBound trace.countStep.frame bound
  rcases sourceHexByteTrace_result trace.trace tailBound trace.countStep.memory with
    ⟨finishEq, memory, outcome⟩
  rcases outcome with ⟨empty, same⟩ | frame
  · have selectedEmpty : image.take imageLength = [] := by rw [← trace.selected, empty]
    refine ⟨by omega, ?_, ?_⟩
    · simpa [sourceEmitImageElements, trace.selected, empty, same] using memory
    · simpa [sourceEmitImageElements, sourceHexByteElements, selectedEmpty, same] using trace.countStep.frame
  · refine ⟨by omega, ?_, ?_⟩
    · simpa [sourceEmitImageElements, trace.selected] using memory
    · simpa [sourceEmitImageElements, trace.selected] using
        WriteFrame.trans trace.countStep.frame frame bound

theorem sourceEmitFunctions_result
    (trace : SourceEmitFunctionsTrace program hexWord root capacity caller elements position
      work workLength stride count starts finalEnd countArguments finish after)
    (bound : root < caller.nextCell) :
    finish = position + 8 + 16 * count ∧
      after.cellEntry? root = some
        { id := root, value := some (.array
          (sourceEmitFunctionsElements elements position count starts finalEnd)) } ∧
      WriteFrame caller after root (.array
        (sourceEmitFunctionsElements elements position count starts finalEnd)) := by
  have tailBound := writeFrame_rootBound trace.countStep.frame bound
  rcases sourceHexWordTrace_result trace.trace tailBound trace.countStep.memory with
    ⟨finishEq, memory, outcome⟩
  have wordsLength : (sourceFunctionWords starts finalEnd).length = 2 * count := by
    rw [sourceFunctionWords_length, trace.table.countEq]
  rcases outcome with ⟨empty, same⟩ | frame
  · refine ⟨by omega, ?_, ?_⟩
    · simpa [sourceEmitFunctionsElements, empty, same] using memory
    · simpa [sourceEmitFunctionsElements, sourceHexWordElements, empty, same] using trace.countStep.frame
  · refine ⟨by omega, ?_, ?_⟩
    · simpa [sourceEmitFunctionsElements] using memory
    · simpa [sourceEmitFunctionsElements] using
        WriteFrame.trans trace.countStep.frame frame bound

theorem hexWord_call_of_body
    {program : Program} {function : Function} {body : Stmt} {caller callee : State}
    {arguments : List Expr} {values : List Value} {bindings : List (VarId × Value)}
    {afterArguments : State} {argumentsFuel bodyFuel : Nat} {result : Value}
    {root : CellId} {elements : List Value} {capacity position : Nat} {value : Int}
    {b0 b1 b2 b3 b4 : Nat} {arguments0 arguments1 arguments2 arguments3 : List Expr}
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some body)
    (argumentsContract : ThresholdPureList argumentsFuel program caller arguments values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (calleeShape : callee = ({ afterArguments with locals := [] }).bindLocals bindings)
    (calleeFrame : CallerFrame caller callee)
    (trace : SourceHexWordBody program hexByte callee bodyFuel body result root elements capacity position value b0 b1 b2 b3 b4 arguments0 arguments1 arguments2 arguments3) :
    StableExpr (max argumentsFuel bodyFuel + 1) program caller (.call function.id arguments) result (restoreLocals caller trace.step3.after) ∧
      OutputBuffer trace.step3.after root (hexWordElements elements position value) capacity (position + 8) b4 ∧
      WriteFrame caller (restoreLocals caller trace.step3.after) root (.array (hexWordElements elements position value)) := by
  have call := stableMutableInternalCall program caller function arguments body values bindings afterArguments callee trace.step3.after result functionFound bodyFound argumentsContract parametersBind calleeShape trace.bodyContract
  have outputBuffer : OutputBuffer trace.step3.after root (hexWordElements elements position value) capacity (position + 8) b4 := by
    simpa [hexWordElements, hexWordByte, trace.b0_eq, trace.b1_eq, trace.b2_eq, trace.b3_eq,
      Nat.add_assoc, Nat.add_left_comm, Nat.add_comm] using trace.step3.nextBuffer
  have bodyFrame : WriteFrame callee trace.step3.after root (.array (hexWordElements elements position value)) := by
    have first := WriteFrame.trans trace.step0.frame trace.step1.frame trace.buffer.rootBound
    have second := WriteFrame.trans first trace.step2.frame trace.buffer.rootBound
    simpa [hexWordElements, trace.b0_eq, trace.b1_eq, trace.b2_eq, trace.b3_eq,
      Nat.add_assoc, Nat.add_left_comm, Nat.add_comm] using
      (WriteFrame.trans second trace.step3.frame trace.buffer.rootBound)
  exact ⟨by simpa [trace.resultEq] using call, outputBuffer, WriteFrame.transCallerFrame calleeFrame bodyFrame⟩

end Lanius.Extraction.CertificateEmitterHexWordExecution
