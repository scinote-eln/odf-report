module ODFReport
  class Text < Field
    def replace!(doc)
      return unless (nodes = find_text_node(doc))

      data_value = @data_source.value
      placeholder = to_placeholder

      nodes.each do |node|
        parser = Parser::Default.new(data_value, node)

        if node.name == 'span'
          txt = node.inner_html
          node.content = txt if txt.gsub!(placeholder, parser.paragraphs.map(&:text).join(' '))
        else
          parser.paragraphs.each do |p|
            node.before(p)
          end

          node.remove
        end
      end
    end

    private

    def find_text_node(doc)
      field = to_placeholder
      doc.xpath(".//*[contains(string(.), '#{field}')
                 and not(.//*[contains(string(.), '#{field}')])]")
    end
  end
end
