## The local web server: runs `nch` commands named in addresses and shows their pages.
##
## A lightweight server on `127.0.0.1` that interprets the address as a command (`/map?selection=...`) and shows its page, or serves
## a file of the cache (`/files/NAME`).  Any web page open in the browser can send requests to localhost, so the rules are
## strict (`request.nim`, pure, fuzzed): a GET with our own Host header (against DNS rebinding) and the token, in a cookie or
## once in the address; only the commands that packages offer (`web/pages`: the command, its options and flags, a check for each
## value) with only their options, each once; values of the kind a cache file name can hold.  The command runs as
## `nch COMMAND --worker ARGS` in a child process, which makes the files and says which the page is.  The libraries the pages
## load from a CDN, with their integrity hashes, are in `libraries.txt`.  The extension point `web/pages` is defined here; `map`
## and `ff` contribute.

import ../../core/manifest
import ./request

const package* = Package(
  depends: @["args", "bundle", "cache", "childasync", "db", "templating", "ui"],
  fragments: @[],
  defines: @[
    PointDecl(
      name: webPage.name,
      summary:
        "the commands the server may run for a page, and the options they may be given (`map`, `ff`)",
    )
  ],
)
