require "crystal_tui"
require "./cresium"
require "./digits"
require "./stopwatch"
require "./timer"
require "./theme"
require "./dispatchable"
require "./screen"
require "./widget/digit_display"
require "./widget/lap_grid"
require "./widget/help_overlay"

# Cresium TUI application: a stopwatch screen and a timer screen (each
# supporting multiple entries), toggled with `[tab]`, plus a help overlay.
class Cresium::App < Tui::App
  include Dispatchable

  LAP_COMPACT_WIDTH_THRESHOLD = 80
  TIMER_DIGITS                =  6
  TIMER_LAST_DIGIT            = TIMER_DIGITS - 1

  # `hh:mm` target-time input, toggled with `[t]` while editing a timer.
  TARGET_TIME_DIGITS      =  4
  TARGET_TIME_LAST_DIGIT  = TARGET_TIME_DIGITS - 1

  # VGA text mode (80x25) is the smallest resolution we support.
  MIN_WIDTH  = 80
  MIN_HEIGHT = 25

  # Terminal size at/above which digits switch to `Digits::LARGE_GLYPHS`.
  LARGE_MIN_WIDTH  = 160
  LARGE_MIN_HEIGHT = 40

  # Vertical position of the gap directly above/below the active slot (where
  # `[↑↓]` scroll indicators go, to the right of the active display), or
  # `nil` when there's nothing to scroll to in that direction. `center_y` is
  # the active display's own `y`, used to vertically center each arrow's cell
  # on the gap.
  record ScrollArrows, up_y : Int32?, down_y : Int32?, active_rect : Tui::Rect

  @timer_cursor_pos : Int32
  @target_time_cursor_pos : Int32
  @stopwatch_scroll_arrows : ScrollArrows?
  @timer_scroll_arrows : ScrollArrows?

  getter stopwatches : Array(Stopwatch)
  getter timers : Array(Timer)
  getter? timer_editing : Bool
  getter timer_buffer : String

  # `show_millis` and `show_message` mirror the `--no-ms` and `--no-message`
  # CLI flags (inverted — see `cli.cr`).
  def initialize(@show_millis : Bool = true, @show_message : Bool = true)
    super()
    @stopwatches = [Stopwatch.new] of Stopwatch
    @active_stopwatch_index = 0
    @stopwatch_scroll_offset = 0

    @timers = [Timer.new] of Timer
    @active_timer_index = 0
    @timer_scroll_offset = 0

    @timer_buffer = "0" * TIMER_DIGITS
    @timer_cursor_pos = TIMER_LAST_DIGIT
    @timer_cursor_active = false
    @timer_editing = true

    @target_time_mode = false
    @target_time_buffer = "0" * TARGET_TIME_DIGITS
    @target_time_cursor_pos = TARGET_TIME_LAST_DIGIT
    @target_time_cursor_active = false
    @timer_history = [] of Time::Span
    @tick_count = 0
    @current_screen = :stopwatch

    @stopwatch_displays = [DigitDisplay.new] of DigitDisplay
    @stopwatch_slots = [nil] of Int32?
    @stopwatch_laps = LapGrid.new
    @stopwatch_status = Tui::Label.new(text: "", align: Tui::Label::Align::Left)
    @stopwatch_scroll_up = DigitDisplay.new
    @stopwatch_scroll_down = DigitDisplay.new
    @stopwatch_scroll_arrows = nil

    @timer_displays = [DigitDisplay.new] of DigitDisplay
    @timer_slots = [nil] of Int32?
    @timer_history_label = Tui::Label.new(text: "")
    @timer_status = Tui::Label.new(text: "", align: Tui::Label::Align::Left)
    @timer_scroll_up = DigitDisplay.new
    @timer_scroll_down = DigitDisplay.new
    @timer_scroll_arrows = nil

    @stopwatch_screen = Screen.new
    @timer_screen = Screen.new
    @timer_screen.visible = false

    @help_overlay = HelpOverlay.new

    @too_small_label = Tui::Label.new(
      text: "", align: Tui::Label::Align::Center, style: Theme.style(Theme::ALERT)
    )
    @too_small_label.text_wrap = Tui::Label::TextWrap::Wrap
    @too_small_label.visible = false

    @stopwatch_status.text_wrap = Tui::Label::TextWrap::Wrap
    @timer_status.text_wrap = Tui::Label::TextWrap::Wrap

    update_timer_status
    @stopwatch_status.text = " Stopwatch — [space] start/pause  [r] reset  [l] lap  [n] new  [d] delete  [↑↓] navigate  [tab] timer  [q] quit" if @show_message

    spawn_tick
  end

  def compose : Array(Tui::Widget)
    @stopwatch_laps.z_index = 1
    @stopwatch_status.z_index = 1
    @stopwatch_scroll_up.z_index = 1
    @stopwatch_scroll_down.z_index = 1
    @stopwatch_screen.add_child(@stopwatch_displays.first)
    @stopwatch_screen.add_child(@stopwatch_laps)
    @stopwatch_screen.add_child(@stopwatch_status)
    @stopwatch_screen.add_child(@stopwatch_scroll_up)
    @stopwatch_screen.add_child(@stopwatch_scroll_down)

    @timer_history_label.z_index = 1
    @timer_status.z_index = 1
    @timer_scroll_up.z_index = 1
    @timer_scroll_down.z_index = 1
    @timer_screen.add_child(@timer_displays.first)
    @timer_screen.add_child(@timer_history_label)
    @timer_screen.add_child(@timer_status)
    @timer_screen.add_child(@timer_scroll_up)
    @timer_screen.add_child(@timer_scroll_down)

    @help_overlay.z_index = 100
    @too_small_label.z_index = 200

    [@stopwatch_screen, @timer_screen, @help_overlay, @too_small_label] of Tui::Widget
  end

  def active_stopwatch : Stopwatch
    @stopwatches[@active_stopwatch_index]
  end

  def active_timer : Timer
    @timers[@active_timer_index]
  end

  private def compact_laps? : Bool
    @rect.width < LAP_COMPACT_WIDTH_THRESHOLD
  end

  # The millisecond format (`mm:ss.fff`, 90 columns) doesn't fit an 80x25
  # VGA terminal — auto-switches to `mm:ss` when width is too narrow, on
  # top of the explicit `--no-ms` flag.
  private def show_millis? : Bool
    @show_millis && @rect.width >= 40
  end

  private def too_small? : Bool
    @rect.width < MIN_WIDTH || @rect.height < MIN_HEIGHT
  end

  private def large_digits? : Bool
    @rect.width >= LARGE_MIN_WIDTH && @rect.height >= LARGE_MIN_HEIGHT
  end

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

  # Gives the app's full rect to both screens (stacked, only one visible).
  private def layout_children : Nil
    @children.each { |child| child.rect = @rect }

    if too_small?
      @stopwatch_screen.visible = false
      @timer_screen.visible = false
      @too_small_label.text = "Terminal trop petit (#{@rect.width}x#{@rect.height})\n" \
                               "Agrandissez-le a #{MIN_WIDTH}x#{MIN_HEIGHT} minimum"
      too_small_label_lines = 2
      @too_small_label.rect = Tui::Rect.new(
        @rect.x, @rect.y + (@rect.height - too_small_label_lines) // 2, @rect.width, too_small_label_lines
      )
      @too_small_label.visible = true
      return
    end

    @too_small_label.visible = false
    @stopwatch_screen.visible = @current_screen == :stopwatch
    @timer_screen.visible = @current_screen == :timer

    @stopwatch_slots, @stopwatch_scroll_offset, @stopwatch_scroll_arrows = layout_stack(
      @stopwatch_displays, @stopwatches.size, @active_stopwatch_index, @stopwatch_scroll_offset,
      @stopwatch_laps, !active_stopwatch.laps.empty?, @stopwatch_status, @stopwatch_screen
    )

    @timer_slots, @timer_scroll_offset, @timer_scroll_arrows = layout_stack(
      @timer_displays, @timers.size, @active_timer_index, @timer_scroll_offset,
      @timer_history_label, @timer_history.size > 1, @timer_status, @timer_screen
    )
  end

  # `side` (laps or history) occupies a FIXED band at the top of the screen.
  # Below it, a scroll area keeps the active display vertically centered;
  # dimmed displays scroll above/below it per `scroll_offset` (↑↓ navigation).
  private def layout_stack(
    displays : Array(DigitDisplay), count : Int32, active_index : Int32, scroll_offset : Int32,
    side : Tui::Widget, side_has_content : Bool, status : Tui::Label, screen : Screen,
  ) : {Array(Int32?), Int32, ScrollArrows}
    rect = @rect
    large = large_digits?
    digit_height = Digits.rows(large)

    # The scroll area's centering always reserves room for the maximum
    # 2-line status, even when the current text only needs 1 — using the
    # actual line count here would shift the center by one row whenever the
    # status text's line count changes (e.g. timer editing vs. running),
    # which reads as the display "jumping" vertically. The status label
    # itself still only occupies (and only draws over) the lines it needs.
    max_status_lines = 2
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

  private def ensure_pool_size(displays : Array(DigitDisplay), screen : Screen, needed : Int32) : Nil
    while displays.size < needed
      d = DigitDisplay.new
      screen.add_child(d)
      displays << d
    end
  end

  def on_capture(event : Tui::Event) : Bool
    return super unless event.is_a?(Tui::KeyEvent)

    return super if too_small?

    if event.char == '?' || (@help_overlay.visible? && event.matches?("escape"))
      @help_overlay.toggle
      return true
    end

    return true if @help_overlay.visible?

    if event.matches?("tab")
      toggle_screen
      return true
    end

    super
  end

  def on_event(event : Tui::Event) : Bool
    return super unless event.is_a?(Tui::KeyEvent)
    return super if too_small?

    handled = @current_screen == :stopwatch ? handle_stopwatch_key(event) : handle_timer_key(event)
    handled || super
  end

  private def toggle_screen : Nil
    if @current_screen == :stopwatch
      @stopwatch_screen.visible = false
      @timer_screen.visible = true
      @current_screen = :timer
    else
      @timer_screen.visible = false
      @stopwatch_screen.visible = true
      @current_screen = :stopwatch
    end

    mark_dirty!
  end

  private def handle_stopwatch_key(event : Tui::KeyEvent) : Bool
    dispatch_key_stopwatch(event)
  end

  @[OnKeyPress(' ', "start/pause", :stopwatch)]
  private def handle_stopwatch_toggle : Nil
    active_stopwatch.toggle
  end

  @[OnKeyPress('r', "reset", :stopwatch)]
  private def handle_stopwatch_reset : Nil
    active_stopwatch.reset
  end

  @[OnKeyPress('l', "lap", :stopwatch)]
  private def handle_stopwatch_lap : Nil
    active_stopwatch.lap
  end

  @[OnKeyPress('n', "new", :stopwatch)]
  private def create_stopwatch : Nil
    @stopwatches << Stopwatch.new
    @active_stopwatch_index = @stopwatches.size - 1
  end

  @[OnKeyPress('d', "delete", :stopwatch)]
  private def delete_stopwatch : Nil
    return if @stopwatches.size <= 1

    @stopwatches.delete_at(@active_stopwatch_index)
    @active_stopwatch_index = Math.min(@active_stopwatch_index, @stopwatches.size - 1)
  end

  @[OnKeyPress("up", "navigate", :stopwatch)]
  private def move_active_stopwatch_up : Nil
    move_active_stopwatch(-1)
  end

  @[OnKeyPress("down", "navigate", :stopwatch)]
  private def move_active_stopwatch_down : Nil
    move_active_stopwatch(1)
  end

  private def move_active_stopwatch(delta : Int32) : Nil
    new_index = (@active_stopwatch_index + delta).clamp(0, @stopwatches.size - 1)
    @active_stopwatch_index = new_index
  end

  private def handle_timer_key(event : Tui::KeyEvent) : Bool
    if @timer_editing
      handled = dispatch_key_timer_editing(event)
      update_timer_status if handled
      handled
    else
      dispatch_key_timer_running(event)
    end
  end

  @[OnKeyPress('t', "target time", :timer_editing)]
  private def handle_timer_editing_toggle_target_time : Nil
    @target_time_mode = !@target_time_mode
  end

  @[OnKeyPress(:digit, "type a digit", :timer_editing)]
  private def handle_timer_editing_digit(c : Char) : Nil
    if @target_time_mode
      if @target_time_cursor_active
        @target_time_buffer = @target_time_buffer.sub(@target_time_cursor_pos, c)
        @target_time_cursor_pos = Math.min(TARGET_TIME_LAST_DIGIT, @target_time_cursor_pos + 1)
      else
        @target_time_buffer = @target_time_buffer[1..] + c
      end
    elsif @timer_cursor_active
      @timer_buffer = @timer_buffer.sub(@timer_cursor_pos, c)
      @timer_cursor_pos = Math.min(TIMER_LAST_DIGIT, @timer_cursor_pos + 1)
    else
      @timer_buffer = @timer_buffer[1..] + c
    end
  end

  @[OnKeyPress(Tui::Key::Backspace, "erase a digit", :timer_editing)]
  private def handle_timer_editing_backspace : Nil
    if @target_time_mode
      if @target_time_cursor_active
        if @target_time_cursor_pos > 0
          @target_time_cursor_pos -= 1
          @target_time_buffer = @target_time_buffer.sub(@target_time_cursor_pos, '0')
        end
      else
        @target_time_buffer = '0' + @target_time_buffer[0..-2]
      end
    elsif @timer_cursor_active
      if @timer_cursor_pos > 0
        @timer_cursor_pos -= 1
        @timer_buffer = @timer_buffer.sub(@timer_cursor_pos, '0')
      end
    else
      @timer_buffer = '0' + @timer_buffer[0..-2]
    end
  end

  @[OnKeyPress(Tui::Key::Escape, "cancel input", :timer_editing)]
  private def handle_timer_editing_escape : Nil
    if @target_time_mode
      @target_time_buffer = "0" * TARGET_TIME_DIGITS
      @target_time_cursor_active = false
    else
      @timer_buffer = "0" * TIMER_DIGITS
      @timer_cursor_active = false
    end
  end

  @[OnKeyPress("left", "move input cursor", :timer_editing)]
  private def handle_timer_editing_left : Nil
    if @target_time_mode
      @target_time_cursor_pos = @target_time_cursor_active ? Math.max(0, @target_time_cursor_pos - 1) : TARGET_TIME_LAST_DIGIT
      @target_time_cursor_active = true
    else
      @timer_cursor_pos = @timer_cursor_active ? Math.max(0, @timer_cursor_pos - 1) : TIMER_LAST_DIGIT
      @timer_cursor_active = true
    end
  end

  @[OnKeyPress("right", "move input cursor", :timer_editing)]
  private def handle_timer_editing_right : Nil
    if @target_time_mode
      @target_time_cursor_pos = @target_time_cursor_active ? Math.min(TARGET_TIME_LAST_DIGIT, @target_time_cursor_pos + 1) : TARGET_TIME_LAST_DIGIT
      @target_time_cursor_active = true
    else
      @timer_cursor_pos = @timer_cursor_active ? Math.min(TIMER_LAST_DIGIT, @timer_cursor_pos + 1) : TIMER_LAST_DIGIT
      @timer_cursor_active = true
    end
  end

  @[OnKeyPress(Tui::Key::Enter, "set the timer", :timer_editing)]
  private def handle_timer_editing_enter : Nil
    duration = @target_time_mode ? target_time_duration : manual_duration

    unless duration.zero?
      @timer_history << duration
      @timer_history.shift if @timer_history.size > 3
      active_timer.set duration
      @timer_editing = false
    end
  end

  private def manual_duration : Time::Span
    hours = @timer_buffer[0..1].to_i
    minutes = @timer_buffer[2..3].to_i
    seconds = @timer_buffer[4..5].to_i
    (hours * 3600 + minutes * 60 + seconds).seconds
  end

  # Duration between now and the entered `hh:mm` target time, rolled over
  # to the next day if that time has already passed today.
  private def target_time_duration : Time::Span
    hours = @target_time_buffer[0..1].to_i
    minutes = @target_time_buffer[2..3].to_i
    return Time::Span.zero unless hours < 24 && minutes < 60

    now = Time.local
    target = Time.local(now.year, now.month, now.day, hours, minutes, 0)
    target += 1.day if target <= now
    target - now
  end

  @[OnKeyPress('n', "new", :timer_editing)]
  @[OnKeyPress('n', "new", :timer_running)]
  private def create_timer : Nil
    @timers << Timer.new
    @active_timer_index = @timers.size - 1
    reset_timer_input true
  end

  @[OnKeyPress('d', "delete", :timer_editing)]
  @[OnKeyPress('d', "delete", :timer_running)]
  private def delete_timer : Nil
    return if @timers.size <= 1
    @timers.delete_at(@active_timer_index)
    @active_timer_index = Math.min(@active_timer_index, @timers.size - 1)
    reset_timer_input !active_timer.set?
    update_timer_status
  end

  @[OnKeyPress("up", "navigate", :timer_editing)]
  @[OnKeyPress("up", "navigate", :timer_running)]
  private def move_active_timer_up : Nil
    move_active_timer(-1)
  end

  @[OnKeyPress("down", "navigate", :timer_editing)]
  @[OnKeyPress("down", "navigate", :timer_running)]
  private def move_active_timer_down : Nil
    move_active_timer(1)
  end

  @[OnKeyPress(' ', "start/pause", :timer_running)]
  private def handle_timer_running_toggle : Nil
    active_timer.toggle
  end

  @[OnKeyPress('r', "new input", :timer_running)]
  private def handle_timer_running_reset : Nil
    active_timer.reset
    reset_timer_input true
    update_timer_status
  end

  @[OnKeyPress(:digit, "start a new input", :timer_running)]
  private def handle_timer_running_digit(c : Char) : Nil
    return false if active_timer.running?
    active_timer.reset
    @target_time_mode = false
    reset_timer_input true, "0" * TIMER_LAST_DIGIT + c.to_s
    update_timer_status
  end

  # Resets the hh:mm:ss input buffer and cursor to `buffer` (blank by
  # default) — shared by timer creation, deletion, navigation, and manual
  # reset ([r], or the first digit typed while not editing).
  private def reset_timer_input(editing : Bool, buffer : String = "0" * TIMER_DIGITS) : Nil
    @timer_buffer = buffer
    @timer_cursor_pos = TIMER_LAST_DIGIT
    @timer_cursor_active = false
    @timer_editing = editing
  end

  private def move_active_timer(delta : Int32) : Nil
    new_index = (@active_timer_index + delta).clamp(0, @timers.size - 1)
    return if new_index == @active_timer_index
    @active_timer_index = new_index
    reset_timer_input !active_timer.set?
    update_timer_status
  end

  private def update_timer_status : Nil
    return unless @show_message

    @timer_status.text = String.build do |io|
      io << " Timer — "

      if @timer_editing
        if @target_time_mode
          io << "type hh:mm then [enter]  [t] duration mode  [←→] cursor  [backspace] erase"
        else
          io << "type hh:mm:ss then [enter]  [t] target time  [←→] cursor  [backspace] erase"
        end
      elsif active_timer.expired?
        io << "Time's up!  [r] new input"
      else
        io << "[space] start/pause  [r] new input"
      end

      io << "  [n] new  [d] delete  [↑↓] navigate  [tab] stopwatch  [q] quit"
    end
  end

  private def spawn_tick : Nil
    spawn do
      loop do
        sleep 16.milliseconds
        refresh_displays
        mark_dirty!
      end
    end
  end

  # The input cursor only shows while the active timer has never been set
  # (never during a pause with an already-entered value).
  private def cursor_visible? : Bool
    @timer_editing && !active_timer.set? && (@tick_count // 30).even?
  end

  private def render_timer_buffer : String
    if @target_time_mode
      @target_time_buffer.insert(2, ':')
    else
      @timer_buffer.insert(4, ':').insert(2, ':')
    end
  end

  # Index (in the rendered `hh:mm[:ss]` text) of the digit to highlight as a
  # blinking cursor, or `nil` if no cursor should show. Shifted by one `:`
  # per two-digit group crossed.
  private def timer_cursor_index : Int32?
    return nil unless cursor_visible?

    if @target_time_mode
      @target_time_cursor_pos + @target_time_cursor_pos // 2
    else
      @timer_cursor_pos + @timer_cursor_pos // 2
    end
  end

  private def refresh_displays : Nil
    @tick_count += 1

    refresh_stopwatch_stack
    refresh_timer_stack
  end

  private def refresh_stopwatch_stack : Nil
    active_text = active_stopwatch.format(show_millis?)

    @stopwatch_slots.each_with_index do |sw_index, slot|
      d = @stopwatch_displays[slot]
      if sw_index && sw_index < @stopwatches.size
        d.text = @stopwatches[sw_index].format(show_millis?)
        d.style = Theme.style(Theme::MUTED)
      else
        d.text = active_text
        d.style = Theme.style(Theme.stopwatch_color(active_stopwatch))
      end
    end

    @stopwatch_laps.laps = active_stopwatch.laps
    @stopwatch_laps.compact = compact_laps?
    @stopwatch_laps.style = Theme.style(Theme::NEUTRAL)

    refresh_scroll_arrows(@stopwatch_scroll_arrows, @stopwatch_scroll_up, @stopwatch_scroll_down, active_text)
  end

  private def refresh_timer_stack : Nil
    active_style = Theme.style(
      if active_timer.expired?
        (@tick_count // 30).even? ? Theme::ALERT : Theme::NEUTRAL
      else
        Theme.timer_color(active_timer, @timer_editing)
      end
    )

    active_text = @timer_editing ? render_timer_buffer : active_timer.format(show_millis?)

    @timer_slots.each_with_index do |tm_index, slot|
      d = @timer_displays[slot]
      if tm_index && tm_index < @timers.size
        d.text = @timers[tm_index].format(show_millis?)
        d.style = Theme.style(Theme::MUTED)
        d.cursor_index = nil
      else
        d.text = active_text
        d.style = active_style
        d.cursor_index = @timer_editing ? timer_cursor_index : nil
      end
    end

    @timer_history_label.text = if @timer_editing
                                  @timer_history.reverse.map { |d| Cresium.format_span d, show_millis? }.join("\n")
                                else
                                  ""
                                end

    refresh_scroll_arrows(@timer_scroll_arrows, @timer_scroll_up, @timer_scroll_down, active_text)
  end

  private def refresh_scroll_arrows(
    arrows : ScrollArrows?, up : DigitDisplay, down : DigitDisplay, active_text : String,
  ) : Nil
    return unless arrows

    text_width = Digits.render(active_text, large_digits?).first.size
    x = arrows.active_rect.x + (arrows.active_rect.width + text_width) // 2 + 3

    layout_scroll_arrow(up, '↑', x, arrows.up_y)
    layout_scroll_arrow(down, '↓', x, arrows.down_y)
  end

  private def layout_scroll_arrow(display : DigitDisplay, glyph : Char, x : Int32, y : Int32?) : Nil
    display.visible = !y.nil?
    return unless y

    display.text = glyph.to_s
    display.style = Theme.style(Theme::MUTED)
    display.rect = Tui::Rect.new(x, y - Digits::HEIGHT // 2, Digits::ARROW_WIDTH, Digits::HEIGHT)
  end
end
