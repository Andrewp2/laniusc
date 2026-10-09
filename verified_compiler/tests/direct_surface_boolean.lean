import verified_compiler.tests.direct_output_writer
import Lanius.Extraction.WriterProof
import Lanius.Extraction.WriterFrame
import Lanius.Semantics.SourceValue
import Lanius.Semantics.ReadOnlyMemory

namespace SurfaceBooleanProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_boolean_output».core
def viewType : Ty := match source.parameters[0]? with | some (_, Ty.slice type) => type | _ => .unit

def viewValue (tree types names functions : Value) (functionIndex unit : Int)
    (output : Value) (capacity : Int) : Value :=
  source_value Extracted.«verified::lean_typed_body».Types.«View».mk
    [tree, types, names, functions, .signed .i32 functionIndex, .signed .i32 unit, output, .signed .i32 capacity]

/-- One native printer context, with the output's existing writable domain.
    Its read is an ordinary memory precondition, not an assumed printer run. -/
structure Context (state : State) extends OutputNaturalProof.Buffer state where
  viewAddress : Nat
  tree : Value
  types : Value
  names : Value
  functions : Value
  functionIndex : Int
  unit : Int
  readView : readRawSliceIndex extractedProgram state viewType viewAddress 1 0 =
    .ok (viewValue tree types names functions functionIndex unit
      (.rawSlice (.scalar (.signed .i32)) address words) capacity)

def Context.value (context : Context state) : Value :=
  viewValue context.tree context.types context.names context.functions context.functionIndex context.unit
    (.rawSlice (.scalar (.signed .i32)) context.address context.words) context.capacity
def Context.views (context : Context state) : Value := .rawSlice viewType context.viewAddress 1
def Context.atPosition (context : Context state) (position : Nat) : Context state := { context with position := position }
def Context.reheap (context : Context before) (heap : after.heap = before.heap) : Context after := {
  context with
  readable := by simpa only [heap] using context.readable
  readView := by simpa only [readRawSliceIndex, heap] using context.readView }

/-- Native View data lives in the immutable input fragment. Output bytes are
    deliberately absent from that fragment, not required to stay unchanged. -/
structure Protected (context : Context state) (reference : Heap) : Prop where
  memory : ReadOnlyMemory reference state.heap context.address (context.words * 4)
  viewRead : readRawSliceIndex extractedProgram { state with heap := reference }
    viewType context.viewAddress 1 0 = .ok context.value

def Context.afterOutput {before after : State} (context : Context before) (input : Protected context reference)
    (effect : OutputEffect before.heap after.heap (context.address + context.position) output)
    (room : context.position + output.length ≤ context.capacity) : Context after := {
  context with
  position := context.position + output.length
  readable := effect.readable context.readable
  readView := (input.memory.afterOutput effect (by omega)
    (by have storage := context.storage; omega)).reads.rawSlice input.viewRead }

theorem Protected.afterOutput {before after : State} {context : Context before} (input : Protected context reference)
    (effect : OutputEffect before.heap after.heap (context.address + context.position) output)
    (room : context.position + output.length ≤ context.capacity) :
    Protected (context.afterOutput input effect room) reference :=
  ⟨input.memory.afterOutput effect (by omega) (by have storage := context.storage; omega), input.viewRead⟩
def Context.call (context : Context state) (value : Bool) : Expr :=
  .call source.id ([context.views, .boolean value, .signed .i32 context.position].map Expr.value)
def spelling (value : Bool) : String := if value then "true" else "false"
def bytes (value : Bool) : List UInt8 := World.utf8Bytes (spelling value)

/-- The actual self-extracted emitter writes the boolean's Lean spelling and
    returns the next cursor. The text writer's total contract is reused. -/
theorem actualCall (context : Context state) (value : Bool)
    (room : context.position + (bytes value).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.call value)
      (.signed .i32 (context.position + (bytes value).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (bytes value) := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  let ready := callee.bindLocal (source.bindingId 0) context.value
  have read : readRawSliceIndex extractedProgram callee viewType context.viewAddress 1 0 =
      .ok context.value := context.readView
  let buffer : OutputNaturalProof.Buffer ready := { context.toBuffer with readable := context.readable }
  have writer := OutputWriterProof.text buffer (spelling value) room (environment.reheap rfl rfl (by core_formed))
  cases value <;> simp only [spelling, Bool.false_eq_true, ↓reduceIte] at writer ⊢ <;> core_writer

/-- Insufficient space returns -1 without any output or IR write. -/
theorem actualRejects (context : Context state) (value : Bool)
    (short : context.capacity < context.position + (bytes value).length)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (context.call value) (.signed .i32 (-1)) after ∧
      PureFrame state after := by
  core_call_pure source as callee
  let ready := callee.bindLocal (source.bindingId 0) context.value
  have read : readRawSliceIndex extractedProgram callee viewType context.viewAddress 1 0 =
      .ok context.value := context.readView
  obtain ⟨after, run, frame⟩ := OutputTextProof.actualCall_rejects
    (.rawSlice (.scalar (.signed .i32)) context.address context.words)
    context.capacity context.position (spelling value) (bytes value).length
    (state := ready) (by core_formed) (by have fits := context.fits; omega)
    (by right; right; right; omega)
  refine ⟨restoreLocals callee after, ?_,
    ((CallerFrame.refl (by core_formed)).bindLocal _ _ |>.transPure frame).restoreLocals⟩
  apply RunsStmt.letLocal
  · core_run
  · cases value <;> simp only [bytes, spelling, Bool.false_eq_true, ↓reduceIte] at run ⊢ <;> core_stmt

#print axioms actualCall
#print axioms actualRejects

end SurfaceBooleanProof
