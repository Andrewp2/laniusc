import Lake

open Lake DSL

package «lanius-formal» where
  version := v!"0.1.0"
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib Lanius

/-- The mini compiler pilot (see MINI_COMPILER.md). -/
lean_lib LaniusMini where
  globs := #[.submodules `Lanius.Mini]

/-- The front end and `compileSource`, compiled, for formal/tools/self_host.py. -/
lean_exe runAll where
  root := `Lanius.Tools.RunAll

/-- The extractor in Lanius, run on a file and laniusc's tree of it. -/
lean_exe extract where
  root := `Lanius.Tools.Extract

/-- The front end's program of some files, for the extraction certificates. -/
lean_exe srcDump where
  root := `Lanius.Tools.SrcDump

/-- The IEEE specification, compiled, for formal/tools/float_test.py. -/
lean_exe floatTest where
  root := `Lanius.Tools.FloatTest

lean_exe checkCompact where
  root := `Lanius.Extraction.CheckCompact

lean_exe checkCurrentSourceClosure where
  root := `Lanius.Extraction.CheckCurrentSourceClosure

lean_exe checkCertificate where
  root := `Lanius.Extraction.CheckCertificate

lean_exe checkELFExecution where
  root := `Lanius.Compiler.CheckELFExecution

-- Native notation is shared infrastructure. The extracted program still goes
-- through ordinary elaboration, kernel checking, compilation, and serialization.
private partial def extractionPluginArgs (lib : Dynlib) :
    StateM (Std.HashSet String × Array String) Unit := do
  if (← get).1.contains lib.name then return
  modify fun (seen, args) => (seen.insert lib.name, args)
  for dependency in lib.deps ++ lib.runtimeOnlyDeps do
    extractionPluginArgs dependency
  let flag := if lib.plugin then "--plugin=" else "--load-dynlib="
  modify fun (seen, args) => (seen, args.push (flag ++ lib.path.toString))

/-- Check or run freshly extracted Lean using the native shared notation. -/
script checkExtraction (args) do
  let args := if args.head? == some "--" then args.tail else args
  let some surfaceModule ← findModule? `Lanius.TypedIR.Surface.Link
    | throw (IO.userError "extraction notation is missing")
  let library ← runBuild surfaceModule.dynlib.fetch
  let plugins := ((extractionPluginArgs library).run ({}, #[])).2.2
  let child ← IO.Process.spawn {
    cmd := (← getLean).toString
    args := plugins ++ args.toArray
    env := ← getAugmentedEnv
  }
  child.wait
