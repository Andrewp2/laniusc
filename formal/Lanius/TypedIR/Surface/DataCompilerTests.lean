import Lanius.TypedIR.Surface.DataCompiler

namespace Lanius.TypedIR.Surface.DataCompilerTests

-- Exercise both the constructor-only path and ordinary code in an importing
-- module, with Lean's intermediate compiler checks enabled after every pass.
set_option compiler.check true

def data : List (Option (Nat × String)) :=
  [some (7, "α"), none, some (4294967297, "x\x00y")]

def build (count : Nat) : List Nat :=
  (List.range count).map fun index => if index % 2 == 0 then index + 3 else index * 2

def captured : Nat → Nat :=
  let values := build 5
  fun offset => values.foldl (· + ·) offset

def effect : IO Nat := do
  let cell ← IO.mkRef (build 3)
  cell.modify (fun values => 10 :: values)
  return (← cell.get).foldl (· + ·) 0

@[inline] def inlineData : List Nat := [1, 2, 3]
def polymorphic : Option α := none

example : data = [some (7, "α"), none, some (4294967297, "x\x00y")] := rfl
example : build 5 = [3, 2, 5, 6, 7] := by decide
example : captured 4 = 27 := by decide

#eval show IO Unit from do
  unless data == [some (7, "α"), none, some (4294967297, "x\x00y")] &&
      build 5 == [3, 2, 5, 6, 7] && captured 4 == 27 && (← effect) == 20 do
    throw (IO.userError "constructor-data compilation changed execution")

end Lanius.TypedIR.Surface.DataCompilerTests
