import Lanius.Compiler.NameResolutionCheck
import Lanius.Compiler.FunctionInstanceCheck

namespace Lanius.Compiler.DirectCallCheck

open Lanius
open Lanius.SurfaceElaboration
open Lanius.Compiler

/- The call checker is deliberately a boundary adapter.  Name resolution and
   instance selection remain the existing executable checkers; this module
   only composes their witnesses with argument lowering evidence. -/

def supportedScalar (type : Core.ScalarTy) : Bool :=
  match type with
  | .bool | .signed .i32 => true
  | _ => false

def supportedGround (type : Static.GroundTy) : Bool :=
  match type with
  | .scalar scalar => supportedScalar scalar
  | _ => false

def supportedGrounds : List Static.GroundTy → Bool
  | [] => true
  | type :: tail => supportedGround type && supportedGrounds tail

def pathNotShadowed? (context : Context) (path : Surface.Path) : Bool :=
  match unqualifiedPathName? path with
  | none => true
  | some name =>
      !(context.locals.any fun binding => decide (binding.name = name))

theorem pathNotShadowed_sound
    (accepted : pathNotShadowed? context path = true) :
    GlobalPathNotShadowed context path := by
  unfold pathNotShadowed? at accepted
  cases found : unqualifiedPathName? path with
  | none => simp [GlobalPathNotShadowed, found]
  | some name =>
      simp only [found] at accepted
      unfold GlobalPathNotShadowed
      simp only [found]
      intro binding member equal
      have any : context.locals.any (fun binding => decide (binding.name = name)) = true := by
        apply List.any_eq_true.mpr
        exact ⟨binding, member, by simp [equal]⟩
      simp [any] at accepted

theorem exprsLower_checks
    (context : Context) (surface : List Surface.Expr)
    (types : List Static.GroundTy) (candidate : List Core.Expr)
    (lowered : ExprsLower context surface types candidate) :
    ExprsCheck context surface types candidate := by
  let rec go {surface : List Surface.Expr} {types : List Static.GroundTy}
      {candidate : List Core.Expr}
      (lowered : ExprsLower context surface types candidate) :
      ExprsCheck context surface types candidate :=
    match lowered with
    | .nil => .nil
    | .cons head tail => .cons (.exact head) (go tail)
  exact go lowered

structure Checked (context : Context) (path : Surface.Path)
    (surfaceArguments : List Surface.Expr) (coreArguments : List Core.Expr)
    (argumentTypes : List Static.GroundTy) where
  candidate : FunctionInstanceCheck.Candidate context path argumentTypes
  global : NameResolutionCheck.GlobalChecked context .value path
  arguments : ExprsCheck context surfaceArguments argumentTypes coreArguments
  notIntrinsic : builtinIntrinsic? path = none
  resolved : ResolvesDirectCall context path argumentTypes
    candidate.scheme candidate.resolved

def check {context : Context} {path : Surface.Path}
    {surfaceArguments : List Surface.Expr} {coreArguments : List Core.Expr}
    {argumentTypes : List Static.GroundTy}
    (lowered : ExprsLower context surfaceArguments argumentTypes coreArguments) :
    Option (Checked context path surfaceArguments coreArguments argumentTypes) :=
  if _argumentsSupported : supportedGrounds argumentTypes = true then
    match _global : NameResolutionCheck.checkGlobal context .value path with
    | none => none
    | some resolvedName =>
        match _selected : FunctionInstanceCheck.checkedForDeclaration context path
            argumentTypes resolvedName.symbol.declaration with
        | none => none
        | some candidate =>
            if _returnSupported : supportedGround candidate.candidate.resolved.returnType = true then
              if shadowed : pathNotShadowed? context path = true then
                if declaration : candidate.candidate.scheme.declaration =
                    resolvedName.symbol.declaration then
                  match intrinsic : builtinIntrinsic? path with
                  | some _ => none
                  | none =>
                      some {
                        candidate := candidate.candidate
                        global := resolvedName
                        arguments := exprsLower_checks context surfaceArguments
                          argumentTypes coreArguments lowered
                        notIntrinsic := intrinsic
                        resolved := candidate.resolvesDirectCallOfGlobal
                          (pathNotShadowed_sound shadowed)
                          resolvedName.symbol resolvedName.resolved declaration }
                else none
              else none
            else none
  else none

end Lanius.Compiler.DirectCallCheck
