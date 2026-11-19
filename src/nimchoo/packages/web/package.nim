## The local web server: runs `nch` commands named in addresses and shows their pages.
##
## A lightweight server on `127.0.0.1` that interprets the address as a command (`/map/activities`, `/map/activities?frame=heat`) and shows its page, or serves
## a file of the cache (`/files/NAME`): the pages and their data are made in the cache directory's `user/` part (by default
## `~/.cache/nch/user/`; `nch packages --config` says where the cache is).  Any web page open in the browser can send requests to localhost, so the rules are
## strict (`request.nim`, pure, fuzzed): a GET with our own Host header (against DNS rebinding) and the token, in a cookie or
## once in the address; only the commands that packages offer (`web/pages`: the command, its options and flags, a check for each
## value) with only their options, each once; values of the kind a cache file name can hold.  The command runs as
## `nch COMMAND --worker ARGS` in a child process, which makes the files again from the data as they are (a view is live: nothing is
## pinned in an address) and says which the page is.  The commands serve their pages by default; `--file` makes the files only.
## Every page is served by one server (`launch.nim`): the first `nch map` (or `nch ff`) serves and stays running (in a terminal of
## its own, or with `&`); a later one finds it (`/status`, which answers only to the token in an `X-Nch-Token` header, never
## to a page's cookie), opens its page there and returns; `--start` starts the server without opening the browser, `--stop`
## stops it from anywhere (`/stop`).  The libraries the pages
## load from a CDN, with their integrity hashes, are in `libraries.txt` (built in, beside this file, and kept in the cache's
## `system/` part, where it can be edited).  The extension point `web/pages` is defined here; `map`
## and `ff` contribute.

import ../../core/manifest
import ./request

const package* = Package(
  depends:
    @["args", "bundle", "cache", "childasync", "db", "templating", "ui", "version"],
  fragments: @[],
  defines: @[
    PointDecl(
      name: webPage.name,
      summary:
        "the commands the server may run for a page, and the options they may be given (`map`, `ff`)",
    )
  ],
)
