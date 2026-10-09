import Lanius.TypedIR.Surface.LinkTests

namespace Lanius.TypedIR.Surface.MetadataImportTests
open Lanius LinkTests
open scoped Surface

-- Metadata survives import, including a public alias of a private type.
def imported : Function [Choice] I32 :=
  function (id := 8, name := "imported", arguments := [choice := 1], bindings := [2]) do
    return match choice with
      | .none => 0
      | .some value => value

def importedProgram : Core.Program :=
  link (types := [Choice, Box I32, HiddenAlias], constants := [], functions := [imported.pack])

example : imported.core.parameters = [(1, .enumeration 9)] := rfl
example : importedProgram.structures =
    [⟨7, [.scalar (.signed .i32), .slice (.enumeration 9)]⟩,
     ⟨11, [.scalar (.signed .i32)]⟩] := rfl
example : importedProgram.enumerations =
    [⟨9, [[], [.scalar (.signed .i32)]]⟩] := rfl

end Lanius.TypedIR.Surface.MetadataImportTests
