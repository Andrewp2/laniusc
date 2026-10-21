import verified_compiler.tests.direct_surface_name
import Lanius.Extraction.WriterCursor

namespace ConstructorNameProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SourceIdentifierProof SurfaceBooleanProof

private def slotSource := Extracted.«verified::lean_syntax».Functions.«variant_slot».core
private def identifierSource := Extracted.«verified::lean_syntax».Functions.«constructor_identifier».core
private def surfaceSource := Extracted.«verified::lean_syntax».Functions.«constructor_surface».core
private def bodySource := Extracted.«verified::lean_typed_body».Functions.«surface_variant».core
def declarationType : Ty := match source_value Extracted.«ir::type_catalog».Types.«TypeDecl».mk [] with
  | .structure id _ => .structure id | _ => .unit

structure Table where
  declarations : Value
  typeCount : Nat
  variants : Value
  variantCount : Nat
  fields : Value
  fieldCount : Nat
def Table.value (table : Table) : Value :=
  source_value Extracted.«ir::type_catalog».Types.«Table».mk
    [table.declarations, .signed .i32 table.typeCount, table.variants, .signed .i32 table.variantCount,
      table.fields, .signed .i32 table.fieldCount]
def enumeration (id start count : Nat) : Value :=
  source_value Extracted.«ir::type_catalog».Types.«TypeDecl».mk
    [source_value Extracted.«ir::type_catalog».Types.«TypeKind».«Enumeration» [],
      .signed .i32 id, .signed .i32 (-1), .signed .i32 0, .signed .i32 start, .signed .i32 count]

/-- Native declaration metadata suffices for slot selection; no name reads or
    successful lookup result are assumed. Unused payload metadata is opaque. -/
structure Selection (reference : Heap) where
  table : Table
  typeIndex : Nat
  ordinal : Nat
  variantStart : Nat
  variantCount : Nat
  typesFit : table.typeCount < 2 ^ 31
  variantsFit : table.variantCount < 2 ^ 31
  typeInside : typeIndex < table.typeCount
  ordinalInside : ordinal < variantCount
  variantRange : variantStart + variantCount ≤ table.variantCount
  declarationRead : ∃ address length, table.declarations = .rawSlice declarationType address length ∧
    readRawSliceIndex extractedProgram { heap := reference } declarationType address length typeIndex =
      .ok (enumeration typeIndex variantStart variantCount)
def Selection.slot (selection : Selection reference) : Nat := selection.variantStart + selection.ordinal

theorem actualSlot (variant : Selection reference) (reads : HeapReads reference state.heap)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call slotSource.id [.value variant.table.value, .value (.signed .i32 variant.typeIndex),
        .value (.signed .i32 variant.ordinal)]) (.signed .i32 variant.slot) after ∧ PureFrame state after := by
  obtain ⟨address, length, descriptor, sourceRead⟩ := variant.declarationRead
  have read := reads.rawSlice sourceRead
  have typeInside := variant.typeInside
  have ordinalInside := variant.ordinalInside
  have range := variant.variantRange
  have fits := variant.variantsFit
  have addition := eval_i32_addNat extractedProgram.target variant.variantStart variant.ordinal (by omega)
  simp only [Table.value, descriptor]
  core_call_pure slotSource as callee
  core_pure

/-- An out-of-range type is rejected before either backing slice is read. -/
theorem rejectsType (table : Table) (typeId ordinal : Int)
    (bad : typeId < 0 ∨ (table.typeCount : Int) ≤ typeId) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call slotSource.id [.value table.value, .value (.signed .i32 typeId),
        .value (.signed .i32 ordinal)]) (.signed .i32 (-1)) after ∧ PureFrame state after := by
  simp only [Table.value]
  core_call_pure slotSource as callee
  core_pure

/-- Surface emission retains the early rejection even with invalid output,
    naming descriptors, or cursor values; no writer is reached. -/
