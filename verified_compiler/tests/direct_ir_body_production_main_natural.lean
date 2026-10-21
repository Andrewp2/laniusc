import verified_compiler.tests.direct_ir_body_production_main_return_value
import verified_compiler.tests.direct_ir_body_production_main_producer

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IREventStoreProof IRBodyProductionScalar IRTypeRefProof
open IRBodyProductionInputs

variable {extra : Nat → Prop}

/-- The real return header and the source-selected expression observations
    form one native stream. Header preservation follows from the original
    used-slot geometry, not an assumed final header read. -/
theorem ValueReturnHeapEffect.native (body : ReturnBody) (nonvoid : body ≠ .void)
    (output : Context anchor) (zero : output.position = 0)
    (permissions : OutputPermissions output body.count)
    (effect : ValueReturnHeapEffect output expression before after)
    (events : ∀ {a b}, expression a b → ∀ index, 1 ≤ index → index < body.count →
      NativeSnapshot 64 extractedProgram b IREventStoreProof.eventType
        (permissions.eventBases index) (body.event index) 40)
    (types : ∀ {a b}, expression a b → output.enabled = true →
      ∀ index, 1 ≤ index → index < body.count → NativeSnapshot 64 extractedProgram b
        IREventStoreProof.referenceType (permissions.typeBases index) (referenceValue result) 16)
    (writes : ∀ {a b}, expression a b → HeapWritesOn a b
      (fun address => extra address ∨ permissions.writesFrom 1 address))
    (apart : ∀ address, permissions.writesFrom 0 address → ¬extra address) :
    (∀ index, index < body.count → NativeSnapshot 64 extractedProgram after
      IREventStoreProof.eventType (permissions.eventBases index) (body.event index) 40) ∧
    (output.enabled = true → ∀ index, index < body.count → NativeSnapshot 64 extractedProgram after
      IREventStoreProof.referenceType (permissions.typeBases index)
        (referenceValue (if index = 0 then .Invalid else result)) 16) ∧
    HeapWritesOn before after (fun address => extra address ∨ permissions.writesFrom 0 address) := by
  have first : 0 < body.count := by cases body <;> simp only [ReturnBody.count] <;> decide
  have eventBase : permissions.eventBases 0 = output.eventBase := by
    have original := output.eventLocation
    rw [zero] at original
    exact Except.ok.inj ((permissions.eventLocation 0 first).symm.trans original)
  have typeBase (enabled : output.enabled = true) : permissions.typeBases 0 = output.typeBase := by
    have original := output.typeLocation enabled
    rw [zero] at original
    exact Except.ok.inj ((permissions.typeLocation enabled 0 first).symm.trans original)
  have eventZero : body.event 0 = returnEvent true := by
    cases body <;> simp only [ReturnBody.event] <;> try rfl
    exact False.elim (nonvoid rfl)
  obtain ⟨header, written, emitted⟩ := effect
  have tailWrites := writes emitted
  have eventSafe : ∀ address, permissions.eventBases 0 ≤ address →
      address < permissions.eventBases 0 + 40 →
      ¬(extra address ∨ permissions.writesFrom 1 address) := by
    intro address lower upper changed
    rcases changed with mutable | tail
    · exact apart address ⟨0, Nat.zero_le _, first, Or.inl ⟨lower, upper⟩⟩ mutable
    · rcases tail with ⟨index, positive, inside, event | annotation⟩
      · have separate := permissions.eventSeparation 0 index first inside (by omega)
        rcases separate with left | right <;> omega
      · have separate := permissions.planes annotation.1 0 index first inside
        rcases separate with left | right <;> omega
  have typeSafe (enabled : output.enabled = true) : ∀ address, permissions.typeBases 0 ≤ address →
      address < permissions.typeBases 0 + 16 →
      ¬(extra address ∨ permissions.writesFrom 1 address) := by
    intro address lower upper changed
    rcases changed with mutable | tail
    · exact apart address ⟨0, Nat.zero_le _, first, Or.inr ⟨enabled, lower, upper⟩⟩ mutable
    · rcases tail with ⟨index, positive, inside, event | annotation⟩
      · have separate := permissions.planes enabled index 0 inside first
        rcases separate with left | right <;> omega
      · have separate := permissions.typeSeparation enabled 0 index first inside (by omega)
        rcases separate with left | right <;> omega
  refine ⟨?_, ?_, ?_⟩
  · intro index inside
    by_cases initial : index = 0
    · subst index
      rw [eventZero, eventBase]
      exact written.1.afterFootprint tailWrites (by simpa only [eventBase] using eventSafe)
    · exact events emitted index (by omega) inside
  · intro enabled index inside
    by_cases initial : index = 0
    · subst index
      rw [if_pos rfl, typeBase enabled]
      obtain ⟨_, _, annotation⟩ := written.2
      simp only [enabled, ↓reduceIte] at annotation
      exact annotation.1.afterFootprint tailWrites (by simpa only [typeBase enabled] using typeSafe enabled)
    · rw [if_neg initial]
      exact types emitted enabled index (by omega) inside
  · have headerWrites : HeapWritesOn before header
        (fun address => extra address ∨ permissions.writesFrom 0 address) :=
      written.footprint.weaken (fun address changed => by
      apply Or.inr
      refine ⟨0, Nat.zero_le _, first, ?_⟩
      rcases changed with event | annotation
      · exact Or.inl (by simpa only [eventBase] using event)
      · exact Or.inr ⟨annotation.1, by simpa only [typeBase annotation.1] using annotation.2⟩)
    exact headerWrites.trans (tailWrites.weaken (fun address changed => by
      rcases changed with mutable | ⟨index, positive, inside, slot⟩
      · exact Or.inl mutable
      · exact Or.inr ⟨index, Nat.zero_le _, inside, slot⟩))

