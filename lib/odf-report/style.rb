require 'digest'
require_relative 'style/css_colors'

module ODFReport
  # Creates automatic styles in the document from CSS (a CSS string or a
  # parsed hash) and returns their names. Styles are named by a digest of
  # their CSS, so the same CSS always reuses the same style.
  class Style

    STYLE_NS = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'.freeze
    DEFAULT_CELL_STYLE_NAME = 'TableBorderCell'.freeze
    DEFAULT_BORDER = '0.75pt solid #000000'.freeze

    NS = {
      'office' => 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
      'style' => STYLE_NS
    }.freeze

    DEFAULT_BULLET_LIST_STYLE_NAME = 'OdfReportBulletList'.freeze
    DEFAULT_NUMBERED_LIST_STYLE_NAME = 'OdfReportNumberedList'.freeze
    LIST_MAX_LEVELS = 10
    BULLET_CHAR = '•'.freeze
    NUMBER_FORMAT = { 'style:num-format' => '1', 'style:num-suffix' => '.' }.freeze

    BORDERS = {
      'border-top' => 'fo:border-top',
      'border-right' => 'fo:border-right',
      'border-bottom' => 'fo:border-bottom',
      'border-left' => 'fo:border-left'
    }.freeze
    PARAGRAPH_CSS_KEYS = %w[text-align margin-left margin-right padding-left padding-right].freeze
    TEXT_CSS_KEYS = %w[font-weight font-size font-style color background-color text-decoration text-properties].freeze
    PX_TO_PT = 0.75

    def initialize(doc)
      @doc = doc
      @auto_styles = doc.at_xpath('//office:automatic-styles', NS)
      create_default_style
    end

    def parse_css(css)
      return {} unless css

      css.split(';').each_with_object({}) do |item, hash|
        key, value = item.split(':', 2)
        next unless key && value

        hash[key.strip] = value.strip
      end
    end

    def cell_style(css)
      return DEFAULT_CELL_STYLE_NAME if css.nil? || css.empty? || @auto_styles.nil?

      find_or_create_style("Cell_#{Digest::MD5.hexdigest(css.to_s)}", 'table-cell') do |style|
        css = parse_css(css) if css.is_a?(String)

        props = Nokogiri::XML::Node.new('style:table-cell-properties', @doc)
        props['fo:background-color'] = normalized_hex_color(css['background-color']) if css['background-color']

        BORDERS.each do |css_border, odf_border|
          props[odf_border] = convert_border(css[css_border]) if css[css_border]
        end
        props['fo:border'] = DEFAULT_BORDER unless css.keys.intersect?(BORDERS.keys)

        props['style:vertical-align'] = css['vertical-align'] if css['vertical-align']

        style.add_child(props)
      end
    end

    def text_style(css, family = 'paragraph')
      return if css.nil? || css.empty? || @auto_styles.nil?

      find_or_create_style("Paragraph_#{Digest::MD5.hexdigest(css.to_s)}", family) do |style|
        css = parse_css(css) if css.is_a?(String)

        style.add_child(paragraph_properties(css)) if css.keys.intersect?(PARAGRAPH_CSS_KEYS)
        style.add_child(text_properties(css)) if css.keys.intersect?(TEXT_CSS_KEYS)
      end
    end

    def list_style(ordered)
      name = ordered ? DEFAULT_NUMBERED_LIST_STYLE_NAME : DEFAULT_BULLET_LIST_STYLE_NAME
      return name unless @auto_styles

      existing = @auto_styles.xpath("./*[local-name()='list-style'][@style:name='#{name}']", 'style' => STYLE_NS).first
      return name if existing

      list_style_node = Nokogiri::XML::Node.new('text:list-style', @doc)
      list_style_node['style:name'] = name

      (1..LIST_MAX_LEVELS).each do |level|
        level_style = ordered ? build_number_level_style(level) : build_bullet_level_style(level)
        list_style_node.add_child(level_style)
      end

      @auto_styles.add_child(list_style_node)

      name
    end

    private

    def paragraph_properties(css)
      props = Nokogiri::XML::Node.new('style:paragraph-properties', @doc)
      props['fo:text-align'] = css['text-align'] if css['text-align']

      margin_left = css['margin-left'] || css['padding-left']
      props['fo:margin-left'] = convert_length(margin_left) if margin_left

      margin_right = css['margin-right'] || css['padding-right']
      props['fo:margin-right'] = convert_length(margin_right) if margin_right

      props
    end

    def text_properties(css)
      props = Nokogiri::XML::Node.new('style:text-properties', @doc)
      props['fo:font-weight'] = css['font-weight'] if css['font-weight']
      props['fo:font-size'] = css['font-size'] if css['font-size']
      props['fo:font-style'] = css['font-style'] if css['font-style']
      props['fo:color'] = normalized_hex_color(css['color']) if css['color']
      props['fo:background-color'] = normalized_hex_color(css['background-color']) if css['background-color']

      case css['text-decoration']
      when 'underline'
        props['style:text-underline-style'] = 'solid'
        props['style:text-underline-type'] = 'single'
      when 'line-through'
        props['style:text-line-through-style'] = 'solid'
      when 'none'
        props['style:text-underline-style'] = 'none'
      end

      case css['text-properties']
      when 'super'
        props['style:text-position'] = 'super 58%'
      when 'sub'
        props['style:text-position'] = 'sub 58%'
      end

      props
    end

    def build_bullet_level_style(level)
      level_style = Nokogiri::XML::Node.new('text:list-level-style-bullet', @doc)
      level_style['text:level'] = level.to_s
      level_style['text:bullet-char'] = BULLET_CHAR

      add_list_level_properties(level_style, level)

      level_style
    end

    def build_number_level_style(level)
      level_style = Nokogiri::XML::Node.new('text:list-level-style-number', @doc)
      level_style['text:level'] = level.to_s
      level_style['style:num-format'] = NUMBER_FORMAT['style:num-format']
      level_style['style:num-suffix'] = NUMBER_FORMAT['style:num-suffix']

      add_list_level_properties(level_style, level)

      level_style
    end

    def add_list_level_properties(level_style, level)
      props = Nokogiri::XML::Node.new('style:list-level-properties', @doc)
      props['text:space-before'] = "#{format('%.1f', 0.75 * (level - 1))}cm"
      props['text:min-label-width'] = '0.5cm'

      level_style.add_child(props)
    end

    def find_or_create_style(name, family)
      existing = @auto_styles.at_xpath("./style:style[@style:name='#{name}']", 'style' => STYLE_NS)

      return name if existing

      style = Nokogiri::XML::Node.new('style:style', @doc)

      style['style:name'] = name
      style['style:family'] = family

      yield style

      @auto_styles.add_child(style)

      name
    end

    def create_default_style
      return unless @auto_styles

      find_or_create_style(DEFAULT_CELL_STYLE_NAME, 'table-cell') do |style|
        props = Nokogiri::XML::Node.new('style:table-cell-properties', @doc)
        props['fo:border'] = DEFAULT_BORDER

        style.add_child(props)
      end
    end

    def convert_length(value)
      px_to_pt(value.strip) if value
    end

    def convert_border(value)
      normalized_hex_color(px_to_pt(value.strip)) if value
    end

    def px_to_pt(value)
      value.gsub(/(\d+(?:\.\d+)?)px/) { "#{(::Regexp.last_match(1).to_f * PX_TO_PT).round(2)}pt" }
    end

    def normalized_hex_color(color)
      return unless color

      color = color.gsub(/[a-zA-Z]+/) { |word| CSS_COLOR_NAMES[word.downcase] || word }
      return color if color.start_with?('#') || color !~ /rgba?\(/i

      "##{color.scan(/\d+/).map(&:to_i).map { |c| c.to_s(16).rjust(2, '0').upcase }.join}"
    end
  end
end
