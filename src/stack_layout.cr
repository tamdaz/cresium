require "crystal_tui"
require "./digits"
require "./screen"
require "./scroll_arrows"
require "./theme"
require "./widget/digit_display"
require "./widget/lap_grid"

# Mixin shared by the stopwatch and timer views: positions a scrollable
# stack of `DigitDisplay`s (the active one dead-centered, dimmed entries
# scrolling above/below it) below a fixed-height `side` band (laps/history)
# and above a `status` label, plus the `[↑↓]` scroll arrow indicators.
module Cresium::StackLayout
  MAX_STATUS_LINES = 2

  # Number of lines `text` wraps to at `width` columns (word-wrapping, same
  # rule as `Tui::Label`'s `TextWrap::Wrap`) — used to size the status label
  # to only what it needs, while the scroll area's centering still always
  # reserves the 2-line maximum (see `layout_stack`).
  private def wrapped_line_count(text : String, width : Int32) : Int32
    return 1 if width <= 0

    lines = 1
    current_width = 0
    text.split(/(\s+)/).each do |segment|
      segment_width = Tui::Unicode.display_width(segment)
      if current_width + segment_width <= width
        current_width += segment_width
      else
        lines += 1
        current_width = Tui::Unicode.display_width(segment.lstrip)
      end
    end
    lines
  end

  # `side` (laps or history) occupies a FIXED band at the top of the screen.
  # Below it, a scroll area keeps the active display vertically centered;
  # dimmed displays scroll above/below it per `scroll_offset` (↑↓ navigation).
  private def layout_stack(
    rect : Tui::Rect, large : Bool,
    displays : Array(DigitDisplay), count : Int32, active_index : Int32, scroll_offset : Int32,
    side : Tui::Widget, side_has_content : Bool, status : Tui::Label, screen : Screen,
  ) : {Array(Int32?), Int32, ScrollArrows}
    digit_height = Digits.rows(large)

    # The scroll area's centering always reserves room for the maximum
    # 2-line status, even when the current text only needs 1 — using the
    # actual line count here would shift the center by one row whenever the
    # status text's line count changes (e.g. timer editing vs. running),
    # which reads as the display "jumping" vertically. The status label
    # itself still only occupies (and only draws over) the lines it needs.
    max_status_lines = MAX_STATUS_LINES
    status_lines = Math.min(max_status_lines, wrapped_line_count(status.text, rect.width))
    max_side_height = Math.max(0, Math.min(LapGrid::ROWS, rect.height - digit_height - max_status_lines - 2))
    side_height = side_has_content ? max_side_height : 0
    side.rect = Tui::Rect.new(rect.x + 2, rect.y + 1, Math.max(0, rect.width - 4), side_height)
    status.rect = Tui::Rect.new(rect.x, rect.bottom - status_lines, rect.width, status_lines)

    scroll_top = rect.y + side_height + 2
    scroll_bottom = rect.bottom - max_status_lines
    scroll_height = Math.max(0, scroll_bottom - scroll_top)
    slot_height = digit_height + 1
    max_slots = Math.max(1, scroll_height // slot_height)
    active_slot = max_slots // 2

    # Entries created before the active one stay above it, later ones stay
    # below — creation order must never flip while navigating.
    earlier = (0...active_index).to_a
    later = ((active_index + 1)...count).to_a

    before_count = Math.min(active_slot, earlier.size)
    max_offset = Math.max(0, earlier.size - before_count)
    offset = scroll_offset.clamp(0, max_offset)

    # By default (offset 0), show the `before_count` entries CLOSEST to the
    # active one (the tail of `earlier`); scrolling up (offset increasing)
    # progressively reveals the older ones.
    before_start = earlier.size - before_count - offset
    before = earlier[before_start, before_count]? || [] of Int32

    after_max = Math.max(0, max_slots - 1 - before.size)
    after = later[0, after_max]? || later

    slots = Array(Int32?).new(before.size, nil)
    before.each_with_index { |sw_index, i| slots[i] = sw_index }
    slots << nil # active slot
    after.each { |sw_index| slots << sw_index }

    ensure_pool_size(displays, screen, slots.size)
    displays.each { |d| d.large = large }

    # The active entry always sits at `active_slot` — fixed dead center —
    # UNLESS the whole list is smaller than `max_slots`, in which case there
    # aren't enough entries to scroll at all and the (smaller) stack is
    # centered as a block instead. Using the block-centering branch whenever
    # `slots.size < max_slots` (e.g. near the start/end of a long list, where
    # `before`/`after` can't fill every slot) would silently pull the active
    # entry away from center — it must stay fixed whenever more scrolling is
    # possible.
    stack_height = slots.size * slot_height - 1
    y = if count <= max_slots
          scroll_top + (scroll_height - stack_height) // 2
        else
          scroll_top + (active_slot - before.size) * slot_height
        end

    active_rect = Tui::Rect.new(rect.x, y + before.size * slot_height, rect.width, digit_height)

    slots.each_with_index do |_, i|
      displays[i].visible = true
      displays[i].rect = Tui::Rect.new(rect.x, y, rect.width, digit_height)
      y += slot_height
    end
    (slots.size...displays.size).each { |i| displays[i].visible = false }

    up_y = (before_start > 0) ? active_rect.y - 1 : nil
    down_y = (after.size < later.size) ? active_rect.bottom : nil

    {slots, offset, ScrollArrows.new(up_y, down_y, active_rect)}
  end

  # Grows `displays` (and adds the new widgets to `screen`) until it has at
  # least `needed` entries — the pool only ever grows, never shrinks.
  private def ensure_pool_size(displays : Array(DigitDisplay), screen : Screen, needed : Int32) : Nil
    while displays.size < needed
      d = DigitDisplay.new
      screen.add_child(d)
      displays << d
    end
  end

  # Positions the `[↑↓]` scroll indicators just to the right of the active
  # display, based on the gap positions computed by `layout_stack`.
  private def refresh_scroll_arrows(
    arrows : ScrollArrows?, up : DigitDisplay, down : DigitDisplay, active_text : String, large : Bool,
  ) : Nil
    return unless arrows

    text_width = Digits.render(active_text, large).first.size
    x = arrows.active_rect.x + (arrows.active_rect.width + text_width) // 2 + 3

    layout_scroll_arrow(up, '↑', x, arrows.up_y)
    layout_scroll_arrow(down, '↓', x, arrows.down_y)
  end

  # Shows/hides and positions a single scroll arrow glyph; hidden when `y` is `nil`.
  private def layout_scroll_arrow(display : DigitDisplay, glyph : Char, x : Int32, y : Int32?) : Nil
    display.visible = !y.nil?
    return unless y

    display.text = glyph.to_s
    display.style = Theme.style(Theme::MUTED)
    display.rect = Tui::Rect.new(x, y - Digits::HEIGHT // 2, Digits::ARROW_WIDTH, Digits::HEIGHT)
  end
end