#print axioms ValueReturnHeapEffect.native

/-- The actual scalar statement/list/block queries compose with the one
    return-value phase. The final original-input scalar theorem discharges
    `expected`; no execution assumption is exported by the total producer. -/
theorem actualScalarBlockWith (input : Inputs) (workspace : Workspace) (memory capacity : Nat)
    (topology : TerminalTopology input before.heap declaration)
    (root : Nat) (optional : topology.optionalNode.production = 90)
    (optionalBound : 0 < topology.optionalNode.count)
    (child : NativeChild input.tree before.heap topology.optionalNode.first)
    (childKind : child.kind = .StateChild) (childPayload : child.payload = root)
    (depth : Nat) (positive : 2 < depth) (fits : depth < 2 ^ 31)
    (body : ReturnBody) (nonvoid : body ≠ .void)
    (output : Context before) (zero : output.position = 0)
    (permissions : OutputPermissions output body.count)
    (expected : ∀ {current : State},
      appendHeapEffect output.enabled output.eventBase output.typeBase (returnEvent true)
        before.heap current.heap → current.CellsWellFormed →
      current.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram current
        (expectedScalarCall input workspace (localsValue memory capacity) root output.value 1 (depth - 3))
        (.signed .i32 body.count) after ∧ MemoryEffect expression current after)
    (events : ∀ {a b}, expression a b → ∀ index, 1 ≤ index → index < body.count →
      NativeSnapshot 64 extractedProgram b IREventStoreProof.eventType
        (permissions.eventBases index) (body.event index) 40)
    (types : ∀ {a b}, expression a b → output.enabled = true →
      ∀ index, 1 ≤ index → index < body.count → NativeSnapshot 64 extractedProgram b
        IREventStoreProof.referenceType (permissions.typeBases index)
        (referenceValue input.signature.result) 16)
    (writes : ∀ {a b}, expression a b → HeapWritesOn a b
      (fun address => extra address ∨ permissions.writesFrom 1 address))
    (apart : ∀ address, permissions.writesFrom 0 address → ¬extra address)
    (count : NativeSnapshot 64 extractedProgram before.heap (.scalar (.signed .i32)) memory (.signed .i32 0) 4)
    (room : before.heap.Readable memory 4)
    (eventApart : ∀ index, index < body.count →
      permissions.eventBases index + 40 ≤ memory ∨ memory + 4 ≤ permissions.eventBases index)
    (typeApart : output.enabled = true → ∀ index, index < body.count →
      permissions.typeBases index + 16 ≤ memory ∨ memory + 4 ≤ permissions.typeBases index)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) : ∃ after,
    RunsExpr extractedProgram before
      (terminalBlockCall (bodyContext input workspace (localsValue memory capacity))
        topology.block output.value output.position depth) (.signed .i32 body.count) after ∧
    MemoryEffect (TerminalStream body output permissions input.signature.result memory
      (fun address => extra address ∨ permissions.writesFrom 0 address)) before after := by
  have native {a b} (effect : ValueReturnHeapEffect output expression a b) :=
    ValueReturnHeapEffect.native body nonvoid output zero permissions effect events types writes apart
  obtain ⟨after, run, effect⟩ := actualTerminalBlock
    (stream := ValueReturnHeapEffect output expression)
    (allowed := fun address => extra address ∨ permissions.writesFrom 0 address)
    input workspace memory capacity topology.block topology.list depth (by omega) fits
    (fun same formed => by
      simpa only [topology.listIndex] using actualBlockList topology.blockNode topology.blockProduction
        topology.blockBound topology.listChild topology.listKind same formed)
    (fun {current} same views cells => by
      apply actualTerminalList input workspace (localsValue memory capacity)
        topology.list topology.statement topology.rest (depth - 1) (by omega) (by omega) (some root)
      · intro selected heap formed
        simpa only [terminalTag, childPayload] using actualReturnValue topology.statementNode
          topology.statementProduction topology.statementBound topology.optionalChild topology.optionalKind
          topology.optionalNode topology.optionalIndex optional optionalBound child childKind
          (by rw [childPayload]; exact Int.natCast_nonneg _) (heap.trans same) formed
      · intro selected heap formed
        exact actualListEnd topology.restNode topology.restProduction (heap.trans same) formed
      · intro selected heap formed
        simpa only [topology.firstIndex, topology.restIndex] using actualListMore topology.listNode
          topology.listProduction topology.listBound topology.firstChild topology.restChild
          topology.firstKind topology.restKind (by rw [topology.firstIndex]; exact Int.natCast_nonneg _)
          (by rw [topology.restIndex]; exact Int.natCast_nonneg _) (heap.trans same) formed
      · intro selected heap selectedViews formed
        have originalHeap := heap.trans same
        obtain ⟨written, writer, effect⟩ := actualValueReturnWith input workspace (localsValue memory capacity)
          root (depth - 1 - 1) (by omega) (by omega) (output.reheap originalHeap) body.count
          (by
            intro state header stateFormed stateViews
            have originalHeader : appendHeapEffect output.enabled output.eventBase output.typeBase
                (returnEvent true) before.heap state.heap := by
              simpa only [Context.reheap, originalHeap] using header
            obtain ⟨after, run, effect⟩ := expected originalHeader stateFormed
              (stateViews.trans (selectedViews.trans views))
            exact ⟨after, by simpa only [Context.reheap, Context.value, zero, Nat.zero_add,
              Int.zero_add, Int.natCast_zero, Nat.sub_sub] using run, effect⟩)
          formed (by rw [originalHeap]; exact unique) ((selectedViews.trans views).trans noViews)
        exact ⟨written, by simpa only [Context.reheap, Context.value] using writer,
          by simpa only [MemoryEffect, ValueReturnHeapEffect, Context.reheap] using effect⟩
      · exact cells)
    (fun phase => (native phase).2.2) count room formed noViews
  exact ⟨after, run, effect.1, effect.2.1, effect.2.2.1,
    TerminalStream.ofBlock body output permissions input.signature.result effect.2.2.2
      (fun phase => (native phase).1) (fun phase => (native phase).2.1)
      (fun phase => (native phase).2.2) eventApart typeApart⟩

#print axioms actualScalarBlockWith

end IRBodyProductionProof
