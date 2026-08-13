require "crystal_tui"

# Adds a `style` property (defaulting to the terminal's default foreground,
# no background/attributes) to a widget — shared by `DigitDisplay` and `LapGrid`.
module Cresium::Styled
  property style : Tui::Style = Tui::Style.new(fg: Tui::Color.default)
end

# Drawing helpers shared by widgets that render raw text character by
# character onto a `Tui::Buffer`, respecting the `clip` rect given by the
# framework (the actually writable visible area).
module Cresium::RenderHelpers
  # Draws *text* starting at (`x`, `y`), one character at a time, skipping
  # columns/rows outside of `clip`.
  def draw_clipped(buffer : Tui::Buffer, clip : Tui::Rect, x : Int32, y : Int32, text : String, style : Tui::Style) : Nil
    return unless y >= clip.y && y < clip.y + clip.height
    text.each_char_with_index do |char, i|
      px = x + i
      next unless clip.contains?(px, y)
      buffer.set(px, y, char, style)
    end
  end

  # Fills a rectangle (`x`, `y`, `w`, `h`) with spaces using `style`,
  # respecting `clip`.
  def fill_rect(buffer : Tui::Buffer, clip : Tui::Rect, x : Int32, y : Int32, w : Int32, h : Int32, style : Tui::Style) : Nil
    # ameba:disable Naming/BlockParameterName
    h.times do |dy|
      # ameba:disable Naming/BlockParameterName
      w.times do |dx|
        next unless clip.contains?(x + dx, y + dy)
        buffer.set(x + dx, y + dy, ' ', style)
      end
    end
  end
end
