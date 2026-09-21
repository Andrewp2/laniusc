import Lanius.Compiler.ConstantCheck

namespace Lanius.Compiler.SignatureCheck


open Lanius
open Lanius.Compiler.ProgramLowering

/-! Successful results are the existing `ProgramLowering` witnesses; this
    file deliberately does not introduce a second lowering relation. -/

inductive Failure where
  | parameterMismatch
  | parameterUnsupported
  | returnMismatch
  | returnUnsupported
deriving DecidableEq, Repr

structure CheckedSignature
    (context : SurfaceElaboration.Context)
    (surfaceParameters : List Surface.Parameter)
    (surfaceReturn : Option Surface.TypeExpr)
    (coreParameters : List (VarId × Core.Ty))
    (coreReturn : Core.Ty) where
  parameters : Typing.Check.ProofOf
    (NamedParametersLower context surfaceParameters context.locals coreParameters)
  returnType : Typing.Check.ProofOf (ReturnTypeLower context surfaceReturn coreReturn)

def checkNamedParameters (context : SurfaceElaboration.Context) :
    (surface : List Surface.Parameter) →
    (bindings : List SurfaceElaboration.LocalBinding) →
    (core : List (VarId × Core.Ty)) →
    Option (Typing.Check.ProofOf (NamedParametersLower context surface bindings core))
  | [], [], [] => some ⟨.nil⟩
  | .named name surfaceType :: surfaceTail, binding :: bindingTail,
      (id, coreType) :: coreTail =>
      match TypeLoweringCheck.check context surfaceType coreType with
      | none => none
      | some typed =>
          if idMatches : id = binding.id then
            if nameMatches : binding.name = name then
              if typeMatches : binding.type = typed.groundType then
                match checkNamedParameters context surfaceTail bindingTail coreTail with
                | none => none
                | some tail =>
                    have result : Typing.Check.ProofOf
                        (NamedParametersLower context
                          (.named name surfaceType :: surfaceTail)
                          (binding :: bindingTail)
                          ((binding.id, coreType) :: coreTail)) :=
                      ⟨.named name surfaceType typed.groundType coreType binding
                        typed.typed.down typed.grounded nameMatches typeMatches tail.down⟩
                    some (by simpa [idMatches] using result)
              else none
            else none
          else none
  | _, _, _ => none

def checkReturnType (context : SurfaceElaboration.Context) :
    (surface : Option Surface.TypeExpr) → (core : Core.Ty) →
    Option (Typing.Check.ProofOf (ReturnTypeLower context surface core))
  | none, .unit => some ⟨.none⟩
  | some surfaceType, coreType =>
      match TypeLoweringCheck.check context surfaceType coreType with
      | none => none
      | some typed =>
          some ⟨.some surfaceType typed.groundType coreType
            typed.typed.down typed.grounded⟩
  | _, _ => none

def check
    (context : SurfaceElaboration.Context)
    (surfaceParameters : List Surface.Parameter)
    (surfaceReturn : Option Surface.TypeExpr)
    (coreParameters : List (VarId × Core.Ty))
    (coreReturn : Core.Ty) :
    Except Failure
      (CheckedSignature context surfaceParameters surfaceReturn coreParameters coreReturn) :=
  match checkNamedParameters context surfaceParameters context.locals coreParameters with
  | none => .error .parameterMismatch
  | some parameters =>
      match checkReturnType context surfaceReturn coreReturn with
      | none => .error .returnMismatch
      | some returnType => .ok { parameters, returnType }

def checkFunction (context : SurfaceElaboration.Context)
    (declaration : Surface.Function) (core : Core.Function) :=
  check context declaration.parameters declaration.returnType core.parameters core.returnType

def checkExternFunction (context : SurfaceElaboration.Context)
    (declaration : Surface.ExternFunction) (core : Core.Function) :=
  check context declaration.parameters declaration.returnType core.parameters core.returnType

end Lanius.Compiler.SignatureCheck
