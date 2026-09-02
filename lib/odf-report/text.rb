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
        elsif node.children.size == 1 && node.children.first.content == to_placeholder
          parser.paragraphs.each do |p|
            node.before(p)
          end

          node.remove
        else
          replace_inline(doc, node, parser.paragraphs.flat_map(&:children))
        end
      end
    end

    private

    def replace_inline(doc, node, replacement_nodes)
      placeholder = to_placeholder

      node.children.to_a.each do |child|
        next unless child.text? && child.content.include?(placeholder)

        parts = child.content.split(placeholder, -1)
        last_part = parts.pop

        parts.each do |part|
          child.add_previous_sibling(Nokogiri::XML::Text.new(part, doc)) unless part.empty?
          replacement_nodes.each do |n|
            child.add_previous_sibling(Nokogiri::XML::Text.new(' ', doc))
            child.add_previous_sibling(n.dup)
          end
        end

        child.add_previous_sibling(Nokogiri::XML::Text.new(last_part, doc)) unless last_part.empty?
        child.remove
      end
    end

    def find_text_node(doc)
      field = to_placeholder
      doc.xpath(".//*[text()[contains(., '#{field}')]]")
    end
  end
end
