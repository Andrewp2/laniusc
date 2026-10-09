import Lanius.Memory.Store

namespace Lanius.Memory

-- Reverse chronology still produces forward byte order, and retains the
-- frame over every other address, including aliases and invalid pointers.
theorem reversePair (unique : HeapBlockBasesUnique before)
    (right : ByteWrite before middle (address + 1) second)
    (left : ByteWrite middle after address first) :
    BytesWrite before after address [first, second] := by
  have suffix : BytesWrite before middle (address + 1) [second] := by
    simpa using (BytesWrite.refl (address := address + 1) unique).snoc right
  exact suffix.cons left

#print axioms reversePair

end Lanius.Memory
