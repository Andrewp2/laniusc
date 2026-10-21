import Lanius.TypedIR.Surface.DataCompilerTests

namespace Lanius.TypedIR.Surface.DataCompilerImportTests
open DataCompilerTests

-- A compact optimizer cache must not hide kernel bodies, lose executable
-- definitions, or disturb the ordinary path for closures and effects.
set_option compiler.check true

example : data = [some (7, "α"), none, some (4294967297, "x\x00y")] := rfl
example : build 5 = [3, 2, 5, 6, 7] := by decide
example : captured 4 = 27 := by decide
example : polymorphic (α := Nat) = none := rfl

#eval show IO Unit from do
  unless data == [some (7, "α"), none, some (4294967297, "x\x00y")] &&
      build 5 == [3, 2, 5, 6, 7] && captured 4 == 27 && (← effect) == 20 &&
      inlineData == [1, 2, 3] && (polymorphic : Option Nat) == none do
    throw (IO.userError "imported constructor data changed execution")

end Lanius.TypedIR.Surface.DataCompilerImportTests
