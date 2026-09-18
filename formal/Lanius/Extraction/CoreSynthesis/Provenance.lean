import Lanius.Extraction.EntrypointAnalysis

namespace Lanius.Extraction.CoreSynthesis.Program

/-- Reuse a certified lowering and typing result when source reconstruction
supplies those exact units. The original synthesis entry point is unchanged. -/
theorem synthesize_of_lowered
    (surfaceData : ArtifactPackChecker.CheckedUnitSurfaces artifacts)
    (decoded : decodeUnitsFrom 0 surfaceData = some units)
    (loweredFound : lowerUnits? units = some lowered)
    (typed : CoreTyping.checkProgram lowered.core = some typing) :
    synthesize? surfaceData = some ({ lowered with
      surfaceData := surfaceData
      typed := typing.proof } : CheckedProgram artifacts) := by
  simp [synthesize?, decoded, loweredFound, typed]

/-- Algorithmic provenance of the entire accepted program, including its
declaration context, layouts, and constants. This is stronger than merely
having a well-typed Core program and lowered functions. It does not replace
the separate semantic preservation obligation for source-to-Core lowering. -/
def SourceBound (checked : CheckedCompactCoreSourcePack encoded sources) : Prop :=
  checkCompactCoreSourcePack encoded sources = .success checked

/-- Compose retained stages into the authoritative source-checker result,
without executing lowering or typing again. Every premise is a checked stage
equation; in particular the reconstructed units remain bound to source bytes. -/
theorem sourceBound_of_lowered
    (surface : CheckedCompactSurfaceSourcePack encoded sources)
    (sourceFound : checkCompactSurfaceArtifactPackSources? encoded sources = some surface)
    (decoded : decodeUnitsFrom 0 surface.surfaceData = some units)
    (loweredFound : lowerUnits? units = some lowered)
    (typed : CoreTyping.checkProgram lowered.core = some typing) :
    SourceBound ⟨surface, { lowered with
      surfaceData := surface.surfaceData, typed := typing.proof }⟩ := by
  obtain ⟨prepared, preparedFound, result⟩ := Option.bind_eq_some_iff.mp loweredFound
  have lowering : lowerPrepared prepared = .ok lowered := by
    cases found : lowerPrepared prepared <;> simp_all [Except.toOption]
  simp [SourceBound, checkCompactCoreSourcePack, sourceFound, prepare?, decoded,
    preparedFound, lowering, typed]

private theorem lowerPrepared_metadata
    (found : lowerPrepared prepared = .ok lowered) :
    lowered.prepared = prepared ∧ lowered.core.structures = prepared.structures := by
  unfold lowerPrepared finishLowering at found
  repeat first | split at found | dsimp only at found | contradiction
  all_goals cases found; exact ⟨rfl, rfl⟩

/-- Recover the source relationships the original Core record did not retain.
The successful checker equation supplies them without recomputing preparation
or synthesis, and binds constants through the complete construction as well. -/
theorem SourceBound.metadata {checked : CheckedCompactCoreSourcePack encoded sources}
    (bound : SourceBound checked) :
    checked.program.surfaceData = checked.surface.surfaceData ∧
      prepare? checked.program.surfaceData = some checked.program.prepared ∧
      checked.program.core.structures = checked.program.prepared.structures := by
  unfold SourceBound checkCompactCoreSourcePack at bound
  repeat first | split at bound | contradiction
  all_goals
    cases bound
    obtain ⟨rfl, structures⟩ := lowerPrepared_metadata (by assumption)
    exact ⟨rfl, by assumption, structures⟩

/-- Even a well-typed replacement cannot be substituted for any part of the
program. Both certificates for the same exact inputs must have the same Core,
including all constants, structures, functions, and target information. -/
theorem SourceBound.unique {left right : CheckedCompactCoreSourcePack encoded sources}
    (first : SourceBound left) (second : SourceBound right) : left = right := by
  exact CoreSourcePackCheck.success.inj (first.symm.trans second)

end Lanius.Extraction.CoreSynthesis.Program

namespace Lanius.Extraction.EntrypointAnalysis

/-- Extractor entrypoint analysis preserves the generic source checker's
result. No independent Core program may be attached to the accepted source. -/
theorem sourceBound {accepted : CheckedExtractorCoreSourcePack encoded sources}
    (produced : checkExtractorCoreSourcePack encoded sources = .success accepted) :
    CoreSynthesis.Program.SourceBound accepted.checked := by
  unfold checkExtractorCoreSourcePack at produced
  repeat first | split at produced | contradiction
  all_goals cases produced; assumption

end Lanius.Extraction.EntrypointAnalysis