theorem rejectsSurfaceType (table : Table) (output names : Value) (capacity position typeId ordinal : Int)
    (bad : typeId < 0 ∨ (table.typeCount : Int) ≤ typeId) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call surfaceSource.id ([output, .signed .i32 capacity, .signed .i32 position, table.value, names,
        .signed .i32 typeId, .signed .i32 ordinal].map Expr.value)) (.signed .i32 (-1)) after ∧
      PureFrame state after := by
  core_call_pure surfaceSource as callee
  have rejected := rejectsType table typeId ordinal bad (state := callee) (by core_formed)
  core_pure

def referenceType : Ty := match SymbolSpellingProof.referenceValue 0 0 with
  | .structure id _ => .structure id | _ => .unit

/-- Naming adds only the existing native reference and source-name reads. -/
structure Variant (reference : Heap) extends Selection reference where
  name : Name reference
  nameInside : (variantStart + ordinal : Nat) < name.catalog.variantCount
  nameRead : ∃ address length, name.catalog.variants = .rawSlice referenceType address length ∧
    readRawSliceIndex extractedProgram { heap := reference } referenceType address length (variantStart + ordinal) =
      .ok name.referenceValue
def bytes (variant : Variant reference) : List UInt8 := [46] ++ EscapedIdentifierProof.bytes variant.name
def identifierCall (buffer : OutputNaturalProof.Buffer state) (variant : Variant reference) : Expr :=
  .call identifierSource.id ([.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position, variant.name.catalog.value,
    .signed .i32 variant.toSelection.slot, .signed .i32 variant.ordinal].map Expr.value)
def surfaceCall (buffer : OutputNaturalProof.Buffer state) (variant : Variant reference) : Expr :=
  .call surfaceSource.id ([.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words,
    .signed .i32 buffer.capacity, .signed .i32 buffer.position, variant.table.value, variant.name.catalog.value,
    .signed .i32 variant.typeIndex, .signed .i32 variant.ordinal].map Expr.value)
def bodyCall (context : Context state) (variant : Variant reference) : Expr :=
  .call bodySource.id ([context.views, .signed .i32 variant.typeIndex,
    .signed .i32 variant.ordinal, .signed .i32 context.position].map Expr.value)

