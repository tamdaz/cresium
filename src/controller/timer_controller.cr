require "crystal_tui"
require "../dispatchable"
require "../digit_input"
require "../screen_controller"
require "../timer"
require "../view/timer_view"

# Owns the timer screen's state (the list of timers, which one is active,
# the hh:mm:ss / target-time input buffers) and its keyboard handlers, and
# drives its `TimerView`.
class Cresium::TimerController
  include Dispatchable
  include ScreenController

  TIMER_DIGITS = 6

  # `hh:mm` target-time input, toggled with `[t]` while editing a timer.
  TARGET_TIME_DIGITS = 4

  HISTORY_MAX = 3

  getter timers : Array(Timer)
  getter input : DigitInput
  getter? editing : Bool
  getter view : TimerView

  # Starts with a single fresh (unset) timer, in editing mode.
  def initialize(show_message : Bool) : Nil
    @timers = [Timer.new] of Timer
    @active_index = 0

    @input = DigitInput.new(TIMER_DIGITS)
    @editing = true

    @target_time_mode = false
    @target_time_input = DigitInput.new(TARGET_TIME_DIGITS)
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
    @view.refresh(rect, @timers, active, @editing, @input, @target_time_mode, @target_time_input, @history, show_millis)
  end

  # The input currently receiving keystrokes: the target-time one while
  # `@target_time_mode`, the manual hh:mm:ss one otherwise.
  private def active_input : DigitInput
    @target_time_mode ? @target_time_input : @input
  end

  @[OnKeyPress('t', "target time", :timer_editing)]
  private def toggle_target_time : Nil
    @target_time_mode = !@target_time_mode
  end

  @[OnKeyPress(:digit, "type a digit", :timer_editing)]
  private def handle_digit(c : Char) : Nil
    active_input.type_digit(c)
  end

  @[OnKeyPress(Tui::Key::Backspace, "erase a digit", :timer_editing)]
  private def handle_backspace : Nil
    active_input.backspace
  end

  @[OnKeyPress(Tui::Key::Escape, "cancel input", :timer_editing)]
  private def handle_escape : Nil
    active_input.reset
  end

  @[OnKeyPress("left", "move input cursor", :timer_editing)]
  private def handle_left : Nil
    active_input.move_left
  end

  @[OnKeyPress("right", "move input cursor", :timer_editing)]
  private def handle_right : Nil
    active_input.move_right
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
    buffer = @input.buffer
    hours = buffer[0..1].to_i
    minutes = buffer[2..3].to_i
    seconds = buffer[4..5].to_i
    
    (hours * 3600 + minutes * 60 + seconds).seconds
  end

  # Duration between now and the entered `hh:mm` target time, rolled over
  # to the next day if that time has already passed today.
  private def target_time_duration : Time::Span
    buffer = @target_time_input.buffer
    hours = buffer[0..1].to_i
    minutes = buffer[2..3].to_i

    return Time::Span.zero unless hours < 24 && minutes < 60

    now = Time.local
    target = Time.local(now.year, now.month, now.day, hours, minutes, 0)
    target += 1.day if target <= now
    target - now
  end

  @[OnKeyPress('n', "new", [:timer_editing, :timer_running])]
  private def create_timer : Nil
    @timers << Timer.new
    @active_index = @timers.size - 1
    reset_input true
  end

  @[OnKeyPress('d', "delete", [:timer_editing, :timer_running])]
  private def delete_timer : Nil
    return if @timers.size <= 1
    @timers.delete_at(@active_index)
    @active_index = Math.min(@active_index, @timers.size - 1)
    reset_input !active.set?
    update_status
  end

  @[OnKeyPress("up", "navigate", [:timer_editing, :timer_running])]
  private def move_active_up : Nil
    move_active(-1)
  end

  @[OnKeyPress("down", "navigate", [:timer_editing, :timer_running])]
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
    reset_input true, "0" * (TIMER_DIGITS - 1) + c.to_s
    update_status
  end

  # Resets the hh:mm:ss input buffer and cursor to `buffer` (blank by
  # default) — shared by timer creation, deletion, navigation, and manual
  # reset ([r], or the first digit typed while not editing).
  private def reset_input(editing : Bool, buffer : String = "0" * TIMER_DIGITS) : Nil
    @input.reset(buffer)
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
