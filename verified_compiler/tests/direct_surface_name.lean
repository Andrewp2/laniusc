import verified_compiler.tests.direct_surface_boolean
import verified_compiler.tests.direct_escaped_identifier

namespace SurfaceNameProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SourceIdentifierProof

private def referenceSource := Extracted.«verified::lean_typed_body».Functions.«surface_reference».core
private def nameSource := Extracted.«verified::lean_typed_body».Functions.«surface_name».core

def referenceCall (context : Context state) (name : Name reference) : Expr :=
  .call referenceSource.id ([context.views, name.referenceValue, .signed .i32 context.position].map Expr.value)
def nameCall (context : Context state) (token : Nat) : Expr :=
  .call nameSource.id ([context.views, .signed .i32 token, .signed .i32 context.position].map Expr.value)

/-- Body references use the catalog in the actual native View and the proved
    escaped-name writer, without assuming spelling resolution or execution. -/
theorem actualReference (context : Context state) (input : Protected context reference) (name : Name reference)
    (catalog : context.names = name.catalog.value)
    (room : context.position + (EscapedIdentifierProof.bytes name).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (referenceCall context name)
      (.signed .i32 (context.position + (EscapedIdentifierProof.bytes name).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (EscapedIdentifierProof.bytes name) := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter referenceSource as callee
  let bound := callee.bindLocal (referenceSource.bindingId 0) context.value
  have read : readRawSliceIndex extractedProgram callee viewType context.viewAddress 1 0 = .ok context.value := context.readView
  let buffer : OutputNaturalProof.Buffer bound := { context.toBuffer with readable := context.readable }
  have writer := EscapedIdentifierProof.actualCall buffer name input.memory room
    (environment.reheap rfl rfl (by core_formed))
  simp only [EscapedIdentifierProof.call] at writer
  rw [← catalog] at writer
  core_writer

/-- Unit-local body names derive their unit from the native View. The actual
    unit guard and reference constructor are checked, not assumed accepted. -/
theorem actualName (context : Context state) (input : Protected context reference) (name : Name reference)
    (catalog : context.names = name.catalog.value) (unit : context.unit = name.unitIndex)
    (room : context.position + (EscapedIdentifierProof.bytes name).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (nameCall context name.tokenIndex)
      (.signed .i32 (context.position + (EscapedIdentifierProof.bytes name).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (EscapedIdentifierProof.bytes name) := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter nameSource as callee
  let bound := callee.bindLocal (nameSource.bindingId 0) context.value
  have read : readRawSliceIndex extractedProgram callee viewType context.viewAddress 1 0 = .ok context.value := context.readView
  let current := context.reheap (after := bound) rfl
  have retained : Protected current reference := ⟨input.memory, input.viewRead⟩
  have writer := actualReference current retained name catalog room
    (environment.reheap rfl rfl (by core_formed))
  simp only [referenceCall, Name.referenceValue, SymbolSpellingProof.referenceValue] at writer
  rw [← unit] at writer
  have nonnegative : 0 ≤ context.unit := by omega
  core_writer

#print axioms actualReference
#print axioms actualName

end SurfaceNameProof
