## The themes in the cache, and which theme is in force.
##
## The themes are files `NAME.theme` in the cache directory's `system/themes/`: the built-in `dark` and `light` (which `ui`
## carries: the names of its styles are those the program uses) are unpacked there (an edited one is kept, a deleted one comes back), and any other file there is a theme too.  The one in force is,
## the first that is given: `--theme NAME`; `$NCH_THEME`; the symbolic link `system/themes/.current`, which the author makes
## (`ln -sf light.theme ~/.cache/nch/system/themes/.current`) and which names a theme in the same directory; `$COLORFGBG`, which
## some terminals set (a light background: `light`); else `dark`.  A theme that cannot be used is warned of, and the
## built-in `dark` is used instead (how text looks is not worth stopping a command for).  The format of the file is in
## `core/theme.nim`; `tools/look.nim` shows what a theme looks like.

import ../../core/manifest

const package* = Package(depends: @["bundle", "cache", "ui"], fragments: @[])
