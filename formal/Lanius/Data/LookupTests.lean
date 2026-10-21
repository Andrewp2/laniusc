import Lanius.Data.Lookup

namespace Lanius.Data.LookupTests

-- Unsorted keys and overlapping ranges must preserve the first declaration.
private def chunks : List (LookupChunk (Prod.fst : Nat × Nat → Nat)) :=
  [⟨7, 9, [(9, 90), (7, 70)], by decide⟩,
   ⟨7, 8, [(7, 700), (8, 80)], by decide⟩,
   ⟨0, 0, [], by decide⟩]
private def index : Lookup Prod.fst [(9, 90), (7, 70), (7, 700), (8, 80)] :=
  Lookup.ofChunks chunks (by rfl)

example (id : Nat) : index.find? id =
    [(9, 90), (7, 70), (7, 700), (8, 80)].find? (fun value => value.1 == id) :=
  index.correct id
example : index.find? 7 = some (7, 70) := by decide +kernel
example : index.find? 8 = some (8, 80) := by decide +kernel
example : index.find? 10 = none := by decide +kernel
example : (Lookup.ofChunks (key := id) [] rfl).find? 0 = none := rfl

example : True := by
  fail_if_success
    have : LookupChunk (id : Nat → Nat) := ⟨8, 9, [7], by decide⟩
  fail_if_success
    have : Lookup Prod.fst [(7, 700)] := Lookup.ofChunks chunks (by rfl)
  trivial

-- Check the compiled path as well as the kernel-reduced examples.
#eval do
  unless index.find? 7 == some (7, 70) && index.find? 8 == some (8, 80) &&
      index.find? 6 == none && index.find? 10 == none do
    throw (IO.userError "indexed lookup changed first-match semantics")

#print axioms Lookup.chunksFind_eq
end Lanius.Data.LookupTests
