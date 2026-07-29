require "./lib/odf-report"

failures = 0
check = lambda { |cond, msg| puts(cond ? "PASS: #{msg}" : "FAIL: #{msg}"); failures += 1 unless cond }

# ---------------------------------------------------------------------------
# Builds a bare in-memory ODF-ish document with an office:automatic-styles
# node
# ---------------------------------------------------------------------------
def build_bare_doc
  doc = Nokogiri::XML::Document.new
  root = Nokogiri::XML::Node.new("office:document-styles", doc)
  root.add_namespace_definition("office", "urn:oasis:names:tc:opendocument:xmlns:office:1.0")
  root.add_namespace_definition("style", "urn:oasis:names:tc:opendocument:xmlns:style:1.0")
  doc.root = root
  auto = Nokogiri::XML::Node.new("office:automatic-styles", doc)
  root.add_child(auto)
  [doc, auto]
end

# ---------------------------------------------------------------------------
# 1) Default style is created on initialize
# ---------------------------------------------------------------------------
doc, auto = build_bare_doc
style = ODFReport::Style.new(doc)

check.(!auto.at_xpath(".//style:style[@style:name='TableBorderCell']").nil?,
       "default cell style pre-created on Style.new")

default_props = auto.at_xpath(".//style:style[@style:name='TableBorderCell']/style:table-cell-properties")
check.(default_props && default_props["fo:border"] == "0.75pt solid #000000",
       "default cell style uses the default border")

# ---------------------------------------------------------------------------
# 2) cell_style: caching -- identical css returns the same style, only once
# ---------------------------------------------------------------------------
name1 = style.cell_style("background-color:#ff0000;border-top:1px solid #000000")
name2 = style.cell_style("background-color:#ff0000;border-top:1px solid #000000")
check.(name1 == name2, "identical css string returns the same cached style name")
check.(auto.xpath(".//style:style[@style:name='#{name1}']").size == 1,
       "style node created exactly once even after two calls with identical css")

different_name = style.cell_style("background-color:#00ff00")
check.(different_name != name1, "different css produces a different style name")

# ---------------------------------------------------------------------------
# 3) cell_style: accepts a plain Hash as well as a css String
# ---------------------------------------------------------------------------
hash_name = style.cell_style({ "background-color" => "#123456" })
hash_props = auto.at_xpath(".//style:style[@style:name='#{hash_name}']/style:table-cell-properties")
check.(hash_props && hash_props["fo:background-color"] == "#123456",
       "cell_style accepts a pre-parsed Hash directly")

hash_name_again = style.cell_style({ "background-color" => "#123456" })
check.(hash_name == hash_name_again, "identical Hash input is cached the same way as identical css string")

# ---------------------------------------------------------------------------
# 4) cell_style: already-hex colors pass through unchanged
# ---------------------------------------------------------------------------
bg_name = style.cell_style("background-color:#ff00aa")
bg_props = auto.at_xpath(".//style:style[@style:name='#{bg_name}']/style:table-cell-properties")
check.(bg_props && bg_props["fo:background-color"] == "#ff00aa", "hex background-color carried through unchanged")

# ---------------------------------------------------------------------------
# 5) cell_style: falls back to DEFAULT_BORDER when no border css given
# ---------------------------------------------------------------------------
no_border_name = style.cell_style("background-color:#123456")
no_border_props = auto.at_xpath(".//style:style[@style:name='#{no_border_name}']/style:table-cell-properties")
check.(no_border_props && no_border_props["fo:border"] == "0.75pt solid #000000",
       "cell_style falls back to DEFAULT_BORDER when no border-* css is provided")

# ---------------------------------------------------------------------------
# 6) cell_style: vertical-align passthrough
# ---------------------------------------------------------------------------
valign_name = style.cell_style("vertical-align:middle")
valign_props = auto.at_xpath(".//style:style[@style:name='#{valign_name}']/style:table-cell-properties")
check.(valign_props && valign_props["style:vertical-align"] == "middle", "vertical-align carried through")

# ---------------------------------------------------------------------------
# 7) cell_style(nil) / cell_style with no @auto_styles: should not raise
# ---------------------------------------------------------------------------
check.(style.cell_style(nil) == ODFReport::Style::DEFAULT_CELL_STYLE_NAME,
       "cell_style(nil) falls back to the default style name instead of raising")

no_styles_doc = Nokogiri::XML::Document.new
no_styles_root = Nokogiri::XML::Node.new("office:document-styles", no_styles_doc)
no_styles_doc.root = no_styles_root
headless_style = ODFReport::Style.new(no_styles_doc)
check.(headless_style.cell_style("background-color:red") == ODFReport::Style::DEFAULT_CELL_STYLE_NAME,
       "cell_style returns the default name when the document has no office:automatic-styles")

