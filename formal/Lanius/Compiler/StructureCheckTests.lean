import Lanius.Compiler.StructureCheck

namespace Lanius.Compiler.StructureCheckTests

open Lanius
open Lanius.Compiler.StructureCheck

def context : SurfaceElaboration.Context := {
  target := .x86_64
  names := {}
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  locals := [] }

example :
    (checkFields context
      [.path [.mk "i32" []], .path [.mk "bool" []]]
      [.scalar (.signed .i32), .scalar .bool]).isSome = true := by
  rfl

example :
    (checkFields context
      [.path [.mk "i32" []]] [.scalar .bool]).isSome = false := by
  rfl

example :
    (checkFields context
      [.path [.mk "usize" []]] [.scalar (.signed .i32)]).isSome = false := by
  rfl

example :
    (checkFields context
      [.path [.mk "usize" []]] [.scalar (.unsigned .usize)]).isSome = true := by
  rfl

example :
    (checkFields context
      [.slice (.path [.mk "i32" []])]
      [.slice (.scalar (.signed .i32))]).isSome = true := by
  rfl

example :
    (checkFields context [] [.scalar (.signed .i32)]).isSome = false := by
  rfl

end Lanius.Compiler.StructureCheckTests
