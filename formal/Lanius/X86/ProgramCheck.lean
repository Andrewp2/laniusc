import Lanius.X86.FunctionCheck
import Lanius.X86.DirectCallFunctionCheck
import Lanius.X86.LocalExpressionCheck
import Lanius.Execution

namespace Lanius.X86.ProgramCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine

/- The image contract is intentionally only an ordered text image.  ELF
   headers, segment permissions, and the backend emitter remain outside this
   certificate until an emitter witness is available. -/
structure FunctionImage where
  address : Machine.Address
  bytes : List UInt8

structure Image where
  functions : List FunctionImage

structure FunctionEvidence where
  function : Function
  image : FunctionImage
  checked : FunctionCheck.Checked function image.bytes

def checkFunctions : List Function → List FunctionImage →
    Option (List FunctionEvidence)
  | [], [] => some []
  | function :: functions, image :: images =>
      do
        let proof ← FunctionCheck.check function image.bytes
        let evidence ← checkFunctions functions images
        return { function := function, image := image, checked := proof } :: evidence
  | _, _ => none

def findEntrypoint? (id : FunctionId) : List FunctionEvidence →
    Option FunctionEvidence
  | [] => none
  | evidence :: rest =>
      if evidence.function.id == id then some evidence else findEntrypoint? id rest

structure Checked (executable : Execution.Executable) (image : Image) where
  functions : List FunctionEvidence
  sourceExact : functions.map (fun evidence => evidence.function) = executable.program.functions
  imageExact : functions.map (fun evidence => evidence.image) = image.functions
  entrypoint : FunctionEvidence
  entrypointFound : findEntrypoint? executable.entrypoint functions = some entrypoint
  entrypointZeroParameters : entrypoint.function.parameters = []

def Loaded (checked : Checked executable image) (machine : Machine.State) : Prop :=
  ∀ evidence, evidence ∈ checked.functions →
    Machine.CodeAt machine.memory evidence.image.address evidence.image.bytes