theorem actualIdentifier (buffer : OutputNaturalProof.Buffer state) (variant : Variant reference)
    (memory : ReadOnlyMemory reference state.heap buffer.address (buffer.words * 4))
    (room : buffer.position + (EscapedIdentifierProof.bytes variant.name).length ≤ buffer.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (identifierCall buffer variant)
      (.signed .i32 (buffer.position + (EscapedIdentifierProof.bytes variant.name).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (EscapedIdentifierProof.bytes variant.name) := by
  have formed := environment.formed
  obtain ⟨address, length, descriptor, sourceRead⟩ := variant.nameRead
  have read := memory.reads.rawSlice sourceRead
  have inside := variant.nameInside
  have slotInside : (variant.toSelection.slot : Int) < variant.name.catalog.variantCount := inside
  have slotNonnegative : (0 : Int) ≤ variant.toSelection.slot := by omega
  have named : 0 < variant.name.catalog.unitCount := by have unit := variant.name.valid.unitInside; omega
  core_call_framed Lanius.Extraction.RunsExpr.callWriter identifierSource as callee
  let bound := callee.bindLocal (identifierSource.bindingId 1) (.rawSlice referenceType address length)
  let current : OutputNaturalProof.Buffer bound := { buffer with readable := buffer.readable }
  have writer := EscapedIdentifierProof.actualCall current variant.name memory room
    (environment.reheap rfl rfl (by core_formed))
  simp only [EscapedIdentifierProof.call] at writer
  have variants : StableExpr 2 extractedProgram callee
      (.field (.local (identifierSource.argumentId 3)) 7) (.rawSlice referenceType address length) callee := by
    rw [← descriptor]
    core_expr
  core_writer

theorem actualSurface (buffer : OutputNaturalProof.Buffer state) (variant : Variant reference)
    (memory : ReadOnlyMemory reference state.heap buffer.address (buffer.words * 4))
    (room : buffer.position + (bytes variant).length ≤ buffer.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (surfaceCall buffer variant)
      (.signed .i32 (buffer.position + (bytes variant).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (bytes variant) := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter surfaceSource as callee
  have lookup := actualSlot variant.toSelection (state := callee) memory.reads (by core_formed)
  apply RunsStmt.letReadWriter
  · apply RunsExpr.callPureArguments
    · core_arguments
    · exact lookup
  · intro ready pure
    let bound := ready.bindLocal (surfaceSource.bindingId 0) (.signed .i32 variant.toSelection.slot)
    have heap : bound.heap = state.heap := pure.heap
    let start : OutputNaturalProof.Buffer bound := { buffer with readable := by rw [heap]; exact buffer.readable }
    have baseEnvironment := environment.reheap (after := bound) pure.heap pure.views (by core_formed)
    have retained : ReadOnlyMemory reference bound.heap buffer.address (buffer.words * 4) := by
      rw [heap]; exact memory
    have firstRoom : start.position + 1 ≤ start.capacity := by simp only [start, bytes, List.length_append, List.length_cons, List.length_nil] at room ⊢; omega
    obtain ⟨first, firstCall, firstFrame⟩ := OutputWriterProof.byte start ⟨46, by decide⟩ firstRoom baseEnvironment
    let next := first.bindLocal (surfaceSource.bindingId 1) (.signed .i32 (buffer.position + 1 : Nat))
    have cursor : WriterCursor bound next (surfaceSource.bindingId 1) first.nextCell
        (buffer.address + buffer.position) buffer.position [46] :=
      WriterCursor.start firstFrame baseEnvironment.formed firstCall.choose_spec.2 _
    have rest := actualIdentifier (start.afterWriter cursor.frame) variant
      (retained.afterOutput cursor.frame.output (by omega) (by
        change buffer.address + buffer.position + [46].length ≤ buffer.address + buffer.words * 4
        have storage := buffer.storage
        simp only [List.length_cons, List.length_nil, bytes, List.length_append] at room ⊢
        omega))
      (by simp only [OutputNaturalProof.Buffer.afterWriter, start, bytes, List.length_append, List.length_cons, List.length_nil] at room ⊢; omega)
      (baseEnvironment.afterWrite cursor.frame)
    obtain ⟨last, returned, frame⟩ := cursor.finishArguments rest
      (expressions := [.local (surfaceSource.argumentId 0), .local (surfaceSource.argumentId 1),
        .local (surfaceSource.bindingId 1), .local (surfaceSource.argumentId 4),
        .local (surfaceSource.bindingId 0), .local (surfaceSource.argumentId 6)])
      (by core_arguments) (by
        simp only [OutputNaturalProof.Buffer.afterWriter, start, List.length_append, List.length_cons, List.length_nil]
        omega)
    have initial : RunsExpr extractedProgram bound
        (.call Extracted.«verified::lean_output».Functions.«byte».core.id
          [.local (surfaceSource.argumentId 0), .local (surfaceSource.argumentId 1),
            .local (surfaceSource.argumentId 2), .value (.signed .i32 46)])
        (.signed .i32 (buffer.position + 1 : Nat)) first :=
      RunsExpr.callArguments (by core_arguments) firstCall
    apply RunsStmt.guardPureWriter false
    · simp
    · core_run
    · exact ⟨restoreLocals first last, .letLocal initial returned, frame.restoreLocals first⟩

theorem actualBody (context : Context state) (input : Protected context reference) (variant : Variant reference)
    (types : context.types = variant.table.value) (names : context.names = variant.name.catalog.value)
    (room : context.position + (bytes variant).length ≤ context.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (bodyCall context variant)
      (.signed .i32 (context.position + (bytes variant).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (bytes variant) := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter bodySource as callee
  let bound := callee.bindLocal (bodySource.bindingId 0) context.value
  have read : readRawSliceIndex extractedProgram callee viewType context.viewAddress 1 0 = .ok context.value := context.readView
  let buffer : OutputNaturalProof.Buffer bound := { context.toBuffer with readable := context.readable }
  have writer := actualSurface buffer variant input.memory room (environment.reheap rfl rfl (by core_formed))
  simp only [surfaceCall] at writer
  rw [← types, ← names] at writer
  core_writer

#print axioms actualSlot
#print axioms rejectsType
#print axioms rejectsSurfaceType
#print axioms actualIdentifier
#print axioms actualSurface
#print axioms actualBody

end ConstructorNameProof
