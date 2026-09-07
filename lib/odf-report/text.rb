module ODFReport
  class Text < Field
    BLOCK_TAGS = %w[table:table].freeze

    def replace!(doc)
      return unless (nodes = find_text_node(doc))

      data_value = @data_source.value

      nodes.each do |node|
        parser = Parser::Default.new(data_value, node)

        if node.children.size == 1 && node.children.first.content == to_placeholder && node.name != 'span'
          parser.paragraphs.each do |p|
            node.before(p)
          end

          node.remove
        else
          replacement_nodes = parser.paragraphs.flat_map do |p|
            BLOCK_TAGS.include?(p.name) ? [p] : p.children.to_a
          end
          if replacement_nodes.any? { |n| BLOCK_TAGS.include?(n.name) }
            node = node.xpath('ancestor-or-self::text:p', node.namespaces).first || node.parent
            replace_inline_table(doc, node, replacement_nodes)
          else
            replace_inline_text(doc, node, replacement_nodes)
          end
        end
      end
    end

    private

    def replace_inline_table(doc, paragraph, replacement_nodes)
      children = paragraph.children
      placeholder = to_placeholder
      return unless children.any? { |child| child.content.include?(placeholder) }

      continuation_style = "#{paragraph['text:style-name']}-cont"
      ensure_continuation_style!(doc, paragraph['text:style-name'], continuation_style)

      current_para = paragraph.dup(2)

      children.each do |child|
        unless child.content.include?(placeholder)
          current_para.add_child(child.dup)
          next
        end
        parts = child.content.split(placeholder, -1)
        last_part = parts.pop

        parts.each do |part|
          current_para = append_part_and_flush_table(replacement_nodes, paragraph, current_para,
                                                     part, doc, continuation_style)
        end

        current_para.add_child(Nokogiri::XML::Text.new(last_part, doc)) unless last_part.empty?
      end

      paragraph.add_previous_sibling(current_para) unless current_para.children.empty?
      paragraph.remove
    end

    def replace_inline_text(doc, node, replacement_nodes)
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

    def append_part_and_flush_table(replacement_nodes, paragraph, accumulator,
                                    part, doc, continuation_style)
      accumulator.add_child(Nokogiri::XML::Text.new(part, doc)) unless part.empty?

      replacement_nodes.each do |n|
        if BLOCK_TAGS.include?(n.name)
          paragraph.add_previous_sibling(accumulator) unless accumulator.children.empty?
          paragraph.add_previous_sibling(n.dup)
          accumulator = paragraph.dup(2)
          accumulator['text:style-name'] = continuation_style
        else
          accumulator.add_child(Nokogiri::XML::Text.new(' ', doc))
          accumulator.add_child(n.dup)
        end
      end

      accumulator
    end

    def ensure_continuation_style!(doc, base_name, new_name)
      return if doc.at_xpath("//style:style[@style:name='#{new_name}']")

      base = doc.at_xpath("//style:style[@style:name='#{base_name}']")
      return unless base

      clone = base.dup(1)
      clone['style:name'] = new_name
      clone.remove_attribute('master-page-name')
      base.add_next_sibling(clone)
    end

    def find_text_node(doc)
      field = to_placeholder
      doc.xpath(".//*[text()[contains(., '#{field}')]]")
    end
  end
end
