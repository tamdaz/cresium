require "crystal_tui"
require "../dispatchable"
require "../timer"
require "../view/timer_view"

# Owns the timer screen's state (the list of timers, which one is active,
# the hh:mm:ss / target-time input buffers) and its keyboard handlers, and
# drives its `TimerView`.
class Cresium::TimerController
  include Dispatchable

  TIMER_DIGITS     = 6
  TIMER_LAST_DIGIT = TIMER_DIGITS - 1

  # `hh:mm` target-time input, toggled with `[t]` while editing a timer.
  TARGET_TIME_DIGITS     = 4
  TARGET_TIME_LAST_DIGIT = TARGET_TIME_DIGITS - 1

  HISTORY_MAX = 3

  @cursor_pos : Int32
  @target_time_cursor_pos : Int32

  getter timers : Array(Timer)
  getter buffer : String
  getter? editing : Bool
  getter view : TimerView

  # Starts with a single fresh (unset) timer, in editing mode.
  def initialize(show_message : Bool)
    @timers = [Timer.new] of Timer
    @active_index = 0

    @buffer = "0" * TIMER_DIGITS
    @cursor_pos = TIMER_LAST_DIGIT
    @cursor_active = false
    @editing = true

    @target_time_mode = false
    @target_time_buffer = "0" * TARGET_TIME_DIGITS
    @target_time_cursor_pos = TARGET_TIME_LAST_DIGIT
    @target_time_cursor_active = false
    @history = [] of Time::Span

    @view = TimerView.new(show_message)
    update_status
  end

  # The currently selected timer (shown centered, in full color).
  def active : Timer
    @timers[@active_index]
  end

  # Entry point for keyboard input on this screen; routes to the
  # `:timer_editing` handlers while entering a duration, or `:timer_running`
  # ones once a timer has been set. Refreshes the status line whenever an
  # editing key was actually handled (its hint text depends on the input).
  def handle_key(event : Tui::KeyEvent) : Bool
    if @editing
      handled = dispatch_key_timer_editing(event)
      update_status if handled
      handled
    else
      dispatch_key_timer_running(event)
    end
  end

  # Positions the view's widgets within `rect` (called on resize/screen switch).
  def layout(rect : Tui::Rect) : Nil
    @view.layout(rect, @timers, @active_index, @history.size)
  end

  # Pushes the current state to the view for rendering (called every frame).
  def tick(rect : Tui::Rect, show_millis : Bool) : Nil
    @view.refresh(
      rect, @timers, active, @editing,
      @buffer, @cursor_pos, @cursor_active,
      @target_time_mode, @target_time_buffer, @target_time_cursor_pos, @target_time_cursor_active,
      @history, show_millis
    )
  end

  @[OnKeyPress('t', "target time", :timer_editing)]
  private def toggle_target_time : Nil
    @target_time_mode = !@target_time_mode
  end

  @[OnKeyPress(:digit, "type a digit", :timer_editing)]
  private def handle_digit(c : Char) : Nil
    if @target_time_mode
      if @target_time_cursor_active
        @target_time_buffer = @target_time_buffer.sub(@target_time_cursor_pos, c)
        @target_time_cursor_pos = Math.min(TARGET_TIME_LAST_DIGIT, @target_time_cursor_pos + 1)
      else
        @target_time_buffer = @target_time_buffer[1..] + c
      end
    elsif @cursor_active
      @buffer = @buffer.sub(@cursor_pos, c)
      @cursor_pos = Math.min(TIMER_LAST_DIGIT, @cursor_pos + 1)
    else
      @buffer = @buffer[1..] + c
    end
  end

  @[OnKeyPress(Tui::Key::Backspace, "erase a digit", :timer_editing)]
  private def handle_backspace : Nil
    if @target_time_mode
      if @target_time_cursor_active
        if @target_time_cursor_pos > 0
          @target_time_cursor_pos -= 1
          @target_time_buffer = @target_time_buffer.sub(@target_time_cursor_pos, '0')
        end
      else
        @target_time_buffer = '0' + @target_time_buffer[0..-2]
      end
    elsif @cursor_active
      if @cursor_pos > 0
        @cursor_pos -= 1
        @buffer = @buffer.sub(@cursor_pos, '0')
      end
    else
      @buffer = '0' + @buffer[0..-2]
    end
  end

  @[OnKeyPress(Tui::Key::Escape, "cancel input", :timer_editing)]
  private def handle_escape : Nil
    if @target_time_mode
      @target_time_buffer = "0" * TARGET_TIME_DIGITS
      @target_time_cursor_active = false
    else
      @buffer = "0" * TIMER_DIGITS
      @cursor_active = false
    end
  end

  @[OnKeyPress("left", "move input cursor", :timer_editing)]
  private def handle_left : Nil
    if @target_time_mode
      @target_time_cursor_pos = @target_time_cursor_active ? Math.max(0, @target_time_cursor_pos - 1) : TARGET_TIME_LAST_DIGIT
      @target_time_cursor_active = true
    else
      @cursor_pos = @cursor_active ? Math.max(0, @cursor_pos - 1) : TIMER_LAST_DIGIT
      @cursor_active = true
    end
  end

  @[OnKeyPress("right", "move input cursor", :timer_editing)]
  private def handle_right : Nil
    if @target_time_mode
      @target_time_cursor_pos = @target_time_cursor_active ? Math.min(TARGET_TIME_LAST_DIGIT, @target_time_cursor_pos + 1) : TARGET_TIME_LAST_DIGIT
      @target_time_cursor_active = true
    else
      @cursor_pos = @cursor_active ? Math.min(TIMER_LAST_DIGIT, @cursor_pos + 1) : TIMER_LAST_DIGIT
      @cursor_active = true
    end
  end

  # Commits the entered duration and starts the countdown immediately —
  # no need to also press `[space]`.
  @[OnKeyPress(Tui::Key::Enter, "set the timer", :timer_editing)]
  private def handle_enter : Nil
    duration = @target_time_mode ? target_time_duration : manual_duration

    unless duration.zero?
      @history << duration
      @history.shift if @history.size > HISTORY_MAX
      active.set duration
      active.start
      @editing = false
    end
  end

  # Parses the hh:mm:ss buffer into a duration.
  private def manual_duration : Time::Span
    hours = @buffer[0..1].to_i
    minutes = @buffer[2..3].to_i
    seconds = @buffer[4..5].to_i
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
    @active_index = @timers.size - 1
    reset_input true
  end

  @[OnKeyPress('d', "delete", :timer_editing)]
  @[OnKeyPress('d', "delete", :timer_running)]
  private def delete_timer : Nil
    return if @timers.size <= 1
    @timers.delete_at(@active_index)
    @active_index = Math.min(@active_index, @timers.size - 1)
    reset_input !active.set?
    update_status
  end

  @[OnKeyPress("up", "navigate", :timer_editing)]
  @[OnKeyPress("up", "navigate", :timer_running)]
  private def move_active_up : Nil
    move_active(-1)
  end

  @[OnKeyPress("down", "navigate", :timer_editing)]
  @[OnKeyPress("down", "navigate", :timer_running)]
  private def move_active_down : Nil
    move_active(1)
  end

  @[OnKeyPress(' ', "start/pause", :timer_running)]
  private def handle_running_toggle : Nil
    active.toggle
  end

  @[OnKeyPress('r', "new input", :timer_running)]
  private def handle_running_reset : Nil
    active.reset
    reset_input true
    update_status
  end

  @[OnKeyPress(:digit, "start a new input", :timer_running)]
  private def handle_running_digit(c : Char) : Nil
    return false if active.running?
    active.reset
    @target_time_mode = false
    reset_input true, "0" * TIMER_LAST_DIGIT + c.to_s
    update_status
  end

  # Resets the hh:mm:ss input buffer and cursor to `buffer` (blank by
  # default) — shared by timer creation, deletion, navigation, and manual
  # reset ([r], or the first digit typed while not editing).
  private def reset_input(editing : Bool, buffer : String = "0" * TIMER_DIGITS) : Nil
    @buffer = buffer
    @cursor_pos = TIMER_LAST_DIGIT
    @cursor_active = false
    @editing = editing
  end

  # Moves the active selection by `delta` (clamped) and resets the input
  # buffer to match the newly active timer's state.
  private def move_active(delta : Int32) : Nil
    new_index = (@active_index + delta).clamp(0, @timers.size - 1)
    return if new_index == @active_index
    @active_index = new_index
    reset_input !active.set?
    update_status
  end

  # Pushes the current mode/state to the view's status line hint.
  private def update_status : Nil
    @view.update_status(@editing, @target_time_mode, active.expired?)
  end
end
