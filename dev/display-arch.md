
# Display Architecture

## Aim

This doument will sketch how nimchoo *should* approach display,
showing a possible architecture that works within the existing package
structure and inter-operates with system state.

## Motivation

Current development is increasingly trapped in managing state without
any clear direction - at one point AI was arguing for two
contradictory approaches.  Taking a step back, much of the work seems
to be driven by the choice to make bookmarks a reproducible "snapshot"
(aka "pinned") - an early decision, given without much thought to the
consequences.

So this document explores an alternaive approach in the hope of (1)
setting a clear direction and (2) reducing the churn in development.

## Architecture

### Selections, Views and URLs

The system is structured around data grouped into **subjects** -
*activities*, *climbs*, **FF statistics** etc.  Each subject is
relatively self-contained and independent, although there are obvious
cross-cutting concerns.

The system is stateful.  Each subject has a current **selection** that
defines the data of interest.  Examples of selections include: all
climbs near a certain city; the latest activity; FF statistics
tailored to measure anaerobic exercise.  And, of course, there's the
rest of the database, full of state.

We can display subjects in different **views**.  For examples: maps;
(line) plots; calendars.

When we generate a view of a subject we display data in the subject's
current selection.  If the current selection changes then the view -
when regenerated - will change too (this is called "live views" by the
AI, as opposed to the previous "pinned views").

Commands have a strong separation of responsibilities: some commands
generate views, other commands manipulate selections.  So, for
example, we may use the `activities` command to select a particular
group of activities and then the `map` command to generate a map
containing those activities.  The arguments for the `map` command will
be concerned solely with aesthetics of display - the choice of
activities displayed has previously been fixed by `activities`.

Given the orthogonality, subjects must be registered with views.  The
package that "manages" a subject will do this via an extension point
on the view.

Some views use web browsers to generate complex user experiences.
These URLs associated with the pages displayed have a close
correspondence to the view command used.  Web browser can "bookmark"
these URLs, reifying a particular set of view options.  Since the view
options do not affect selection, the display generated for a
particular bookmark will change over time to reflect changes in the
selection (or any other relevant state), but it will always have the
same aesthetics.

### Views, Frames and Extension Points

Different views expect the data to be framed in different ways.  A map
presents layers of spatial data; a plot contains lines of (x, y) data;
a calendar shows a daily sequence.  These different ways of grouping
data are different types of **frames**.

Views are subject-agnostic; they present extension points that accept
particular frame types.  Frames are subject-specific; packages can
register the ability to provide frames (we call these packages frame
providers) and each registration will be for a particular subject.
But note that, in the case of a package that is a frame provider *and*
manages a subject's selection, the subject used in the registration
need not be the same as the subject managed.

For example, the climbs package may register with the map view the
ability to provide data frames for the climbs subject.  In that case
it will provide spatial data showing the climbs in the current
selection of climbs.  But it may also register for the activities
subject and, in that context, will provide spatial data for climbs
associated with the current selection of activities.  In this second
case we say the climbs are providing support.  In other words, in some
frames, subjects can take on a supporting (or secondary), rather than
a primary role - a frame may have a primary and a secondary subject.

A view command is invoked - a view is generated - for a particular
subject.  So we can have a map of activities, a plot of FF statistics,
a calendar of activity dates.  Views allow the user to select from the
available frames.  So a map of activities may, or may not, include the
climbs frame for those activities.

Secondary *selections* are ignored - they play no part in the view of
the primary selection.

### Caching

It is normal for data to be cached to improve efficiency.  Caching is
the responsibility of the frame provider.

When using a cache we need to know if the cache is still valid, or if
the frame needs to be recreated.  We can do this by associating a
frame with a key - an existing frame with the same key can be reused
(assuming hashes are large enough to avoid collisions).  So when a
frame is requested we calculate the frame's key, see if a cache is
available and, if not, generate a new frame.

The key for a frame is generated by combining some combination of:

* The key for the primary selection

