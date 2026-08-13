require "crystal_tui"
require "../stopwatch"
require "../format_span"
require "../render_helpers"

# Renders a `Stopwatch`'s `laps` in columns, most recent first, `ROWS`
# lines per column. Adds columns as long as the widget's width allows.
class Cresium::LapGrid < Tui::Widget
  include RenderHelpers
  include Styled

  # Number maximal of rows
  ROWS = 5

  property laps : Array(Time::Span) = [] of Time::Span

  # True to omit milliseconds from lap times (narrow terminals, see
  # `Cresium::LayoutConfig.compact_laps?`).
  property? compact : Bool = false

  # No minimum width (columns collapse to zero if there's no room); always
  # reserves `ROWS` lines of height.
  def min_size : Tuple(Int32, Int32)
    {0, ROWS}
  end

  # Draws as many lap columns as fit in the widget's width.
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
        text = "Lap #{lap_index + 1}: #{Cresium.format_span(laps[lap_index], !compact?)}"
        x = @rect.x + col * col_w
        y = @rect.y + row
        next unless y < @rect.bottom

        draw_clipped(buffer, clip, x, y, text, @style)
      end
    end
  end

  # Column width, sized to the widest possible lap line at the current count.
  private def cell_width : Int32
    sample = "Lap #{laps.size}: " + Cresium.format_span(Time::Span.zero, !compact?)
    sample.size + 2
  end
end
