import verified_compiler.tests.direct_surface_expression_tree

namespace SurfaceBooleanTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics Lanius.Extraction SurfaceBooleanProof IRTypeRefProof

-- A physical native View, not a proposed successful evaluator result. Its
-- first 53 slots hold zero-valued metadata; the last three hold the output.
private def viewBlock : Block := {
  base := 64, size := 448, alignment := 8
  bytes := List.replicate 424 0 ++ encodeNatLE 8 16 ++ encodeNatLE 8 8 ++ i32Bytes 32 ++ List.replicate 4 0 }
private def reference : Heap := { blocks := [viewBlock], nextAddress := 512 }
private def sample : State := { heap := { reference with blocks :=
  { base := 16, size := 32, alignment := 4, bytes := List.replicate 32 0 } :: reference.blocks } }
private def fields : List Value := match readRawSliceIndex extractedProgram sample viewType 504 1 0 with
  | .ok (.structure _ values) => values | _ => []
private def field (index : Nat) := fields[index]?.getD .unit

-- A connected kernel proof of the continuation boundary: the first real
-- writer's output effect supplies the second real writer's native View read,
-- readable buffer, and heap/cell environment. No second run is assumed.
theorem consecutiveWriters (context : Context state) (input : Protected context reference)
    (first second : Bool) (environment : WriterEnvironment state)
    (room : context.position + (bytes first ++ bytes second).length ≤ context.capacity) :
    ∃ after, RunsExprs extractedProgram state
      [context.call first, (context.atPosition (context.position + (bytes first).length)).call second]
      [.signed .i32 (context.position + (bytes first).length : Nat),
        .signed .i32 (context.position + (bytes first ++ bytes second).length : Nat)] after ∧
      WriterFrame state after (context.address + context.position) (bytes first ++ bytes second) := by
  have firstRoom : context.position + (bytes first).length ≤ context.capacity := by
    simp only [List.length_append] at room
    omega
  obtain ⟨ready, firstRun, firstFrame⟩ := actualCall context first firstRoom environment
  let next := context.afterOutput input firstFrame.output firstRoom
  have secondRoom : next.position + (bytes second).length ≤ next.capacity := by
    simpa only [next, Context.afterOutput, List.length_append, Nat.add_assoc] using room
  obtain ⟨after, secondRun, secondFrame⟩ := actualCall next second secondRoom (environment.afterWrite firstFrame)
  have appended := firstFrame.append (show WriterFrame ready after
    (context.address + context.position + (bytes first).length) (bytes second) from
    by simpa only [next, Context.afterOutput, Nat.add_assoc] using secondFrame)
  exact ⟨after, by simpa only [next, Context.afterOutput, Context.atPosition, Context.call, Context.views,
    List.length_append, Nat.add_assoc] using RunsExprs.cons firstRun (RunsExprs.cons secondRun RunsExprs.nil),
    appended⟩

#print axioms consecutiveWriters

