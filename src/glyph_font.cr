# Shared ASCII-art font rendering: each glyph is a block of lines. `Digits`
# and `Letters` each provide their own `glyphs`/`rows` (by overriding the
# hooks below) and `extend` this module to inherit `render`. A module with a
# single size only needs to define `GLYPHS`/`HEIGHT` and can leave the hooks
# at their defaults; `Digits` overrides them to pick between its small
# (`GLYPHS`/`HEIGHT`) and large (`LARGE_GLYPHS`/`LARGE_HEIGHT`) variants.
module Cresium::GlyphFont
  # Injects `self.render` into the module that extends `GlyphFont`, so that
  # `GLYPHS` and `HEIGHT` resolve in that target module's context (a plain
  # `def self.render` defined here would stay bound to `GlyphFont` itself).
  macro extended
    # Glyph table to render from; `large` is a no-op unless overridden.
    def self.glyphs(large : Bool = false) : Hash(Char, Array(String))
      GLYPHS
    end

    # Number of lines per glyph; `large` is a no-op unless overridden.
    def self.rows(large : Bool = false) : Int32
      HEIGHT
    end

    # Renders *text* as an array of ASCII-art lines, glyphs separated by a
    # space. Characters missing from the glyph table fall back to `':'`.
    def self.render(text : String, large : Bool = false) : Array(String)
      table = glyphs(large)

      glyph_rows = text.chars.map do |char|
        table[char]? || table[':']
      end

      Array.new(rows(large)) do |row|
        glyph_rows.map(&.[row]).join(" ")
      end
    end
  end
end