# ---------------------------------------------------------------------------
# 8) text_style: text-align, font-weight, font-size, font-style
# ---------------------------------------------------------------------------
tname = style.text_style("text-align:center;font-weight:bold;font-size:14pt;font-style:italic")
talign_props = auto.at_xpath(".//style:style[@style:name='#{tname}']/style:paragraph-properties")
ttext_props = auto.at_xpath(".//style:style[@style:name='#{tname}']/style:text-properties")
check.(talign_props && talign_props["fo:text-align"] == "center", "text_style: text-align applied")
check.(ttext_props && ttext_props["fo:font-weight"] == "bold", "text_style: font-weight applied")
check.(ttext_props && ttext_props["fo:font-size"] == "14pt", "text_style: font-size applied")
check.(ttext_props && ttext_props["fo:font-style"] == "italic", "text_style: font-style applied")

# ---------------------------------------------------------------------------
# 9) text_style: accepts a family override (e.g. for non-paragraph contexts)
# ---------------------------------------------------------------------------
family_name = style.text_style("font-weight:bold", "text")
family_node = auto.at_xpath(".//style:style[@style:name='#{family_name}']")
check.(family_node && family_node["style:family"] == "text", "text_style honors the family argument")

# ---------------------------------------------------------------------------
# 10) text_style: text-decoration -> underline / line-through / none
# ---------------------------------------------------------------------------
underline_name = style.text_style("font-weight:bold;text-decoration:underline")
underline_props = auto.at_xpath(".//style:style[@style:name='#{underline_name}']/style:text-properties")
check.(underline_props && underline_props["style:text-underline-style"] == "solid" &&
       underline_props["style:text-underline-type"] == "single",
       "text-decoration:underline sets the ODF underline properties")

strike_name = style.text_style("font-weight:bold;text-decoration:line-through")
strike_props = auto.at_xpath(".//style:style[@style:name='#{strike_name}']/style:text-properties")
check.(strike_props && strike_props["style:text-line-through-style"] == "solid",
       "text-decoration:line-through sets the ODF strike-through property")

# ---------------------------------------------------------------------------
# 11) text_style(nil) / empty string handling
# ---------------------------------------------------------------------------
check.(style.text_style("").nil?, "text_style('') returns nil (no properties to apply)")

begin
  result = style.text_style(nil)
  check.(result.nil?, "REGRESSION: text_style(nil) should return nil instead of raising")
rescue StandardError => e
  check.(false, "REGRESSION: text_style(nil) should return nil instead of raising " \
                "(raised #{e.class}: #{e.message} -- `!style_element.empty?` calls #empty? on nil)")
end

# ---------------------------------------------------------------------------
# 12) normalized_hex_color: named colors, hex passthrough, and rgb() triples
#     (previously broken: the gsub result was computed but never returned)
# ---------------------------------------------------------------------------
converted = style.send(:normalized_hex_color, "red")
check.(converted == "#FF0000", "normalized_hex_color('red') returns '#FF0000' (got #{converted.inspect})")

hex_passthrough = style.send(:normalized_hex_color, "#4682B4")
check.(hex_passthrough == "#4682B4", "normalized_hex_color leaves an already-hex value unchanged")

rgb_input = style.send(:normalized_hex_color, "rgb(255,0,0)")
check.(rgb_input == "#FF0000", "normalized_hex_color converts rgb(...) triples to hex (got #{rgb_input.inspect})")

# ---------------------------------------------------------------------------
# 13) convert_border: only the color token is converted, the width/style
#     portions of the shorthand are left intact
#     (previously broken: the whole string was fed to the digit-scanning
#     fallback, mangling the width into the "color")
# ---------------------------------------------------------------------------
named_border_name = style.cell_style("border-top:1px solid black")
named_border = auto.at_xpath(".//style:style[@style:name='#{named_border_name}']/style:table-cell-properties")["fo:border-top"]
check.(named_border == "0.75pt solid #000000",
       "border-top with a named color renders as a full ODF border spec (width + style + hex color), " \
       "got #{named_border.inspect}")

hex_border_name = style.cell_style("border-top:2px solid #4682B4")
hex_border = auto.at_xpath(".//style:style[@style:name='#{hex_border_name}']/style:table-cell-properties")["fo:border-top"]
check.(hex_border == "1.5pt solid #4682B4",
       "border-top already given as hex still renders as a full ODF border spec, got #{hex_border.inspect}")

abort("\n#{failures} failure(s)") unless failures.zero?
puts "\nOK (#{failures} failures)"
