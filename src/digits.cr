module Cresium
  # Police ASCII art façon afficheur "VCR OSD" : chaque caractère est un bloc
  # de 7 lignes. `SEPARATOR` sert de deux-points entre heures/minutes/secondes.
  module Digits
    HEIGHT = 7

    GLYPHS = {
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
      '█' => ["██████████", "██████████", "██████████", "██████████", "██████████", "██████████", "██████████"],
      '>' => ["▀██▄      ", "  ▀██▄    ", "    ▀██▄  ", "      ███ ", "    ▄██▀  ", "  ▄██▀    ", "▄██▀      "],
      '<' => ["      ▄██▀", "    ▄██▀  ", "  ▄██▀    ", " ███      ", "  ▀██▄    ", "    ▀██▄  ", "      ▀██▄"],
      ' ' => ["   ", "   ", "   ", "   ", "   ", "   ", "   "],
    }

    # Rend *text* (chiffres et `:`) en un tableau de `HEIGHT` lignes ASCII art,
    # chaque glyphe séparé d'un espace.
    def self.render(text : String) : Array(String)
      glyphs = text.chars.map { |c| GLYPHS[c]? || GLYPHS[':'] }
      Array.new(HEIGHT) { |row| glyphs.map { |g| g[row] }.join(" ") }
    end

    # Plage de colonnes (dans le rendu ASCII art) occupée par le glyphe du
    # caractère `index` de `text`, ou `nil` si l'index est absent.
    def self.glyph_column_range(text : String, index : Int32?) : Range(Int32, Int32)?
      return nil unless index
      return nil unless index >= 0 && index < text.size

      col = 0
      text.chars.each_with_index do |c, i|
        width = (GLYPHS[c]? || GLYPHS[':']).first.size
        return (col...(col + width)) if i == index
        col += width + 1
      end
      nil
    end
  end
end

module Cresium::Letters
  HEIGHT = 7

  GLYPHS = {
    'C' => [" ▄██████▄ ", "██▀    ▀██", "██        ", "██        ", "██        ", "██▄    ▄██", " ▀██████▀ "],
    'R' => ["████████▄ ", "██     ▀██", "██     ▄██", "████████▀ ", "██ ▀██▄   ", "██   ▀██▄ ", "██     ▀██"],
    'E' => ["██████████", "██        ", "██        ", "████████  ", "██        ", "██        ", "██████████"],
    'S' => [" ▄██████▄ ", "██▀    ▀██", "██▄       ", " ▀██████▄ ", "       ▀██", "██▄    ▄██", " ▀██████▀ "],
    'I' => ["██████████", "    ██    ", "    ██    ", "    ██    ", "    ██    ", "    ██    ", "██████████"],
    'U' => ["██      ██", "██      ██", "██      ██", "██      ██", "██      ██", "██▄    ▄██", " ▀██████▀ "],
    'M' => ["██      ██", "███▄  ▄███", "██▀████▀██", "██  ▀▀  ██", "██      ██", "██      ██", "██      ██"],
  }

  def self.render(text : String) : Array(String)
    glyphs = text.chars.map { |c| GLYPHS[c]? || GLYPHS[':'] }
    Array.new(HEIGHT) { |row| glyphs.map { |g| g[row] }.join(" ") }
  end
end
