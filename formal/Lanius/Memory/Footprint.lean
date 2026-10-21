import Lanius.Memory.Read

namespace Lanius.Memory

/-- Byte-only writes within a proved permission set. This frames all other
    reads, including invalid addresses, and retains allocation metadata. -/
structure HeapWritesOn (before after : Heap) (allowed : Address → Prop) : Prop where
  outside : ∀ pointer offset, ¬allowed (pointer + offset) →
    after.loadByte pointer offset = before.loadByte pointer offset
  readable : ∀ pointer count, before.Readable pointer count → after.Readable pointer count
  unique : HeapBlockBasesUnique after
  frontier : after.nextAddress = before.nextAddress
  budget : after.remaining = before.remaining
  layout : after.blocks.map (fun block => { block with bytes := [] }) =
    before.blocks.map (fun block => { block with bytes := [] })

theorem HeapWritesOn.refl (unique : HeapBlockBasesUnique heap) : HeapWritesOn heap heap allowed :=
  ⟨fun _ _ _ => rfl, fun _ _ read => read, unique, rfl, rfl, rfl⟩

theorem HeapWritesOn.trans (first : HeapWritesOn before middle allowed)
    (second : HeapWritesOn middle after allowed) : HeapWritesOn before after allowed :=
  ⟨fun _ _ apart => (second.outside _ _ apart).trans (first.outside _ _ apart),
    fun _ _ read => second.readable _ _ (first.readable _ _ read), second.unique,
    second.frontier.trans first.frontier, second.budget.trans first.budget,
    second.layout.trans first.layout⟩

theorem HeapWritesOn.weaken (write : HeapWritesOn before after allowed)
    (contains : ∀ address, allowed address → larger address) : HeapWritesOn before after larger :=
  ⟨fun _ _ apart => write.outside _ _ (fun inside => apart (contains _ inside)),
    write.readable, write.unique, write.frontier, write.budget, write.layout⟩

theorem BytesWrite.footprint (write : BytesWrite before after address bytes) :
    HeapWritesOn before after (fun location => address ≤ location ∧ location < address + bytes.length) := by
  refine ⟨?_, fun _ _ => write.readable, write.unique, write.frontier, write.budget, write.layout⟩
  intro pointer offset apart
  rw [write.reads]
  split
  · rw [List.getElem?_eq_none (by dsimp only [Address] at *; omega)]
  · rfl

theorem HeapWritesOn.loadBytes (write : HeapWritesOn before after allowed)
    (loaded : before.loadBytes pointer count = .ok bytes)
    (apart : ∀ index, index < count → ¬allowed (pointer + index)) :
    after.loadBytes pointer count = .ok bytes :=
  Heap.loadBytes_congr loaded (fun index bound => write.outside _ _ (apart index bound))

#print axioms BytesWrite.footprint
#print axioms HeapWritesOn.trans

end Lanius.Memory
