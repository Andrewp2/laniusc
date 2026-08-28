import Lanius.Extraction.ArtifactContextChecker
import Lanius.Extraction.ParseChecker
import Lanius.Extraction.CoreChecker
import Lanius.Extraction.CoreTypingChecker
import Lanius.Extraction.EvidenceStructureChecker
import Lanius.Extraction.SurfaceElaborationChecker
import Lanius.Extraction.SurfaceChecker
import Lanius.Extraction.SurfaceReconstruct
import Lanius.Extraction.ArtifactQuote

namespace Lanius.Extraction

set_option maxRecDepth 100000

def verifiedDigitsSourceText : String :=
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "digits.lani"

def verifiedDigitsSourceBytes : List Nat :=
  verifiedDigitsSourceText.toUTF8.toList.map UInt8.toNat

def verifiedDigitsArtifact : Artifact :=
  artifact% (include_str "Artifacts" / "digits.json")

theorem verifiedDigitsArtifact_checked :
    checkParseArtifact verifiedDigitsArtifact = true := by
  native_decide

/-- This theorem deliberately depends on both checked-in files. If the Lanius
    source changes without regenerating its artifact, the formal build fails. -/
theorem verifiedDigitsArtifact_tracks_source :
    verifiedDigitsArtifact.sources.map (·.bytes) = [verifiedDigitsSourceBytes] := by
  native_decide

theorem verifiedDigitsArtifact_valid :
    ParseArtifactValid verifiedDigitsArtifact :=
  checkParseArtifact_sound verifiedDigitsArtifact_checked

def verifiedDigitsSurface : Option Surface.File :=
  decodeReconstructedSurface verifiedDigitsArtifact

/-- Lean's source-tracked reconstruction decodes into the formal Surface AST;
    semantic elaboration never consumes the exporter's proposal directly. -/
theorem verifiedDigitsSurface_decodes : verifiedDigitsSurface.isSome = true := by
  native_decide

theorem verifiedDigitsSurface_reconstructs :
    surfaceReconstructionMatches verifiedDigitsArtifact = true := by
  native_decide

def verifiedDigitsArtifactWithWrongSurfaceRoot : Artifact :=
  match verifiedDigitsArtifact.surface with
  | none => verifiedDigitsArtifact
  | some surface => {
      verifiedDigitsArtifact with
      surface := some { surface with id := surface.id + 1 }
    }

theorem verifiedDigitsSurface_rejects_exporter_disagreement :
    checkSurfaceArtifact verifiedDigitsArtifactWithWrongSurfaceRoot = false := by
  native_decide

theorem verifiedDigitsSurface_checked :
    checkSurfaceArtifact verifiedDigitsArtifact = true := by
  native_decide

/-- A node with the right production is still rejected when its claimed
    grammatical container does not contain it. This guards against reducing
    Surface origins to a production-number-only check. -/
theorem verifiedDigitsSurface_rejects_false_containment :
    nodeClaimValid verifiedDigitsArtifact {
      id := 26
      parseNode := 57
      containingParseNode := some 58
      allowedProductions := [173]
    } = false := by
  native_decide

theorem verifiedDigitsSurface_valid : SurfaceArtifactValid verifiedDigitsArtifact :=
  checkSurfaceArtifact_sound verifiedDigitsSurface_checked

/-- The checked-in source-derived Core proposal is accepted only after both
    structural decoding and the existing Core typing judgment succeed. -/
theorem verifiedDigitsExtractedCore_well_typed :
    CoreTyping.checkCoreArtifactTyping verifiedDigitsArtifact = true := by
  native_decide

theorem verifiedDigitsEvidenceStructure_checked :
    checkEvidenceStructure verifiedDigitsArtifact = true := by
  native_decide

def verifiedDigitsArtifactWithForwardTypePremise : Artifact :=
  match verifiedDigitsArtifact.types with
  | [] => verifiedDigitsArtifact
  | head :: tail => {
      verifiedDigitsArtifact with
      types := { head with premises := [verifiedDigitsArtifact.types.length] } :: tail
    }

theorem verifiedDigitsEvidenceStructure_rejects_forward_type_premise :
    checkEvidenceStructure verifiedDigitsArtifactWithForwardTypePremise = false := by
  native_decide

def verifiedDigitsArtifactWithoutFirstLoweringRow : Artifact := {
  verifiedDigitsArtifact with lowering := verifiedDigitsArtifact.lowering.drop 1
}

theorem verifiedDigitsEvidenceStructure_rejects_incomplete_core_coverage :
    checkEvidenceStructure verifiedDigitsArtifactWithoutFirstLoweringRow = false := by
  native_decide

def verifiedDigitsWholeProgramSemanticallyChecked : Bool :=
  (ArtifactContextChecker.checkArtifactProgram? verifiedDigitsArtifact).isSome

