import Lanius.Compiler.ConstantCheck

namespace Lanius.Compiler.ConstantCheckTests


open Lanius
open Lanius.Compiler
open Lanius.Compiler.ConstantCheck

def context : SurfaceElaboration.Context := {
  target := .x86_64
  names := {}
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  locals := [] }

example :
    (checkLiteralExpr { target := .x86_64 }
      context (.literal (.boolean true)) (.boolean true) (.scalar .bool) rfl).isSome = true := by
  rfl

example :
    (checkLiteralExpr { target := .x86_64 }
      context (.literal (.integer "7"))
      (.signed .i32 (Int.ofNat 7)) (.scalar (.signed .i32)) rfl).isSome = true := by
  rfl

example :
    (checkLiteralExpr { target := .x86_64 }
      context (.literal (.boolean true)) (.boolean false) (.scalar .bool) rfl).isSome = false := by
  rfl

example :
    (checkLiteralExpr { target := .x86_64 }
      context (.literal (.integer "7"))
      (.signed .i32 (Int.ofNat 8)) (.scalar (.signed .i32)) rfl).isSome = false := by
  rfl

example :
    (checkTypeGrounds context (.path [.mk "i32" []]) (.scalar (.signed .i32))).isSome = true := by
  rfl

example :
    (checkTypeGrounds context (.path [.mk "bool" []]) (.scalar (.signed .i32))).isSome = false := by
  rfl

example :
    (checkTypeGrounds context (.path [.mk "usize" []])
      (.scalar (.unsigned .usize))).isSome = true := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context (.path [.mk "ptr" []])
      (.scalar .rawPtr)).isSome = true := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context (.path [.mk "str" []])
      (.scalar .string)).isSome = true := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context (.slice (.path [.mk "i32" []]))
      (.slice (.scalar (.signed .i32)))).isSome = true := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context (.reference (.path [.mk "bool" []]))
      (.reference (.scalar .bool))).isSome = true := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context
      (.array (.path [.mk "usize" []]) (.literal 3))
      (.array (.scalar (.unsigned .usize)) 3)).isSome = true := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context (.slice (.path [.mk "i32" []]))
      (.reference (.scalar (.signed .i32)))).isSome = false := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context
      (.array (.path [.mk "i32" []]) (.literal 3))
      (.array (.scalar (.signed .i32)) 4)).isSome = false := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.check context
      (.path [.mk "Thing" []]) (.structure 7)).isSome = false := by
  rfl

end Lanius.Compiler.ConstantCheckTests
