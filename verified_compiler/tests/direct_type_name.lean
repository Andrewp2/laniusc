import verified_compiler.tests.direct_declaration_name

namespace TypeNameProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SymbolSpellingProof SourceIdentifierProof SurfaceBooleanProof DeclarationNameProof

private def identifierSource := Extracted.«verified::lean_syntax».Functions.«type_identifier».core
private def nominalSource := Extracted.«verified::lean_syntax».Functions.«named_type_ref».core
private def bodySource := Extracted.«verified::lean_typed_body».Functions.«type_name».core

/-- A type's existing catalog slot and native Ref, not successful emission. -/
structure Named (reference : Heap) where
  path : Path reference
  index : Nat
  inside : (index : Int) < path.name.catalog.typeCount
  read : ∃ address length, path.name.catalog.types = .rawSlice DeclarationNameProof.referenceType address length ∧
    readRawSliceIndex extractedProgram { heap := reference }
      DeclarationNameProof.referenceType address length index = .ok path.name.referenceValue

def bytes (name : Named reference) : List UInt8 := DeclarationNameProof.bytes name.path .TypeSpace
def call (buffer : OutputNaturalProof.Buffer state) (name : Named reference) : Expr :=
  .call identifierSource.id ([.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position,
    name.path.name.catalog.value, .signed .i32 name.index].map Expr.value)
def nominalValue (index : Nat) : Value :=
  source_value Extracted.«ir::type_ref».Types.«TypeRef».«Nominal» [.signed .i32 index]
private def nominalId : VarId := match nominalSource.body with
  | some (.returnValue (some (.matchValue _ arms))) => match selectedArm (nominalValue 0) arms with
    | some (binding :: _, _) => binding.1 | _ => 0
  | _ => 0

/-- Read the type Ref and run the proved qualified-name emitter. -/
theorem actualCall (buffer : OutputNaturalProof.Buffer state) (name : Named reference)
    (memory : ReadOnlyMemory reference state.heap buffer.address (buffer.words * 4))
    (room : buffer.position + (bytes name).length ≤ buffer.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (call buffer name)
      (.signed .i32 (buffer.position + (bytes name).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (bytes name) := by
  have formed := environment.formed
  obtain ⟨address, length, descriptor, nativeRead⟩ := name.read
  have read := memory.reads.rawSlice nativeRead
  have inside := name.inside
  have named : 0 < name.path.name.catalog.unitCount := by
    have unit := name.path.name.valid.unitInside
    omega
  core_call_framed Lanius.Extraction.RunsExpr.callWriter identifierSource as callee
  let ready := callee.bindLocal (identifierSource.bindingId 1)
    (.rawSlice DeclarationNameProof.referenceType address length)
  let buffer' : OutputNaturalProof.Buffer ready := { buffer with readable := buffer.readable }
  have writer := DeclarationNameProof.actualCall buffer' name.path .TypeSpace memory room
    (environment.reheap rfl rfl (by core_formed))
  simp only [DeclarationNameProof.call] at writer
  have references : StableExpr 2 extractedProgram callee
      (.field (.local (identifierSource.argumentId 3)) 5)
      (.rawSlice DeclarationNameProof.referenceType address length) callee := by
    rw [← descriptor]
    core_expr
  core_writer

/-- Bad named type IDs reject before catalog/output backing is accessed. -/
theorem rejectsIndex (catalog : Catalog) (output : Value) (capacity position index : Int)
    (bad : index < 0 ∨ (0 < catalog.unitCount ∧ catalog.typeCount ≤ index))
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call identifierSource.id ([output, .signed .i32 capacity, .signed .i32 position,
        catalog.value, .signed .i32 index].map Expr.value)) (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call_pure identifierSource as callee
  apply RunsStmt.guardPureTrue
  · simp
  · core_run
  · core_pure

/-- The nominal arm uses the same type-name contract, without rechecking the
    typing of the IR or interpreting a separate type-proof tree. -/
theorem actualNominal (buffer : OutputNaturalProof.Buffer state) (name : Named reference) (types : Value)
    (memory : ReadOnlyMemory reference state.heap buffer.address (buffer.words * 4))
    (room : buffer.position + (bytes name).length ≤ buffer.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state
      (.call nominalSource.id ([.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
        .signed .i32 buffer.capacity, .signed .i32 buffer.position, types,
        name.path.name.catalog.value, nominalValue name.index].map Expr.value))
      (.signed .i32 (buffer.position + (bytes name).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (bytes name) := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter nominalSource as callee
  let ready := callee.bindLocal nominalId (.signed .i32 name.index)
  let buffer' : OutputNaturalProof.Buffer ready := { buffer with readable := buffer.readable }
  have writer := actualCall buffer' name memory room (environment.reheap rfl rfl (by core_formed))
  simp only [call] at writer
  core_writer

/-- Connect nominal names to the actual native View-based body printer. -/
theorem actualBody (context : Context state) (input : Protected context reference) (name : Named reference)
    (names : context.names = name.path.name.catalog.value)
    (room : context.position + (bytes name).length ≤ context.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state
      (.call bodySource.id ([context.views, nominalValue name.index, .signed .i32 context.position].map Expr.value))
      (.signed .i32 (context.position + (bytes name).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (bytes name) := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter bodySource as callee
  let viewed := callee.bindLocal (bodySource.bindingId 0) context.value
  let output := viewed.bindLocal (bodySource.bindingId 1)
    (.rawSlice (.scalar (.signed .i32)) context.address context.words)
  let ready := output.bindLocal (bodySource.bindingId 2) (.signed .i32 context.capacity)
  have read := context.readView
  let buffer : OutputNaturalProof.Buffer ready := { context.toBuffer with readable := context.readable }
  have writer := actualNominal buffer name context.types input.memory room
    (environment.reheap rfl rfl (by core_formed))
  rw [← names] at writer
  core_writer

#print axioms actualCall
#print axioms rejectsIndex
#print axioms actualNominal
#print axioms actualBody

end TypeNameProof
