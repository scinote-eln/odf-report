module ODFReport
  # Replaces a placeholder with rich content (HTML parsed by Parser::Default).
  #
  # The replacement is rendered either inline or as blocks:
  #
  #   - inline: a single paragraph whose content is put in place of the
  #     placeholder, so it can sit mid-sentence ("Tags: [TAGS]").
  #   - block: anything else (several paragraphs, lists, tables, checklists), or
  #     any text added with `display: :block`. The paragraph holding the
  #     placeholder is split around it, keeping the formatting of the text on
  #     both sides, and the blocks are inserted in between. Placing them inside
  #     the paragraph (or a span of it) would render them on a single line.
  #
  # Subclasses only build the replacement (#replacement_nodes) and configure
  # the rendering through the options:
  #   :display       - :auto (default) or :block
  #   :inherit_style - blocks take the style of the paragraph they replace
  class Text < Field
    DISPLAYS = %i[auto block].freeze
    PARAGRAPH_ELEMENTS = %w[text:p text:h].freeze
    # Elements that alone don't make a split-off paragraph half worth keeping.
    INSIGNIFICANT_ELEMENTS = %w[text:span text:s text:tab text:line-break text:soft-page-break].freeze
    MARKER = "odf-report-placeholder".freeze
    MARKER_XPATH = ".//*[local-name()='#{MARKER}']".freeze

    def initialize(opts, &block)
      @display = opts.fetch(:display, :auto)
      raise ArgumentError, "display must be one of #{DISPLAYS.inspect}" unless DISPLAYS.include?(@display)

      @inherit_style = opts.fetch(:inherit_style, false)
      super
    end

    def replace!(doc)
      markers = insert_markers(doc)
      return if markers.empty?

      replacement = replacement_nodes(markers.first.document)
      block_markers, inline_markers = markers.partition { |marker| block?(marker, replacement) }

      inline_markers.each { |marker| replace_inline!(marker, replacement) }

      # Deepest paragraphs first, so a paragraph nested in another one (e.g. in
      # a text box) is resolved before its parent gets split and copied.
      block_markers.map { |marker| enclosing_paragraph_of(marker) }.uniq
                   .sort_by { |paragraph| -paragraph.ancestors.size }
                   .each { |paragraph| split_paragraph!(paragraph, replacement) }
    end

    private

    def replacement_nodes(doc)
      Parser::Default.new(@data_source.value, doc).paragraphs
    end

    # Swaps every placeholder occurrence for a marker element, so all of them
    # are located before the document is modified. Placeholders emitted by the
    # replacement itself (e.g. for chaining) are therefore left for later.
    def insert_markers(scope)
      placeholder = to_placeholder

      scope.xpath(".//text()[contains(., '#{placeholder}')]").flat_map do |text|
        parts = text.content.split(placeholder, -1)
        last_part = parts.pop

        markers = parts.map do |part|
          text.add_previous_sibling(Nokogiri::XML::Text.new(part, text.document)) unless part.empty?
          text.add_previous_sibling(Nokogiri::XML::Node.new(MARKER, text.document))
        end

        text.add_previous_sibling(Nokogiri::XML::Text.new(last_part, text.document)) unless last_part.empty?
        text.remove

        markers
      end
    end

    def block?(marker, replacement)
      paragraph = enclosing_paragraph_of(marker)
      return false unless paragraph
      # A paragraph holding nothing but the placeholder is replaced as a whole.
      return true if marker.parent == paragraph && paragraph.children.one?
      return false if replacement.empty?

      @display == :block || !(replacement.one? && qualified_name(replacement.first) == "text:p")
    end

    def replace_inline!(marker, replacement)
      replacement.each do |node|
        children = qualified_name(node) == "text:p" ? node.children : [node]
        children.each { |child| marker.add_previous_sibling(child.dup) }
      end

      marker.remove
    end

    # Replaces the paragraph with its parts around each marker, and a copy of
    # the replacement in place of each marker. Only the first part keeps the
    # paragraph's style, the ones after it continue the paragraph (see
    # #continuation_style).
    def split_paragraph!(paragraph, replacement)
      parts = [] # [node, takes the paragraph's style]
      remainder = paragraph

      while find_marker(remainder)
        before, remainder = split_at_first_marker(remainder)
        parts << [before, true] unless blank_paragraph?(before)
        replacement.each { |node| parts << [node.dup, @inherit_style] }
      end
      parts << [remainder, true] unless blank_paragraph?(remainder)

      style_name = paragraph["text:style-name"]
      parts.each_with_index do |(node, styled), index|
        if styled && style_name
          node["text:style-name"] = index.zero? ? style_name : continuation_style(paragraph.document, style_name)
        end
        paragraph.add_previous_sibling(node)
      end

      paragraph.remove
    end

    # Returns copies of the paragraph with everything after, and everything
    # before the first marker. Ancestors of the marker (spans) are neither
    # following nor preceding it, so they wrap the text on both sides.
    def split_at_first_marker(paragraph)
      before = paragraph.dup
      marker = find_marker(before)
      marker.xpath("following::node()").each(&:remove)
      marker.remove

      after = paragraph.dup
      marker = find_marker(after)
      marker.xpath("preceding::node()").each(&:remove)
      marker.remove

      [before, after].each { |half| remove_empty_spans!(half) }
    end

    # Reverse document order visits nested spans before their parents.
    def remove_empty_spans!(paragraph)
      paragraph.xpath(".//*").reverse_each do |node|
        node.remove if qualified_name(node) == "text:span" && node.children.empty?
      end
    end

    def find_marker(node)
      node.at_xpath(MARKER_XPATH)
    end

    def enclosing_paragraph_of(marker)
      marker.ancestors.find { |node| node.element? && PARAGRAPH_ELEMENTS.include?(qualified_name(node)) }
    end

    def blank_paragraph?(paragraph)
      paragraph.text.strip.empty? &&
        paragraph.xpath(".//*").all? { |node| INSIGNIFICANT_ELEMENTS.include?(qualified_name(node)) }
    end

    # The parts after the first one continue the original paragraph, so they
    # must not repeat its page break or master page. Returns the name of a
    # style without them, creating it if needed: a copy of an automatic style,
    # or a child of a common one (those live in styles.xml).
    def continuation_style(doc, base_name)
      name = "#{base_name}-cont"
      return name if doc.at_xpath("//style:style[@style:name='#{name}']")

      automatic_styles = doc.at_xpath("//office:automatic-styles")
      return base_name unless automatic_styles

      base = automatic_styles.at_xpath("./style:style[@style:name='#{base_name}']")
      if base
        style = base.add_next_sibling(base.dup(1))
        style.remove_attribute("master-page-name")
      else
        style = automatic_styles.add_child(Nokogiri::XML::Node.new("style:style", doc))
        style["style:family"] = "paragraph"
        style["style:parent-style-name"] = base_name
      end
      style["style:name"] = name

      properties = style.at_xpath("./style:paragraph-properties") ||
                   style.prepend_child(Nokogiri::XML::Node.new("style:paragraph-properties", doc))
      properties["fo:break-before"] = "auto"
      properties.remove_attribute("page-number")

      name
    end

    # Nodes built with Node.new("text:p", doc) keep the prefix in their name
    # until attached, attached ones expose it through their namespace.
    def qualified_name(node)
      node.namespace ? "#{node.namespace.prefix}:#{node.name}" : node.name
    end
  end
end
