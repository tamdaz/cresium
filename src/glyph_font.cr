# Shared ASCII-art font rendering: each glyph is a block of `HEIGHT` lines.
# `Digits` and `Letters` each provide their own `GLYPHS` table and `extend`
# this module to inherit `render`.
module Cresium::GlyphFont
  # Injects `self.render` into the module that extends `GlyphFont`, so that
  # `GLYPHS` and `HEIGHT` resolve in that target module's context (a plain
  # `def self.render` defined here would stay bound to `GlyphFont` itself).
  macro extended
    # Renders *text* as an array of `HEIGHT` ASCII-art lines, glyphs
    # separated by a space. Characters missing from `GLYPHS` fall back to `':'`.
    def self.render(text : String) : Array(String)
      glyphs = text.chars.map { |c| GLYPHS[c]? || GLYPHS[':'] }
      Array.new(HEIGHT) { |row| glyphs.map { |g| g[row] }.join(" ") }
    end
  end
end