-- A complete execution regression builds a real tree, stores that returned
-- tree in the native View, prints, and navigates the same tree afterwards.
#eval (do
  let cases : List (Value × Int × Reference × String × Bool × Nat) := [
    (booleanEvent true, 1, .Bool, "true", true, 0), (booleanEvent false, 0, .Bool, "false", true, 0),
    (SurfaceIntegerProof.integerEvent 0, 0, .I32, "0", true, 0),
    (SurfaceIntegerProof.integerEvent 7, 7, .I32, "7", true, 0),
    (SurfaceIntegerProof.integerEvent 2147483647, 2147483647, .I32, "2147483647", true, 0),
    (SurfaceIntegerProof.integerEvent (-2147483648), -2147483648, .I32, "-2147483648", true, 0),
    (SurfaceIntegerProof.integerEvent (-1), -1, .I32, "", false, 0),
    (booleanEvent true, 1, .I32, "", false, 0),
    (booleanEvent true, 1, .Bool, "(!(true))", true, 1),
    (booleanEvent false, 0, .Bool, "(!(false))", true, 1),
    (booleanEvent true, 1, .Bool, "(!((!(true))))", true, 2),
    (booleanEvent false, 0, .Bool, "(!((!(false))))", true, 2),
    (booleanEvent true, 1, .Bool, "(!((!((!((!((!(true))))))))))", true, 5),
    (booleanEvent false, 0, .Bool, "(!((!((!((!((!(false))))))))))", true, 5)]
  for (event, payload, kind, spelling, accepted, depth) in cases do
    let expected := World.utf8Bytes spelling
    let .enumeration eventId tag _ := event | throw (IO.userError "scalar event is not an enum")
    let .enumeration _ annotationTag _ := referenceValue kind | throw (IO.userError "annotation is not an enum")
    let leaf := encodeNatLE 4 tag ++ List.replicate 4 0 ++
      i32Bytes payload ++ List.replicate 28 0
    let .enumeration _ unaryTag _ := SurfaceUnaryProof.Unary.not.event
      | throw (IO.userError "unary event is not an enum")
    let count := depth + 1
    -- Native nominal-slice indexing moves down from element zero's high word.
    let storage := leaf ++ (List.replicate depth (encodeNatLE 4 unaryTag ++ List.replicate 36 0)).flatten
    let eventsAddress := 528 + count * 40 - 8
    let annotationsBase := 528 + count * 40 + 16
    let annotationsAddress := annotationsBase + count * 16 - 8
    let annotation := encodeNatLE 4 annotationTag ++ List.replicate 12 0
    let before : State := { sample with heap := { sample.heap with
      blocks := sample.heap.blocks ++ [
        { base := 528, size := count * 40, alignment := 8, bytes := storage },
        { base := annotationsBase, size := count * 16, alignment := 8,
          bytes := (List.replicate count annotation).flatten }]
      nextAddress := annotationsBase + count * 16 } }
    let referenceType := ((Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit)).2
    let region := source_value Extracted.«ir::body_events».Types.«Region».mk
      [.rawSlice (.enumeration eventId) eventsAddress count,
        .rawSlice referenceType annotationsAddress count, .boolean true, .signed .i32 count]
    let .done tree built := evalExpr 500 extractedProgram before
      (.call Extracted.«ir::body_tree».Functions.«build».core.id [.value region, .value (.signed .i32 count)])
      | throw (IO.userError "builder trapped before printing")
    let .structure _ [_, _, _, _, .signed .i32 builtCount] := tree
      | throw (IO.userError "builder rejected scalar tree")
    unless builtCount == (count : Int) do
      throw (IO.userError s!"builder returned {builtCount} instead of {count} for {spelling}")
    let view := viewValue tree (field 1) (field 2) (field 3) 0 0
      (.rawSlice (.scalar (.signed .i32)) 16 8) 32
    let .ok heap := writeNativeValue 64 extractedProgram built built.heap viewType 64 view
      | throw (IO.userError "native View construction failed")
    let printing := { built with heap := heap }
    let .done cursor printed := evalExpr 500 extractedProgram printing
      (.call Extracted.«verified::lean_typed_body».Functions.«surface_expression_output».core.id
        [.value (.rawSlice viewType 504 1), .value (.signed .i32 0), .value (.signed .i32 2)])
      | throw (IO.userError "actual IR expression printing trapped")
    if accepted then
      unless cursor == .signed .i32 (2 + expected.length : Nat) do throw (IO.userError "wrong print cursor")
      let .ok output := printed.heap.loadBytes 18 expected.length | throw (IO.userError "output became unreadable")
      unless output == expected do throw (IO.userError "wrong scalar spelling")
    else
      unless cursor == .signed .i32 (-1) do throw (IO.userError "unsupported scalar was not rejected")
      let .ok output := printed.heap.loadBytes 16 32 | throw (IO.userError "rejection lost output storage")
      unless output == List.replicate 32 0 do throw (IO.userError "rejected scalar wrote output")
      unless printed.heap.nextAddress == printing.heap.nextAddress do throw (IO.userError "rejected scalar borrowed storage")
    unless printed.locals == printing.locals do throw (IO.userError "printing changed caller locals")
    let oldCells := printing.cells.map fun cell => (cell.id, cell.value)
    let retainedCells := (printed.cells.take printing.cells.length).map fun cell => (cell.id, cell.value)
    unless retainedCells == oldCells do throw (IO.userError "printing changed caller cells")
    let .done child after := evalExpr 100 extractedProgram printed
      (.call Extracted.«ir::body_tree».Functions.«first_child».core.id [.value tree, .value (.signed .i32 0)])
      | throw (IO.userError "printed tree became unnavigable")
    unless child == .signed .i32 (if depth > 0 then 1 else -1) do throw (IO.userError "printing changed the tree's children")
    let .ok storedEvent := readRawSliceIndex extractedProgram after (.enumeration eventId)
      eventsAddress count depth
      | throw (IO.userError "IR event became unreadable")
    unless storedEvent == event do throw (IO.userError "printing changed an IR event")
    let .ok endpoint := readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) before.heap.nextAddress count 0
      | throw (IO.userError "IR endpoint became unreadable")
    unless endpoint == .signed .i32 count do throw (IO.userError "printing changed an endpoint")
    let .ok annotation := readRawSliceIndex extractedProgram after referenceType
      annotationsAddress count depth
      | throw (IO.userError "IR annotation became unreadable")
    unless annotation == referenceValue kind do throw (IO.userError "printing changed an annotation") : IO Unit)

-- A too-small output range must reject before borrowing or writing text.
#eval (do
  let .done result after := evalExpr 100 extractedProgram sample
    (.call Extracted.«verified::lean_typed_body».Functions.«surface_boolean_output».core.id
      [.value (.rawSlice viewType 504 1), .value (.boolean false), .value (.signed .i32 30)])
    | throw (IO.userError "short-buffer boolean writer trapped")
  unless result == .signed .i32 (-1) do throw (IO.userError "short-buffer boolean writer did not reject")
  let .ok output := after.heap.loadBytes 16 32 | throw (IO.userError "rejection lost output storage")
  unless output == List.replicate 32 0 do throw (IO.userError "rejection wrote output")
  unless after.heap.nextAddress == sample.heap.nextAddress do throw (IO.userError "rejection borrowed string storage") : IO Unit)

end SurfaceBooleanTests
