import Lanius.Memory.Output

namespace Lanius.Memory

-- Fresh string storage may be allocated between two writes. The final
-- output and every old readable alias/canary still have the stated contents.
theorem textThenByte (text : OutputEffect before middle address bytes)
    (last : ByteWrite middle after (address + bytes.length) byte)
    (readable : before.Readable address (bytes.length + 1)) :
    after.loadBytes address (bytes ++ [byte]).length = .ok (bytes ++ [byte]) := by
  have single : BytesWrite middle after (address + bytes.length) [byte] := by
    simpa using (BytesWrite.refl (address := address + bytes.length) text.unique).snoc last
  exact (text.append (.write single)).loadBytes (by simpa using readable)

theorem borrowKeepsCanary (below : HeapBlocksBelowNext before)
    (written : BytesWrite (before.borrowedI32 storage) after address bytes)
    (old : before.loadByte pointer offset = .ok value)
    (outside : pointer + offset < address ∨ address + bytes.length ≤ pointer + offset) :
    after.loadByte pointer offset = .ok value ∧ HeapBlocksBelowNext after :=
  ⟨(OutputEffect.borrow storage below written).outside old outside,
    (OutputEffect.borrow storage below written).belowNext below⟩

#print axioms textThenByte
#print axioms borrowKeepsCanary

end Lanius.Memory
