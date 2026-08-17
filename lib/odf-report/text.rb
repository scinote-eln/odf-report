module ODFReport
  class Text < Field
    def replace!(doc)
      return unless (node = find_text_node(doc))

      parser = Parser::Default.new(@data_source.value, node)

      if node.name == 'span'
        txt = node.inner_html
        node.inner_html = txt if txt.gsub!(to_placeholder, sanitize(parser.paragraphs.map(&:inner_html).join))
      else
        parser.paragraphs.each do |p|
          node.before(p)
        end

        node.remove
      end
    end

    private

    def find_text_node(doc)
      nodes = doc.xpath(".//text:p[text()='#{to_placeholder}']")
      return nodes.first unless nodes.empty?

      doc.xpath(".//text:p/text:span[text()='#{to_placeholder}']").first
    end
  end
end
