import Lanius.Open.F14.PreFrontEndWords.Red1
import Lanius.Open.F14.PreBuildFiles.Proof
import Lanius.Open.F14.ReadFilesHeight.Proof
import Lanius.Open.F14.ValidateFilesHeight.Proof

/-! # `PreFrontEndWords`: by its reduction from `build_files`' precondition and the files' and trees' heights -/

theorem Lanius.Open.PreFrontEndWords.proof : Lanius.Open.PreFrontEndWords :=
  Lanius.Open.PreFrontEndWords.red1 Lanius.Open.PreBuildFiles.proof Lanius.Open.ReadFilesHeight.proof
    Lanius.Open.ValidateFilesHeight.proof
