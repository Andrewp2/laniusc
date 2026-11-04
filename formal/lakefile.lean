import Lake

open Lake DSL

package «lanius-formal» where
  version := v!"0.1.0"
  leanOptions := #[⟨`experimental.module, true⟩]
  -- Share build outputs between worktrees: a module whose inputs match one
  -- built anywhere is restored from Lake's cache instead of rebuilt.
  enableArtifactCache := true
  restoreAllArtifacts := true

@[default_target]
lean_lib Lanius

/-- The mini compiler pilot (see MINI_COMPILER.md). -/
lean_lib LaniusMini where
  globs := #[.submodules `Lanius.Mini]

/-- Open statements, their reductions and proofs (OPEN_STATEMENTS.md): the
gate builds the whole library. -/
lean_lib LaniusOpen where
  -- each area but Cert, which is LaniusCert's (add a new area here)
  globs := #[.one `Lanius.Open, .submodules `Lanius.Open.F5, .submodules `Lanius.Open.F14]

/-- The certificate checker (formal/cert/, check_mini.lani) through the
verified compiler, and its soundness through the open statements under
Lanius.Open.Cert. Nothing in Lanius, LaniusMini or LaniusOpen imports it, so
an edit here or to check_mini.lani rebuilds only this library. -/
lean_lib LaniusCert where
  globs := #[.submodules `Lanius.Cert, .submodules `Lanius.Open.Cert]

/-- The precondition tactic (`pre_auto`, `post_auto`), compiled to native code
so the generated SelfPre/GenP proofs do not run it in the interpreter. It
imports only Lean and HBAttr; declared after `Lanius` so it owns these
modules (Lake takes the last library that matches). -/
lean_lib LaniusTactic where
  roots := #[`Lanius.Faithful.SelfPre.Tactic]
  precompileModules := true

/-- The `hb_simp` attribute and the tactic's options, which the tactic and
SelfPre/HB import: a library of its own, so HB need not wait for the tactic's
native code. -/
lean_lib LaniusHBAttr where
  roots := #[`Lanius.Faithful.SelfPre.HBAttr]
  precompileModules := true

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

/-- The x86 model's decode and execute, compiled, for formal/tools/x86_model_test.py. -/
lean_exe x86ModelTest where
  root := `Lanius.Tools.X86ModelTest

/-- The top theorems' axioms and statement hashes, for formal/tools/trusted_check.py. -/
lean_exe topAxioms where
  root := `Lanius.Tools.TopAxioms

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
