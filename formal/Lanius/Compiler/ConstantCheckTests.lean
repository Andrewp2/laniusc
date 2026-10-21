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

private def accepts (literal : Surface.Literal) (value : Core.Value)
    (type : Core.Ty) : Bool :=
  (checkLiteralExpr { target := .x86_64 } context (.literal literal) value type rfl).isSome

-- Type-directed checking preserves strings exactly and uses the declared
-- integer domain. No native computation or per-input axiom is involved.
example (value : String) : accepts (.string value) (.string value) (.scalar .string) = true := by
  simp [accepts, checkLiteralExpr]

example : accepts (.string "Aé\x00") (.string "Aé") (.scalar .string) = false := by decide
example : accepts (.string "") (.string "") (.scalar .string) = true := by decide
example : accepts (.integer "0") (.unsigned .usize 0) (.scalar (.unsigned .usize)) = true := by decide
example : accepts (.integer "18446744073709551615") (.unsigned .usize (2^64 - 1))
    (.scalar (.unsigned .usize)) = true := by decide
example : accepts (.integer "18446744073709551616") (.unsigned .usize (2^64))
    (.scalar (.unsigned .usize)) = false := by decide
example : accepts (.integer "19") (.unsigned .usize 20) (.scalar (.unsigned .usize)) = false := by decide
example : accepts (.integer "19") (.unsigned .usize 19) (.scalar (.signed .i32)) = false := by decide
example : accepts (.integer "0") (.pointer 0) (.scalar .rawPtr) = true := by decide
example : accepts (.integer "1") (.pointer 0) (.scalar .rawPtr) = false := by decide
example : accepts (.integer "0") (.pointer 1) (.scalar .rawPtr) = false := by decide
example : accepts (.integer "oops") (.pointer 0) (.scalar .rawPtr) = false := by decide
example : accepts (.integer "0") (.boolean false) (.scalar .bool) = false := by decide
example : accepts (.integer "2147483647") (.signed .i32 2147483647)
    (.scalar (.signed .i32)) = true := by decide
example : accepts (.integer "2147483648") (.signed .i32 2147483648)
    (.scalar (.signed .i32)) = false := by decide

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
    (TypeLoweringCheck.checkGround context (.path [.mk "i32" []]) (.scalar (.signed .i32))).isSome = true := by
  rfl

example :
    (TypeLoweringCheck.checkGround context (.path [.mk "bool" []]) (.scalar (.signed .i32))).isSome = false := by
  rfl

example :
    (TypeLoweringCheck.checkGround context (.path [.mk "usize" []])
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

private def integer (value : String) : Surface.Expr := .literal (.integer value)
private def negative (value : String) : Surface.Expr := .unary .negative (integer value)
private def folds (source : Surface.Expr) (value : Int) : Bool :=
  (checkInitializer { target := .x86_64 } [] context source (.signed .i32 value)
    (.scalar (.signed .i32)) rfl).isSome

-- Values agree with Core's wrapping arithmetic and truncation toward zero.
example : folds (negative "7") (-7) = true := by decide
example : folds (negative "2147483648") (-2147483648) = true := by decide
example : folds (.unary .negative (negative "2147483648")) (-2147483648) = true := by decide
example : folds (.unary .positive (integer "7")) 7 = true := by decide
example : folds (.binary .add (integer "2147483647") (integer "1")) (-2147483648) = true := by decide
example : folds (.binary .multiply (integer "65536") (integer "65536")) 0 = true := by decide
example : folds (.binary .divide (negative "7") (integer "3")) (-2) = true := by decide
example : folds (.binary .remainder (negative "7") (integer "3")) (-1) = true := by decide
example : folds (.binary .subtract
    (.binary .divide (integer "84") (integer "2")) (integer "35")) 7 = true := by decide

-- A well-typed but changed result is not sufficient. Traps and circular
-- constant-table references cannot furnish evaluation evidence either.
example : folds (negative "7") 7 = false := by decide
example : folds (integer "2147483648") (-2147483648) = false := by decide
example : folds (negative "2147483649") 2147483647 = false := by decide
example : folds (.binary .divide (integer "7") (integer "0")) 0 = false := by decide
example : folds (.binary .divide (negative "2147483648") (negative "1")) (-2147483648) = false := by decide
example : folds (.binary .remainder (negative "2147483648") (negative "1")) 0 = false := by decide
example : folds (.path { segments := [.mk "SELF" []] }) 7 = false := by decide
example : (checkInitializer { target := .x86_64 } [] context (negative "7")
    (.unsigned .usize 7) (.scalar (.unsigned .usize)) rfl).isSome = false := by decide

-- Accepted evidence connects to actual execution, for arbitrary caller state.
example (checked : CheckedInitializer program available context source value type)
    (state : Semantics.State) :
    Semantics.Evaluates program state checked.expression value state :=
  checked.evaluates.evaluates state

end Lanius.Compiler.ConstantCheckTests
