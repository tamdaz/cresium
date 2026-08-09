require "crystal_tui"
require "../stopwatch"

class Cresium::LapGrid < Tui::Widget
  ROWS = 5

  property laps : Array(Time::Span) = [] of Time::Span
  property style : Tui::Style = Tui::Style.new(fg: Tui::Color.default)
  property compact : Bool = false

  def min_size : {Int32, Int32}
    {0, ROWS}
  end

  def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
    return unless visible?
    return if @rect.empty? || laps.empty?

    col_w = cell_width
    max_cols = Math.max(1, @rect.width // col_w)
    total = laps.size
    cols_needed = (total + ROWS - 1) // ROWS
    cols = Math.min(max_cols, cols_needed)

    cols.times do |col|
      hi = total - col * ROWS
      lo = Math.max(0, hi - ROWS)

      (lo...hi).to_a.reverse.each_with_index do |lap_index, row|
        text = "Lap #{lap_index + 1}: #{Cresium.format_span(laps[lap_index], !compact)}"
        x = @rect.x + col * col_w
        y = @rect.y + row
        next unless y < @rect.bottom

        text.each_char_with_index do |char, i|
          px = x + i
          next unless clip.contains?(px, y)
          buffer.set(px, y, char, @style)
        end
      end
    end
  end

  private def cell_width : Int32
    sample = "Lap #{laps.size}: " + Cresium.format_span(Time::Span.zero, !compact)
    sample.size + 2
  end
end
