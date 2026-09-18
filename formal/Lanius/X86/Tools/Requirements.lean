import Lanius.X86.Transport.Core
import Lanius.Core.Dependencies.Closure
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! Planning evidence from the authenticated input program, not another
extractor or a compiler pass. Reports implementation needs, not proof coverage.
Every Core constructor is visited, including assignment places and call args. -/
namespace Lanius.X86.Tools.Requirements

open Lanius.Core Lanius.Extraction Lanius.Extraction.CoreSynthesis.Program

def typeNeeds : Ty → List String
  | .scalar (.signed .i32) | .scalar .bool => []
  | .unit => ["unit values/returns"]
  | .scalar .rawPtr => ["raw pointers"]
  | .scalar .string => ["strings"]
  | .scalar (.unsigned .usize) => ["usize"]
  | .scalar type => [s!"scalar {reprStr type}"]
  | .slice type => "slices" :: typeNeeds type
  | .array type _ => "arrays" :: typeNeeds type
  | .reference type => "references" :: typeNeeds type
  | .structure _ => ["structs"]
  | .enumeration _ => ["enums"]

def valueNeeds : Value → List String
  | .signed .i32 _ | .boolean _ => []
  | .unit => ["unit values/returns"]
  | .signed type _ => typeNeeds (.scalar (.signed type))
  | .unsigned type _ => typeNeeds (.scalar (.unsigned type))
  | .f32Bits _ => ["scalar float32"]
  | .f64Bits _ => ["scalar float64"]
  | .character _ => ["scalar char"]
  | .string _ => ["strings"]
  | .pointer _ => ["raw pointers"]
  | .array _ => ["array values"]
  | .slice _ _ _ _ _ => ["slice values"]
  | .structure _ _ => ["struct values"]
  | .enumeration _ _ _ => ["enum values"]
  | .reference _ _ _ => ["reference values"]

mutual
  def expression : Expr → List String
    | .value value => valueNeeds value
    | .local _ => []
    | .constant _ => ["constant references"]
    | .unary _ value => expression value
    | .binary _ left right => expression left ++ expression right
    | .cast type value => "casts" :: typeNeeds (.scalar type) ++ expression value
    | .array type values => "arrays" :: typeNeeds type ++ expressions values
    | .arrayToSlice type value => "array-to-slice" :: typeNeeds type ++ expression value
    | .index base index => "indexed reads" :: expression base ++ expression index
    | .structValue _ values => "structs" :: expressions values
    | .field value _ => "fields" :: expression value
    | .enumValue _ _ values => "enums" :: expressions values
    | .matchValue value branches => "matches" :: expression value ++ arms branches
    | .assign _ target value => place target ++ expression value
    | .borrow type target => "references" :: typeNeeds type ++ place target
    | .dereference value => "references" :: expression value
    | .call _ values => "calls" :: expressions values
    | .intrinsic operation value => s!"intrinsic {reprStr operation}" :: expression value
    | .i32ArrayDataPtr value => "array data pointers" :: expression value
    | .i32SliceFromRawParts pointer length => "raw-parts slices" :: expression pointer ++ expression length
    | .i32SliceDataPtr value => "slice data pointers" :: expression value
    | .stringDataPtr value => "string data pointers" :: expression value
    | .alloc size alignment => "allocation" :: expression size ++ expression alignment
    | .realloc pointer oldSize newSize alignment =>
        "reallocation" :: expression pointer ++ expression oldSize ++ expression newSize ++ expression alignment
    | .dealloc pointer size alignment => "deallocation" :: expression pointer ++ expression size ++ expression alignment
    | .loadByte pointer offset => "byte loads" :: expression pointer ++ expression offset
    | .storeByte pointer offset value => "byte stores" :: expression pointer ++ expression offset ++ expression value
  def expressions : List Expr → List String
    | [] => []
    | first :: rest => expression first ++ expressions rest
  def place : Place → List String
    | .local _ => []
    | .field base _ => "field stores" :: place base
    | .index base index => "indexed stores" :: place base ++ expression index
  def arms : List (Pattern × Expr) → List String
    | [] => []
    | (_, value) :: rest => expression value ++ arms rest
end

def optional : Option Expr → List String
  | none => []
  | some value => expression value

