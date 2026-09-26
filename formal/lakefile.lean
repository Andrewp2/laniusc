import Lake

open Lake DSL

package «lanius-formal» where
  version := v!"0.1.0"

@[default_target]
lean_lib Lanius

lean_exe checkCompact where
  root := `Lanius.Extraction.CheckCompact

lean_exe checkCurrentSourceClosure where
  root := `Lanius.Extraction.CheckCurrentSourceClosure

lean_exe checkCertificate where
  root := `Lanius.Extraction.CheckCertificate

lean_exe checkELFExecution where
  root := `Lanius.Compiler.CheckELFExecution
