module ODFReport
  # Renders table with data and style into placeholder.
  # report.add_table_from_data(:table {
  #                                     contents: [[1, 2, 4], ['res', '2', 1]],
  #                                     columns_title: ["A", "test", "C"]
  #                                     rows_title: [1, 2, 3]
  #                                     cells_attributes:  {[0, 0] => {style: ";text-align:center;vertical-align:middle"},
  #                                                         [0, 1] => {style: ";text-align:center;vertical-align:middle"},
  #                                                         [0, 2] => {style: ";text-align:center;vertical-align:middle"},
  #                                                         [0, 3] => {style: ";text-align:center;vertical-align:middle"},
  #                                                         [0, 4] => {style: ";text-align:center;vertical-align:middle"},
  #                                                         [0, 5] => {style: ";text-align:center;vertical-align:middle"}}
  #                                     table_name: 'Test table'
  #                                   })
  class TableFromData
    DEFAULT_HEADER_CELL_STYLE = 'background-color:#f0f0f6;vertical-align:middle'.freeze
    DEFAULT_HEADER_TEXT_STYLE = 'text-align:center;font-weight:bold'.freeze

    def initialize(opts)
      @name = opts[:name]
      data_source = opts[:value] || {}

      @table_data = data_source[:contents] || []
      @columns_title = data_source[:columns_title]
      @rows_title = data_source[:rows_title]
      @cells_attributes = data_source[:cells_attributes] || {}
      @table_name = data_source[:table_name]
    end

    def replace!(doc)
      return if @table_data.nil? || @table_data.empty?

      node = find_text_node(doc)
      return unless node

      @styles = Style.new(doc)

      node.replace(build_table(doc, @table_name))
    end

    private

    def build_table(doc, name)
      table = Nokogiri::XML::Node.new('table:table', doc)
      table['table:name'] = name.to_s

      add_columns(doc, table)
      add_header_row(doc, table)
      add_rows(doc, table)

      table
    end

    def add_columns(doc, table)
      columns_count = [@table_data.map(&:length).max, @rows_title&.length].compact.max.to_i

      return if columns_count.zero?

      column = Nokogiri::XML::Node.new('table:table-column', doc)
      column['table:number-columns-repeated'] = columns_count + (@rows_title ? 1 : 0)
      table.add_child(column)
    end

    def add_header_row(doc, table)
      return unless @columns_title

      append_row(doc, table, @columns_title, @rows_title ? '' : nil, header: true)
    end

    def add_rows(doc, table)
      @table_data.each_with_index do |row, row_index|
        append_row(doc, table, row, @rows_title&.[](row_index), row_index)
      end
    end

    def find_text_node(doc)
      nodes = doc.xpath(".//text:p[text()='#{to_placeholder}']")
      return nodes.first unless nodes.empty?

      span = doc.xpath(".//text:p/text:span[text()='#{to_placeholder}']").first
      span&.parent
    end

    def to_placeholder
      open, close = ODFReport.delimiters
      "#{open}#{@name.to_s.upcase}#{close}"
    end

    def append_row(doc, table, row, title, row_index = nil, header: false)
      table_row = Nokogiri::XML::Node.new('table:table-row', doc)

      if title
        append_cell(doc, table_row, title, @styles.cell_style(DEFAULT_HEADER_CELL_STYLE),
                    @styles.text_style(DEFAULT_HEADER_TEXT_STYLE))
      end

      row.each_with_index do |value, column_index|
        if header
          cell_style = @styles.cell_style(DEFAULT_HEADER_CELL_STYLE)
          paragraph_style = @styles.text_style(DEFAULT_HEADER_TEXT_STYLE)
        else
          cell_style = cell_style(row_index, column_index)
          paragraph_style = paragraph_style(row_index, column_index)
        end

        append_cell(doc, table_row, value, cell_style, paragraph_style)
      end

      table.add_child(table_row)
    end

    def cell_style(row_index, column_index)
      return Style::DEFAULT_CELL_STYLE_NAME if row_index.nil? || column_index.nil?

      style = @cells_attributes&.dig([row_index, column_index], :style)
      style ? @styles.cell_style(style) : Style::DEFAULT_CELL_STYLE_NAME
    end

    def paragraph_style(row_index, column_index)
      return nil if row_index.nil? || column_index.nil?

      style = @cells_attributes&.dig([row_index, column_index], :style)

      style ? @styles.text_style(style) : nil
    end

    def append_cell(doc, table_row, value, cell_style_name, paragraph_style_name)
      cell = Nokogiri::XML::Node.new('table:table-cell', doc)
      cell['table:style-name'] = cell_style_name if cell_style_name

      paragraph = Nokogiri::XML::Node.new('text:p', doc)
      paragraph['text:style-name'] = paragraph_style_name if paragraph_style_name
      paragraph.content = value.to_s

      cell.add_child(paragraph)
      table_row.add_child(cell)
    end
  end
end
