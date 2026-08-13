require "crystal_tui"
require "../format_span"
require "../layout_config"
require "../scroll_arrows"
require "../screen"
require "../stack_layout"
require "../timer"
require "../theme"
require "../widget/digit_display"

# Composite widget for the timer screen: a scrollable stack of
# `DigitDisplay`s (one per timer, the active one centered), a history label
# above it (while editing), and a status line below.
class Cresium::TimerView
  include StackLayout

  getter screen : Screen
  getter status : Tui::Label

  @arrows : ScrollArrows?

  # Creates the widgets, unattached to a `Screen` until `build` is called.
  def initialize(@show_message : Bool) : Nil
    @displays = [DigitDisplay.new] of DigitDisplay
    @slots = [nil] of Int32?
    @history_label = Tui::Label.new(text: "")
    @status = Tui::Label.new(text: "", align: Tui::Label::Align::Left)
    @scroll_up = DigitDisplay.new
    @scroll_down = DigitDisplay.new
    @arrows = nil
    @scroll_offset = 0
    @tick_count = 0

    @status.text_wrap = Tui::Label::TextWrap::Wrap

    @screen = Screen.new
  end

  # Wires the initial widgets into `screen`; called once from `App#compose`.
  def build : Nil
    @history_label.z_index = 1
    @status.z_index = 1
    @scroll_up.z_index = 1
    @scroll_down.z_index = 1
    @screen.add_child(@displays.first)
    @screen.add_child(@history_label)
    @screen.add_child(@status)
    @screen.add_child(@scroll_up)
    @screen.add_child(@scroll_down)
  end

  # Shows or hides the whole screen (used when switching to/from the
  # stopwatch screen, or hiding both when the terminal is too small).
  def visible=(value : Bool) : Nil
    @screen.visible = value
  end

  # Positions the display stack, history label, and status line within `rect`.
  def layout(rect : Tui::Rect, timers : Array(Timer), active_index : Int32, history_size : Int32) : Nil
    large = LayoutConfig.large_digits?(rect)

    @slots, @scroll_offset, @arrows = layout_stack(
      rect, large,
      @displays, timers.size, active_index, @scroll_offset,
      @history_label, history_size > 1, @status, @screen
    )
  end

  # Updates the displayed text/styles/history/scroll arrows from the current
  # state; called every frame by `TimerController#tick`. `buffer`/
  # `target_time_buffer` are the raw hh:mm[:ss] digit strings being typed;
  # `cursor_pos`/`target_time_cursor_pos` and `cursor_active`/
  # `target_time_cursor_active` drive the blinking input cursor.
  def refresh(
    rect : Tui::Rect, timers : Array(Timer), active : Timer, editing : Bool,
    buffer : String, cursor_pos : Int32, cursor_active : Bool,
    target_time_mode : Bool, target_time_buffer : String, target_time_cursor_pos : Int32, target_time_cursor_active : Bool,
    history : Array(Time::Span), show_millis_flag : Bool,
  ) : Nil
    @tick_count += 1
    show_millis = LayoutConfig.show_millis?(rect, show_millis_flag)

    active_style = Theme.style(
      if active.expired?
        (@tick_count // 30).even? ? Theme::ALERT : Theme::NEUTRAL
      else
        Theme.timer_color(active, editing)
      end
    )

    active_text = editing ? render_timer_buffer(buffer, target_time_buffer, target_time_mode) : active.format(show_millis)
    cursor_index = editing ? timer_cursor_index(
      active, editing, cursor_pos, cursor_active, target_time_mode, target_time_cursor_pos, target_time_cursor_active
    ) : nil

    @slots.each_with_index do |tm_index, slot|
      d = @displays[slot]
      if tm_index && tm_index < timers.size
        d.text = timers[tm_index].format(show_millis)
        d.style = Theme.style(Theme::MUTED)
        d.cursor_index = nil
      else
        d.text = active_text
        d.style = active_style
        d.cursor_index = cursor_index
      end
    end

    @history_label.text = if editing
                            history.reverse.map { |d| Cresium.format_span d, show_millis }.join("\n")
                          else
                            ""
                          end

    refresh_scroll_arrows(@arrows, @scroll_up, @scroll_down, active_text, LayoutConfig.large_digits?(rect))
  end

  def update_status(editing : Bool, target_time_mode : Bool, expired : Bool) : Nil
    return unless @show_message

    @status.text = String.build do |io|
      io << " Timer — "

      if editing
        if target_time_mode
          io << "type hh:mm then [enter]  [t] duration mode  [←→] cursor  [backspace] erase"
        else
          io << "type hh:mm:ss then [enter]  [t] target time  [←→] cursor  [backspace] erase"
        end
      elsif expired
        io << "Time's up!  [r] new input"
      else
        io << "[space] start/pause  [r] new input"
      end

      io << "  [n] new  [d] delete  [↑↓] navigate  [tab] stopwatch  [q] quit"
    end
  end

  # The input cursor only shows while the active timer has never been set
  # (never during a pause with an already-entered value).
  private def cursor_visible?(editing : Bool, active : Timer) : Bool
    editing && !active.set? && (@tick_count // 30).even?
  end

  # Inserts the `:` separators into the raw digit buffer for display.
  private def render_timer_buffer(buffer : String, target_time_buffer : String, target_time_mode : Bool) : String
    if target_time_mode
      target_time_buffer.insert(2, ':')
    else
      buffer.insert(4, ':').insert(2, ':')
    end
  end

  # Index (in the rendered `hh:mm[:ss]` text) of the digit to highlight as a
  # blinking cursor, or `nil` if no cursor should show. Shifted by one `:`
  # per two-digit group crossed.
  private def timer_cursor_index(
    active : Timer, editing : Bool, cursor_pos : Int32, cursor_active : Bool,
    target_time_mode : Bool, target_time_cursor_pos : Int32, target_time_cursor_active : Bool,
  ) : Int32?
    return nil unless cursor_visible?(editing, active)

    if target_time_mode
      target_time_cursor_pos + target_time_cursor_pos // 2
    else
      cursor_pos + cursor_pos // 2
    end
  end
end
