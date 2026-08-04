module ODFReport
  module Parser
    # Default HTML parser
    #
    # Converts an HTML fragment into ODF nodes. Supported:
    #   - <p>, <h1>..<h6>                -> paragraphs (headings use "title")
    #   - <blockquote>                   -> paragraphs use the "quote" style
    #   - <ul>, <ol>, <li>               -> ODF lists (text:list / text:list-item),
    #                                       including nested lists, with proper
    #                                       bullet or numbered list styling
    #   - <strong>/<b>, <em>/<i>, <u>    -> styled text:span
    #   - <br>                           -> text:line-break
    #
    # Any other element is unwrapped: its tags are dropped and its text kept.
    # This guarantees only ODF elements end up in content.xml — foreign HTML
    # tags (e.g. <a>, <span>, <div>) embedded verbatim would otherwise make
    # LibreOffice reject the document with a "Format error".
    #
    class Default
      attr_reader :paragraphs

      LIST_TAGS = %w[ul ol].freeze
      HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze
      BLOCK_LEVEL_CSS_KEYS = %w[
        text-align margin-left margin-right padding-left padding-right
        margin-top margin-bottom padding-top padding-bottom
      ].freeze

      SEMANTIC_STYLES = {
        'strong' => { 'font-weight' => 'bold' },
        'em' => { 'font-style' => 'italic' },
        's' => { 'text-decoration' => 'line-through' },
        'sup' => { 'text-properties' => 'super' },
        'sub' => { 'text-properties' => 'sub' }
      }.freeze

      TEXT_P = 'text:p'.freeze
      TEXT_SPAN = 'text:span'.freeze
      TEXT_LIST = 'text:list'.freeze
      TEXT_LIST_ITEM = 'text:list-item'.freeze
      TEXT_STYLE_NAME = 'text:style-name'.freeze
      TEXT_LINE_BREAK = 'text:line-break'.freeze
      TABLE_TABLE = 'table:table'.freeze
      TABLE_TABLE_COLUMN = 'table:table-column'.freeze
      TABLE_TABLE_ROW = 'table:table-row'.freeze
      TABLE_TABLE_CELL = 'table:table-cell'.freeze
      TABLE_STYLE_NAME = 'table:style-name'.freeze

      XML_ESCAPE = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze

      def initialize(text, template_node)
        @text = text
        @paragraphs = []
        @template_node = template_node
        @style = Style.new(template_node)

        parse
      end

      private

      def parse
        html = Nokogiri::HTML5.fragment(@text)
        process(html.children)
      end

      def inherited_css(node, css = {})
        css = css.dup
        css.merge(node['style'] ? @style.parse_css(node['style']) : {})
           .merge(SEMANTIC_STYLES.fetch(node.name, {}))
      end

      # Walk top-level nodes in document order so lists interleave correctly
      # with paragraphs. Unknown container elements (e.g. <div>) are descended
      # into, preserving the behaviour where nested paragraphs were picked up.
      def process(nodes)
        nodes.each do |node|
          case node.name
          when "p"
            add_paragraph(node)
          when *HEADING_TAGS
            add_paragraph(node, 'title')
          when "ul", "ol"
            @paragraphs << build_list(node)
          when 'table'
            @paragraphs << build_table(node)
          when "text"
            unless node.text.strip.empty?
              paragraph = xml(TEXT_P)
              paragraph.content = node.text
              @paragraphs << paragraph
            end
          else
            process(node.children) if node.element?
          end
        end
      end

      def add_paragraph(node, style = nil)
        @paragraphs << build_paragraph(node, style)
      end

      def build_paragraph(node, style = nil)
        paragraph = xml(TEXT_P)

        css = node['style'] ? @style.parse_css(node['style']) : {}
        style_name = style || (css.empty? ? nil : @style.text_style(css, 'paragraph'))
        paragraph[TEXT_STYLE_NAME] = style_name if style_name

        render_inline(node, paragraph)

        paragraph
      end

      def render_inline(node, parent, css = {})
        css = inherited_css(node, css)

        if node.text?
          add_text(parent, node.text, css)
          return
        end

        case node.name
        when 'br'
          parent.add_child(xml(TEXT_LINE_BREAK))
        when 'table'
          parent.add_child(build_table(node))
        when 'ul', 'ol'
          parent.add_child(build_list(node))
        else
          node.children.each do |child|
            render_inline(child, parent, css)
          end
        end
      end

      def add_text(parent, text, css)
        return if text.nil? || text.empty?

        span = xml(TEXT_SPAN)
        span_css = css.reject { |key, _| BLOCK_LEVEL_CSS_KEYS.include?(key) }
        style = span_css.empty? ? nil : @style.text_style(span_css, 'text')
        span[TEXT_STYLE_NAME] = style if style
        span.content = text.delete("\n")
        parent.add_child(span)
      end

      def build_list(node)
        ordered = node.name == 'ol'

        list = xml(TEXT_LIST)
        list[TEXT_STYLE_NAME] = @style.list_style(ordered)

        node.children
            .select { |child| child.name == 'li' }
            .each do |li|
              list.add_child(build_list_item(li))
            end

        list
      end

      def build_list_item(li)
        item = xml(TEXT_LIST_ITEM)
        paragraph = xml(TEXT_P)

        li.children.each do |child|
          next if block_whitespace?(child)

          if child.name == 'p'
            item.add_child(paragraph) unless paragraph.children.empty?
            item.add_child(build_paragraph(child))
            paragraph = xml(TEXT_P)
          elsif HEADING_TAGS.include?(child.name)
            item.add_child(paragraph) unless paragraph.children.empty?
            item.add_child(build_paragraph(child, 'title'))
            paragraph = xml(TEXT_P)
          elsif LIST_TAGS.include?(child.name)
            item.add_child(paragraph) unless paragraph.children.empty?
            item.add_child(build_list(child))
            paragraph = xml(TEXT_P)
          else
            render_inline(child, paragraph)
          end
        end

        item.add_child(paragraph) unless paragraph.children.empty?

        item
      end

      def build_table(node)
        table = xml(TABLE_TABLE)

        node.children.each do |child|
          case child.name
          when 'colgroup'
            add_columns(table, child)
          when 'tbody'
            child.children
                 .select { |row| row.name == 'tr' }
                 .each do |row|
                   table.add_child(build_table_row(row))
                 end
          end
        end

        table
      end

      def add_columns(table, colgroup)
        column = xml(TABLE_TABLE_COLUMN)
        column['table:number-columns-repeated'] = colgroup.children.count { |c| c.name == 'col' }

        table.add_child(column)
      end

      def build_table_row(row)
        table_row = xml(TABLE_TABLE_ROW)

        row.children.select { |cell| %w[td th].include?(cell.name) }.each do |cell|
          table_cell = xml(TABLE_TABLE_CELL)
          table_cell[TABLE_STYLE_NAME] = @style.cell_style(inherited_css(cell))

          paragraph = xml(TEXT_P)

          cell.children.each do |child|
            next if block_whitespace?(child)

            if child.name == 'p'
              table_cell.add_child(paragraph) unless paragraph.children.empty?
              table_cell.add_child(build_paragraph(child))
              paragraph = xml(TEXT_P)
            elsif HEADING_TAGS.include?(child.name)
              table_cell.add_child(paragraph) unless paragraph.children.empty?
              table_cell.add_child(build_paragraph(child, 'title'))
              paragraph = xml(TEXT_P)
            elsif LIST_TAGS.include?(child.name)
              table_cell.add_child(paragraph) unless paragraph.children.empty?
              table_cell.add_child(build_list(child))
              paragraph = xml(TEXT_P)
            elsif child.name == 'table'
              table_cell.add_child(paragraph) unless paragraph.children.empty?
              table_cell.add_child(build_table(child))
              paragraph = xml(TEXT_P)
            else
              render_inline(child, paragraph)
            end
          end

          table_cell.add_child(paragraph) unless paragraph.children.empty?
          table_row.add_child(table_cell)
        end

        table_row
      end

      def xml(name, parent = @template_node)
        Nokogiri::XML::Node.new(name, parent)
      end

      def block_whitespace?(node)
        node.text? && node.text.strip.empty?
      end
    end
  end
end