def statement : Stmt → List String
  | .skip | .breakLoop | .continueLoop => []
  | .expression value => expression value
  | .sequence first second => statement first ++ statement second
  | .letLocal _ type value body => typeNeeds type ++ expression value ++ statement body
  | .letUninitialized _ type body => "uninitialized locals" :: typeNeeds type ++ statement body
  | .ifThenElse condition yes no => expression condition ++ statement yes ++ statement no
  | .whileLoop condition body => expression condition ++ statement body
  | .forValues _ values body => "for-values" :: expression values ++ statement body
  | .forRange _ start stop _ body => "for-range" :: expression start ++ optional stop ++ statement body
  | .returnValue none => ["unit values/returns"]
  | .returnValue (some value) => expression value

def functionNeeds (function : Function) : List String :=
  (typeNeeds function.returnType ++ function.parameters.flatMap (fun (_, type) => typeNeeds type) ++
    (match function.body with | none => [] | some body => statement body) ++
    (if function.external.isSome then ["external runtime"] else [])).eraseDups

-- Visitors must not lose dependencies in assignment indexes or nested args.
example : expression (.assign .set (.index (.local 0) (.call 7 [.constant 2])) (.local 1)) =
    ["indexed stores", "calls", "constant references"] := by decide
example : let needed := statement (.letLocal 0 (.slice (.scalar (.signed .i32)))
    (.i32SliceFromRawParts (.value (.pointer 0)) (.value (.unsigned .usize 4))) (.returnValue none))
    needed.contains "slices" && needed.contains "raw-parts slices" && needed.contains "unit values/returns" = true := by decide

def main (arguments : List String) : IO UInt32 := do
  let modulePath :: paths := arguments | throw (IO.userError "expected extracted module and exact ordered source paths")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid extracted source pack framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : SourceFile)
  let .success checked := checkCompactCoreSourcePack encoded sources
    | throw (IO.userError "exact input sources failed authentication")
  let some entry := checkSourceFunction? checked.program ["app", "main"] "main"
    | throw (IO.userError "no authenticated app::main::main")
  let program := checked.program.core
  let reachable := Dependencies.closure program [entry.function.id]
  unless reachable.contains entry.function.id && Dependencies.closed program reachable.contains do
    throw (IO.userError "discovered call graph is not closed")
  let functions := program.functions.filter fun function => reachable.contains function.id
  let internal := functions.filter fun function => function.external.isNone
  let accepted := internal.filter fun function => (Transport.function? program function).isSome
  IO.println s!"Exact sources: {sources.length}; Core functions: {program.functions.length}; reachable: {functions.length}; internal: {internal.length}; external runtime: {functions.length - internal.length}"
  IO.println s!"Current Core function transport accepts {accepted.length}/{internal.length} reachable internal functions (not a compilation or machine-correctness claim)."
  IO.println s!"Maximum reachable Core parameter count: {(functions.map (fun function => function.parameters.length)).foldl max 0}"
  let reports := internal.map fun function => (function.id, functionNeeds function)
  let needs := ((reports.flatMap Prod.snd).eraseDups).mergeSort (· ≤ ·)
  for need in needs do
    let affected := reports.filter fun (_, required) => required.contains need
    IO.println s!"{need}: {affected.length} reachable internal functions"
  IO.println s!"Declared structs: {program.structures.length}"
  for declaration in program.structures do
    IO.println s!"  struct {declaration.id}: {declaration.fields.length} fields; all i32 = {declaration.fields.all (· == .scalar (.signed .i32))}"
  IO.println "Remaining function-transport blockers:"
  for allocation in checked.program.prepared.allocations do
    let sourceFunctions := ArtifactContextChecker.collectFunctions allocation.unit.surface.items
    for (index, function) in sourceFunctions.zipIdx |>.map Prod.swap do
      let id := allocation.functionIdStart + index
      if reachable.contains id && !(accepted.any (fun compiled => compiled.id == id)) then
        let needs := (reports.find? fun report => report.1 == id).map Prod.snd |>.getD []
        IO.println s!"  {String.intercalate "::" allocation.unit.modulePath}::{function.name}: {String.intercalate ", " needs}"
  for function in functions do
    if let some external := function.external then
      IO.println s!"Runtime function {function.id}: {reprStr external}"
  pure 0

end Lanius.X86.Tools.Requirements

def main := Lanius.X86.Tools.Requirements.main
