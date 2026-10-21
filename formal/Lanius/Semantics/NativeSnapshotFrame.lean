import Lanius.Semantics.NativeReadFrame

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Memory

/-- Retain a scoped native snapshot through allocation or other operations
    already proved to preserve its heap's successful reads. -/
theorem NativeSnapshot.afterHeapReads
    (snapshot : NativeSnapshot fuel program before type address value size)
    (reads : HeapReads before after) : NativeSnapshot fuel program after type address value size := by
  intro other within
  apply snapshot other
  intro pointer width bytes lower upper loaded
  exact within pointer width bytes lower upper (reads.loadBytes loaded)

/-- Retain one represented native slot through an already proved union footprint. -/
theorem NativeSnapshot.afterFootprint (snapshot : NativeSnapshot fuel program before type pointer value size)
    (write : HeapWritesOn before after allowed)
    (apart : ∀ address, pointer ≤ address → address < pointer + size → ¬allowed address) :
    NativeSnapshot fuel program after type pointer value size := by
  intro other reads
  apply snapshot other
  intro address width bytes lower upper loaded
  apply reads _ _ _ lower upper
  exact write.loadBytes loaded (fun offset bound => apart _ (by omega) (by omega))

#print axioms NativeSnapshot.afterHeapReads
#print axioms NativeSnapshot.afterFootprint

end Lanius.Semantics
