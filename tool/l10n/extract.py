"""Lists every string passed to tr('...') in lib/, plus labels that are
translated indirectly (categories, enum labels, month and weekday names).
Writes tool/l10n/keys.txt as `number|English` lines."""
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIT = re.compile(r"\btr\(\s*'((?:[^'\\]|\\.)*)'", re.S)


def unescape(s):
    return (s.replace("\\'", "'").replace('\\"', '"').replace('\\$', '$')
             .replace('\\n', '\n').replace('\\\\', '\\'))


keys = []
for path in sorted((ROOT / 'lib').rglob('*.dart')):
    if 'l10n' in path.parts:
        continue
    src = path.read_text()
    keys += [unescape(m.group(1)) for m in LIT.finditer(src)]

models = (ROOT / 'lib/models/models.dart').read_text()
planning = (ROOT / 'lib/models/planning.dart').read_text()
# enum labels: name('Label'),
for src in (models, planning):
    for body in re.findall(r'enum \w+ \{(.*?);', src, re.S):
        keys += re.findall(r"\w+\('([^']+)'\)", body)
# categories
for name in ('expenseCategories', 'incomeCategories'):
    m = re.search(name + r' = \[(.*?)\];', models, re.S)
    keys += re.findall(r"'([^']+)'", m.group(1))
keys += ['January', 'February', 'March', 'April', 'May', 'June', 'July',
         'August', 'September', 'October', 'November', 'December',
         'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
         'Oct', 'Nov', 'Dec', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
         'Sun', 'Amount', 'Bal', 'Owed']

# Keep existing numbers stable: old keys first (in their order), new keys
# appended. Keys no longer used stay listed; they are harmless.
# In keys.txt a newline inside a key is written as the two characters \n.
def decode(k):
    return re.sub(r'\\+n', '\n', k)


def encode(k):
    return k.replace('\n', '\\n')


out, seen = [], set()
existing = ROOT / 'tool/l10n/keys.txt'
if existing.exists():
    for line in existing.read_text().splitlines():
        _, _, k = line.partition('|')
        k = decode(k)
        if k and k not in seen:
            seen.add(k)
            out.append(k)
for k in keys:
    if k not in seen and re.search('[A-Za-z]', k):
        seen.add(k)
        out.append(k)
lines = [f"{i + 1}|{encode(k)}" for i, k in enumerate(out)]
existing.write_text('\n'.join(lines) + '\n')
print(len(out), 'keys')
