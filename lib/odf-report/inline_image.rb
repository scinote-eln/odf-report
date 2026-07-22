module ODFReport

  # Inserts an image at a *text* placeholder (e.g. [PHOTO]), without requiring
  # a pre-existing draw:frame/draw:image in the template.
  #
  # It reuses Image's file-embedding and manifest-registration machinery: an
  # InlineImage is stored in the same `images` collection as Image, so the
  # binary is copied into Pictures/ and registered in META-INF/manifest.xml by
  # the existing Report#include_images pipeline. The only thing this class does
  # differently is *build* the draw:frame at the placeholder instead of
  # locating one by name.
  #
  #   report.add_inline_image(:photo, "/path/to/photo.png", width: "4cm", height: "3cm")
  #   report.add_inline_image(:photo, "/path/to/photo.png", width: 200, height: 150)      # pixels
  #   report.add_inline_image(:photo, "/path/to/photo.png", width: "200px", dpi: 72)
  #
  # In the template, simply type the placeholder where the image should appear:
  #
  #   Employee photo: [PHOTO]
  #
  # Options:
  #   :width   - frame width  (default "3cm")
  #   :height  - frame height (default "3cm")
  #             Accepts either an ODF length string with an explicit unit
  #             (cm, mm, in, pt, pc) which is passed through unchanged, OR a
  #             pixel value — a Numeric (200), a "200px" string, or a bare
  #             numeric string ("200") — which is converted to centimetres.
  #             (ODF/LibreOffice do not reliably honour "px" for frame sizes,
  #             so pixels are converted rather than emitted verbatim.)
  #   :dpi     - resolution used to convert pixels -> cm (default 96)
  #   :anchor  - text:anchor-type: "as-char" (default, flows inline in the text),
  #              "char", "paragraph" or "page"
  #   :style   - optional draw:style-name referencing a graphic style already
  #              defined in the template (omitted by default; LibreOffice then
  #              applies its default graphic style)
  #
  class InlineImage < Image

    DEFAULT_WIDTH  = "3cm".freeze
    DEFAULT_HEIGHT = "3cm".freeze
    DEFAULT_ANCHOR = "as-char".freeze
    DEFAULT_DPI    = 96
    CM_PER_INCH    = 2.54

    UNIT_LENGTH = /\A\s*([\d.]+)\s*(cm|mm|in|pt|pc)\s*\z/i
    PIXELS      = /\A\s*([\d.]+)\s*(?:px)?\s*\z/i

    def initialize(opts, &block)
      @dpi    = (opts[:dpi] || DEFAULT_DPI).to_f
      @width  = to_length(opts[:width])  || DEFAULT_WIDTH
      @height = to_length(opts[:height]) || DEFAULT_HEIGHT
      @anchor = opts[:anchor] || DEFAULT_ANCHOR
      @style  = opts[:style]
      super
    end

    # Mirrors Field#replace!: operate on the serialized markup and swap the
    # placeholder for a freshly built draw:frame. Using a gsub block gives each
    # occurrence a unique draw:name (ODF frame names must be unique) and lets a
    # single placeholder appear in any text context, inline with surrounding
    # text.
    def replace!(doc)
      file = @data_source.value
      replaced = false

      markup = doc.inner_html
      new_markup = markup.gsub(to_placeholder) do
        replaced = true
        file ? frame_xml(file) : ""
      end

      return unless replaced

      doc.inner_html = new_markup
      @files << file if file
    end

    private

    # Normalize a dimension into an ODF length string.
    #   nil                              -> nil (caller applies default)
    #   Numeric (200)                    -> pixels -> cm
    #   "200px" / "200"                  -> pixels -> cm
    #   "4cm" / "50mm" / "2in" / "12pt"  -> passed through unchanged
    def to_length(value)
      return nil if value.nil?
      return px_to_cm(value) if value.is_a?(Numeric)

      case value.to_s
      when UNIT_LENGTH then "#{$1}#{$2.downcase}"
      when PIXELS      then px_to_cm($1.to_f)
      else value.to_s
      end
    end

    def px_to_cm(pixels)
      cm = pixels.to_f / @dpi * CM_PER_INCH
      "#{cm.round(4)}cm"
    end

    def frame_xml(file)
      href  = self.class.image_href(file)
      name  = SecureRandom.uuid
      style = @style ? %( draw:style-name="#{@style}") : ""

      %(<draw:frame#{style} draw:name="#{name}" ) +
        %(text:anchor-type="#{@anchor}" ) +
        %(svg:width="#{@width}" svg:height="#{@height}" draw:z-index="0">) +
        %(<draw:image xlink:href="#{href}" xlink:type="simple" ) +
        %(xlink:show="embed" xlink:actuate="onLoad"/>) +
        %(</draw:frame>)
    end

  end
end
