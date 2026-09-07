import Lanius.ExecutionRules

namespace Lanius.Extraction.CanonicalTokens.Compaction

/-- The compacted prefix replaces caller storage without discarding spare capacity. -/
def replacePrefix (original written : List Int) : List Int :=
  written ++ original.drop written.length

theorem replacePrefix_length (original written : List Int)
    (fits : written.length ≤ original.length) :
    (replacePrefix original written).length = original.length := by
  simp [replacePrefix]
  omega

theorem replacePrefix_unread (original written : List Int) (index : Nat)
    (unread : written.length ≤ index) :
    (replacePrefix original written)[index]? = original[index]? := by
  rw [replacePrefix, List.getElem?_append_right unread, List.getElem?_drop]
  congr 1
  omega

theorem replacePrefix_written (original written : List Int) (index : Nat)
    (inside : index < written.length) :
    (replacePrefix original written)[index]? = written[index]? := by
  exact List.getElem?_append_left inside

def writeRow (records : List Int) (index : Nat) (kind start finish : Int) : List Int :=
  ((records.set index kind).set (index + 1) start).set (index + 2) finish

@[simp] theorem writeRow_length (records : List Int) (index : Nat) (kind start finish : Int) :
    (writeRow records index kind start finish).length = records.length := by
  simp [writeRow]

theorem writeRow_at_boundary (written : List Int) (a b c kind start finish : Int) (rest : List Int) :
    writeRow (written ++ a :: b :: c :: rest) written.length kind start finish =
      written ++ kind :: start :: finish :: rest := by
  simp [writeRow, List.set_append_right]

theorem writeRow_unread (records : List Int) (index next : Nat) (kind start finish : Int)
    (afterRow : index + 2 < next) :
    (writeRow records index kind start finish)[next]? = records[next]? := by
  simp [writeRow, List.getElem?_set, show index ≠ next by omega,
    show index + 1 ≠ next by omega, show index + 2 ≠ next by omega]

theorem replacePrefix_push_row (original written : List Int) (kind start finish : Int)
    (fits : written.length + 3 ≤ original.length) :
    writeRow (replacePrefix original written) written.length kind start finish =
      replacePrefix original (written ++ [kind, start, finish]) := by
  have first := List.drop_eq_getElem_cons (show written.length < original.length by omega)
  have second := List.drop_eq_getElem_cons (show written.length + 1 < original.length by omega)
  have third := List.drop_eq_getElem_cons (show written.length + 1 + 1 < original.length by omega)
  unfold replacePrefix
  rw [first, second, third, writeRow_at_boundary]
  simp [List.append_assoc, Nat.add_assoc]

end Lanius.Extraction.CanonicalTokens.Compaction