/-! The complete source-derived `digits.lani` program receives its names,
nominal layout, fields, function signatures, and monomorphic instances from
the reconstructed Surface/Core pair. -/
theorem verifiedDigitsWholeProgram_semantically_checked :
    verifiedDigitsWholeProgramSemanticallyChecked = true := by
  native_decide

def verifiedDigitsArtifactWithMismatchedScanReturn : Artifact :=
  match verifiedDigitsArtifact.core_program with
  | none => verifiedDigitsArtifact
  | some program => {
      verifiedDigitsArtifact with
      core_program := some {
        program with
        functions := program.functions.map fun function =>
          if function.id = 6 then
            { function with return_type := .scalar (.signed .i32) }
          else function
      }
    }

theorem verifiedDigitsWholeProgram_rejects_mismatched_scan_signature :
    (ArtifactContextChecker.checkArtifactProgram?
      verifiedDigitsArtifactWithMismatchedScanReturn).isSome = false := by
  native_decide

def verifiedDigitsArtifactWithMismatchedStructLayout : Artifact :=
  match verifiedDigitsArtifact.core_program with
  | none => verifiedDigitsArtifact
  | some program => {
      verifiedDigitsArtifact with
      core_program := some {
        program with
        structures := program.structures.map fun row =>
          if row.id = 0 then
            { row with fields := [.scalar (.signed .i32),
                .scalar (.signed .i32), .scalar (.signed .i32)] }
          else row
      }
    }

theorem verifiedDigitsWholeProgram_rejects_mismatched_struct_layout :
    (ArtifactContextChecker.checkArtifactProgram?
      verifiedDigitsArtifactWithMismatchedStructLayout).isSome = false := by
  native_decide

def verifiedDigitsCoreShape : CoreProgram := {
  target := { pointer_width := .bits64 }
  structures := []
  enumerations := []
  constants := []
  functions := [{
    id := 0
    parameters := []
    return_type := .unit
    body := some { id := 0, value := .skip }
    external := none
  }]
}

def verifiedDigitsArtifactWithCoreShape : Artifact := {
  verifiedDigitsArtifact with core_program := some verifiedDigitsCoreShape
}

theorem verifiedDigitsCoreShape_checked :
    checkCoreStructure verifiedDigitsArtifactWithCoreShape = true := by
  native_decide

theorem verifiedDigitsCoreShape_well_typed :
    CoreTyping.checkCoreArtifactTyping verifiedDigitsArtifactWithCoreShape = true := by
  native_decide

def verifiedDigitsArtifactWithWrongFunctionReturn : Artifact := {
  verifiedDigitsArtifact with
  core_program := some {
    verifiedDigitsCoreShape with
    functions := [{
      id := 0
      parameters := []
      return_type := .scalar (.signed .i32)
      body := some { id := 0, value := .skip }
      external := none
    }]
  }
}

theorem verifiedDigitsCoreTyping_rejects_wrong_function_return :
    CoreTyping.checkCoreArtifactTyping
      verifiedDigitsArtifactWithWrongFunctionReturn = false := by
  native_decide

def verifiedDigitsArtifactWithMissingCallee : Artifact := {
  verifiedDigitsArtifact with
  core_program := some {
    verifiedDigitsCoreShape with
    functions := [{
      id := 0
      parameters := []
      return_type := .unit
      body := some {
        id := 1
        value := .expression {
          id := 0
          value := .call 99 []
        }
      }
      external := none
    }]
  }
}

theorem verifiedDigitsCoreTyping_rejects_missing_callee :
    CoreTyping.checkCoreArtifactTyping
      verifiedDigitsArtifactWithMissingCallee = false := by
  native_decide

def verifiedDigitsArtifactWithDuplicateCoreNode : Artifact := {
  verifiedDigitsArtifact with
  core_program := some {
    verifiedDigitsCoreShape with
    functions := [{
      id := 0
      parameters := []
      return_type := .unit
      body := some {
        id := 1
        value := .sequence
          { id := 0, value := .skip }
          { id := 0, value := .skip }
      }
      external := none
    }]
  }
}

theorem verifiedDigitsCoreShape_rejects_reused_node_identity :
    checkCoreStructure verifiedDigitsArtifactWithDuplicateCoreNode = false := by
  native_decide

def verifiedDigitsArtifactWithTruncatedFloatBits : Artifact := {
  verifiedDigitsArtifact with
  core_program := some {
    verifiedDigitsCoreShape with
    constants := [{
      id := 0
      ty := .scalar .f32
      value := .f32_bits (2 ^ 32)
    }]
  }
}

theorem verifiedDigitsCoreShape_rejects_noncanonical_machine_bits :
    checkCoreStructure verifiedDigitsArtifactWithTruncatedFloatBits = false := by
  native_decide

end Lanius.Extraction
