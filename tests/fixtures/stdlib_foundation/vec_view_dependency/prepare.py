"""Prepare an isolated stdlib copy for the nested view-factory reproduction."""
from pathlib import Path
import shutil
import sys

source_root = Path(__file__).resolve().parents[4]
destination = Path(sys.argv[1]).resolve()
shutil.copytree(source_root / "stdlib", destination)
shutil.copyfile(Path(__file__).with_name("wrapper.lani"), destination / "alloc/extend_wrapper.lani")
if len(sys.argv) > 2 and sys.argv[2] == "--nested-factory":
    vector = destination / "alloc/vec.lani"
    source = vector.read_text()
    direct = """    pub fn as_view(&self) -> core::slice::View<T> {
        // Owned storage already establishes the initialized count.
        return core::slice::View { values: self.as_slice(), start: 0, length: self.length };
    }"""
    nested = """    pub fn as_view(&self) -> core::slice::View<T> {
        return core::result::unwrap(core::slice::view(self.as_slice(), self.length));
    }"""
    assert source.count(direct) == 1, "update the reproduction for the current Vec view constructor"
    vector.write_text(source.replace(direct, nested))
print(destination)
