import Lanius.Compiler.FunctionContextCheck

namespace Lanius.Compiler.FunctionContextCheckTests

open Lanius
open Lanius.Compiler.FunctionContextCheck

def base : SurfaceElaboration.Context := {
  target := .x86_64
  names := {}
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  locals := [] }

def i32Type : Surface.TypeExpr := .path [.mk "i32" []]
def boolType : Surface.TypeExpr := .path [.mk "bool" []]
def parameter : Surface.Parameter := .named "x" i32Type
def core : Core.Function := {
  id := 0
  parameters := [(7, .scalar (.signed .i32))]
  returnType := .scalar .bool
  body := none
  external := some .panic }

example :
    (checkExternFunction base 3 {
      name := "f"
      parameters := [parameter]
      returnType := some boolType } core).isOk = true := by
  rfl

example :
    (checkExternFunction base 3 {
      name := "f"
      parameters := [parameter]
      returnType := some boolType }
      { core with parameters := [(7, .scalar (.signed .i32)),
        (7, .scalar (.signed .i32))] }).isOk = false := by
  rfl

example :
    (checkFunction base 3 {
      name := "f"
      parameters := [.selfValue none]
      returnType := some boolType
      body := [] }
      { core with body := some .skip, external := none }).isOk = false := by
  decide

example :
    (checkFunction base 3 {
      name := "f"
      parameters := [.named "x" boolType]
      returnType := some boolType
      body := [] }
      { core with body := some .skip, external := none }).isOk = false := by
  decide

example (checked :
    Checked base 3 [parameter] (some boolType) core) :
    checked.next = checked.context.nextExpressionLocalId := checked.nextCanonical

end Lanius.Compiler.FunctionContextCheckTests
