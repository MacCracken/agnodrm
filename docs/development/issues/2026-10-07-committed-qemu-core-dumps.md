# Four qemu core dumps are committed to the repository

Filed 2026-10-07 from the cyrius 6.6.20 closeout (information only; nothing in cyrius waits on it).

`git ls-files | grep '\.core$'` lists four `qemu_repro_*_2026050*.core` files (~9.5 MB each, ~38 MB
total), committed in `1344fb1` ("bite 1; json") and carried by every tag since 1.1.12. Every
`cyrius deps` checkout of agnodrm therefore carries them — `~/.cyrius/deps/agnodrm/{1.5.1,1.6.0,1.6.2}`
each hold all four.

Suggested fix: `git rm` the four files, add `*.core` (or `qemu_*.core`) to `.gitignore`, and cut a
patch release so consumers' dep caches stop downloading them.
