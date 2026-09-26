import Lanius.Compiler.ContextSynthesis

namespace Lanius.Compiler.ContextSynthesisTests

open Lanius
open Lanius.Declarations
open Lanius.Compiler.ContextSynthesis

def pack : SourcePack := { files := [] }
def catalog : Catalog := { headers := [] }
def program : Core.Program := { target := .x86_64 }

def context : SurfaceElaboration.Context :=
  synthesize pack catalog [] program [] []

example : context.names = Declarations.nameEnvironment pack catalog [] := by
  rfl

example : context.target = .x86_64 := by
  rfl

example : context.functions = [] ∧ context.functionInstances = [] := by
  exact ⟨rfl, rfl⟩

example : context.constants = [] ∧ context.fields = [] := by
  exact ⟨rfl, rfl⟩

example : context.nominalSchemes = [] ∧ context.nominalInstances = [] := by
  exact ⟨rfl, rfl⟩

example : context.typeAliases = [] ∧ context.structures = [] := by
  exact ⟨rfl, rfl⟩

example :
    groundOfCore (.array (.reference (.scalar (.signed .i32))) 4) =
      .array (.reference (.scalar (.signed .i32))) 4 := by
  rfl

example :
    (monomorphization program).resolveNominal 3 [] [] = none := by
  rfl

example :
    (monomorphization program).resolveNominal 3 [.scalar .bool] [] = none := by
  rfl

def nominalProgram : Core.Program := {
  structures := [{ id := 3, fields := [] }]
  enumerations := [{ id := 4, variants := [[]] }] }

example :
    (monomorphization nominalProgram).resolveNominal 3 [] [] =
      some (.structure 3) := by
  rfl

example :
    (monomorphization nominalProgram).resolveNominal 4 [] [] =
      some (.enumeration 4) := by
  rfl

def function : Core.Function := {
  id := 7
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.opaque 0) }

example :
    Static.FunctionInstantiates []
      { declaration := 4
        genericParameters := []
        parameterTypes := [.scalar (.signed .i32)]
        returnType := .scalar (.signed .i32)
        requirements := [] }
      {}
      { declaration := 4
        function := 7
        typeArguments := []
        constArguments := []
        parameterTypes := [.scalar (.signed .i32)]
        returnType := .scalar (.signed .i32) } := by
  simpa [function, groundOfCore, groundsOfCore, Static.GroundTy.toTy] using
    function_row_instantiates function 4

end Lanius.Compiler.ContextSynthesisTests
