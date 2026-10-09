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

-- Padding does not authorize another word, negative lengths, or a different
-- logical allocation size. Ordinary exact-block slice checks remain intact.
example : rejects "A" 2 = true := by decide
example : rejects "ABCD" 2 = true := by decide
example : rejects "" 1 = true := by decide
example : rejects "A" (-1) = true := by decide
example : rejects "ABCDE" 1 = true := by decide

end Lanius.Semantics.StringStorageTests
