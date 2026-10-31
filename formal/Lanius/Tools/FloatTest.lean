import Lanius.IEEE

/-! The IEEE specification (`Lanius.IEEE`), compiled, for
formal/tools/float_test.py, which compares it with this machine's SSE unit.

    lake exe floatTest < CASES

Each input line is `OP W ARGS...` with `W` 32 or 64 (the format) and decimal
arguments: `add`, `sub`, `mul`, `div`, `eq`, `lt`, `le` take two patterns;
`neg` and `cvt` (to the other format) one; `int` an integer; `trunc` a
pattern and the bounds; `dec` a decimal significand and exponent. Each prints
one line: the result pattern, 0 or 1 for a comparison, the integer for
`trunc`. -/

open Lanius.IEEE

namespace Lanius.Tools.FloatTest

def run (words : List String) : Option String := do
  let op :: w :: args := words | none
  let F ← if w == "32" then some binary32 else if w == "64" then some binary64 else none
  let G := if w == "32" then binary64 else binary32
  let nat (s : String) : Option Nat := s.toNat?
  let int (s : String) : Option Int := s.toInt?
  let bool (b : Bool) : String := if b then "1" else "0"
  match op, args with
  | "add", [a, b] => return toString (F.add (← nat a) (← nat b))
  | "sub", [a, b] => return toString (F.sub (← nat a) (← nat b))
  | "mul", [a, b] => return toString (F.mul (← nat a) (← nat b))
  | "div", [a, b] => return toString (F.div (← nat a) (← nat b))
  | "eq", [a, b] => return bool (F.eq (← nat a) (← nat b))
  | "lt", [a, b] => return bool (F.lt (← nat a) (← nat b))
  | "le", [a, b] => return bool (F.le (← nat a) (← nat b))
  | "neg", [a] => return toString (F.neg (← nat a))
  | "cvt", [a] => return toString (F.convert G (← nat a))
  | "int", [i] => return toString (F.ofInt (← int i))
  | "trunc", [a, lo, hi] => return toString (F.truncSat (← nat a) (← int lo) (← int hi))
  | "dec", [m, e] => return toString (F.ofDecimal (← nat m) (← int e))
  | _, _ => none

end Lanius.Tools.FloatTest

def main : IO UInt32 := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  let mut failed := false
  repeat
    let line ← stdin.getLine
    if line.isEmpty then break
    let words := (line.trimAscii.toString.splitOn " ").filter (· ≠ "")
    if words.isEmpty then continue
    match Lanius.Tools.FloatTest.run words with
    | some out => stdout.putStrLn out
    | none => stdout.putStrLn "bad"; failed := true
  stdout.flush
  return if failed then 1 else 0
