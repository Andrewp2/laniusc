import verified_compiler.tests.direct_ir_catalog_append_outer

namespace IRCatalogCountReadProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogAppendProof

/-- The actual CountCell decoder reads its sole i32 field, not stride padding. -/
theorem fromScalarRead {state : State} {address length : Nat} {value : Int}
    (bound : 0 < length)
    (read : readNativeValue 64 extractedProgram state.heap (.scalar (.signed .i32)) address =
      .ok (.signed .i32 value)) :
    readRawSliceIndex extractedProgram state (.structure countId) address length 0 =
      .ok (.structure countId [.signed .i32 value]) := by
  have declaration : extractedProgram.structure? countId =
      some { id := countId, fields := [.scalar (.signed .i32)] } := by decide +kernel
  have offset : NativeLayout.structureFieldOffset? extractedProgram countId 0 = some 0 := by decide +kernel
  have layout : NativeLayout.valueWords? extractedProgram (.structure countId) = some 1 := by decide +kernel
  have location : rawSliceElementAddress? extractedProgram (.structure countId) address 0 = .ok address := by
    simp [rawSliceElementAddress?, layout, NativeLayout.elementBase?, NativeLayout.wordBytes,
      Pure.pure, Except.pure]
  have fieldRead : readNativeValue 63 extractedProgram state.heap (.scalar (.signed .i32)) address =
      .ok (.signed .i32 value) := read
  simp only [readRawSliceIndex, Nat.not_le_of_lt bound, ↓reduceIte, location]
  dsimp only [Bind.bind, Except.bind]
  change readNativeValue 64 extractedProgram state.heap (.structure countId) address = _
  rw [readNativeValue, declaration]
  simp only [List.length_cons, List.length_nil, List.range_succ, List.range_zero,
    List.cons_append, List.nil_append, List.mapM_cons, List.mapM_nil,
    List.getElem?_cons_zero, offset, Nat.add_zero, fieldRead]
  rfl

#print axioms fromScalarRead

end IRCatalogCountReadProof
