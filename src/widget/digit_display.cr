require "crystal_tui"
require "../digits"

# Renders a string (time or input) as ASCII art via `Digits`, centered in
# its rect, with an optional character highlighted (`cursor_index`).
class Cresium::DigitDisplay < Tui::Widget
  getter text : String = ""
  property style : Tui::Style = Tui::Style.new(fg: Tui::Color.default)

  # Renders with `Digits::LARGE_GLYPHS` (7 lines) instead of the default
  # small set (4 lines, block octants) when `true`.
  getter? large : Bool = false

  # Index (in `text`) of the character to render as a blinking cursor
  # (reversed style), or `nil` to show no cursor.
  property cursor_index : Int32? = nil

  def text=(value : String) : Nil
    return if @text == value
    @text = value
    mark_dirty!
  end

  def large=(value : Bool) : Nil
    return if @large == value
    @large = value
    mark_dirty!
  end

  def cursor_index=(value : Int32?) : Nil
    return if @cursor_index == value
    @cursor_index = value
    mark_dirty!
  end

  def min_size : Tuple(Int32, Int32)
    lines = Digits.render @text, @large

    {lines.first.size, Digits.rows(@large)}
  end

  def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
    return unless visible?
    return if @rect.empty?

    lines = Digits.render @text, @large
    width = lines.first.size
    height = Digits.rows(@large)
    cursor_col_range = Digits.glyph_column_range(@text, @cursor_index, @large)
    cursor_style = Tui::Style.new(fg: @style.fg, bg: @style.bg, attrs: @style.attrs | Tui::Attributes::Reverse)

    x_offset = @rect.x + (@rect.width - width + 1) // 2
    y_offset = @rect.y + (@rect.height - height + 1) // 2

    lines.each_with_index do |line, row|
      y = y_offset + row
      next unless y >= clip.y && y < clip.y + clip.height

      line.each_char_with_index do |char, col|
        x = x_offset + col
        next unless clip.contains?(x, y)
        style = cursor_col_range.try(&.includes?(col)) ? cursor_style : @style
        buffer.set(x, y, char, style)
      end
    end
  end
end
