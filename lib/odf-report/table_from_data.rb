module ODFReport
  # Renders a table built from data into a placeholder. It is always rendered
  # as a block (see Text), splitting the paragraph when the placeholder sits
  # inside other text.
  #
  #   report.add_table_from_data(:table, {
  #     contents: [[1, 2, 4], ['res', '2', 1]],
  #     columns_title: ['A', 'test', 'C'],
  #     rows_title: [1, 2],
  #     cells_attributes: { [0, 0] => { style: 'text-align:center;vertical-align:middle' },
  #                         [1, 2] => { style: 'background-color:#f0f0f6' } },
  #     table_name: 'Test table'
  #   })
  #
  # Without contents the placeholder is removed.
  class TableFromData < Text
    HEADER_CELL_CSS = 'background-color:#f0f0f6;vertical-align:middle'.freeze
    HEADER_TEXT_CSS = 'text-align:center;font-weight:bold'.freeze

    def initialize(opts)
      super(opts.merge(display: :block))
    end

    private

    def replacement_nodes(doc)
      data = @data_source.value || {}
      @contents = data[:contents]
      return [] if @contents.nil? || @contents.empty?

      @columns_title = data[:columns_title]
      @rows_title = data[:rows_title]
      @cells_attributes = data[:cells_attributes] || {}
      @styles = Style.new(doc)

      [build_table(doc, data[:table_name])]
    end

    def build_table(doc, name)
      table = Nokogiri::XML::Node.new('table:table', doc)
      table['table:name'] = name.to_s

      add_columns(doc, table)

      # The header row gets an empty corner cell above the row titles.
      append_row(doc, table, @columns_title, @rows_title && '') if @columns_title

      @contents.each_with_index do |row, row_index|
        append_row(doc, table, row, @rows_title&.[](row_index), row_index)
      end

      table
    end

    def add_columns(doc, table)
      columns_count = [@contents.map(&:length).max, @columns_title&.length].compact.max.to_i
      return if columns_count.zero?

      column = Nokogiri::XML::Node.new('table:table-column', doc)
      column['table:number-columns-repeated'] = columns_count + (@rows_title ? 1 : 0)
      table.add_child(column)
    end

    # Rows without a row_index are header rows. Title cells are styled as
    # headers, data cells use their cells_attributes style for both the cell
    # and its paragraph.
    def append_row(doc, table, values, title, row_index = nil)
      table_row = Nokogiri::XML::Node.new('table:table-row', doc)

      append_cell(doc, table_row, title, HEADER_CELL_CSS, HEADER_TEXT_CSS) if title

      values.each_with_index do |value, column_index|
        if row_index
          css = @cells_attributes.dig([row_index, column_index], :style)
          append_cell(doc, table_row, value, css, css)
        else
          append_cell(doc, table_row, value, HEADER_CELL_CSS, HEADER_TEXT_CSS)
        end
      end

      table.add_child(table_row)
    end

    def append_cell(doc, table_row, value, cell_css, text_css)
      cell = Nokogiri::XML::Node.new('table:table-cell', doc)
      cell['table:style-name'] = @styles.cell_style(cell_css)

      paragraph = Nokogiri::XML::Node.new('text:p', doc)
      text_style = @styles.text_style(text_css)
      paragraph['text:style-name'] = text_style if text_style
      paragraph.content = value.to_s

      cell.add_child(paragraph)
      table_row.add_child(cell)
    end
  end
end
