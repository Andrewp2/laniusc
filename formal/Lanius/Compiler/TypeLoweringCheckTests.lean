import Lanius.Compiler.TypeLoweringCheck

namespace Lanius.Compiler.TypeLoweringCheckTests

open Lanius
open Lanius.Compiler.TypeLoweringCheck

def scalarPath : Surface.Path := { segments := [.mk "Answer" []] }

def scalarSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Answer"
  visibility := .exported
  declaration := 7 }

def scalarAlias : SurfaceElaboration.TypeAliasEntry := {
  declaration := 7
  moduleId := 0
  target := .path [.mk "i32" []] }

def scalarContext : SurfaceElaboration.Context := {
  names := { symbols := [scalarSymbol] }
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  typeAliases := [scalarAlias] }

example :
    (check scalarContext (.path scalarPath.segments)
      (.scalar (.signed .i32))).isSome = true := by
  decide

def slicePath : Surface.Path := { segments := [.mk "Bytes" []] }

def sliceSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Bytes"
  visibility := .exported
  declaration := 9 }

def sliceAlias : SurfaceElaboration.TypeAliasEntry := {
  declaration := 9
  moduleId := 0
  target := .slice (.path [.mk "i32" []]) }

def sliceContext : SurfaceElaboration.Context := {
  names := { symbols := [sliceSymbol] }
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  typeAliases := [sliceAlias] }

example :
    (check sliceContext (.path slicePath.segments)
      (.slice (.scalar (.signed .i32)))).isSome = true := by
  decide

example :
    (check scalarContext (.path scalarPath.segments)
      (.scalar .bool)).isSome = false := by
  rfl

def missingContext : SurfaceElaboration.Context := {
  scalarContext with
  typeAliases := [] }

example :
    (check missingContext (.path scalarPath.segments)
      (.scalar (.signed .i32))).isSome = false := by
  rfl

def ambiguousContext : SurfaceElaboration.Context := {
  scalarContext with
  names := { symbols := [scalarSymbol, { scalarSymbol with declaration := 8 }] },
  symbolsAreUnique := none }

example :
    (check ambiguousContext (.path scalarPath.segments)
      (.scalar (.signed .i32))).isSome = false := by
  rfl

def genericAlias : SurfaceElaboration.TypeAliasEntry := {
  scalarAlias with
  parameters := [.typeParameter "T" 0]
  target := .path [.mk "T" []] }

def genericContext : SurfaceElaboration.Context := {
  scalarContext with
  typeAliases := [genericAlias] }

example :
    (check genericContext (.path scalarPath.segments)
      (.scalar (.signed .i32))).isSome = false := by
  rfl

def parameterContext : SurfaceElaboration.Context := {
  scalarContext with
  typeParameters := [{ name := "Answer", parameter := 0 }] }

example :
    (check parameterContext (.path scalarPath.segments)
      (.scalar (.signed .i32))).isSome = false := by
  rfl

def cycleAPath : Surface.Path := { segments := [.mk "A" []] }
def cycleBPath : Surface.Path := { segments := [.mk "B" []] }

def cycleA : SurfaceElaboration.TypeAliasEntry := {
  declaration := 11
  moduleId := 0
  target := .path cycleBPath.segments }

def cycleB : SurfaceElaboration.TypeAliasEntry := {
  declaration := 12
  moduleId := 0
  target := .path cycleAPath.segments }

def cycleContext : SurfaceElaboration.Context := {
  names := { symbols := [
    { moduleId := 0, lookupNamespace := .type, name := "A",
      visibility := .exported, declaration := 11 },
    { moduleId := 0, lookupNamespace := .type, name := "B",
      visibility := .exported, declaration := 12 }] }
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  typeAliases := [cycleA, cycleB] }

example :
    (check cycleContext (.path cycleAPath.segments)
      (.scalar (.signed .i32))).isSome = false := by
  rfl

def pointPath : Surface.Path := { segments := [.mk "Point" []] }

def pointSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Point"
  visibility := .exported
  declaration := 20 }

def pointScheme : Static.NominalScheme := {
  declaration := 20
  type := 3
  kind := .structure }

def pointInstance : Static.NominalInstance := {
  declaration := 20
  sourceType := 3
  kind := .structure
  coreType := 11 }

def pointContext : SurfaceElaboration.Context := {
  names := { symbols := [pointSymbol] }
  currentModule := 0
  monomorphization := {
    resolveNominal := fun source types constants =>
      match source, types, constants with
      | 3, [], [] => some (.structure 11)
      | _, _, _ => none }
  nominalSchemes := [pointScheme]
  nominalInstances := [pointInstance] }

example :
    (check pointContext (.path pointPath.segments) (.structure 11)).isSome = true := by
  decide

example :
    (check pointContext (.path pointPath.segments) (.structure 12)).isSome = false := by
  rfl

def pointAliasPath : Surface.Path := { segments := [.mk "PointAlias" []] }

def pointAliasSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "PointAlias"
  visibility := .exported
  declaration := 21 }

def pointAlias : SurfaceElaboration.TypeAliasEntry := {
  declaration := 21
  moduleId := 0
  target := .path pointPath.segments }

def pointAliasContext : SurfaceElaboration.Context := {
  pointContext with
  names := { symbols := [pointSymbol, pointAliasSymbol] }
  symbolsAreUnique := none
  typeAliases := [pointAlias] }

example :
    (check pointAliasContext (.path pointAliasPath.segments)
      (.structure 11)).isSome = true := by
  decide

def ambiguousPointContext : SurfaceElaboration.Context := {
  pointContext with
  nominalInstances := [pointInstance, { pointInstance with coreType := 12 }] }

example :
    (check ambiguousPointContext (.path pointPath.segments)
      (.structure 11)).isSome = false := by
  rfl

def ambiguousSchemeContext : SurfaceElaboration.Context := {
  pointContext with
  nominalSchemes := [pointScheme, { pointScheme with type := 4 }] }

example :
    (check ambiguousSchemeContext (.path pointPath.segments)
      (.structure 11)).isSome = false := by
  rfl

def genericPointContext : SurfaceElaboration.Context := {
  pointContext with
  nominalSchemes := [{ pointScheme with
    genericParameters := [.typeParameter 0] }] }

example :
    (check genericPointContext (.path pointPath.segments)
      (.structure 11)).isSome = false := by
  rfl

end Lanius.Compiler.TypeLoweringCheckTests
