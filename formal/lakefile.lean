import Lake

open Lake DSL

package «lanius-formal» where
  version := v!"0.1.0"

@[default_target]
lean_lib Lanius

lean_exe «lanius-check-extraction» where
  root := `Lanius.Extraction.Main

/-- Lake supplies the built dependency graph; load each library after its
dependencies, once. Paths and platform suffixes come from Lake, not conventions. -/
private partial def appendLibraries (library : Dynlib) (seen : Std.HashSet String)
    (order : Array Dynlib) : Std.HashSet String × Array Dynlib := Id.run do
  if seen.contains library.name then return (seen, order)
  let (seen, order) := (library.deps ++ library.runtimeOnlyDeps).foldl
    (fun (seen, order) dependency => appendLibraries dependency seen order)
    (seen.insert library.name, order)
  return (seen, order.push library)

/-- Rebuild the driver when needed, then execute its checked code with native
checker dependencies. Only the driver is reused: each input is validated anew.
This runs IO tests and does not create a kernel acceptance certificate. -/
private def runChecked (driverName : Lean.Name) (nativeModules : Array Lean.Name)
    (args : Array String) : ScriptM UInt32 := do
  let some driver ← findModule? driverName
    | throw (IO.userError s!"validation module not found: {driverName}")
  let resources ← nativeModules.mapM fun name => do
    let some resource ← findModule? name
      | throw (IO.userError s!"native checker module not found: {name}")
    pure resource
  let libraries ← runBuild (cfg := { verbosity := .quiet }) do
    let checked ← driver.leanArts.fetch
    let mut ready ← checked.mapM fun _ => pure (#[] : Array Dynlib)
    for resource in resources do
      let native ← resource.dynlib.fetch
      ready ← ready.bindM fun order => native.mapM fun library => pure (order.push library)
    ready.mapM fun roots => pure (roots.foldl
      (fun (seen, order) library => appendLibraries library seen order) ({}, #[])).2
  let mut leanArgs := (← getLeanArgs)
  for library in libraries do
    leanArgs := leanArgs.push
      ((if library.plugin then "--plugin=" else "--load-dynlib=") ++ library.path.toString)
  let root ← getRootPackage
  let repository := root.dir / ".."
  -- Import the built driver rather than elaborating its unchanged main again.
  -- Supplying this through stdin leaves no import-only files in the repository.
  leanArgs := leanArgs ++ #["--stdin", "--run", driver.leanFile.toString] ++ args
  let process : IO.Process.Child { stdin := .null } ← do
    let (input, process) ← (← IO.Process.spawn {
      cmd := (← getLeanInstall).lean.toString
      args := leanArgs
      env := ← getAugmentedEnv
      stdin := .piped
      cwd := some repository }).takeStdin
    input.putStr s!"import {driver.name}\n"
    input.flush
    pure process
  process.wait

/-- Fresh self-validation, including source binding and parser resources. -/
script «check-self» args do
  unless args.length == 2 do
    IO.eprintln "usage: lake run check-self EMITTED_MODULE PARSER_ENVELOPES"
    return 1
  let sources ← IO.FS.lines ((← getRootPackage).dir / "../verified_compiler/source-closure.txt")
  runChecked `Lanius.Extraction.Tests.Self
    #[`Lanius.Extraction.CompactArtifact, `Lanius.Extraction.Parser.Tree.Bounds.Propose]
    (args.toArray ++ sources)

/-- Source-bound backend execution and mutation checks over the current closure. -/
script «check-backend» args do
  unless args.length == 3 do
    IO.eprintln "usage: lake run check-backend BACKEND FIXTURE_DIRECTORY EMITTED_MODULE"
    return 1
  let sources ← IO.FS.lines ((← getRootPackage).dir / "../verified_compiler/backend-sources.txt")
  runChecked `Lanius.X86.Tests.Frame #[`Lanius.Extraction.CompactArtifact]
    (args.toArray ++ sources)

/-- Native decoding only proposes certificate data. The supplied Lean recipe
specifies the claims to authenticate as ordinary kernel-checked declarations. -/
script «certify» args do
  unless args.length == 2 do
    IO.eprintln "usage: lake run certify RECIPE OUTPUT_OLEAN"
    return 1
  let some reader ← findModule? `Lanius.Extraction.CompactDecode.Reader
    | throw (IO.userError "compact reader module not found")
  let support ← #[`Lanius.Extraction.CompactDecode.Checked,
    `Lanius.Extraction.CompactDecode.Bounded, `Lanius.Extraction.CompactDecode.Indexed,
    `Lanius.Extraction.Surface.Views, `Lanius.Extraction.Surface.Paths,
    `Lanius.Extraction.ArtifactCacheQuote,
    `Lanius.Extraction.KernelReduction, `Lanius.Extraction.Reconstruction.Validated,
    `Lanius.Extraction.Reconstruction.Plan,
    `Lanius.Extraction.Parse.Grammar, `Lanius.Core.Quote,
    `Lanius.Extraction.CoreSynthesis.Provenance].mapM fun name => do
      let some module ← findModule? name
        | throw (IO.userError s!"certificate support module not found: {name}")
      pure module
  let libraries ← runBuild (cfg := { verbosity := .quiet }) do
    let native ← reader.dynlib.fetch
    let mut ready ← native.mapM fun library => pure (appendLibraries library {} #[]).2
    for module in support do
      let checked ← module.leanArts.fetch
      ready ← ready.bindM fun libraries => checked.mapM fun _ => pure libraries
    return ready
  let mut leanArgs := (← getLeanArgs)
  for library in libraries do
    leanArgs := leanArgs.push
      ((if library.plugin then "--plugin=" else "--load-dynlib=") ++ library.path.toString)
  let root ← getRootPackage
  let repository ← IO.FS.realPath (root.dir / "..")
  let environment ← getAugmentedEnv
  let leanPath := ((environment.find? (·.1 == "LEAN_PATH")).bind (·.2)).getD ""
  let environment := (environment.filter (·.1 != "LEAN_PATH")).push
    ("LEAN_PATH", some s!"{repository / "target/verified-compiler"}:{leanPath}")
  let process ← IO.Process.spawn {
    cmd := (← getLeanInstall).lean.toString
    -- Keep certificate checking bounded on hosts with many logical CPUs.
    -- This limits resources, not the proof obligations or kernel trust level.
    args := leanArgs ++ #["-j4", "-M7000", args[0]!, "-o", args[1]!]
    env := environment
    cwd := some repository }
  process.wait
