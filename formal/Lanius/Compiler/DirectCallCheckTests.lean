import Lanius.Compiler.DirectCallCheck

namespace Lanius.Compiler.DirectCallCheckTests

open Lanius
open Lanius.SurfaceElaboration
open Lanius.Compiler.DirectCallCheck

def path : Surface.Path := { segments := [.mk "callee" []] }

def symbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .value
  name := "callee"
  visibility := .modulePrivate
  declaration := 42 }

def environment : Names.Environment := {
  modules := [{ id := 0, path := [] }]
  symbols := [symbol] }

def scheme : Static.FunctionScheme := {
  declaration := 42
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32) }

def calleeInstance : Static.FunctionInstance := {
  declaration := 42
  function := 7
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32) }

def context : Context := {
  target := .x86_64
  names := environment
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  functions := [scheme]
  functionInstances := [calleeInstance] }

def surfaceArguments : List Surface.Expr := [.literal (.integer "7")]
def coreArguments : List Core.Expr := [.value (.signed .i32 (Int.ofNat 7))]

def argumentLowering (ctx : Context) : ExprsLower ctx surfaceArguments
    [.scalar (.signed .i32)] coreArguments :=
  .cons (ExprLowers.literal
    (context := ctx) (literal := .integer "7")
    (groundType := .scalar (.signed .i32))
    (expression := .value (.signed .i32 (Int.ofNat 7)))
    (.signedInteger rfl (by simp [Typing.signedMax, Core.SignedIntTy.bits])) rfl) .nil

example :
    (@check context path surfaceArguments coreArguments
      [.scalar (.signed .i32)] (argumentLowering context)).isSome = true := by
  decide

def floatingReturnContext : Context :=
  { context with
    functions := [{ scheme with returnType := .scalar .f32 }]
    functionInstances := [{ calleeInstance with returnType := .scalar .f32 }] }

example :
    (@check floatingReturnContext path surfaceArguments coreArguments
      [.scalar (.signed .i32)] (argumentLowering floatingReturnContext)).isSome = false := by
  decide

def genericContext : Context :=
  { context with
    functions := [{ scheme with genericParameters := [.typeParameter 0] }]
    functionInstances := [{ calleeInstance with
      typeArguments := [.scalar (.signed .i32)] }] }

example :
    (@check genericContext path surfaceArguments coreArguments
      [.scalar (.signed .i32)] (argumentLowering genericContext)).isSome = false := by
  decide

def incoherentContext : Context :=
  { context with
    functionInstances := [calleeInstance, { calleeInstance with function := 8 }] }

example :
    (@check incoherentContext path surfaceArguments coreArguments
      [.scalar (.signed .i32)] (argumentLowering incoherentContext)).isSome = false := by
  decide

end Lanius.Compiler.DirectCallCheckTests
