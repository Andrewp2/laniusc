import Lanius.Compiler.NamedTypeCheck
import Lanius.Compiler.TypeLoweringCheck

namespace Lanius.Compiler.NamedTypeCheckTests

open Lanius
open Lanius.Compiler.NamedTypeCheck

def path : Surface.Path := { segments := [.mk "Point" []] }

def symbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Point"
  visibility := .exported
  declaration := 7 }

def names : Names.Environment := { symbols := [symbol] }

def scheme : Static.NominalScheme := {
  declaration := 7
  type := 3
  kind := .structure }

def resolvedInstance : Static.NominalInstance := {
  declaration := 7
  sourceType := 3
  kind := .structure
  coreType := 11 }

def context : SurfaceElaboration.Context := {
  names := names
  currentModule := 0
  monomorphization := {
    resolveNominal := fun source types constants =>
      match source, types, constants with
      | 3, [], [] => some (.structure 11)
      | _, _, _ => none }
  nominalSchemes := [scheme]
  nominalInstances := [resolvedInstance] }

def globalResolved : SurfaceElaboration.ResolvesGlobal context .type path symbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .type "Point")
  · rfl
  · constructor
    · exact .local (by simp [context, names, symbol]) rfl rfl rfl
    · intro candidate selected
      cases selected with
      | «local» member sameModule sameNamespace sameName =>
          have equal : candidate = symbol := by
            simpa [context, names] using member
          subst candidate
          simp [symbol]
      | importedUnqualified module foundModule imported noLocal member
          symbolModule isPublic sameNamespace sameName =>
          simp [context, names] at foundModule

def notShadowed : SurfaceElaboration.GlobalTypePathNotShadowed context path := by
  intro name binding _ resolved
  cases resolved

def instantiated : SurfaceElaboration.NominalConstructorInstantiates context
    scheme.declaration scheme.type scheme.kind scheme.genericParameters
    scheme.requirements context.substitution resolvedInstance := by
  refine ⟨by simp [context, resolvedInstance], rfl, rfl, rfl, .nil, .nil, ?_⟩
  intro candidate member _ _ _
  have equal : candidate = resolvedInstance := by simpa [context] using member
  simpa [equal]

def candidate : Candidate context path := {
  symbol := symbol
  scheme := scheme
  resolvedInstance := resolvedInstance
  notBuiltin := by rfl
  notShadowed := notShadowed
  resolved := globalResolved
  schemeMember := by simp [context, scheme]
  declaration := rfl
  surfaceArguments := []
  argumentsFound := by rfl
  arguments := .nil
  instantiated := instantiated
  mapped := by rfl }

example : (check context path (.structure 11) candidate).isSome = true := by
  rfl

example :
    (Lanius.Compiler.TypeLoweringCheck.checkNamed context path
      (.structure 11) candidate).isSome = true := by
  rfl

example : (check context path (.enumeration 11) candidate).isSome = false := by
  rfl

example :
    instance_coreTy_unique resolvedInstance resolvedInstance instantiated instantiated = rfl := by
  rfl

end Lanius.Compiler.NamedTypeCheckTests
