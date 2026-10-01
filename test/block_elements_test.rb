require "./lib/odf-report"
require "tmpdir"

NS = %(xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ) +
     %(xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ) +
     %(xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ) +
     %(xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" ) +
     %(xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0")

failures = 0
check = lambda { |cond, msg| puts(cond ? "PASS: #{msg}" : "FAIL: #{msg}"); failures += 1 unless cond }

# Renders `body` as the office:text of a minimal .odt and returns the
# office:text node of the generated document.
def render(body, styles = "")
  Dir.mktmpdir do |dir|
    src = File.join(dir, "tpl.odt")
    Zip::OutputStream.open(src) do |z|
      z.put_next_entry("mimetype"); z.write("application/vnd.oasis.opendocument.text")
      z.put_next_entry("content.xml")
      z.write(%(<?xml version="1.0"?><office:document-content #{NS}>) +
              %(<office:automatic-styles>#{styles}</office:automatic-styles>) +
              %(<office:body><office:text>#{body}</office:text></office:body></office:document-content>))
      z.put_next_entry("META-INF/manifest.xml")
      z.write(%(<?xml version="1.0"?><manifest:manifest ) +
              %(xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">) +
              %(<manifest:file-entry manifest:full-path="/" ) +
              %(manifest:media-type="application/vnd.oasis.opendocument.text"/></manifest:manifest>))
    end
    out = File.join(dir, "out.odt")
    ODFReport::Report.new(src) { |r| yield r }.generate(out)
    Zip::File.open(out) { |z| return Nokogiri::XML(z.read("content.xml")).at_xpath("//office:text") }
  end
end

def paragraphs(text) = text.xpath("./text:p").map(&:text)

ITEMS = [["one", true], ["two", false]].freeze

# 1) Checklist inside a styled span next to other text is split out of it
out = render(%(<text:p>Intro <text:span text:style-name="B">bold [CL] tail</text:span> end</text:p>)) do |r|
  r.add_checklist(:cl, ITEMS)
end
check.(paragraphs(out) == ["Intro bold ", "☑ one", "☐ two", " tail end"],
       "checklist in span becomes own paragraphs (got #{paragraphs(out).inspect})")
check.(out.xpath("./text:p[1]/text:span[@text:style-name='B']").text == "bold ", "span style kept before the checklist")
check.(out.xpath("./text:p[4]/text:span[@text:style-name='B']").text == " tail", "span style kept after the checklist")

# 2) Checklist placeholder alone in a span leaves no empty paragraph behind
out = render(%(<text:p text:style-name="P1"><text:span>[CL]</text:span></text:p>)) { |r| r.add_checklist(:cl, ITEMS) }
check.(paragraphs(out) == ["☑ one", "☐ two"], "sole span placeholder replaced by items only")
check.(out.xpath("./text:p").map { |p| p["text:style-name"] } == %w[P1 P1-cont],
       "first checklist item keeps the paragraph style, the next continues it")

# 3) Several paragraphs of text inside a span are kept as paragraphs
out = render(%(<text:p><text:span>[T]</text:span></text:p>)) { |r| r.add_text(:t, "<p>a</p><p>b</p>") }
check.(paragraphs(out) == ["a", "b"], "multi-paragraph text in span is not flattened (got #{paragraphs(out).inspect})")

# 4) A single paragraph still renders inline next to other text
out = render(%(<text:p>Tags: [T]!</text:p>)) { |r| r.add_text(:t, "<p>x, <strong>y</strong></p>") }
check.(paragraphs(out) == ["Tags: x, y!"], "single paragraph stays inline (got #{paragraphs(out).inspect})")

# 5) ...unless it's added with display: :block
out = render(%(<text:p>Notes: [T] end</text:p>)) { |r| r.add_text(:t, "<p>x</p>", display: :block) }
check.(paragraphs(out) == ["Notes: ", "x", " end"], "display: :block splits the paragraph (got #{paragraphs(out).inspect})")

# 6) An empty value only removes the placeholder
out = render(%(<text:p>A [T] B</text:p>)) { |r| r.add_text(:t, "", display: :block) }
check.(paragraphs(out) == ["A  B"], "empty value doesn't split the paragraph (got #{paragraphs(out).inspect})")

# 7) Every occurrence in a paragraph is replaced
out = render(%(<text:p>[CL] and [CL]</text:p>)) { |r| r.add_checklist(:cl, [["x", true]]) }
check.(paragraphs(out) == ["☑ x", " and ", "☑ x"], "all occurrences replaced (got #{paragraphs(out).inspect})")

# 8) A table inside a span, after-text gets the continuation style
styles = %(<style:style style:name="P1" style:family="paragraph" style:master-page-name="First"/>)
out = render(%(<text:p text:style-name="P1">Before <text:span>[TB] after</text:span></text:p>), styles) do |r|
  r.add_table_from_data(:tb, contents: [[1, 2]])
end
check.(out.xpath("./*").map(&:name) == %w[p table p], "table is split out of the span (got #{out.xpath('./*').map(&:name).inspect})")
check.(out.at_xpath("./text:p[2]")["text:style-name"] == "P1-cont", "text after the table uses the continuation style")
cont = out.document.at_xpath("//style:style[@style:name='P1-cont']")
check.(cont && cont["style:master-page-name"].nil?, "continuation style drops the master page")

# 9) Only the first part keeps a page break / master page, the rest continue
styles = %(<style:style style:name="PB" style:family="paragraph" style:master-page-name="MP0">) +
         %(<style:paragraph-properties fo:break-before="page"/><style:text-properties fo:color="#ff0000"/></style:style>)
out = render(%(<text:p text:style-name="PB">a [TB] b [TB] c</text:p>), styles) do |r|
  r.add_table_from_data(:tb, contents: [[1]])
end
check.(out.xpath("./*").map { |n| n["text:style-name"] || n.name } == %w[PB table PB-cont table PB-cont],
       "parts after the first use the continuation style (got #{out.xpath('./*').map { |n| n['text:style-name'] || n.name }.inspect})")
cont = out.document.at_xpath("//style:style[@style:name='PB-cont']")
check.(cont["style:master-page-name"].nil? && cont.at_xpath("./style:paragraph-properties")["fo:break-before"] == "auto",
       "continuation style drops the master page and the page break")
check.(cont.at_xpath("./style:text-properties")["fo:color"] == "#ff0000", "continuation style keeps the rest of the style")
check.(cont.element_children.map(&:name) == %w[paragraph-properties text-properties], "paragraph properties come first")

# 10) A common style (not in content.xml) gets a continuation style inheriting it
out = render(%(<text:p text:style-name="Standard">a [TB] b</text:p>)) { |r| r.add_table_from_data(:tb, contents: [[1]]) }
cont = out.document.at_xpath("//style:style[@style:name='Standard-cont']")
check.(cont && cont["style:parent-style-name"] == "Standard" && cont["style:family"] == "paragraph" &&
       cont.at_xpath("./style:paragraph-properties")["fo:break-before"] == "auto",
       "continuation style of a common style is defined and inherits it")

# 11) Chaining: a replacement may re-emit its own placeholder for the next one
out = render(%(<text:p><text:span>[P]</text:span></text:p>)) do |r|
  r.add_text(:p, "<div>1. Step</div><div>[P]</div>")
  r.add_text(:p, "<div>Checklist</div><div>[P_CL]</div><div>[P]</div>")
  r.add_checklist(:p_cl, ITEMS)
  r.add_text(:p, "")
end
check.(paragraphs(out) == ["1. Step", "Checklist", "☑ one", "☐ two"],
       "chained replacements render as separate paragraphs (got #{paragraphs(out).inspect})")

# 12) Invalid display values are rejected
begin
  ODFReport::Text.new(name: :x, value: "", display: :inline_block)
  check.(false, "invalid display raises")
rescue ArgumentError
  check.(true, "invalid display raises")
end

abort("\n#{failures} failure(s)") unless failures.zero?
puts "\nOK (#{failures} failures)"