* The key for any secondary subject instances used in the frame

* The key for any additional information from the database that affect
  the frame.  Implicitly, this may include the program version.

* A key that identifies the frame itself, to avoid collision with
  another frame that has exactly th esame data.

Which keys are used depends on the frame - only keys that correspond
to information that changes the frame are combined.

I have oscillated on whether it is useful to expose the generated
files and/or have a view command that does only this.  Currently I
believe that:

* Exposing the files for display in a third party tool is useful (as
  now).

* That the files can exposed via the cache (as now).

* That the files will presumably be named with some prefix and the
  associated key (currently we prettify names, which we can drop)

* The default view command should generate the web display (ie
  equivalent to `map --web` now); the version to generate files only
  should be `map --file` (in other words, swapped).

## Implementation

### FF Statistics

The FF statistics support used here is more complex than that
currently available.  It assumes that there are various statistics
available and that particular statistics can be selected in a similar
way to the selection of other subjects.

### Data Ownership

In general, only data owned by the current user are displayed.  The
exception is "global" data that combines - without selection - data
from all users.  So climbs are constructed from all user activities, a
global heatmap is constructed from all user's activities, etc.

Review recommends treating global data as a separate type of frame (ie
distinct from the same data constructed from a selection).  This
simplifies the user interface (afaik it is not critical, just a useful
implementation detail).

### Backwards Compatibility

There is no need to worry about preserving information in existing
databases or existing bookmarks.

### Frame Styling

I don't understand the web data flow in detail, but it seems
reasonable that this is set by the frmae provider.  It would be nice
if the file appeared in the cache and could be user edited (as now?).
It would also be nice if it could somehow be tweaked in the view, but
I suspect that is difficult and don't want to get into specifying it
here.

### Hashes

Typically an instance of a subject - a particular activity, say - is a
row in a table in the database.  This row contains the data asociated
with the subject.  It could also contains a key column, which is a
hash of the data in the rest of the row (or a similar value could be
calculated on the fly).  The key for a collection of instances - the
selection, for example - can then be calculated by combining the keys
for each member of the collection.

Review suggests using a "last modified" column and hashing that with
the rowid (assuming auto-increment), which is functionally equivalent
to the hash described above, but more efficient.

Review also suggest using SHA-256 to combine, mentioning that xor is
not available in SQL and that it is not secure when combining two
equal values (as might occur if the implementation of a view with no
secondary subject that uses the convention that secondary and primary
subject are identical).  I have no strong preference on the details of
hash key generation (as long as it works) and leave it to the
implementator.

### Inverted Dependency Example

The examples above have tended to be "easy cases" where the secondary
subject package depends on the primary (eg climbs for activities).
But what happens (in the less common case) when we invert this
relationship?

Consider showing activities that use the selected climbs.  We have
selected the climbs we are interested in and now we use the map
command.

It is impossible for the activities layer to have registered an
extension to provide a frame containing activities for a given climb -
the activities package precedes the climbs package and so it "knows"
nothing of climbs.  Instead, this frame provider must be registered by
the climbs package.

To accurately cache this frame the key must be generated from (1) the
selection of climbs (known to the climbs package) and (2) the
activities that use those climbs.  The climbs contains the logic to
select the activities - exactly how the key is calculated depends on
the implementation (either the climbs package uses the keys in the
activity table, or it asks the activity package to do the
calculation).



to consider

3. **Register subjects once, not with each view.** If each view
   defines a point for subjects, the package that manages a subject
   contributes to every view: `activities` would depend on `map`, the
   plot view and `calendar`, and a new view would mean editing every
   subject's package.  Better: **one point, `subjects`** (name, owner,
   how to get the selection, and the key of any set of its items),
   defined by a small package below the views, which every view reads.
   Frames stay per view (or per frame type, if two views ever share
   one).  Either way the direction of the dependencies turns round:
   the views become low packages (on `web`, `ui`, `cache`), and the
   data packages, as providers, sit above them.
