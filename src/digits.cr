require "./glyph_font"

# VCR-OSD-style ASCII-art digit font. Covers digits, `:` (hour/minute/second
# separator) and `.` (millisecond separator). Provides two sizes: the default
# (4 lines, block octants) fits VGA text mode (80x25); `LARGE_GLYPHS` (7
# lines, full blocks) is used instead on big enough terminals (see
# `Cresium::App#large_digits?`). `↑`/`↓` (scroll indicators) and `█` are only
# defined in the small set — they're always rendered at that size (see
# `Cresium::App#refresh_scroll_arrows`), never as part of a large-mode digit.
module Cresium::Digits
  extend GlyphFont

  HEIGHT      = 4
  ARROW_WIDTH = 5

  LARGE_HEIGHT = 7

  LARGE_GLYPHS = {
    '0' => [" ▄██████▄ ", "██▀    ▀██", "██   ▄████", "██ ▄██▀ ██", "████▀   ██", "██▄    ▄██", " ▀██████▀ "],
    '1' => ["   ▄██    ", " ▄████    ", "    ██    ", "    ██    ", "    ██    ", "    ██    ", "██████████"],
    '2' => [" ▄██████▄ ", "██▀    ▀██", "       ▄██", " ▄██████▀ ", "██▀       ", "██        ", "██████████"],
    '3' => [" ▄██████▄ ", "██▀    ▀██", "        ██", "   ██████ ", "        ██", "██▄    ▄██", " ▀██████▀ "],
    '4' => ["     ▄██  ", "   ▄████  ", " ▄██▀ ██  ", "██▀   ██  ", "██████████", "      ██  ", "      ██  "],
    '5' => ["██████████", "██        ", "██ ▄▄▄▄▄  ", "███▀▀▀▀██▄", "        ██", "██▄    ▄██", " ▀██████▀ "],
    '6' => [" ▄██████▄ ", "██▀    ▀██", "██        ", "████████▄ ", "██     ▀██", "██▄    ▄██", " ▀██████▀ "],
    '7' => ["██████████", "        ██", "       ▄██", "     ▄██▀ ", "    ██▀   ", "    ██    ", "    ██    "],
    '8' => [" ▄██████▄ ", "██▀    ▀██", "██▄    ▄██", " ████████ ", "██▀    ▀██", "██▄    ▄██", " ▀██████▀ "],
    '9' => [" ▄██████▄ ", "██▀    ▀██", "██▄     ██", " ▀████████", "        ██", "██▄    ▄██", " ▀██████▀ "],
    ':' => ["      ", "      ", "  ██  ", "      ", "  ██  ", "      ", "      "],
    '.' => ["      ", "      ", "      ", "      ", "      ", "  ██  ", "      "],
    ' ' => ["   ", "   ", "   ", "   ", "   ", "   ", "   "],
  }

  GLYPHS = {
    '0' => ["𜷋𜵭𜴳𜶨𜶻", "█ 𜷋𜵭█", "█𜴵𜴂 █", "𜴅𜴴𜴳𜴵𜴂"],
    '1' => [" 𜷋▆  ", " 🮂█  ", "  █  ", " 𜴳🮅𜴳 "],
    '2' => ["𜷋𜵭𜴳𜶨𜶻", "🮂▂▂𜷋𜵰", "𜷥𜴂🮂🮂 ", "🮅𜴳𜴳𜴳𜴳"],
    '3' => ["𜷋𜵭𜴳𜶨𜶻", "🮂▂▂𜷋𜵰", "▂🮂🮂𜴅𜷤", "𜴅𜴴𜴳𜴵𜴂"],
    '4' => ["  𜷋▆ ", "𜷋𜵯𜴂█ ", "🮅𜴳𜴳█𜴳", "   🮅 "],
    '5' => ["▆𜴳𜴳𜴳𜴳", "█𜷋▄▄𜺣", "𜶮𜺨 𜺫█", "𜴅𜴴𜴳𜴵𜴂"],
    '6' => ["𜷋𜵭𜴳𜶨𜶻", "█▂▂▂🮂", "█🮂🮂𜴅𜷤", "𜴅𜴴𜴳𜴵𜴂"],
    '7' => ["𜴳𜴳𜴳𜴳▆", "  𜺠𜷡𜴗", "  █𜺨 ", "  🮅  "],
    '8' => ["𜷋𜵭𜴳𜶨𜶻", "𜶫𜶻▂𜷋𜵰", "𜷥𜴂🮂𜴅𜷤", "𜴅𜴴𜴳𜴵𜴂"],
    '9' => ["𜷋𜵭𜴳𜶨𜶻", "𜶫𜶻▂▂█", "▂🮂🮂🮂█", "𜴅𜴴𜴳𜴵𜴂"],
    ':' => ["▂", "🮂", "▂", "🮂"],
    '.' => [" ", " ", " ", "𜴳"],
    ' ' => ["     ", "     ", "     ", "     "],
    '█' => ["█████", "█████", "█████", "█████"],
    '↑' => ["𜷋𜵯█𜶩𜶻", "𜴂 █ 𜴅", "  █  ", "  ▀  "],
    '↓' => ["  ▄  ", "  █  ", "𜶻 █ 𜷋", "𜴅𜶩█𜵯𜴂"],
  }

  # Column range (in the rendered ASCII art) covered by the glyph at
  # `index` in `text`, or `nil` if `index` is out of bounds.
  def self.glyph_column_range(text : String, index : Int32?, large : Bool = false) : Range(Int32, Int32)?
    return nil unless index
    return nil unless index >= 0 && index < text.size

    table = glyphs(large)
    col = 0
    text.chars.each_with_index do |c, i|
      width = (table[c]? || table[':']).first.size
      return (col...(col + width)) if i == index
      col += width + 1
    end
    nil
  end

  def self.glyphs(large : Bool = false) : Hash(Char, Array(String))
    large ? LARGE_GLYPHS : GLYPHS
  end

  def self.rows(large : Bool = false) : Int32
    large ? LARGE_HEIGHT : HEIGHT
  end
end
