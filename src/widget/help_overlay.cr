require "crystal_tui"
require "../letters"
require "../theme"
require "../render_helpers"

# Modal help overlay: CRESIUM ASCII-art logo plus the merged stopwatch/timer
# keyboard shortcut list. Draws on top of both screens, centered in its rect.
class Cresium::HelpOverlay < Tui::Widget
  include RenderHelpers

  PADDING_X = 3
  PADDING_Y = 1

  SHORTCUTS = [
    {"?", "toggle this help"},
    {"tab", "switch stopwatch / timer"},
    {"space", "start / pause"},
    {"r", "reset / new input"},
    {"l", "lap (stopwatch)"},
    {"hh:mm:ss + enter", "set the timer"},
    {"←→", "move input cursor (timer)"},
    {"backspace", "erase a digit (timer)"},
    {"n", "new"},
    {"d", "delete"},
    {"↑↓", "navigate"},
    {"q", "quit"},
  ]

  def initialize(id : String? = nil)
    super(id)
    @visible = false
  end

  def toggle : Nil
    @visible = !@visible
    mark_dirty!
  end

  def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
    return unless visible?
    return if @rect.empty?

    logo = Cresium::Letters.render("CRESIUM")
    logo_width = logo.first.size
    key_col_width = SHORTCUTS.max_of { |k, _| k.size }
    lines_width = SHORTCUTS.max_of { |k, desc| key_col_width + 2 + desc.size }
    content_width = Math.max(logo_width, lines_width)

    box_width = content_width + PADDING_X * 2
    box_height = logo.size + 1 + SHORTCUTS.size + PADDING_Y * 2

    box_x = @rect.x + (@rect.width - box_width) // 2
    box_y = @rect.y + (@rect.height - box_height) // 2

    border_style = Theme.style(Theme::MUTED)
    title_style = Theme.style(Theme::RUNNING)
    text_style = Theme.style(Theme::NEUTRAL)
    key_style = Theme.style(Theme::PAUSED)

    fill_rect(buffer, clip, box_x, box_y, box_width, box_height, text_style)
    buffer.draw_box(box_x, box_y, box_width, box_height, border_style, Tui::BorderStyle::Round)

    logo_x = box_x + (box_width - logo_width) // 2
    logo.each_with_index do |line, row|
      draw_clipped(buffer, clip, logo_x, box_y + PADDING_Y + row, line, title_style)
    end

    text_x = box_x + PADDING_X
    SHORTCUTS.each_with_index do |(key, desc), i|
      y = box_y + PADDING_Y + logo.size + 1 + i
      draw_clipped(buffer, clip, text_x, y, key.rjust(key_col_width), key_style)
      draw_clipped(buffer, clip, text_x + key_col_width + 2, y, desc, text_style)
    end
  end
end
