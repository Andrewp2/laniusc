# Slang atomic exchange reproduction

`repro.slang` is an eight-line compiler reproduction, not a dispatched test.
The installed Slang 2026.2 compiler receives `-target spirv -profile glsl_450
-emit-spirv-directly -minimum-slang-optimization` and either `-O0` or `-O1`.
Exact commands and outcomes are in `results.json`.

- At `-O0`, compilation succeeds, but `spirv-val --target-env vulkan1.2` rejects
  an undefined result ID. Disassembly shows a store instead of an atomic exchange.
- At `-O1`, this compiler exits with SIGSEGV.

The same consumed-result operation made the catalog atom and implementation
index artifacts invalid. Loading the latter crashed in the NVIDIA SPIR-V driver;
the parent directory retains its backtrace and validator output.

The catalog uses compare-and-swap publication instead. Each index row publishes
once, preventing ABA. The total active row count bounds insertion attempts,
including an initial miss against a head from an earlier dispatch chunk. Readers
run only after the complete insertion phase, so publishing a head before its
link is safe. This avoids changing the external shader compiler.
