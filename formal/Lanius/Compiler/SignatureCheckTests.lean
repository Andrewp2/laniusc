import Lanius.Compiler.SignatureCheck

namespace Lanius.Compiler.SignatureCheckTests

open Lanius
open Lanius.Compiler.SignatureCheck

def context : SurfaceElaboration.Context := {
  target := .x86_64
  names := {}
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  locals := [{ name := "x", id := 3, type := .scalar (.signed .i32) }] }

def i32Type : Surface.TypeExpr := .path [.mk "i32" []]
def boolType : Surface.TypeExpr := .path [.mk "bool" []]
def usizeType : Surface.TypeExpr := .path [.mk "usize" []]
def strType : Surface.TypeExpr := .path [.mk "str" []]
def i32Parameter : Surface.Parameter := .named "x" i32Type

example :
    (checkNamedParameters context [i32Parameter] context.locals
      [(3, .scalar (.signed .i32))]).isSome = true := by
  rfl

example :
    (checkNamedParameters context [i32Parameter] context.locals
      [(4, .scalar (.signed .i32))]).isSome = false := by
  rfl

example :
    (checkNamedParameters context [i32Parameter] context.locals
      [(3, .scalar (.unsigned .usize))]).isSome = false := by
  rfl

example :
    (checkNamedParameters context [.selfValue none] context.locals
      [(3, .scalar (.signed .i32))]).isSome = false := by
  rfl

example :
    (checkNamedParameters context [.named "y" i32Type] context.locals
      [(3, .scalar (.signed .i32))]).isSome = false := by
  rfl

example :
    (checkReturnType context (some i32Type) (.scalar (.signed .i32))).isSome = true := by
  rfl

example :
    (checkReturnType context none .unit).isSome = true := by
  rfl

example :
    (checkReturnType context none (.scalar (.signed .i32))).isSome = false := by
  rfl

example :
    (checkReturnType context (some i32Type) (.array (.scalar (.signed .i32)) 2)).isSome = false := by
  rfl

def usizeContext : SurfaceElaboration.Context :=
  { context with locals := [{ name := "x", id := 3, type := .scalar (.unsigned .usize) }] }

example :
    (checkNamedParameters usizeContext [.named "x" usizeType] usizeContext.locals
      [(3, .scalar (.unsigned .usize))]).isSome = true := by
  rfl

example :
    (checkReturnType context (some strType) (.scalar .string)).isSome = true := by
  rfl

example :
    (checkReturnType context (some usizeType) (.scalar (.signed .i32))).isSome = false := by
  rfl

example :
    (check context [i32Parameter] (some boolType)
      [(3, .scalar (.signed .i32))] (.scalar .bool)).isOk = true := by
  rfl

example :
    (check context [i32Parameter] (some boolType)
      [(3, .scalar (.signed .i32))] (.scalar (.signed .i32))).isOk = false := by
  rfl

def extern : Surface.ExternFunction := {
  name := "f"
  parameters := [i32Parameter]
  returnType := some boolType }

def coreExtern : Core.Function := {
  id := 9
  parameters := [(3, .scalar (.signed .i32))]
  returnType := .scalar .bool
  body := none
  external := some .panic }

example : (checkExternFunction context extern coreExtern).isOk = true := by
  rfl

end Lanius.Compiler.SignatureCheckTests
