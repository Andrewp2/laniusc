import Lanius.Extraction.CompactOutput.Append

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics

/-- Keep early capacity failure distinct from normal completion of an empty
sequence. Empty writers return their original cursor, even if it is negative. -/
inductive AppendOutcome where
  | done (position : Int) (contents : List Int)
  | full (contents : List Int)
  deriving Repr, BEq

def AppendOutcome.position : AppendOutcome → Int
  | .done position _ => position
  | .full _ => -1

def AppendOutcome.contents : AppendOutcome → List Int
  | .done _ contents | .full contents => contents

def AppendOutcome.completion : AppendOutcome → Completion
  | .done _ _ => .next
  | .full _ => .returned (some (.signed .i32 (-1)))

def appendAll (capacity : Nat) : List Nat → Int → List Int → AppendOutcome
  | [], position, original => .done position original
  | value :: rest, position, original =>
    let next := nextPosition capacity position
    let contents := appended original capacity position value
    if next < 0 then .full contents else appendAll capacity rest next contents

theorem appendAll_length (capacity : Nat) (values : List Nat) (position : Int) (original : List Int) :
    (appendAll capacity values position original).contents.length = original.length := by
  induction values generalizing position original with
  | nil => rfl
  | cons value rest ih =>
    simp only [appendAll]
    split
    · exact appended_length
    · rw [ih, appended_length]

/-- Fixed width and high-to-low order, matching the compact reader's base-16
accumulation. In particular, leading zeroes are not dropped. -/
def hexDigits (value : Nat) : Nat → List Nat
  | 0 => []
  | count + 1 => hexDigit (value / 2 ^ (count * 4) % 16) :: hexDigits value count

theorem hexDigits_length (value count : Nat) : (hexDigits value count).length = count := by
  induction count with
  | zero => rfl
  | succ count ih => simp only [hexDigits, List.length_cons, ih]

theorem hexDigits_bytes (member : digit ∈ hexDigits value count) : digit < 256 := by
  induction count with
  | zero => simp [hexDigits] at member
  | succ count ih =>
    simp only [hexDigits, List.mem_cons] at member
    rcases member with rfl | member
    · exact hexDigit_bound (by omega)
    · exact ih member

end Lanius.Extraction.CompactOutput