theorem checkFunctions_sound {functions : List Function} {images : List FunctionImage}
    {evidence : List FunctionEvidence} (accepted : checkFunctions functions images = some evidence) :
    evidence.map (fun item => item.function) = functions ∧
      evidence.map (fun item => item.image) = images := by
  induction functions generalizing images evidence with
  | nil =>
      cases images with
      | nil =>
          simp only [checkFunctions] at accepted
          cases accepted
          constructor <;> rfl
      | cons image images => simp [checkFunctions] at accepted
  | cons function functions ih =>
      cases images with
      | nil => simp [checkFunctions] at accepted
      | cons image images =>
          simp only [checkFunctions] at accepted
          cases h : FunctionCheck.check function image.bytes with
          | none =>
              simp [h] at accepted
          | some proof =>
              cases h' : checkFunctions functions images with
              | none =>
                  simp [h, h'] at accepted
              | some rest =>
                  simp [h, h'] at accepted
                  cases accepted
                  have tail := ih h'
                  simp only [List.map_cons]
                  exact ⟨congrArg (List.cons function) tail.1,
                    congrArg (List.cons image) tail.2⟩

theorem findEntrypoint_id {id : FunctionId} {evidence : List FunctionEvidence}
    {entrypoint : FunctionEvidence}
    (found : findEntrypoint? id evidence = some entrypoint) :
    entrypoint.function.id = id := by
  induction evidence with
  | nil => simp [findEntrypoint?] at found
  | cons head tail ih =>
      simp only [findEntrypoint?] at found
      split at found
      next same =>
        cases found
        simpa using same.symm
      next different =>
        exact ih found

theorem findEntrypoint_mem {id : FunctionId} {evidence : List FunctionEvidence}
    {entrypoint : FunctionEvidence}
    (found : findEntrypoint? id evidence = some entrypoint) :
    entrypoint ∈ evidence := by
  induction evidence with
  | nil => simp [findEntrypoint?] at found
  | cons head tail ih =>
      simp only [findEntrypoint?] at found
      split at found
      next same =>
        cases found
        simp
      next different =>
        exact List.mem_cons_of_mem head (ih found)

theorem findEntrypoint_map (id : FunctionId) (evidence : List FunctionEvidence) :
    (evidence.map (fun item => item.function)).find?
        (fun function => function.id == id) =
      (findEntrypoint? id evidence).map (fun item => item.function) := by
  induction evidence with
  | nil => rfl
  | cons head tail ih =>
      simp only [List.map_cons, findEntrypoint?]
      split <;> simp_all

def check (executable : Execution.Executable) (image : Image) :
    Option (Checked executable image) :=
  match functionsChecked : checkFunctions executable.program.functions image.functions with
  | none => none
  | some functions =>
      match entrypointFound : findEntrypoint? executable.entrypoint functions with
      | none => none
      | some entrypoint =>
          if zeroParameters : entrypoint.function.parameters = [] then
            let exact := checkFunctions_sound functionsChecked
            some {
              functions := functions
              sourceExact := exact.1
              imageExact := exact.2
              entrypoint := entrypoint
              entrypointFound := entrypointFound
              entrypointZeroParameters := zeroParameters }
          else none

theorem check_sound {executable : Execution.Executable} {image : Image}
    {checked : Checked executable image} (_accepted : check executable image = some checked) :
    checked.entrypoint.function.id = executable.entrypoint ∧
      checked.entrypoint.function.parameters = [] := by
  exact ⟨findEntrypoint_id checked.entrypointFound,
    checked.entrypointZeroParameters⟩

theorem Checked.entrypoint_found
    (checked : Checked executable image) :
    executable.program.function? executable.entrypoint =
      some checked.entrypoint.function := by
  unfold Core.Program.function?
  rw [← checked.sourceExact, findEntrypoint_map, checked.entrypointFound]
  rfl

/- A loaded image is all that the machine proof consumes.  In particular,
   this theorem does not assert that `backend/image.lani` emitted the image. -/
def LiteralPreservation (function : Function) (supported : LiteralReturn.Supported function)
    (program : Program) (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (returnAddress : Machine.Address) : Prop :=
  function.body = some (LiteralReturn.body supported.literal) ∧
    Executes program coreBefore (LiteralReturn.body supported.literal)
      (.returned (some supported.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = supported.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = supported.literal.bits ∧
      LiteralReturn.RaxMatches supported.literal.value
        ((after.registers 0).setWidth 32) ∧ after.rip = returnAddress ∧
      after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags

def LiteralTrailingPreservation (function : Function)
    (supported : LiteralReturn.TrailingSupported function)
    (program : Program) (coreBefore : Semantics.State)
    (machineBefore : Machine.State) (returnAddress : Machine.Address) : Prop :=
  function.body = some (LiteralReturn.trailingBody supported.literal) ∧
    Executes program coreBefore (LiteralReturn.trailingBody supported.literal)
      (.returned (some supported.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = supported.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = supported.literal.bits ∧
      LiteralReturn.RaxMatches supported.literal.value
        ((after.registers 0).setWidth 32) ∧ after.rip = returnAddress ∧
      after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags

def LiteralParametersPreservation (function : Function)
    (supported : LiteralReturn.ParametersSupported function)
    (program : Program) (coreBefore : Semantics.State)
    (machineBefore : Machine.State) (returnAddress : Machine.Address) : Prop :=
  function.body = some (LiteralReturn.body supported.literal) ∧
    Executes program coreBefore (LiteralReturn.body supported.literal)
      (.returned (some supported.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = supported.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = supported.literal.bits ∧
      LiteralReturn.RaxMatches supported.literal.value
        ((after.registers 0).setWidth 32) ∧ after.rip = returnAddress ∧
      after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags

def LiteralParametersTrailingPreservation (function : Function)
    (supported : LiteralReturn.ParametersTrailingSupported function)
    (program : Program) (coreBefore : Semantics.State)
    (machineBefore : Machine.State) (returnAddress : Machine.Address) : Prop :=
  function.body = some (LiteralReturn.trailingBody supported.literal) ∧
    Executes program coreBefore (LiteralReturn.trailingBody supported.literal)
      (.returned (some supported.literal.value)) coreBefore ∧
    ∃ middle after, Machine.Step machineBefore middle ∧ Machine.Step middle after ∧
      after.registers 0 = supported.literal.bits.setWidth 64 ∧
      (after.registers 0).setWidth 32 = supported.literal.bits ∧
      LiteralReturn.RaxMatches supported.literal.value
        ((after.registers 0).setWidth 32) ∧ after.rip = returnAddress ∧
      after.registers 4 = machineBefore.registers 4 + 8 ∧
      (∀ register, register ≠ 0 → register ≠ 4 →
        after.registers register = machineBefore.registers register) ∧
      after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags


def Preserves (evidence : FunctionEvidence) (program : Program)
    (coreBefore : Semantics.State) (machineBefore : Machine.State)
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip evidence.image.bytes)
    (coreFormed : coreBefore.CellsWellFormed)
    (textStack : Machine.TextStackDisjoint machineBefore machineBefore.rip
      evidence.image.bytes.length)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) : Prop :=
  /- `textStack` is an explicit runtime-entry layout fact.  Flat `CodeAt`
     over the ELF image alone cannot establish stack non-aliasing. -/
  match evidence.checked with
  | .literal supported _bytesExact =>
      LiteralPreservation evidence.function supported program coreBefore machineBefore returnAddress
  | .literalParameters supported bytesExact =>
      LiteralParametersPreservation evidence.function supported program coreBefore machineBefore returnAddress
  | .literalParametersTrailing supported bytesExact =>
      LiteralParametersTrailingPreservation evidence.function supported program coreBefore machineBefore returnAddress
  | .literalTrailing supported _bytesExact =>
      LiteralTrailingPreservation evidence.function supported program coreBefore machineBefore returnAddress
  | .parameter supported _bytesExact =>
      LocalExpressionCheck.parameterResult supported program coreBefore machineBefore
        returnAddress
  | .body supported =>
      ∀ frame : ExpressionFunctionCheck.BodyFrameInvariant
          supported.checkedShape.1 machineBefore,
        ExpressionFunctionCheck.BodySupported.result supported program coreBefore machineBefore
          returnAddress

theorem Checked.entrypoint_preserves
    (checked : Checked executable image) (coreBefore : Semantics.State)
    (machineBefore : Machine.State) (loaded : Loaded checked machineBefore)
    (coreFormed : coreBefore.CellsWellFormed)
    (ripAtEntry : machineBefore.rip = checked.entrypoint.image.address)
    (textStack : Machine.TextStackDisjoint machineBefore machineBefore.rip
      checked.entrypoint.image.bytes.length)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) :
    Preserves checked.entrypoint executable.program coreBefore machineBefore (by
        rw [ripAtEntry]
        exact loaded checked.entrypoint (findEntrypoint_mem checked.entrypointFound))
      coreFormed textStack returnAddress poppedReturn := by
  unfold Preserves
  cases checked.entrypoint.checked with
  | literal supported bytesExact =>
      simpa [LiteralPreservation] using
        (supported.preserves executable.program coreBefore machineBefore
        checked.entrypoint.image.bytes bytesExact (by
          rw [ripAtEntry]
          exact loaded checked.entrypoint (findEntrypoint_mem checked.entrypointFound))
        returnAddress poppedReturn)
  | literalParameters supported bytesExact =>
      simpa [LiteralParametersPreservation] using
        (supported.preserves executable.program coreBefore machineBefore
        checked.entrypoint.image.bytes bytesExact (by
          rw [ripAtEntry]
          exact loaded checked.entrypoint (findEntrypoint_mem checked.entrypointFound))
        returnAddress poppedReturn)
  | literalParametersTrailing supported bytesExact =>
      simpa [LiteralParametersTrailingPreservation] using
        (supported.preserves executable.program coreBefore machineBefore
        checked.entrypoint.image.bytes bytesExact (by
          rw [ripAtEntry]
          exact loaded checked.entrypoint (findEntrypoint_mem checked.entrypointFound))
        returnAddress poppedReturn)
  | literalTrailing supported bytesExact =>
      simpa [LiteralTrailingPreservation] using
        (supported.preserves executable.program coreBefore machineBefore
        checked.entrypoint.image.bytes bytesExact (by
          rw [ripAtEntry]
          exact loaded checked.entrypoint (findEntrypoint_mem checked.entrypointFound))
        returnAddress poppedReturn)
  | parameter supported bytesExact =>
      have loadedImage : Machine.CodeAt machineBefore.memory machineBefore.rip
          checked.entrypoint.image.bytes := by
        rw [ripAtEntry]
        exact loaded checked.entrypoint (findEntrypoint_mem checked.entrypointFound)
      let loadedParameter : Machine.CodeAt machineBefore.memory machineBefore.rip
          (ParameterReturn.bytes supported.argument) := by
        simpa [bytesExact] using loadedImage
      exact LocalExpressionCheck.parameter_preserves supported executable.program
        coreBefore machineBefore loadedParameter returnAddress poppedReturn
  | body supported =>
      intro frame
      exact ExpressionFunctionCheck.BodySupported.preserves supported executable.program
        coreBefore machineBefore
        (by
          rw [ripAtEntry]
          exact loaded checked.entrypoint (findEntrypoint_mem checked.entrypointFound))
        frame coreFormed returnAddress poppedReturn

end Lanius.X86.ProgramCheck

namespace Lanius.X86.ProgramCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86.Machine
open Lanius.X86.DirectCallCheck
open Lanius.X86.DirectCallFunctionCheck

structure ImageEvidence where
  function : Function
  image : FunctionImage

structure DirectImageEvidence (callerId : FunctionId) where
  function : Function
  image : FunctionImage
  nonCallerChecked : function.id ≠ callerId →
    FunctionCheck.Checked function image.bytes

structure DirectCalleeEvidence (callerId : FunctionId)
    (evidence : List (DirectImageEvidence callerId)) where
  item : DirectImageEvidence callerId
  member : item ∈ evidence

structure FunctionImageEvidence (id : FunctionId) where
  function : Function
  idExact : function.id = id
  image : FunctionImage

/- The direct-call variant is kept at the program boundary: the ordinary
   FunctionCheck remains intentionally call-free, while this branch checks the
   caller bytes, the callee certificate, and their exact image/source pairing.
   Runtime preservation is still available only for the literal modes below;
   generic body certificates are retained for the next composition step. -/
structure DirectLiteralEvidence (callee : Function) (calleeImage : FunctionImage) where
  calleeChecked : FunctionCheck.Checked callee calleeImage.bytes
  calleeLiteral : LiteralReturn.Literal
  calleeZeroParameters : callee.parameters = []
  calleeBody : Core.Stmt
  calleeBodyExact : callee.body = some calleeBody
  calleeBodyShape : calleeBody = LiteralReturn.body calleeLiteral ∨
    calleeBody = LiteralReturn.trailingBody calleeLiteral
  calleeBits : BitVec 32
  calleeLiteralExact : calleeLiteral = .i32 calleeBits
  calleeBytesExact : calleeImage.bytes = LiteralReturn.bytes (.i32 calleeBits)

inductive DirectCalleeMode (callee : Function) (calleeImage : FunctionImage) where
  | literal (evidence : DirectLiteralEvidence callee calleeImage)
  | literalParametersTrailing (evidence : DirectLiteralEvidence callee calleeImage)
  | body (supported : ExpressionFunctionCheck.BodySupported callee calleeImage.bytes)

def DirectCalleeMode.checked {callee : Function} {calleeImage : FunctionImage}
    (mode : DirectCalleeMode callee calleeImage) :
    FunctionCheck.Checked callee calleeImage.bytes :=
  match mode with
  | .literal evidence => evidence.calleeChecked
  | .literalParametersTrailing evidence => evidence.calleeChecked
  | .body supported => .body supported

/- This dependent payload is deliberately empty for generic bodies.  It keeps
   the already-proved literal direct path available without adding a false
   body-preservation theorem. -/
def DirectCalleeMode.LiteralEvidence {callee : Function} {calleeImage : FunctionImage}
    (mode : DirectCalleeMode callee calleeImage) : Type :=
  match mode with
  | .literal evidence => DirectLiteralEvidence callee calleeImage
  | .literalParametersTrailing evidence => DirectLiteralEvidence callee calleeImage
  | .body _ => Empty

def DirectCalleeMode.literalEvidence {callee : Function} {calleeImage : FunctionImage}
    {mode : DirectCalleeMode callee calleeImage}
  (evidence : mode.LiteralEvidence) : DirectLiteralEvidence callee calleeImage :=
  match mode with
  | .literal evidence => evidence
  | .literalParametersTrailing evidence => evidence
  | .body _ => nomatch evidence

def DirectCalleeMode.BodyEvidence {callee : Function} {calleeImage : FunctionImage}
    (mode : DirectCalleeMode callee calleeImage) : Type :=
  match mode with
  | .literal _ => Empty
  | .literalParametersTrailing _ => Empty
  | .body supported => ExpressionFunctionCheck.BodySupported callee calleeImage.bytes

def DirectCalleeMode.bodyEvidence {callee : Function} {calleeImage : FunctionImage}
    {mode : DirectCalleeMode callee calleeImage}
    (evidence : mode.BodyEvidence) :
    ExpressionFunctionCheck.BodySupported callee calleeImage.bytes :=
  match mode with
  | .literal _ => nomatch evidence
  | .literalParametersTrailing _ => nomatch evidence
  | .body supported => evidence

structure DirectChecked (executable : Execution.Executable) (image : Image)
    (displacement : BitVec 32) where
  caller : Function
  callee : Function
  callerImage : FunctionImage
  calleeImage : FunctionImage
  callerChecked : DirectCallFunctionCheck.Checked caller callee
    callerImage.address calleeImage.address displacement callerImage.bytes
  calleeMode : DirectCalleeMode callee calleeImage
  callerBodyShape : caller.body =
      some (.returnValue (some (.call callee.id []))) ∨
    caller.body = some (.sequence
      (.returnValue (some (.call callee.id []))) .skip)
  functions : List (DirectImageEvidence executable.entrypoint)
  functionsExact : functions.map (fun evidence => evidence.function) =
    executable.program.functions
  imagesExact : functions.map (fun evidence => evidence.image) = image.functions
  functionsUnique : (executable.program.functions.map (fun function => function.id)).Nodup
  entrypointExact : executable.entrypoint = caller.id
  calleeMember : callee ∈ executable.program.functions
  callerEvidenceMember : ∃ evidence, evidence ∈ functions ∧
    evidence.function = caller ∧ evidence.image = callerImage
  calleeEvidenceMember : ∃ evidence, evidence ∈ functions ∧
    evidence.function = callee ∧ evidence.image = calleeImage
  idsDistinct : caller.id ≠ callee.id

def DirectChecked.calleeChecked
    (checked : DirectChecked executable image displacement) :
    FunctionCheck.Checked checked.callee checked.calleeImage.bytes :=
  checked.calleeMode.checked

def checkDirectImages (callerId : FunctionId) :
    List Function → List FunctionImage →
    Option (List (DirectImageEvidence callerId))
  | function :: functions, image :: images =>
      if same : function.id = callerId then
        do
          let evidence ← checkDirectImages callerId functions images
          let item : DirectImageEvidence callerId := {
            function := function
            image := image
            nonCallerChecked := by
              intro different
              exact (different same).elim }
          return item :: evidence
      else
        do
          let checked ← FunctionCheck.check function image.bytes
          let evidence ← checkDirectImages callerId functions images
          let item : DirectImageEvidence callerId := {
            function := function
            image := image
            nonCallerChecked := fun _ => checked }
          return item :: evidence
  | [], [] => some []
  | [], _ => none
  | _, [] => none

theorem checkDirectImages_sound
    {callerId : FunctionId} {functions : List Function}
    {images : List FunctionImage}
    {evidence : List (DirectImageEvidence callerId)}
    (accepted : checkDirectImages callerId functions images = some evidence) :
    evidence.map (fun item => item.function) = functions ∧
      evidence.map (fun item => item.image) = images := by
  induction functions generalizing images evidence with
  | nil =>
      cases images with
      | nil =>
          simp only [checkDirectImages] at accepted
          cases accepted
          exact ⟨rfl, rfl⟩
      | cons image images => simp [checkDirectImages] at accepted
  | cons function functions inductionHypothesis =>
      cases images with
      | nil => simp [checkDirectImages] at accepted
      | cons image images =>
          simp only [checkDirectImages] at accepted
          split at accepted
          next same =>
            cases h : checkDirectImages callerId functions images with
            | none => simp [h] at accepted
            | some rest =>
                simp [h] at accepted
                cases accepted
                have tail := inductionHypothesis h
                exact ⟨congrArg (List.cons function) tail.1,
                  congrArg (List.cons image) tail.2⟩
          next different =>
            cases h : FunctionCheck.check function image.bytes with
            | none => simp [h] at accepted
            | some checked =>
                cases h' : checkDirectImages callerId functions images with
                | none => simp [h, h'] at accepted
                | some rest =>
                    simp [h, h'] at accepted
                    cases accepted
                    have tail := inductionHypothesis h'
                    exact ⟨congrArg (List.cons function) tail.1,
                      congrArg (List.cons image) tail.2⟩

def findFunctionImage? (id : FunctionId) :
    List Function → List FunctionImage →
      Option (FunctionImageEvidence id)
  | function :: functions, image :: images =>
      if same : function.id = id then
        some { function := function, idExact := same, image := image }
      else findFunctionImage? id functions images
  | _, _ => none

def findDirectImage? (id : FunctionId) :
    List (DirectImageEvidence callerId) → Option (DirectImageEvidence callerId)
  | item :: evidence =>
      if item.function.id == id then some item else findDirectImage? id evidence
  | [] => none

theorem findDirectImage_member {id : FunctionId}
    {evidence : List (DirectImageEvidence id)}
    {item : DirectImageEvidence id}
    (found : findDirectImage? id evidence = some item) : item ∈ evidence := by
  induction evidence with
  | nil => simp [findDirectImage?] at found
  | cons head tail inductionHypothesis =>
      simp only [findDirectImage?] at found
      split at found
      next same => cases found; simp
      next different => exact List.mem_cons_of_mem head (inductionHypothesis found)

theorem findDirectImage_id {id : FunctionId}
    {evidence : List (DirectImageEvidence id)}
    {item : DirectImageEvidence id}
    (found : findDirectImage? id evidence = some item) : item.function.id = id := by
  induction evidence with
  | nil => simp [findDirectImage?] at found
  | cons head tail inductionHypothesis =>
      simp only [findDirectImage?] at found
      split at found
      next same => cases found; simpa using same.symm
      next different => exact inductionHypothesis found

def findDirectCallee? (caller : Function) (callerImage : FunctionImage)
    (displacement : BitVec 32) :
    (evidence : List (DirectImageEvidence callerId)) →
      Option (DirectCalleeEvidence callerId evidence)
  | item :: evidence =>
      if item.function.id == caller.id then
        match findDirectCallee? caller callerImage displacement evidence with
        | none => none
        | some found => some {
            item := found.item
            member := List.mem_cons_of_mem item found.member }
      else
        match DirectCallFunctionCheck.check caller item.function callerImage.address
            item.image.address displacement callerImage.bytes with
        | some _ =>
            match FunctionCheck.check item.function item.image.bytes with
            | some _ => some { item := item, member := List.mem_cons_self }
            | none =>
                match findDirectCallee? caller callerImage displacement evidence with
                | none => none
                | some found => some {
                    item := found.item
                    member := List.mem_cons_of_mem item found.member }
        | none =>
            match findDirectCallee? caller callerImage displacement evidence with
            | none => none
            | some found => some {
                item := found.item
                member := List.mem_cons_of_mem item found.member }
  | [] => none

def checkDirect (executable : Execution.Executable) (image : Image)
    (displacement : BitVec 32) :
    Option (DirectChecked executable image displacement) :=
  if unique : (executable.program.functions.map (fun function => function.id)).Nodup then
    match imagesChecked : checkDirectImages executable.entrypoint
        executable.program.functions image.functions with
    | none => none
    | some functions =>
        match callerFound : findDirectImage? executable.entrypoint functions with
        | none => none
        | some callerEvidence =>
            match calleeFound : findDirectCallee? callerEvidence.function
                callerEvidence.image displacement functions with
            | none => none
            | some calleeEvidence =>
                if sameId : callerEvidence.function.id =
                    calleeEvidence.item.function.id then
                  none
                else
                  match DirectCallFunctionCheck.check callerEvidence.function
                      calleeEvidence.item.function callerEvidence.image.address
                      calleeEvidence.item.image.address displacement callerEvidence.image.bytes with
                  | none => none
                  | some callerChecked =>
                      have imageSound := checkDirectImages_sound imagesChecked
                      have calleeMember : calleeEvidence.item.function ∈
                          executable.program.functions := by
                        rw [← imageSound.1]
                        exact List.mem_map.mpr ⟨calleeEvidence.item,
                          calleeEvidence.member, rfl⟩
                      let makeChecked (mode : DirectCalleeMode
                          calleeEvidence.item.function calleeEvidence.item.image) :
                          DirectChecked executable image displacement := {
                        caller := callerEvidence.function
                        callee := calleeEvidence.item.function
                        callerImage := callerEvidence.image
                        calleeImage := calleeEvidence.item.image
                        callerChecked := callerChecked
                        calleeMode := mode
                        callerBodyShape := callerChecked.callerSupported.bodyExact
                        functions := functions
                        functionsExact := imageSound.1
                        imagesExact := imageSound.2
                        functionsUnique := unique
                        entrypointExact := (findDirectImage_id callerFound).symm
                        calleeMember := calleeMember
                        callerEvidenceMember := ⟨callerEvidence,
                          findDirectImage_member callerFound, rfl, rfl⟩
                        calleeEvidenceMember := ⟨calleeEvidence.item,
                          calleeEvidence.member, rfl, rfl⟩
                        idsDistinct := sameId }
                      match FunctionCheck.check calleeEvidence.item.function
                          calleeEvidence.item.image.bytes with
                      | some (.literal calleeLiteral bytesExact) =>
                          match literal : calleeLiteral.literal with
                          | .i32 bits =>
                              some (makeChecked (.literal {
                                calleeChecked := .literal calleeLiteral bytesExact
                                calleeLiteral := calleeLiteral.literal
                                calleeZeroParameters := calleeLiteral.zeroParameters
                                calleeBody := LiteralReturn.body calleeLiteral.literal
                                calleeBodyExact := calleeLiteral.bodyExact
                                calleeBodyShape := Or.inl rfl
                                calleeBits := bits
                                calleeLiteralExact := literal
                                calleeBytesExact := by simpa [literal] using bytesExact }))
                          | .bool _ => none
                      | some (.literalParametersTrailing calleeLiteral bytesExact) =>
                          match literal : calleeLiteral.literal with
                          | .i32 bits =>
                              have zeroParameters : calleeEvidence.item.function.parameters = [] := by
                                apply List.eq_nil_of_length_eq_zero
                                simpa using callerChecked.direct.arityExact.symm
                              some (makeChecked (.literalParametersTrailing {
                                calleeChecked :=
                                  .literalParametersTrailing calleeLiteral bytesExact
                                calleeLiteral := calleeLiteral.literal
                                calleeZeroParameters := zeroParameters
                                calleeBody := LiteralReturn.trailingBody calleeLiteral.literal
                                calleeBodyExact := calleeLiteral.bodyExact
                                calleeBodyShape := Or.inr rfl
                                calleeBits := bits
                                calleeLiteralExact := literal
                                calleeBytesExact := by simpa [literal] using bytesExact }))
                          | .bool _ => none
                      | some (.body supported) =>
                          some (makeChecked (.body supported))
                      | _ => none
  else none

theorem checkDirect_sound {executable : Execution.Executable} {image : Image}
    {displacement : BitVec 32} {checked : DirectChecked executable image displacement}
    (_accepted : checkDirect executable image displacement = some checked) :
    checked.callerImage.bytes = functionBytes displacement ∧
      FunctionCheck.Checked.Authenticated checked.calleeChecked :=
  ⟨checked.callerChecked.bytesExact,
    FunctionCheck.Checked.bytesExact checked.calleeChecked⟩

private theorem literalCalleePreservation (bits : BitVec 32)
    (entry after : Machine.State) (target : Machine.Address)
    (_entryRip : entry.rip = target)
    (loaded : Machine.CodeAt entry.memory entry.rip
      (LiteralReturn.bytes (.i32 bits)))
    (afterExact : after = entry.immediate32 0 bits
      (LiteralReturn.immediateBytes (.i32 bits)).length) :
    DirectCallCheck.CalleePreservation entry after target [] bits.toInt := by
  have loadedImmediate : Machine.CodeAt entry.memory entry.rip
      (LiteralReturn.immediateBytes (.i32 bits)) :=
    Machine.CodeAt.prefix (first := LiteralReturn.immediateBytes (.i32 bits))
      (rest := Machine.returnBytes) loaded
  have step : Machine.Step entry after := by
    apply Machine.immediate_step entry after .w32 0 bits 0 loadedImmediate
    exact afterExact
  refine {
    steps := ⟨1, Machine.Steps.cons step (Machine.Steps.refl after)⟩
    resultFrom := ?_, stack := ?_, stable := ?_, memory := ?_, flags := ?_ }
  · intro _ _; rw [afterExact]
    simp [Machine.State.immediate32, DirectCallCheck.resultRegister]
  · rw [afterExact]
    simp [Machine.State.immediate32, DirectCallCheck.stackRegister]
  · intro register notResult notStack
    rw [afterExact]
    have notZero : register ≠ 0 := by
      simpa [DirectCallCheck.resultRegister] using notResult
    simp [Machine.State.immediate32, notZero]
  · rw [afterExact]; rfl
  · rw [afterExact]; rfl

def calleeCodePrologueDisjoint (before : Machine.State)
    (calleeImage : FunctionImage) : Prop :=
  ∀ index, index < calleeImage.bytes.length → ∀ lane : Fin 8,
    calleeImage.address + BitVec.ofNat 64 index ≠
      (before.registers DirectCallCheck.stackRegister - 8) + BitVec.ofNat 64 lane.val

def calleeCodeCallDisjoint (before : Machine.State)
    (calleeImage : FunctionImage) : Prop :=
  ∀ index, index < calleeImage.bytes.length → ∀ lane : Fin 8,
    calleeImage.address + BitVec.ofNat 64 index ≠
      ((Machine.prologueState before 1).registers DirectCallCheck.stackRegister - 8) +
        BitVec.ofNat 64 lane.val

structure DirectLayout (checked : DirectChecked executable image displacement)
    (before : Machine.State) : Prop where
  prologue : DirectCallFunctionCheck.prologueDisjoint before
  tail : DirectCallFunctionCheck.tailDisjoint before displacement
  call : DirectCallFunctionCheck.callDisjoint before displacement
  calleePrologue : calleeCodePrologueDisjoint before checked.calleeImage
  calleeCall : calleeCodeCallDisjoint before checked.calleeImage

def CalleeBridge (calleeImage : FunctionImage) (result : Int) : Prop :=
  ∀ (entry : Machine.State), entry.rip = calleeImage.address →
    Machine.CodeAt entry.memory entry.rip calleeImage.bytes →
      ∃ after, DirectCallCheck.CalleePreservation entry after
          calleeImage.address [] result ∧
        Machine.CodeAt after.memory after.rip DirectCallCheck.returnBytes

private theorem literalCalleeBridge
    (checked : DirectChecked executable image displacement)
    (literal : DirectLiteralEvidence checked.callee checked.calleeImage) :
    CalleeBridge checked.calleeImage literal.calleeBits.toInt := by
  intro entry entryRip loaded
  have loadedLiteral : Machine.CodeAt entry.memory entry.rip
      (LiteralReturn.bytes (.i32 literal.calleeBits)) := by
    rw [literal.calleeBytesExact] at loaded
    exact loaded
  let calleeAfter := entry.immediate32 0 literal.calleeBits
      (LiteralReturn.immediateBytes (.i32 literal.calleeBits)).length
  have loadedReturn : Machine.CodeAt calleeAfter.memory calleeAfter.rip
      DirectCallCheck.returnBytes := by
    have source := Machine.CodeAt.suffix
      (first := LiteralReturn.immediateBytes (.i32 literal.calleeBits))
      (rest := Machine.returnBytes) loadedLiteral
    simpa [calleeAfter, Machine.State.immediate32,
      DirectCallCheck.returnBytes] using source
  exact ⟨calleeAfter,
    literalCalleePreservation literal.calleeBits entry calleeAfter
      checked.calleeImage.address entryRip loadedLiteral rfl,
    loadedReturn⟩

theorem directPreserves
    (checked : DirectChecked executable image displacement)
    (result : Int)
    (calleeBridge : CalleeBridge checked.calleeImage result)
    (before : Machine.State)
    (ripAtCaller : before.rip = checked.callerImage.address)
    (loadedCaller : Machine.CodeAt before.memory before.rip
      checked.callerImage.bytes)
    (layout : DirectLayout checked before)
    (loadedCallee : Machine.CodeAt before.memory checked.calleeImage.address
      checked.calleeImage.bytes)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 before.memory
      (before.registers DirectCallCheck.stackRegister) = returnAddress) :
    ∃ after calleeCount, Machine.Steps (calleeCount + 9) before after ∧
      ((after.registers DirectCallCheck.resultRegister).setWidth 32).toInt =
        result ∧
      after.rip = returnAddress ∧
      after.registers DirectCallCheck.stackRegister =
        before.registers DirectCallCheck.stackRegister + 8 ∧
      after.memory =
        (DirectCallFunctionCheck.callAfterState before displacement).memory := by
  have loadedCalleePrologue := Machine.CodeAt.write64 loadedCallee
    (before.registers rbpRegister) (by
      intro index bound lane
      exact layout.calleePrologue index bound lane)
  have loadedCalleeAtPrologue : Machine.CodeAt
      (Machine.prologueState before 1).memory checked.calleeImage.address
      checked.calleeImage.bytes := by
    simpa [Machine.prologueState, Machine.State.push64, Machine.State.move64,
      Machine.State.immediate32, Machine.State.alu64, Machine.State.alu,
      rbpRegister, DirectCallCheck.stackRegister] using loadedCalleePrologue
  have loadedCalleeCall := Machine.CodeAt.write64 loadedCalleeAtPrologue
    ((Machine.prologueState before 1).rip +
      BitVec.ofNat 64 (Machine.callBytes displacement).length) (by
      intro index bound lane
      exact layout.calleeCall index bound lane)
  let callAfter := callAfterState before displacement
  have callRip : (Machine.prologueState before 1).rip =
      callSite checked.callerImage.address := by
    simp [Machine.prologueState, callSite, ripAtCaller, Machine.State.alu64,
      Machine.State.alu, Machine.State.immediate32, Machine.State.move64,
      Machine.State.push64, framePrologueBytes, rbpRegister,
      DirectCallCheck.stackRegister, r11Register, BitVec.ofNat_add,
      BitVec.add_assoc]
  have targetRip : callAfter.rip = checked.calleeImage.address := by
    change (Machine.prologueState before 1).rip +
      BitVec.ofNat 64 (Machine.callBytes displacement).length +
      displacement.signExtend 64 = checked.calleeImage.address
    rw [callRip]
    have targetEquation := checked.callerChecked.direct.targetExact
    simp only [DirectCallCheck.callBytes] at targetEquation
    rw [← targetEquation]
  have loadedCalleeAtCall : Machine.CodeAt callAfter.memory callAfter.rip
      checked.calleeImage.bytes := by
    have atAddress : Machine.CodeAt callAfter.memory checked.calleeImage.address
        checked.calleeImage.bytes := by
      simpa [callAfter, callAfterState, Machine.State.call,
        DirectCallCheck.stackRegister] using loadedCalleeCall
    simpa [targetRip] using atAddress
  obtain ⟨calleeAfter, calleePreservation, loadedReturn⟩ :=
    calleeBridge callAfter targetRip loadedCalleeAtCall
  exact DirectCallFunctionCheck.preserves checked.callerChecked before calleeAfter
    result ripAtCaller loadedCaller layout.prologue layout.tail
    layout.call calleePreservation loadedReturn returnAddress poppedReturn

private theorem findFunction_of_mem_unique
    {functions : List Core.Function} {function : Core.Function}
    (unique : (functions.map fun candidate => candidate.id).Nodup)
    (member : function ∈ functions) :
    functions.find? (fun candidate => candidate.id == function.id) = some function := by
  induction functions with
  | nil => simp at member
  | cons head tail inductionHypothesis =>
      simp only [List.map_cons, List.nodup_cons] at unique
      by_cases same : head.id == function.id
      · have sameId : head.id = function.id := by simpa using same
        have headEq : head = function := by
          rcases List.mem_cons.mp member with headMember | tailMember
          · exact headMember.symm
          · exfalso
            apply unique.1
            exact List.mem_map.mpr ⟨function, tailMember, sameId.symm⟩
        simp [headEq]
      · have different : head.id ≠ function.id := by
          intro equality
          apply same
          simp [equality]
        have tailMember : function ∈ tail := by
          rcases List.mem_cons.mp member with headMember | tailMember
          · exfalso
            apply different
            simp [headMember]
          · exact tailMember
        have sameFalse : (head.id == function.id) = false := by
          cases h : (head.id == function.id) with
          | false => rfl
          | true => exact (same h).elim
        simp [List.find?, sameFalse,
          inductionHypothesis unique.2 tailMember]

theorem directCoreExecutes
    (checked : DirectChecked executable image displacement)
    (literal : DirectLiteralEvidence checked.callee checked.calleeImage)
    (coreBefore : Semantics.State)
    (formed : coreBefore.CellsWellFormed) :
    ∃ body, checked.caller.body = some body ∧
      Executes executable.program coreBefore body
        (.returned (some (.signed .i32 literal.calleeBits.toInt))) coreBefore := by
  have callerBody := checked.callerChecked.callerSupported.bodyExact
  have calleeBody : checked.callee.body = some literal.calleeBody :=
    literal.calleeBodyExact
  have calleeFound : executable.program.function? checked.callee.id =
      some checked.callee := by
    unfold Core.Program.function?
    exact findFunction_of_mem_unique checked.functionsUnique checked.calleeMember
  have arguments : ThresholdPureList 1 executable.program coreBefore [] [] coreBefore :=
    ThresholdPureList.nil formed
  have parametersBind : bindParameters checked.callee.parameters [] = some [] := by
    simp [bindParameters, literal.calleeZeroParameters]
  let calleeState : Semantics.State := { coreBefore with locals := [] }
  have calleeShape : calleeState =
      ({ coreBefore with locals := [] }).bindLocals [] := by
    simp [calleeState, State.bindLocals]
  have valueRun : StableExpr 1 executable.program calleeState
      (.value (.signed .i32 literal.calleeBits.toInt))
      (.signed .i32 literal.calleeBits.toInt) calleeState := by
    intro fuel enough
    cases fuel with
    | zero => omega
    | succ fuel => exact evalExpr_value fuel executable.program calleeState _
  have bodyContract : StableStmt 3 executable.program calleeState
      literal.calleeBody
      (.returned (some (.signed .i32 literal.calleeBits.toInt))) calleeState := by
    rcases literal.calleeBodyShape with bare | trailing
    · rw [bare]
      intro fuel enough
      cases fuel with
      | zero => omega
      | succ fuel =>
          have valueRun' : evalExpr fuel executable.program calleeState
              (.value (.signed .i32 literal.calleeBits.toInt)) =
              .done (.signed .i32 literal.calleeBits.toInt) calleeState := by
            simpa [show fuel - 1 + 1 = fuel by omega] using
              (evalExpr_value (fuel - 1) executable.program calleeState
                (.signed .i32 literal.calleeBits.toInt))
          simpa [LiteralReturn.body, LiteralReturn.Literal.value, calleeState,
            literal.calleeLiteralExact] using
            (execStmt_return fuel executable.program calleeState
              (.value (.signed .i32 literal.calleeBits.toInt))
              (.signed .i32 literal.calleeBits.toInt) calleeState valueRun')
    · rw [trailing, literal.calleeLiteralExact]
      exact StableStmt.returnValueSequence executable.program calleeState
        (.value (.signed .i32 literal.calleeBits.toInt))
        (.signed .i32 literal.calleeBits.toInt) valueRun
  have calleeFrame : CallerFrame coreBefore calleeState := by
    refine ⟨formed, ?_, rfl, rfl, rfl⟩
    exact ⟨[], by simp [calleeState], Nat.le_refl _, by simp⟩
  have calleeFormed : calleeState.CellsWellFormed := calleeFrame.currentFormed
  have call := thresholdInternalCall executable.program coreBefore checked.callee
    [] literal.calleeBody [] [] coreBefore calleeState
    calleeState (.signed .i32 literal.calleeBits.toInt) calleeFound calleeBody
    arguments parametersBind calleeShape bodyContract calleeFrame
    (PureFrame.refl calleeFormed)
  rcases callerBody with bare | sequence
  · refine ⟨_, bare, ?_⟩
    refine ⟨max 1 3 + 1 + 1, ?_⟩
    simpa [calleeState, restoreLocals] using
      (execStmt_return (max 1 3 + 1) executable.program coreBefore
      (.call checked.callee.id []) (.signed .i32 literal.calleeBits.toInt) coreBefore
      (call.run (max 1 3 + 1) (by omega)))
  · refine ⟨_, sequence, ?_⟩
    refine ⟨max 1 3 + 1 + 2, ?_⟩
    simpa [calleeState, restoreLocals] using
      ((StableStmt.returnValueSequence executable.program coreBefore
        (.call checked.callee.id []) (.signed .i32 literal.calleeBits.toInt)
        call.run) _ (by omega))

/- A direct branch is selected only after the image has fixed the caller and
   callee addresses.  The signed rel32 is computed from that authenticated
   pair, then checked by the ordinary byte-level direct-call checker. -/
def directDisplacement? (caller target : Machine.Address) : Option (BitVec 32) :=
  let callBase := callSite caller + BitVec.ofNat 64 5
  let delta : Int := Int.ofNat target.toNat - Int.ofNat callBase.toNat
  if bounds : (-2147483648 : Int) ≤ delta ∧ delta < 2147483648 then
    let displacement := BitVec.ofInt 32 delta
    if target = callBase + displacement.signExtend 64 then some displacement else none
  else none

inductive Authenticated (executable : Execution.Executable) (image : Image) where
  | standard (checked : Checked executable image)
  | direct (displacement : BitVec 32)
      (checked : DirectChecked executable image displacement)

def Authenticated.functions
    (checked : Authenticated executable image) : List ImageEvidence :=
  match checked with
  | .standard checked => checked.functions.map (fun evidence =>
      { function := evidence.function, image := evidence.image })
  | .direct _ checked => checked.functions.map (fun evidence =>
      { function := evidence.function, image := evidence.image })

def Authenticated.entrypoint
    (checked : Authenticated executable image) : ImageEvidence :=
  match checked with
  | .standard checked =>
      { function := checked.entrypoint.function, image := checked.entrypoint.image }
  | .direct _ checked =>
      { function := checked.caller, image := checked.callerImage }

theorem Authenticated.functions_exact
    (checked : Authenticated executable image) :
    (checked.functions.map (fun evidence => evidence.function)) = executable.program.functions := by
  cases checked with
  | standard checked =>
      simpa [Authenticated.functions, List.map_map, Function.comp_def] using
        checked.sourceExact
  | direct displacement checked =>
      simpa [Authenticated.functions, List.map_map, Function.comp_def] using
        checked.functionsExact

theorem Authenticated.images_exact
    (checked : Authenticated executable image) :
    (checked.functions.map (fun evidence => evidence.image)) = image.functions := by
  cases checked with
  | standard checked =>
      simpa [Authenticated.functions, List.map_map, Function.comp_def] using
        checked.imageExact
  | direct displacement checked =>
      simpa [Authenticated.functions, List.map_map, Function.comp_def] using
        checked.imagesExact

theorem Authenticated.entrypoint_exact
    (checked : Authenticated executable image) :
    (checked.entrypoint.function.id = executable.entrypoint) := by
  cases checked with
  | standard checked => exact findEntrypoint_id checked.entrypointFound
  | direct displacement checked => exact checked.entrypointExact.symm

theorem Authenticated.entrypoint_zero_parameters
    (checked : Authenticated executable image) :
    checked.entrypoint.function.parameters = [] := by
  cases checked with
  | standard checked => exact checked.entrypointZeroParameters
  | direct displacement checked => exact checked.callerChecked.callerSupported.noParameters

theorem Authenticated.entrypoint_allocation_count_le
    (checked : Authenticated executable image) :
    FunctionCheck.functionAllocationCount checked.entrypoint.function ≤ 2^28 := by
  cases checked with
  | standard checked =>
      exact FunctionCheck.Checked.function_allocation_count_le checked.entrypoint.checked
  | direct displacement checked =>
      rcases checked.callerChecked.callerSupported.bodyExact with body | body
      · simp [Authenticated.entrypoint, FunctionCheck.functionAllocationCount, body,
          FunctionCheck.statementAllocationCount, FunctionCheck.expressionAllocationCount]
      · simp [Authenticated.entrypoint, FunctionCheck.functionAllocationCount, body,
          FunctionCheck.statementAllocationCount, FunctionCheck.expressionAllocationCount]

def Authenticated.Loaded (checked : Authenticated executable image)
    (machine : Machine.State) : Prop :=
  ∀ evidence, evidence ∈ checked.functions →
    Machine.CodeAt machine.memory evidence.image.address evidence.image.bytes

theorem Authenticated.loaded_of_slices
    (checked : Authenticated executable image) (machine : Machine.State)
    (sliceLoaded : ∀ function : FunctionImage, function ∈ image.functions →
      Machine.CodeAt machine.memory function.address function.bytes) :
    checked.Loaded machine := by
  intro evidence member
  apply sliceLoaded evidence.image
  have member' : evidence.image ∈
      checked.functions.map (fun item => item.image) :=
    List.mem_map.mpr ⟨evidence, member, rfl⟩
  rw [checked.images_exact] at member'
  exact member'

theorem Authenticated.loaded_standard
    {executable : Execution.Executable} {image : Image}
    (checked : Checked executable image) (machine : Machine.State)
    (loaded : (Authenticated.standard checked).Loaded machine) :
    ProgramCheck.Loaded checked machine := by
  intro evidence member
  exact loaded { function := evidence.function, image := evidence.image }
    (List.mem_map.mpr ⟨evidence, member, rfl⟩)

def Authenticated.bytesAuthenticated
    (checked : Authenticated executable image) : Prop :=
  match checked with
  | .standard checked =>
      ∀ evidence, evidence ∈ checked.functions →
        FunctionCheck.Checked.Authenticated evidence.checked
  | .direct displacement checked =>
      And (checked.callerImage.bytes = functionBytes displacement)
        (FunctionCheck.Checked.Authenticated checked.calleeChecked)

theorem Authenticated.bytes_authenticated
    (checked : Authenticated executable image) :
    checked.bytesAuthenticated := by
  cases checked with
  | standard checked =>
      intro evidence _member
      exact FunctionCheck.Checked.bytesExact evidence.checked
  | direct displacement checked =>
      exact ⟨checked.callerChecked.bytesExact,
        FunctionCheck.Checked.bytesExact checked.calleeChecked⟩

inductive PreservationEnvironment :
    Authenticated executable image → Semantics.State → Machine.State → Type where
  | standard {checked : Checked executable image}
      (coreBefore : Semantics.State) (machineBefore : Machine.State)
      (formed : coreBefore.CellsWellFormed)
      (textStack : Machine.TextStackDisjoint machineBefore machineBefore.rip
        checked.entrypoint.image.bytes.length) :
      PreservationEnvironment (.standard checked) coreBefore machineBefore
  | direct {displacement : BitVec 32}
      {checked : DirectChecked executable image displacement}
      {coreBefore : Semantics.State} {machineBefore : Machine.State}
      (literal : checked.calleeMode.LiteralEvidence)
      (formed : coreBefore.CellsWellFormed) (layout : DirectLayout checked machineBefore) :
      PreservationEnvironment (.direct displacement checked) coreBefore machineBefore

def Authenticated.Preserves (checked : Authenticated executable image)
    (coreBefore : Semantics.State)
    (machineBefore : Machine.State) (loaded : checked.Loaded machineBefore)
    (environment : PreservationEnvironment checked coreBefore machineBefore)
    (ripAtEntry : machineBefore.rip = checked.entrypoint.image.address)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) : Prop :=
  match checked, environment with
  | .standard checked, .standard _ _ formed textStack =>
      ProgramCheck.Preserves checked.entrypoint executable.program coreBefore machineBefore (by
        rw [ripAtEntry]
        exact loaded
          { function := checked.entrypoint.function, image := checked.entrypoint.image }
          (List.mem_map.mpr ⟨checked.entrypoint,
            findEntrypoint_mem checked.entrypointFound, rfl⟩))
        formed textStack returnAddress poppedReturn
  | .direct displacement checked, .direct literal formed layout =>
      let callee := DirectCalleeMode.literalEvidence literal
      (∃ body, checked.caller.body = some body ∧
        Executes executable.program coreBefore body
          (.returned (some (.signed .i32 callee.calleeBits.toInt))) coreBefore) ∧
      ∃ after calleeCount, Machine.Steps (calleeCount + 9)
              machineBefore after ∧
      ((after.registers DirectCallCheck.resultRegister).setWidth 32).toInt =
              callee.calleeBits.toInt ∧
      after.rip = returnAddress ∧
      after.registers DirectCallCheck.stackRegister =
        machineBefore.registers DirectCallCheck.stackRegister + 8 ∧
      after.memory =
        (DirectCallFunctionCheck.callAfterState machineBefore displacement).memory

theorem Authenticated.entrypoint_preserves
    (checked : Authenticated executable image) (coreBefore : Semantics.State)
    (machineBefore : Machine.State)
    (loaded : checked.Loaded machineBefore)
    (environment : PreservationEnvironment checked coreBefore machineBefore)
    (ripAtEntry : machineBefore.rip = checked.entrypoint.image.address)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers 4) = returnAddress) :
    checked.Preserves coreBefore machineBefore loaded environment ripAtEntry
      returnAddress poppedReturn := by
  cases checked with
  | standard checked =>
      cases environment with
      | standard _ _ formed textStack =>
          unfold Authenticated.Preserves
          have loadedStandard := Authenticated.loaded_standard checked machineBefore loaded
          exact checked.entrypoint_preserves coreBefore machineBefore loadedStandard
            formed ripAtEntry textStack returnAddress poppedReturn
  | direct displacement checked =>
      cases environment with
      | direct literal formed layout =>
          let callee := DirectCalleeMode.literalEvidence literal
          unfold Authenticated.Preserves
          rcases checked.callerEvidenceMember with
            ⟨callerEvidence, callerMember, callerFunction, callerImage⟩
          have callerLoaded := loaded
            { function := checked.caller, image := checked.callerImage } (by
              apply List.mem_map.mpr
              exact ⟨callerEvidence, callerMember, by
                simp [callerFunction, callerImage]⟩)
          rcases checked.calleeEvidenceMember with
            ⟨calleeEvidence, calleeMember, calleeFunction, calleeImage⟩
          have calleeLoaded := loaded
            { function := checked.callee, image := checked.calleeImage } (by
              apply List.mem_map.mpr
              exact ⟨calleeEvidence, calleeMember, by
                simp [calleeFunction, calleeImage]⟩)
          have core := directCoreExecutes checked callee coreBefore formed
          have machine := directPreserves checked callee.calleeBits.toInt
            (literalCalleeBridge checked callee) machineBefore ripAtEntry
            (by rw [ripAtEntry]; exact callerLoaded)
            layout calleeLoaded returnAddress poppedReturn
          exact ⟨core, machine⟩

def checkDirectDerivedImages (executable : Execution.Executable) (image : Image)
    (callerImage : FunctionImage) :
    List FunctionImage →
      Option (Σ displacement, DirectChecked executable image displacement)
  | targetImage :: targets =>
      match directDisplacement? callerImage.address targetImage.address with
      | none => checkDirectDerivedImages executable image callerImage targets
      | some displacement =>
          match checkDirect executable image displacement with
          | some checked => some ⟨displacement, checked⟩
          | none => checkDirectDerivedImages executable image callerImage targets
  | [] => none

def checkDirectDerived (executable : Execution.Executable) (image : Image) :
    Option (Σ displacement, DirectChecked executable image displacement) :=
  match findFunctionImage? executable.entrypoint executable.program.functions
      image.functions with
  | none => none
  | some callerEvidence =>
      checkDirectDerivedImages executable image callerEvidence.image image.functions

def checkAuthenticated (executable : Execution.Executable) (image : Image) :
    Option (Authenticated executable image) :=
  match check executable image with
  | some checked => some (.standard checked)
  | none =>
      match checkDirectDerived executable image with
      | none => none
      | some ⟨displacement, checked⟩ => some (.direct displacement checked)

end Lanius.X86.ProgramCheck
