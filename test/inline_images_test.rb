require "./lib/odf-report"
require "tmpdir"

# Self-contained test (no launchy/visual inspection needed): builds a minimal
# .odt with a text placeholder, inserts an image with add_inline_image, and
# verifies the generated document contains the frame, the embedded binary and
# the manifest entry.

NS = <<~NS.strip
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
  xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
  xmlns:xlink="http://www.w3.org/1999/xlink"
NS

def content_xml(body)
  %(<?xml version="1.0"?><office:document-content #{NS}>) +
    %(<office:body><office:text>#{body}</office:text></office:body></office:document-content>)
end

failures = 0
check = lambda do |cond, msg|
  puts(cond ? "PASS: #{msg}" : "FAIL: #{msg}")
  failures += 1 unless cond
end

# --- unit: placeholder inline in surrounding text -------------------------
doc = Nokogiri::XML(content_xml("<text:p>Photo: [PHOTO] (today)</text:p>"))
ODFReport::InlineImage.new(name: :photo, value: "/dir/photo.png", width: "4cm", height: "3cm").replace!(doc)

check.(!doc.at_xpath("//draw:frame").nil?, "draw:frame inserted at text placeholder")
check.(doc.at_xpath("//draw:frame")["text:anchor-type"] == "as-char", "anchored inline (as-char)")
check.(doc.at_xpath("//draw:image")["xlink:href"] == "Pictures/photo.png", "href points to Pictures/")
check.(doc.to_xml.include?("Photo:") && doc.to_xml.include?("(today)"), "surrounding text preserved")

# --- unit: dimension handling (pixels, units, defaults) -------------------
def frame_dims(opts)
  d = Nokogiri::XML(content_xml("<text:p>[PHOTO]</text:p>"))
  ODFReport::InlineImage.new({name: :photo, value: "/d/p.png"}.merge(opts)).replace!(d)
  f = d.at_xpath("//draw:frame")
  [f["svg:width"], f["svg:height"]]
end

check.(frame_dims(width: "4cm", height: "3cm") == ["4cm", "3cm"], "explicit cm passed through")
check.(frame_dims(width: "2in", height: "12pt") == ["2in", "12pt"], "other ODF units passed through")
check.(frame_dims({}) == ["3cm", "3cm"], "defaults to 3cm x 3cm")
check.(frame_dims(width: 96, height: 96) == ["2.54cm", "2.54cm"], "96px @ 96dpi -> 2.54cm")
check.(frame_dims(width: "200px", height: "150px") == ["5.2917cm", "3.9688cm"], "px strings converted @96dpi")
check.(frame_dims(width: "300", height: "300") == ["7.9375cm", "7.9375cm"], "bare numeric string treated as px")
check.(frame_dims(width: 96, dpi: 72) == ["3.3867cm"] + [frame_dims(width: 96, dpi: 72)[1]], "custom dpi affects conversion")
check.(frame_dims(width: 72, dpi: 72)[0] == "2.54cm", "72px @ 72dpi -> 2.54cm")

# --- unit: nil value removes the placeholder ------------------------------
doc_nil = Nokogiri::XML(content_xml("<text:p>x [PHOTO] y</text:p>"))
ODFReport::InlineImage.new(name: :photo, value: nil).replace!(doc_nil)
check.(doc_nil.at_xpath("//draw:frame").nil? && !doc_nil.to_xml.include?("[PHOTO]"),
       "nil value removes placeholder, inserts no frame")

# --- end to end: full generate against a minimal template -----------------
Dir.mktmpdir do |dir|
  src = File.join(dir, "tpl.odt")
  Zip::OutputStream.open(src) do |z|
    z.put_next_entry("mimetype"); z.write("application/vnd.oasis.opendocument.text")
    z.put_next_entry("content.xml"); z.write(content_xml("<text:p>My photo: [PHOTO]</text:p>"))
    z.put_next_entry("META-INF/manifest.xml")
    z.write(%(<?xml version="1.0"?><manifest:manifest ) +
            %(xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">) +
            %(<manifest:file-entry manifest:full-path="/" ) +
            %(manifest:media-type="application/vnd.oasis.opendocument.text"/></manifest:manifest>))
  end

  out = File.join(dir, "out.odt")
  ODFReport::Report.new(src) do |r|
    r.add_inline_image(:photo, "test/templates/images/image_1.jpg", width: "5cm", height: "4cm")
  end.generate(out)

  Zip::File.open(out) do |zip|
    content  = zip.read("content.xml")
    manifest = zip.read("META-INF/manifest.xml")
    check.(content.include?("draw:frame") && content.include?("Pictures/image_1.jpg"),
           "generated content.xml has frame + image href")
    check.(!zip.find_entry("Pictures/image_1.jpg").nil?, "image binary embedded under Pictures/")
    check.(manifest.include?("Pictures/image_1.jpg") && manifest.include?("image/jpeg"),
           "manifest entry added with correct media-type")
  end
end

abort("\n#{failures} failure(s)") unless failures.zero?
puts "\nOK (#{failures} failures)"
