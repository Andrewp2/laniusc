import Lanius.Extraction.ScopedSurface

namespace Lanius.Extraction.ScopedSurface.Tests

open Lanius.Extraction

def spelled (token : Nat) (text : String) : SpelledName := ⟨token, text⟩

def boolExpr (id : Nat) : SurfaceExpr :=
  ⟨id, id, .literal (.boolean true)⟩

def nameExpr (id : Nat) (name : String) : SurfaceExpr :=
  ⟨id, id, .path ⟨id + 1000, id, ⟨[
    ⟨id + 2000, id, spelled id name, []⟩
  ]⟩⟩⟩

/-- Declaration visibility is sequential, and branch-local shadowing does not
    leak to its sibling or the enclosing statement tail. -/
def shadowingFunction : SurfaceFunction := {
  name := spelled 0 "shadowing"
  is_public := false
  parameters := []
  return_type := none
  body := [
    ⟨10, 10, .let_local (spelled 10 "x") none none⟩,
    ⟨20, 20, .if_then_else (boolExpr 21) [
      ⟨30, 30, .let_local (spelled 30 "x") none none⟩,
      ⟨31, 31, .expression (nameExpr 310 "x")⟩
    ] [
      ⟨32, 32, .expression (nameExpr 320 "x")⟩
    ]⟩,
    ⟨40, 40, .expression (nameExpr 400 "x")⟩
  ]
}

def checkedShadowing : CheckedFunction :=
  (checkFunction? 0 1 shadowingFunction).get (by native_decide)

example : checkedShadowing.localDeclarationNode? 310 = some 30 := by
  native_decide

example : checkedShadowing.localDeclarationNode? 320 = some 10 := by
  native_decide

example : checkedShadowing.localDeclarationNode? 400 = some 10 := by
  native_decide

end Lanius.Extraction.ScopedSurface.Tests
