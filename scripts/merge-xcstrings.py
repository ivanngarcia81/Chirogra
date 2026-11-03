# Fusión a tres bandas de App/Localizable.xcstrings por clave (choques de git entre ramas que añaden textos).
# Uso: python3 scripts/merge-xcstrings.py base.json nuestra.json suya.json App/Localizable.xcstrings
# Las tres versiones salen de: git show ":1:App/Localizable.xcstrings" (base), ":2:" (nuestra), ":3:" (suya).
# Si una clave cambió en las dos ramas gana «suya» y se lista para revisarla a mano.
import json, sys
base, ours, theirs = (json.load(open(p, encoding='utf-8')) for p in sys.argv[1:4])
b, o, t = base['strings'], ours['strings'], theirs['strings']
res, conflicts = {}, []
for k in sorted(set(b) | set(o) | set(t)):
    bv, ov, tv = b.get(k), o.get(k), t.get(k)
    if ov == tv: v = ov
    elif ov == bv: v = tv
    elif tv == bv: v = ov
    else:
        conflicts.append(k); v = tv  # cambiados en los dos: gana el último en fusionarse
    if v is not None: res[k] = v
out = dict(ours); out['strings'] = res
s = json.dumps(out, ensure_ascii=False, indent=2, separators=(',', ' : '))
open(sys.argv[4], 'w', encoding='utf-8').write(s + '\n')
print('claves:', len(res), 'conflictos:', conflicts)
