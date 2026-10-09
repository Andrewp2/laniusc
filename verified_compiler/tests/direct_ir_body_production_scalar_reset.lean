import verified_compiler.tests.direct_ir_body_production_scalar_arena

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def extractSource := Extracted.«verified::surface_expr».Functions.«extract».core

/-- The real extract1871 count reset needs four writable bytes, not a
    readable old count value or any CountCell padding. -/
theorem actualExtractResetCount (arena : Arena)
    (found : before.local? (extractSource.bindingId 0) =
      some (.rawSlice (.structure expressionCountId) arena.count arena.countLength))
    (room : before.heap.Readable arena.count 4) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ heap, RunsExpr extractedProgram before (extractSource.effectExpression 0) .unit { before with heap } ∧
      NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32)) arena.count (.signed .i32 0) 4 ∧
      HeapRegionWrite before.heap heap arena.count 4 := by
  have declaration : extractedProgram.structure? expressionCountId =
      some { id := expressionCountId, fields := [.scalar (.signed .i32)] } := by decide +kernel
  have layout : NativeLayout.valueWords? extractedProgram (.structure expressionCountId) = some 1 := by decide +kernel
  have location : rawSliceElementAddress? extractedProgram (.structure expressionCountId) arena.count 0 = .ok arena.count := by
    simp [rawSliceElementAddress?, layout, NativeLayout.elementBase?, NativeLayout.wordBytes, Pure.pure, Except.pure]
  have codec : NativeStoreSpec 64 extractedProgram (.scalar (.signed .i32)) (.signed .i32 0) 4 := by
    simpa using NativeStoreSpec.i32 (program := extractedProgram) (fuel := 63) (0 : BitVec 32)
  obtain ⟨heap, run, snapshot, write, _⟩ := RunsExpr.assignRawFieldNative
    (program := extractedProgram) (before := before) (indexed := before) (ready := before)
    (sourceId := extractSource.bindingId 0) (indexExpression := .value (.signed .i32 0))
    (field := 0) (displacement := 0) (expression := .value (.signed .i32 0))
    found (by core_run) arena.countPositive location declaration rfl (by decide +kernel) codec
    (by simpa only [Nat.add_zero] using room) unique noViews (by core_run)
  exact ⟨heap, run, snapshot, write⟩

#print axioms actualExtractResetCount

end IRBodyProductionScalar
