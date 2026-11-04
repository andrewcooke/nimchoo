## The licence notice (NOTICE: the data and libraries the program carries and their licences), kept
## as a file in the cache's `system/` part so that it can be read.  Nothing reads it back.

import ./unpack

{.push raises: [].}

const noticeBundle* = Bundle(name: "NOTICE", data: staticRead("../../../NOTICE"))

proc unpackNotice*(top: string) =
  ## Put NOTICE in `top`'s `system/` part, if it is not already there.
  discard resolve(top, noticeBundle)
