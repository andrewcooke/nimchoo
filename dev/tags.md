
i'd like to add a new package that supports tags.  tags are small text
labels associated with the data, and the motivating example here is
tracking the bike model used.

(an aside here; an adversarial review ended up - if i understood
correctly - questioning the more general implicit selection.  it amde
some good arguments, which basically remove --all and add --within,
but it doesn't change much below, except that, kind-of related, i have
modified the discussion on editing tags).

tags can contain letters, digits, "-", "_" and ":" (no idea how that
carries across to unicode, but it would be nice to support accents),
and while i expect them to be small i don't see any need to specify an
upper size limit.  below i will assume that "foo:bar" syntax inside a
tag names key/value pair, but i think this is only a convention
(doesn't need to be enforced or parsed in code).

the tags package will exist at a low level because it will be used by
a wide variety of tasks (typically to select data, where it will act
transitively - tags are defined on activities, but apply to the
associated efforts, for example).

presumably there will be a table that associates tag value with
activity id.

when importing data, we should support importing from a path that
includes tag templates:

  nch import ~/fit/{bike}/{}.fit

will import, for example, a file at ~/fit/cotic/foo.fit with two tags,
once "bike:cotic" and the other "foo".  the import spec will also
allow "*" between directory separators implying "all".

(there are subtle details that i am not specifying that will need to
be ironed out).

the importer also sets tags.  we need to define these based on fits
file fields, but activity type (sport) might be one, for example.  and
if we currently allow selection on those fields then that is dropped
and replaced with tag-based selection.

tags are not - despite what i said earlier - editable objects, because
they do not have a set of attributes to modify.  but their interface
is as similar to editable objects as possible.  so they can be
selected with --name, but they may also be restricted by the current
activity selection if --within is given.  and they can be deleted or
added, but they are renamed, not edited (previous discussion had
--edit --rename, but it seems to me that just --rename would be
sufficient).

commands like activities and climbs will take --tags parameter as an
additional parameter, with space-separated values that support '*', so
--tags "bike:*" will match all activities with a tag starting with
"bike:".

in the future i suspect we might need some kind of mini language and
logic (and/or), but for now selection with multiple tags is "and".  we
could maybe support "or" by allowing "the current selection" to be
appended (this is --also, post adversarial review).

tags will need displaying in various places; there's a new style
called tag.

tags are also important for the upcoming ff work.

notes from previous discussion:

* sport could be handled as sport:cycling:road
  (tagname:sport:sub-sport)

* no a:b value for a tag means no tag at all (eg no sport in fits
  means no sport: tag)

* you suggested sport:latest, but i am not sure that is necessary (i
  can't imaging using it; if it does seem necessary after testsing we
  can add it later).

* no tags for climbs (they are not activities).  but presumably
  efforts (subsections of activities) would inherit the tags from
  their parent activities.

* themes will define a tag syle (although it is not an error if they
  do not) that will be used in the same way as other styles.


---

## Decided (with the author, 2026-11-22)

* **Selection** (after an adversarial review of "the selection as the default for everything", refined 2026-11-23): a
  search looks at everything; what it lists is found in steps, written in the usage: 1. all; 2. `--within`: only the
  selection; 3. the filters ("and"); 4. `--newest`/`--oldest`; 5. `--also`: the selection added; 6. shown;
  7. `--select`: the selection replaced by it.  `--select` has one meaning (what is listed is the selection now);
  `--within` and `--also` are modifiers (alone they show without keeping: a preview); `--save` is gone.  `--all` stays:
  with no criteria step 2 is taken, and `--all` says not to.  For every command that selects (activities, climbs, tags,
  a future efforts).
* **A tag**: letters (accents too), digits, `-`, `_` and `:`; it does not start with `-` (it would read as an option).
  `key:value` is a convention only.  Matching ignores case and accents, as `--names` does; `*` matches anything
  (`--tags 'bike:*'`, quoted for the shell); several tags are "and".
* **Sport as a tag**: `sport:cycling:road`, or `sport:cycling` when the sub-sport is none or "generic"; no sport, no tag.
  `--sports` and `--sub-sports` go (`--tags 'sport:cycling*'`, `--tags 'sport:*:road'`); `sport:latest` is not needed
  now.  The list's last line keeps its count by sport (when there are several), from the tags, ignoring the sub-sport.
  The sport is the only tag taken from the FIT files for now (the device, sensors and profile names were looked at and
  are not interesting).
* **Tags given by hand** are lost when the database is rebuilt: nch is a command-line tool, and whoever wants a set of
  tags scripts it (`~/rebuild.sh`) and runs it again after an import.  No file of tags kept beside the database.
* **Import paths with templates**: `nch import '~/fit/{bike}/*/{}.fit'` (quoted: the program expands `~` and `*`):
  `{name}` gives `name:VALUE`, `{}` gives `VALUE` (of a file name, its stem), `*` matches anything and gives no tag.  An
  import only adds tags.
* **`nch tags`**: not an editable object (no attributes) but as like one as possible: the tags with their counts,
  `--names` patterns to choose them, `--within` to count those of the selection; `--add TAG...` and `--delete TAG...` on
  the activities that criteria give, or the selection (`--delete` asks); `--rename OLD NEW`.
* **Climbs have no tags** (they are not activities); efforts inherit their activity's tags (a future `nch efforts`).
* **The `tag` style**: reverse video, setting no colour, so that a tag in a selected row is reverse video in the
  selection's colour (styles stack: `[select, tag]`); `alt-tag` comes with it, as every style's alt does.  A theme may
  leave it out.
* **Where the package goes**: above `importer` (the table refers to activities); the import step writes the tags
  (the heart rate's mechanism), `--tags` is contributed to `activities` (as `--climbs` is).
