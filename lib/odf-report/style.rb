module ODFReport
  class Style
    require 'digest'

    STYLE_NS = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'.freeze
    DEFAULT_CELL_STYLE_NAME = 'TableBorderCell'.freeze
    DEFAULT_BORDER = '0.75pt solid #000000'.freeze

    NS = {
      'office' => 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
      'style' => STYLE_NS
    }.freeze

     # CSS3/SVG named colors -> hex. Used to translate border/text colors
    # given as CSS keywords (e.g. "red", "steelblue") into the hex values
    # ODF attributes expect. Keys are lowercase; lookups downcase first.
    CSS_COLOR_NAMES = {
      'aliceblue' => '#F0F8FF', 'antiquewhite' => '#FAEBD7', 'aqua' => '#00FFFF', 'aquamarine' => '#7FFFD4',
      'azure' => '#F0FFFF', 'beige' => '#F5F5DC', 'bisque' => '#FFE4C4', 'black' => '#000000',
      'blanchedalmond' => '#FFEBCD', 'blue' => '#0000FF', 'blueviolet' => '#8A2BE2', 'brown' => '#A52A2A',
      'burlywood' => '#DEB887', 'cadetblue' => '#5F9EA0', 'chartreuse' => '#7FFF00', 'chocolate' => '#D2691E',
      'coral' => '#FF7F50', 'cornflowerblue' => '#6495ED', 'cornsilk' => '#FFF8DC', 'crimson' => '#DC143C',
      'cyan' => '#00FFFF', 'darkblue' => '#00008B', 'darkcyan' => '#008B8B', 'darkgoldenrod' => '#B8860B',
      'darkgray' => '#A9A9A9', 'darkgreen' => '#006400', 'darkgrey' => '#A9A9A9', 'darkkhaki' => '#BDB76B',
      'darkmagenta' => '#8B008B', 'darkolivegreen' => '#556B2F', 'darkorange' => '#FF8C00', 'darkorchid' => '#9932CC',
      'darkred' => '#8B0000', 'darksalmon' => '#E9967A', 'darkseagreen' => '#8FBC8F', 'darkslateblue' => '#483D8B',
      'darkslategray' => '#2F4F4F', 'darkslategrey' => '#2F4F4F', 'darkturquoise' => '#00CED1',
      'darkviolet' => '#9400D3', 'deeppink' => '#FF1493', 'deepskyblue' => '#00BFFF', 'dimgray' => '#696969',
      'dimgrey' => '#696969', 'dodgerblue' => '#1E90FF', 'firebrick' => '#B22222', 'floralwhite' => '#FFFAF0',
      'forestgreen' => '#228B22', 'fuchsia' => '#FF00FF', 'gainsboro' => '#DCDCDC', 'ghostwhite' => '#F8F8FF',
      'gold' => '#FFD700', 'goldenrod' => '#DAA520', 'gray' => '#808080', 'green' => '#008000',
      'greenyellow' => '#ADFF2F', 'grey' => '#808080', 'honeydew' => '#F0FFF0', 'hotpink' => '#FF69B4',
      'indianred' => '#CD5C5C', 'indigo' => '#4B0082', 'ivory' => '#FFFFF0', 'khaki' => '#F0E68C',
      'lavender' => '#E6E6FA', 'lavenderblush' => '#FFF0F5', 'lawngreen' => '#7CFC00', 'lemonchiffon' => '#FFFACD',
      'lightblue' => '#ADD8E6', 'lightcoral' => '#F08080', 'lightcyan' => '#E0FFFF',
      'lightgoldenrodyellow' => '#FAFAD2', 'lightgray' => '#D3D3D3', 'lightgreen' => '#90EE90',
      'lightgrey' => '#D3D3D3', 'lightpink' => '#FFB6C1', 'lightsalmon' => '#FFA07A', 'lightseagreen' => '#20B2AA',
      'lightskyblue' => '#87CEFA', 'lightslategray' => '#778899', 'lightslategrey' => '#778899',
      'lightsteelblue' => '#B0C4DE', 'lightyellow' => '#FFFFE0', 'lime' => '#00FF00', 'limegreen' => '#32CD32',
      'linen' => '#FAF0E6', 'magenta' => '#FF00FF', 'maroon' => '#800000', 'mediumaquamarine' => '#66CDAA',
      'mediumblue' => '#0000CD', 'mediumorchid' => '#BA55D3', 'mediumpurple' => '#9370DB',
      'mediumseagreen' => '#3CB371', 'mediumslateblue' => '#7B68EE', 'mediumspringgreen' => '#00FA9A',
      'mediumturquoise' => '#48D1CC', 'mediumvioletred' => '#C71585', 'midnightblue' => '#191970',
      'mintcream' => '#F5FFFA', 'mistyrose' => '#FFE4E1', 'moccasin' => '#FFE4B5', 'navajowhite' => '#FFDEAD',
      'navy' => '#000080', 'oldlace' => '#FDF5E6', 'olive' => '#808000', 'olivedrab' => '#6B8E23',
      'orange' => '#FFA500', 'orangered' => '#FF4500', 'orchid' => '#DA70D6', 'palegoldenrod' => '#EEE8AA',
      'palegreen' => '#98FB98', 'paleturquoise' => '#AFEEEE', 'palevioletred' => '#DB7093', 'papayawhip' => '#FFEFD5',
      'peachpuff' => '#FFDAB9', 'peru' => '#CD853F', 'pink' => '#FFC0CB', 'plum' => '#DDA0DD',
      'powderblue' => '#B0E0E6', 'purple' => '#800080', 'rebeccapurple' => '#663399', 'red' => '#FF0000',
      'rosybrown' => '#BC8F8F', 'royalblue' => '#4169E1', 'saddlebrown' => '#8B4513', 'salmon' => '#FA8072',
      'sandybrown' => '#F4A460', 'seagreen' => '#2E8B57', 'seashell' => '#FFF5EE', 'sienna' => '#A0522D',
      'silver' => '#C0C0C0', 'skyblue' => '#87CEEB', 'slateblue' => '#6A5ACD', 'slategray' => '#708090',
      'slategrey' => '#708090', 'snow' => '#FFFAFA', 'springgreen' => '#00FF7F', 'steelblue' => '#4682B4',
      'tan' => '#D2B48C', 'teal' => '#008080', 'thistle' => '#D8BFD8', 'tomato' => '#FF6347', 'turquoise' => '#40E0D0',
      'violet' => '#EE82EE', 'wheat' => '#F5DEB3', 'white' => '#FFFFFF', 'whitesmoke' => '#F5F5F5',
      'yellow' => '#FFFF00', 'yellowgreen' => '#9ACD32'
    }.freeze

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

    def cell_style(style_element)
      return DEFAULT_CELL_STYLE_NAME if style_element.nil? || style_element.empty?
      return DEFAULT_CELL_STYLE_NAME unless @auto_styles

      cached_style("Cell_#{Digest::MD5.hexdigest(style_element.to_s)}", 'table-cell') do |style|
        styles = style_element.is_a?(String) ? parse_css(style_element) : style_element

        props = Nokogiri::XML::Node.new('style:table-cell-properties', @doc)
        props['fo:background-color'] = normalized_hex_color(styles['background-color']) if styles['background-color']

        any_border = false
        # Borders
        {
          'border-top' => 'fo:border-top',
          'border-right' => 'fo:border-right',
          'border-bottom' => 'fo:border-bottom',
          'border-left' => 'fo:border-left'
        }.each do |css_border, odt_border|
          next unless styles[css_border]

          props[odt_border] = convert_border(styles[css_border])
          any_border = true
        end

        props['fo:border'] = DEFAULT_BORDER unless any_border

        props['style:vertical-align'] = styles['vertical-align'] if styles['vertical-align']

        style.add_child(props)
      end
    end

    def text_style(style_element, family = 'paragraph')
      return if style_element.nil? || style_element.empty?
      return unless @auto_styles

      cached_style("Paragraph_#{Digest::MD5.hexdigest(style_element.to_s)}", family) do |style|
        styles = style_element.is_a?(String) ? parse_css(style_element) : style_element

        if styles['text-align']
          props = Nokogiri::XML::Node.new('style:paragraph-properties', @doc)
          props['fo:text-align'] = styles['text-align']
          style.add_child(props)
        end

        if styles['font-weight'] || styles['font-size'] || styles['color'] || styles['font-style'] ||
           styles['text-decoration'] || styles['style:text-position'] || styles['background-color'] || styles['text-properties']
          props = Nokogiri::XML::Node.new('style:text-properties', @doc)
          props['fo:font-weight'] = styles['font-weight'] if styles['font-weight']
          props['fo:font-size'] = styles['font-size'] if styles['font-size']
          props['fo:font-style'] = styles['font-style'] if styles['font-style']
          props['fo:color'] = normalized_hex_color(styles['color']) if styles['color']
          props['fo:background-color'] = normalized_hex_color(styles['background-color']) if styles['background-color']

          case styles['text-decoration']
          when 'underline'
            props['style:text-underline-style'] = 'solid'
            props['style:text-underline-type'] = 'single'
          when 'line-through'
            props['style:text-line-through-style'] = 'solid'
          when 'none'
            props['style:text-underline-style'] = 'none'
          end

          case styles['text-properties']
          when 'super'
            props['style:text-position'] = 'super 58%'
          when 'sub'
            props['style:text-position'] = 'sub 58%'
          end

          style.add_child(props)
        end
      end
    end

    private

    def cached_style(name, family)
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

      cached_style(DEFAULT_CELL_STYLE_NAME, 'table-cell') do |style|
        props = Nokogiri::XML::Node.new('style:table-cell-properties', @doc)
        props['fo:border'] = DEFAULT_BORDER

        style.add_child(props)
      end
    end

    def convert_border(value)
      return unless value

      value = value.strip

      # px to pt
      value = value.gsub(/(\d+)px/) do
        "#{::Regexp.last_match(1).to_f * 0.75}pt"
      end

      # colors
      normalized_hex_color(value)
    end

    def normalized_hex_color(color)
      return unless color

      color = color.gsub(/[a-zA-Z]+/) { |word| CSS_COLOR_NAMES[word.downcase] || word }
      return color if color.start_with?('#') || color !~ /rgba?\(/i

      "##{color.scan(/\d+/).map(&:to_i).map { |c| c.to_s(16).rjust(2, '0').upcase }.join}"
    end
  end
end
