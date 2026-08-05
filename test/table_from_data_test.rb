require "./lib/odf-report"
require "tmpdir"

NS = %(xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ) +
     %(xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ) +
     %(xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ) +
     %(xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" ) +
     %(xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0")

failures = 0
check = lambda { |cond, msg| puts(cond ? "PASS: #{msg}" : "FAIL: #{msg}"); failures += 1 unless cond }

# ---------------------------------------------------------------------------
# Builds a minimal .odt with a single placeholder paragraph, runs
# add_table_from_data against it, and returns the resulting content.xml.
# ---------------------------------------------------------------------------
def render(name, data)
  Dir.mktmpdir do |dir|
    src = File.join(dir, "tpl.odt")
    placeholder = "[#{name.to_s.upcase}]"

    Zip::OutputStream.open(src) do |z|
      z.put_next_entry("mimetype"); z.write("application/vnd.oasis.opendocument.text")
      z.put_next_entry("content.xml")
      z.write(%(<?xml version="1.0"?><office:document-content #{NS}>) +
              %(<office:automatic-styles/>) +
              %(<office:body><office:text><text:p>#{placeholder}</text:p></office:text></office:body>) +
              %(</office:document-content>))
      z.put_next_entry("META-INF/manifest.xml")
      z.write(%(<?xml version="1.0"?><manifest:manifest ) +
              %(xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">) +
              %(<manifest:file-entry manifest:full-path="/" ) +
              %(manifest:media-type="application/vnd.oasis.opendocument.text"/></manifest:manifest>))
    end

    out = File.join(dir, "out.odt")
    ODFReport::Report.new(src) { |r| r.add_table_from_data(name, data) }.generate(out)
    Zip::File.open(out) { |z| return z.read("content.xml") }
  end
end

# ---------------------------------------------------------------------------
# 1) Basic table shape: header row, row titles, data rows, column count
# ---------------------------------------------------------------------------
out = render(:tasks,
             contents: [[1, 2, 4], ["res", "2", 1]],
             columns_title: ["A", "B", "C"],
             rows_title: [1, 2],
             table_name: "Test table")
d = Nokogiri::XML(out)

check.(d.errors.empty?, "well-formed output (basic table)")
check.(!out.include?("[TASKS]"), "placeholder paragraph replaced")

table = d.at_xpath("//table:table")
check.(!table.nil?, "table:table element created")
check.(table && table["table:name"] == "Test table", "table name applied")

rows = d.xpath("//table:table/table:table-row")
check.(rows.size == 3, "header row + 2 data rows present (got #{rows.size})")

header_cells = rows[0].xpath("./table:table-cell")
check.(header_cells.size == 4, "header row has corner cell + 3 column titles (got #{header_cells.size})")

data_row_cells = rows[1].xpath("./table:table-cell")
check.(data_row_cells.size == 4, "data row has row-title cell + 3 data cells (got #{data_row_cells.size})")

col_def = d.at_xpath("//table:table/table:table-column")
check.(col_def && col_def["table:number-columns-repeated"].to_s == "4",
       "table:table-column repeats 4 times (3 data cols + 1 title col), got #{col_def && col_def['table:number-columns-repeated']}")

cell_texts = rows[1].xpath("./table:table-cell/text:p").map(&:text)
check.(cell_texts == ["1", "1", "2", "4"], "row title + data values render in order (got #{cell_texts.inspect})")

# ---------------------------------------------------------------------------
# 2) No row/column titles at all -> plain data-only table
# ---------------------------------------------------------------------------
out = render(:plain, contents: [[1, 2], [3, 4]])
d = Nokogiri::XML(out)
rows = d.xpath("//table:table/table:table-row")
check.(rows.size == 2, "no header row when columns_title is absent (got #{rows.size})")
check.(rows[0].xpath("./table:table-cell").size == 2, "no title column when rows_title is absent")

col_def = d.at_xpath("//table:table/table:table-column")
check.(col_def && col_def["table:number-columns-repeated"].to_s == "2",
       "column count matches row width when no titles given")

# ---------------------------------------------------------------------------
# 3) Header cell styling: background color + bold centered text
# ---------------------------------------------------------------------------
out = render(:styled, contents: [[1]], columns_title: ["Only"])
d = Nokogiri::XML(out)
header_cell = d.at_xpath("//table:table/table:table-row[1]/table:table-cell")
style_name = header_cell["table:style-name"]
cell_style = d.at_xpath("//style:style[@style:name='#{style_name}']/style:table-cell-properties")
check.(cell_style && cell_style["fo:background-color"] == "#f0f0f6",
       "header cell gets default header background color")

header_para_style = d.at_xpath("//table:table/table:table-row[1]/table:table-cell/text:p")["text:style-name"]
para_style = d.at_xpath("//style:style[@style:name='#{header_para_style}']/style:text-properties")
check.(para_style && para_style["fo:font-weight"] == "bold",
       "header text style is bold")

# ---------------------------------------------------------------------------
# 4) Data cells with no cells_attributes get the plain default cell style
# ---------------------------------------------------------------------------
out = render(:defaults, contents: [[1, 2]])
d = Nokogiri::XML(out)
data_cell = d.at_xpath("//table:table/table:table-row[1]/table:table-cell[1]")
check.(data_cell["table:style-name"] == "TableBorderCell",
       "data cell without cells_attributes uses the default border style")

# ---------------------------------------------------------------------------
# 5) Per-cell custom style via cells_attributes
# ---------------------------------------------------------------------------
out = render(:custom,
             contents: [[1, 2], [3, 4]],
             cells_attributes: {
               [0, 0] => { style: "text-align:center;vertical-align:middle" }
             })
d = Nokogiri::XML(out)

first_cell = d.at_xpath("//table:table/table:table-row[1]/table:table-cell[1]")
custom_para_style_name = first_cell.at_xpath("./text:p")["text:style-name"]
custom_para = d.at_xpath("//style:style[@style:name='#{custom_para_style_name}']/style:paragraph-properties")
check.(custom_para && custom_para["fo:text-align"] == "center", "custom per-cell paragraph style applied")

untouched_cell = d.at_xpath("//table:table/table:table-row[1]/table:table-cell[2]")
check.(untouched_cell["table:style-name"] == "TableBorderCell",
       "cells not listed in cells_attributes keep the default style")


# ---------------------------------------------------------------------------
# 6) column count now accounts for the longest row, not just the
#    first row (previously ragged rows would overflow the declared columns)
# ---------------------------------------------------------------------------
out = render(:ragged, contents: [[1, 2], [1, 2, 3, 4]])
d = Nokogiri::XML(out)
col_def = d.at_xpath("//table:table/table:table-column")
declared = col_def ? col_def["table:number-columns-repeated"].to_i : 0
longest_row_cells = d.xpath("//table:table/table:table-row[2]/table:table-cell").size
check.(declared == longest_row_cells,
       "column count matches the longest row (declared #{declared}, longest row has #{longest_row_cells} cells)")

# ---------------------------------------------------------------------------
# 7) empty/missing contents leaves the placeholder untouched instead
#    of replacing it with an empty table
# ---------------------------------------------------------------------------
out = render(:empty, {})
check.(!out.include?("[EMPTY]"), "placeholder is left untouched when contents is missing")
d = Nokogiri::XML(out)
check.(d.at_xpath("//table:table").nil?, "no table:table element is created when contents is missing")

out = render(:empty_array, contents: [])
check.(!out.include?("[EMPTY_ARRAY]"), "placeholder is left untouched when contents is an empty array")

abort("\n#{failures} failure(s)") unless failures.zero?
puts "\nOK (#{failures} failures)"