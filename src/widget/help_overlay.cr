require "crystal_tui"
require "../letters"
require "../theme"
require "../render_helpers"
require "../controller/stopwatch_controller"
require "../controller/timer_controller"

# Modal help overlay: CRESIUM ASCII-art logo plus the merged stopwatch/timer
# keyboard shortcut list. Draws on top of both screens, centered in its rect.
class Cresium::HelpOverlay < Tui::Widget
  include RenderHelpers

  PADDING_X = 3
  PADDING_Y = 1

  # Every binding declared through `@[OnKeyPress]`, both screens — source of
  # truth for the descriptions in `ROWS` below.
  ALL_BINDINGS = StopwatchController::KEY_BINDINGS + TimerController::KEY_BINDINGS

  # Display rows, in display order: `{displayed key, [raw key specs it
  # covers], description override}`. `nil` looks the description up in
  # `ALL_BINDINGS`; an override is needed where a row merges bindings with
  # different descriptions ("r"), merges several keys ("←→", "↑↓"), or reads
  # better rephrased ("hh:mm:ss + enter", "t"). An empty key list means an
  # app-level key handled directly in `App#on_capture`, which never goes
  # through `Dispatchable`.
  ROWS = [
    {"?", [] of String, "toggle this help"},
    {"tab", [] of String, "switch stopwatch / timer"},
    {"space", ["space"], "start / pause"},
    {"r", ["r"], "reset / new input"},
    {"l", ["l"], "lap (stopwatch)"},
    {"hh:mm:ss + enter", ["enter"], "set the timer"},
    {"t", ["t"], "target time input (timer)"},
    {"←→", ["left", "right"], "move input cursor (timer)"},
    {"backspace", ["backspace"], "erase a digit (timer)"},
    {"n", ["n"], nil},
    {"d", ["d"], nil},
    {"↑↓", ["up", "down"], nil},
    {"q", [] of String, "quit"},
  ]

  SHORTCUTS = ROWS.map do |display_key, raw_keys, override|
    desc = override || ALL_BINDINGS.find { |key, _, _| raw_keys.includes?(key) }.try(&.[1])
    raise "HelpOverlay: no @[OnKeyPress] found for #{raw_keys.inspect}" unless desc
    {display_key, desc}
  end

  # Starts hidden — shown only after `toggle` is called (`[?]`).
  def initialize(id : String? = nil)
    super(id)
    @visible = false
  end

  # Shows or hides the overlay.
  def toggle : Nil
    @visible = !@visible
    mark_dirty!
  end

  # Draws the bordered box (logo + shortcut list), centered in `rect`.
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
