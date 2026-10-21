import Lanius.Typing
import Lanius.Data.List

namespace Lanius.TypedIR.Intrinsic

open Lanius Core Typing

/-- A callable identity contains no body. Recursive functions therefore do
    not make the type of their own syntax depend on that syntax. -/
structure FunctionType where
  id : FunctionId
  parameters : List Core.Ty
  result : Core.Ty
deriving DecidableEq, Repr

def FunctionType.ofCore (function : Core.Function) : FunctionType :=
  ⟨function.id, function.parameters.map Prod.snd, function.returnType⟩

structure Signature where
  target : Target := .x86_64
  structures : List StructDecl := []
  enumerations : List EnumDecl := []
  constants : List Core.Constant := []
  functions : List FunctionType := []

def Signature.declarations (signature : Signature) : Core.Program :=
  { target := signature.target, structures := signature.structures,
    enumerations := signature.enumerations, constants := signature.constants }

def Signature.function? (signature : Signature) (id : FunctionId) : Option FunctionType :=
  signature.functions.find? (fun function => function.id == id)

/-- Linking must establish exact signature agreement, including first-match
    lookup behavior. It cannot substitute a same-named, differently typed body. -/
structure Signature.Realizes (signature : Signature) (program : Core.Program) : Prop where
  target : program.target = signature.target
  structures : program.structures = signature.structures
  enumerations : program.enumerations = signature.enumerations
  constants : program.constants = signature.constants
  functions : program.functions.map FunctionType.ofCore = signature.functions

theorem Signature.Realizes.function {signature : Signature} {program : Core.Program}
    {id : FunctionId} {header : FunctionType}
    (linked : signature.Realizes program)
    (found : signature.function? id = some header) :
    ∃ function, program.function? id = some function ∧ FunctionType.ofCore function = header := by
  have mapped : (program.function? id).map FunctionType.ofCore = some header := by
    simpa only [Signature.function?, ← linked.functions, List.find?_map,
      Core.Program.function?, Function.comp_def, FunctionType.ofCore] using found
  cases selected : program.function? id with
  | none => simp [selected] at mapped
  | some function => exact ⟨function, rfl, by simpa [selected] using mapped⟩

theorem Signature.Realizes.structure {signature : Signature} {program : Core.Program}
    {id : TypeId} {declaration : StructDecl}
    (linked : signature.Realizes program)
    (found : signature.declarations.structure? id = some declaration) :
    program.structure? id = some declaration := by
  simpa only [Core.Program.structure?, linked.structures, Signature.declarations] using found

theorem Signature.Realizes.enumeration {signature : Signature} {program : Core.Program}
    {id : TypeId} {declaration : EnumDecl}
    (linked : signature.Realizes program)
    (found : signature.declarations.enumeration? id = some declaration) :
    program.enumeration? id = some declaration := by
  simpa only [Core.Program.enumeration?, linked.enumerations, Signature.declarations] using found

theorem Signature.Realizes.constant {signature : Signature} {program : Core.Program}
    {id : ConstantId} {declaration : Core.Constant}
    (linked : signature.Realizes program)
    (found : signature.declarations.constant? id = some declaration) :
    program.constant? id = some declaration := by
  simpa only [Core.Program.constant?, linked.constants, Signature.declarations] using found

theorem Signature.Realizes.nominal {signature : Signature} {program : Core.Program}
    (linked : signature.Realizes program)
    (element : RawNominalSliceElement signature.declarations type) :
    RawNominalSliceElement program type := by
  cases element with
  | structureType id declaration found => exact .structureType id declaration (linked.structure found)
  | enumerationType id declaration found => exact .enumerationType id declaration (linked.enumeration found)

theorem Signature.Realizes.sliceElement {signature : Signature} {program : Core.Program}
    (linked : signature.Realizes program)
    (element : RawSliceElement signature.declarations type) : RawSliceElement program type := by
  cases element with
  | i32 => exact .i32
  | nominal element => exact .nominal (linked.nominal element)

mutual
  theorem Signature.Realizes.value {signature : Signature} {program : Core.Program}
      {value : Core.Value} {type : Core.Ty}
      (linked : signature.Realizes program)
      (typed : ValueHasType signature.declarations value type) : ValueHasType program value type :=
    match typed with
    | .unit => .unit
    | .boolean value => .boolean value
    | .signed type value lower upper => .signed type value
        (by simpa only [signedMin, linked.target, Signature.declarations] using lower)
        (by simpa only [signedMax, linked.target, Signature.declarations] using upper)
    | .unsigned type value upper => .unsigned type value
        (by simpa only [unsignedMax, linked.target, Signature.declarations] using upper)
    | .f32Bits bits => .f32Bits bits
    | .f64Bits bits => .f64Bits bits
    | .character value => .character value
    | .string value => .string value
    | .pointer address => .pointer address
    | .array values element length elements => .array values element length (linked.values elements)
    | .slice type cell projections start length => .slice type cell projections start length
    | .rawSlice element address length => .rawSlice (linked.sliceElement element) address length
    | .structure declaration found fields => .structure declaration (linked.structure found) (linked.values fields)
    | .enumeration declaration found variant payload =>
        .enumeration declaration (linked.enumeration found) variant (linked.values payload)
    | .reference referent cell projections => .reference referent cell projections

  theorem Signature.Realizes.values {signature : Signature} {program : Core.Program}
      {values : List Core.Value} {types : List Core.Ty}
      (linked : signature.Realizes program)
      (typed : ValuesHaveTypes signature.declarations values types) : ValuesHaveTypes program values types :=
    match typed with
    | .nil => .nil
    | .cons head tail => .cons (linked.value head) (linked.values tail)
end

end Lanius.TypedIR.Intrinsic
