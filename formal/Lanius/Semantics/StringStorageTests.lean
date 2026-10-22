import Lanius.Semantics

namespace Lanius.Semantics.StringStorageTests

open Lanius

-- Storage rounds up by bytes, not Unicode characters; logical contents stay
-- unchanged, including empty strings and embedded NULs.
example : (["", "A", "AB", "ABC", "ABCD", "ABCDE", "é", "🙂", "\x00"]).map
    (fun value => (stringStorage value).length) = [0, 4, 4, 4, 4, 8, 4, 4, 4] := by decide

example : stringStorage "é" = [195, 169, 0, 0] := by decide

private def view (value : String) (words : Int) : Outcome Core.Value :=
  match mapStringDataPtr {} value with
  | .done (.pointer address) state => mapRawI32Slice state address words
  | other => other

private def rejects (value : String) (words : Int) : Bool :=
  match view value words with
  | .trapped .rawMemoryBounds _ => true
  | _ => false

private def traps (value : String) (words : Int) : Bool :=
  match view value words with
  | .trapped _ _ => true
  | _ => false

private def views (value : String) (words : Int) : Bool :=
  match view value words with
  | .done (.rawSlice _ _ _) _ => true
  | _ => false

-- Padding does not authorize another word, and negative lengths trap. A view
-- of a prefix of the storage is a view of a range inside the block.
example : rejects "A" 2 = true := by decide
example : rejects "ABCD" 2 = true := by decide
example : traps "" 1 = true := by decide
example : rejects "A" (-1) = true := by decide
example : views "ABCDE" 1 = true := by decide
example : views "ABCDE" 2 = true := by decide
example : rejects "ABCDE" 3 = true := by decide

end Lanius.Semantics.StringStorageTests
