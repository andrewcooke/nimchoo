import std/[strutils, unittest]
import nimchoo/templating

proc r(source: string, values: openArray[(string, Value)] = []): string =
  render(source, context(values))

proc failsWith(source: string, values: openArray[(string, Value)] = []): string =
  ## The message of the TemplateError that filling in the template gives ("" if none).
  try:
    discard render(source, context(values))
  except TemplateError as e:
    return e.msg

suite "templating: values":
  test "text without tags is as it is":
    check r("") == ""
    check r("plain text\nover two lines\n") == "plain text\nover two lines\n"
    check r("braces { and } and }} are text, and so is { {") ==
      "braces { and } and }} are text, and so is { {"
    check r("js: f({ a: 1 }, [{b: 2}])") == "js: f({ a: 1 }, [{b: 2}])"
  test "a name is replaced, and escaped for HTML":
    check r("a {{x}} b", {"x": text("1")}) == "a 1 b"
    check r("{{x}}", {"x": text("<b>\"R&D\"</b>")}) ==
      "&lt;b&gt;&quot;R&amp;D&quot;&lt;/b&gt;"
    check htmlEscape("<>&\"") == "&lt;&gt;&amp;&quot;"
  test "three braces or an ampersand: as it is":
    check r("{{{x}}} {{&x}}", {"x": text("<b>&")}) == "<b>& <b>&"
  test "spaces inside a tag do not matter":
    check r("{{  x }}{{{ x   }}}{{& x }}", {"x": text("v")}) == "vvv"
  test "a flag shows as true or false, for use in a script":
    check r(
      "const on = {{{f}}}; const off = {{{g}}};", {"f": flag(true), "g": flag(false)}
    ) == "const on = true; const off = false;"
  test "the same name twice, several names, names with - and _":
    check r("{{a-b}}{{c_d}}{{a-b}}", {"a-b": text("1"), "c_d": text("2")}) == "121"
  test "a value is put in once: what it holds is not looked at again":
    check r("{{x}}", {"x": text("{{y}}")}) == "{{y}}"

suite "templating: sections":
  test "a flag":
    check r("[{{#f}}yes{{/f}}]", {"f": flag(true)}) == "[yes]"
    check r("[{{#f}}yes{{/f}}]", {"f": flag(false)}) == "[]"
    check r("[{{^f}}no{{/f}}]", {"f": flag(false)}) == "[no]"
    check r("[{{^f}}no{{/f}}]", {"f": flag(true)}) == "[]"
  test "a text counts as true if it is not empty":
    check r("{{#t}}some: {{t}}{{/t}}{{^t}}none{{/t}}", {"t": text("x")}) == "some: x"
    check r("{{#t}}some: {{t}}{{/t}}{{^t}}none{{/t}}", {"t": text("")}) == "none"
  test "a list: the part is repeated for each item, which has values of its own":
    let items = list(
      @[context({"n": text("1")}), context({"n": text("2")}), context({"n": text("3")})]
    )
    check r("{{#l}}<{{n}}>{{/l}}", {"l": items}) == "<1><2><3>"
    check r("{{#l}}x{{/l}}{{^l}}empty{{/l}}", {"l": list(@[])}) == "empty"
    check r("{{^l}}empty{{/l}}", {"l": items}) == ""
  test "inside an item, what the item lacks is looked for around it; the item's own wins":
    let items =
      list(@[context({"n": text("1")}), context({"n": text("2"), "who": text("item")})])
    check r("{{#l}}{{n}}:{{who}} {{/l}}", {"l": items, "who": text("page")}) ==
      "1:page 2:item "
  test "sections inside sections":
    let v = {"a": flag(true), "b": flag(false), "c": flag(true)}
    check r("{{#a}}A{{#b}}B{{/b}}{{^b}}b{{/b}}{{#c}}C{{/c}}{{/a}}", v) == "AbC"
    check r("{{#b}}{{#a}}X{{/a}}{{/b}}.", v) == "."
  test "an inverted section on a name that is not there is an error, like any name":
    check failsWith("{{^nothing}}x{{/nothing}}").contains("no value called 'nothing'")

suite "templating: lines of their own":
  test "a section's tags on lines of their own leave no blank lines":
    let t = "a\n{{#f}}\nb\n{{/f}}\nc\n"
    check r(t, {"f": flag(true)}) == "a\nb\nc\n"
    check r(t, {"f": flag(false)}) == "a\nc\n"
  test "indented tags and comments too":
    check r("a\n  {{#f}}  \n  b\n  {{/f}}\n{{! a comment }}\nc\n", {"f": flag(true)}) ==
      "a\n  b\nc\n"
  test "at the start and the end of the template":
    check r("{{#f}}\nb\n{{/f}}", {"f": flag(true)}) == "b\n"
    check r("{{! x }}\nrest") == "rest"
  test "a tag with other text on its line is not on a line of its own":
    check r("x {{#f}}y{{/f}} z\n", {"f": flag(true)}) == "x y z\n"
    check r("{{#f}}y{{/f}}\n", {"f": flag(true)}) == "y\n"
    check r("a{{! c }}b") == "ab"
  test "a variable on a line of its own keeps the line":
    check r("a\n{{x}}\nb\n", {"x": text("1")}) == "a\n1\nb\n"
  test "a list of items on lines of their own":
    let items = list(@[context({"n": text("1")}), context({"n": text("2")})])
    check r("<ul>\n{{#l}}\n<li>{{n}}</li>\n{{/l}}\n</ul>\n", {"l": items}) ==
      "<ul>\n<li>1</li>\n<li>2</li>\n</ul>\n"

suite "templating: mistakes are errors, with the line":
  test "a name nothing has":
    check failsWith("a\nb\n{{nope}}\n") == "line 3: there is no value called 'nope'"
    check failsWith("{{#f}}\n{{nope}}\n{{/f}}", {"f": flag(true)}) ==
      "line 2: there is no value called 'nope'"
    check failsWith("{{nope}}", {"x": text("")}).contains("'nope'")
  test "a tag that is not closed":
    check failsWith("a {{x").contains("a tag is not closed")
    check failsWith("a\n{{{x}}").startsWith("line 2: a tag is not closed")
  test "a bad name":
    check failsWith("{{}}").contains("is not a name")
    check failsWith("{{a b}}").contains("'a b' is not a name")
    check failsWith("{{a.b}}").contains("is not a name")
  test "sections that do not match":
    check failsWith("{{#a}}x", {"a": flag(true)}).contains("{{#a}} is never closed")
    check failsWith("x{{/a}}", {"a": flag(true)}).contains("closes nothing")
    check failsWith("{{#a}}{{#b}}{{/a}}{{/b}}", {"a": flag(true), "b": flag(true)})
      .contains("closes {{#b}}")
    check failsWith("\n\n{{#a}}x", {"a": flag(true)}).startsWith("line 3:")
  test "a list cannot be shown as a tag":
    check failsWith("{{l}}", {"l": list(@[])}).contains("is a list")
  test "the error is a kind of NchError":
    expect NchError:
      discard render("{{x", context(newSeq[(string, Value)]()))
