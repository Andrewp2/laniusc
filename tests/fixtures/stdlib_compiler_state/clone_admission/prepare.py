"""Create isolated intended-module stdlib classification controls; test only."""
from pathlib import Path
import shutil

repo = Path(__file__).resolve().parents[4]
source = Path(__file__).resolve().parent
work = repo / 'target/stdlib-work/clone-admission'
stdlib = work / 'overlay-stdlib'
user = work / 'overlay-user'
if stdlib.exists() or user.exists():
    raise SystemExit('overlay paths already exist; preserve them as evidence')
shutil.copytree(repo / 'stdlib', stdlib)
(user / 'probe').mkdir(parents=True)
protocol = (source / 'probe/protocol.lani').read_text().replace('probe::protocol','core::clone')
(stdlib / 'core/clone.lani').write_text(protocol)
helper = (source / 'probe/vec_clone.lani').read_text().replace('probe::vec_clone','alloc::clone').replace('probe::protocol','core::clone')
(stdlib / 'alloc/clone.lani').write_text(helper)
owner = (source / 'probe/owners.lani').read_text()
begin = owner.index('pub impl probe::protocol::TryClone<alloc::string::String')
end = owner.index('pub impl probe::protocol::TryClone<Pair')
owner = owner[:begin] + owner[end:]
(user / 'probe/owners.lani').write_text(owner.replace('probe::protocol','core::clone'))
string = stdlib / 'alloc/string.lani'
string.write_text(string.read_text() + '''
// Isolated admission extension, never written to the production stdlib.
pub impl core::clone::TryClone<String,Error> for String {
    pub fn try_clone_value(source: String) -> core::result::Result<String,Error> { return source.try_clone(); }
}
pub impl core::clone::Destroy<String> for String {
    pub fn destroy_value(owned: String) { owned.destroy(); }
}
''')
string.write_text(string.read_text().replace('module alloc::string;','module alloc::string;\nimport core::clone;'))
for name in ('main.lani','generic_return.lani','fixed_error.lani','direct.lani'):
    code = (source / name).read_text().replace('probe::protocol','core::clone').replace('probe::vec_clone','alloc::clone')
    (user / name).write_text(code)
print(stdlib)
print(user)
