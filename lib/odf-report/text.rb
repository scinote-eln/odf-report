module ODFReport
  class Text < Field
    def replace!(doc)
      return unless (node = find_text_node(doc))

      parser = Parser::Default.new(@data_source.value, node)

      if node.name == 'span'
        txt = node.inner_html
        node.content = txt if txt.gsub!(to_placeholder, parser.paragraphs.map(&:text).join(' '))
      else
        parser.paragraphs.each do |p|
          node.before(p)
        end

        node.remove
      end
    end

    private

    def find_text_node(doc)
      field = to_placeholder
      doc.xpath(".//*[contains(string(.), '#{field}')
                 and not(.//*[contains(string(.), '#{field}')])]").first
    end
  end
end
