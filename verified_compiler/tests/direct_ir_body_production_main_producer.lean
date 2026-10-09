import verified_compiler.tests.direct_ir_body_production_main_block
import verified_compiler.tests.direct_ir_body_production_scalar_memory

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IREventStoreProof
open IRBodyProductionScalar

/-- One source-selected native stream, including the actual locals-count
    restore and used workspace/output footprint. It records observations,
    not execution of a decoder or a second semantic body model. -/
def TerminalStream (body : ReturnBody) (output : Context state)
    (permissions : OutputPermissions output body.count) (result : IRTypeRefProof.Reference)
    (memory : Nat) (allowed : Nat → Prop) (before after : Heap) : Prop :=
  (∀ index, index < body.count → NativeSnapshot 64 extractedProgram after
    IREventStoreProof.eventType (permissions.eventBases index) (body.event index) 40) ∧
  (output.enabled = true → ∀ index, index < body.count → NativeSnapshot 64 extractedProgram after
    IREventStoreProof.referenceType (permissions.typeBases index)
      (IRTypeRefProof.referenceValue (if index = 0 then .Invalid else result)) 16) ∧
  NativeSnapshot 64 extractedProgram after (.scalar (.signed .i32)) memory (.signed .i32 0) 4 ∧
  HeapWritesOn before after (fun address => allowed address ∨ memory ≤ address ∧ address < memory + 4)

/-- The same produced stream survives the real block's four-byte count
    restore. Only the native output observations cross this boundary. -/
theorem TerminalStream.ofBlock (body : ReturnBody) (output : Context state)
    (permissions : OutputPermissions output body.count) (result : IRTypeRefProof.Reference)
    (effect : BlockHeapEffect relation memory before after)
    (events : ∀ {a b}, relation a b → ∀ index, index < body.count →
      NativeSnapshot 64 extractedProgram b IREventStoreProof.eventType
        (permissions.eventBases index) (body.event index) 40)
    (types : ∀ {a b}, relation a b → output.enabled = true → ∀ index, index < body.count →
      NativeSnapshot 64 extractedProgram b IREventStoreProof.referenceType
        (permissions.typeBases index)
        (IRTypeRefProof.referenceValue (if index = 0 then .Invalid else result)) 16)
    (writes : ∀ {a b}, relation a b → HeapWritesOn a b allowed)
    (eventApart : ∀ index, index < body.count →
      permissions.eventBases index + 40 ≤ memory ∨ memory + 4 ≤ permissions.eventBases index)
    (typeApart : output.enabled = true → ∀ index, index < body.count →
      permissions.typeBases index + 16 ≤ memory ∨ memory + 4 ≤ permissions.typeBases index) :
    TerminalStream body output permissions result memory allowed before after := by
  obtain ⟨emitted, produced, restoredCount, restored⟩ := effect
  exact ⟨fun index inside => (events produced index inside).afterWrite restored (eventApart index inside),
    fun enabled index inside => (types produced enabled index inside).afterWrite restored
      (typeApart enabled index inside), restoredCount,
    BlockHeapEffect.footprint ⟨emitted, produced, restoredCount, restored⟩ writes⟩

def VoidStream (output : Context state) (memory : Nat) (before after : Heap) : Prop :=
  NativeSnapshot 64 extractedProgram after eventType output.eventBase (returnEvent false) 40 ∧
  (output.enabled = true → NativeSnapshot 64 extractedProgram after referenceType output.typeBase invalid 16) ∧
  NativeSnapshot 64 extractedProgram after (.scalar (.signed .i32)) memory (.signed .i32 0) 4 ∧
  HeapWritesOn before after (fun address =>
    (output.eventBase ≤ address ∧ address < output.eventBase + 40) ∨
    (output.enabled = true ∧ output.typeBase ≤ address ∧ address < output.typeBase + 16) ∨
    (memory ≤ address ∧ address < memory + 4))

/-- Original topology and initialized local storage discharge the complete
    block phase, including the real save and restore calls in both modes. -/
theorem actualVoidBlock (input : Inputs) (workspace : Workspace) (memory capacity : Nat)
    (topology : TerminalTopology input before.heap declaration)
    (optional : topology.optionalNode.production = 91) (kind : input.signature.result = .Void)
    (depth : Nat) (positive : 2 < depth) (fits : depth < 2 ^ 31) (output : Context before)
    (count : NativeSnapshot 64 extractedProgram before.heap (.scalar (.signed .i32)) memory (.signed .i32 0) 4)
    (room : before.heap.Readable memory 4)
    (eventApart : output.eventBase + 40 ≤ memory ∨ memory + 4 ≤ output.eventBase)
    (typeApart : output.enabled = true → output.typeBase + 16 ≤ memory ∨ memory + 4 ≤ output.typeBase)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) : ∃ after,
    RunsExpr extractedProgram before
      (terminalBlockCall (bodyContext input workspace (localsValue memory capacity))
        topology.block output.value output.position depth)
      (.signed .i32 (output.position + 1 : Nat)) after ∧ MemoryEffect (VoidStream output memory) before after := by
  obtain ⟨after, run, effect⟩ := actualTerminalBlock
    (stream := appendHeapEffect output.enabled output.eventBase output.typeBase (returnEvent false))
    (allowed := fun address => (output.eventBase ≤ address ∧ address < output.eventBase + 40) ∨
      (output.enabled = true ∧ output.typeBase ≤ address ∧ address < output.typeBase + 16))
    input workspace memory capacity topology.block topology.list depth
    (by omega) fits
    (fun same formed => by
      simpa only [topology.listIndex] using actualBlockList topology.blockNode topology.blockProduction
        topology.blockBound topology.listChild topology.listKind same formed)
    (fun {current} same views formed => by
      simpa only [Appended, Context.reheap, Context.value, TerminalTopology.afterReads] using
        actualVoidTerminalList (before := current) input workspace (localsValue memory capacity)
          (topology.afterReads (fun _ _ _ read => by simpa only [same] using read))
          optional kind (depth - 1) (by omega) (by omega) (output.reheap same) formed
          (by rw [same]; exact unique) (views.trans noViews))
    (fun produced => produced.footprint) count room formed noViews
  obtain ⟨emitted, produced, restoredCount, restored⟩ := effect.2.2.2
  refine ⟨after, run, effect.1, effect.2.1, effect.2.2.1,
    produced.1.afterWrite restored eventApart, ?_, restoredCount, ?_⟩
  · intro enabled
    obtain ⟨_, _, annotated⟩ := produced.2
    simp only [enabled, ↓reduceIte] at annotated
    exact annotated.1.afterWrite restored (typeApart enabled)
  · exact (BlockHeapEffect.footprint ⟨emitted, produced, restoredCount, restored⟩
      (fun phase => phase.footprint)).weaken (fun _ inside => by
        rcases inside with (event | annotation) | counterRange
        · exact Or.inl event
        · exact Or.inr (Or.inl annotation)
        · exact Or.inr (Or.inr counterRange))

#print axioms actualVoidBlock
#print axioms TerminalStream.ofBlock

end IRBodyProductionProof
