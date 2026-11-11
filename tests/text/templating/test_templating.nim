import std/[strutils, unittest]
import nimchoo/packages/text/templating/templating

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

suite "templating: lines of their own":
  test "a comment on a line of its own leaves no blank line":
    check r("a\n{{! a comment }}\nc\n") == "a\nc\n"
    check r("a\n  {{! indented }}  \nc\n") == "a\nc\n"
  test "at the start and the end of the template":
    check r("{{! x }}\nrest") == "rest"
    check r("rest\n{{! x }}") == "rest\n"
  test "a comment with other text on its line is not on a line of its own":
    check r("a{{! c }}b") == "ab"
    check r("x {{! c }} z\n") == "x  z\n"
  test "a variable on a line of its own keeps the line":
    check r("a\n{{x}}\nb\n", {"x": text("1")}) == "a\n1\nb\n"

suite "templating: mistakes are errors, with the line":
  test "a name nothing has":
    check failsWith("a\nb\n{{nope}}\n") == "line 3: there is no value called 'nope'"
    check failsWith("{{!\n}}\n{{nope}}") == "line 3: there is no value called 'nope'"
    check failsWith("{{nope}}", {"x": text("")}).contains("'nope'")
  test "a tag that is not closed":
    check failsWith("a {{x").contains("a tag is not closed")
    check failsWith("a\n{{{x}}").startsWith("line 2: a tag is not closed")
  test "a bad name":
    check failsWith("{{}}").contains("is not a name")
    check failsWith("{{a b}}").contains("'a b' is not a name")
    check failsWith("{{a.b}}").contains("is not a name")
  test "the error is a kind of NchError":
    expect NchError:
      discard render("{{x", context(newSeq[(string, Value)]()))
