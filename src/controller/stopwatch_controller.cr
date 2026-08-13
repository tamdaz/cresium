require "crystal_tui"
require "../dispatchable"
require "../screen_controller"
require "../stopwatch"
require "../view/stopwatch_view"

# Owns the stopwatch screen's state (the list of stopwatches, which one is
# active) and its keyboard handlers, and drives its `StopwatchView`.
class Cresium::StopwatchController
  include Dispatchable
  include ScreenController

  getter stopwatches : Array(Stopwatch)
  getter view : StopwatchView

  # Starts with a single fresh stopwatch, active and selected.
  def initialize(show_message : Bool) : Nil
    @stopwatches = [Stopwatch.new] of Stopwatch
    @active_index = 0
    @view = StopwatchView.new(show_message)
  end

  # The currently selected stopwatch (shown centered, in full color).
  def active : Stopwatch
    @stopwatches[@active_index]
  end

  # Entry point for keyboard input on this screen; routes to whichever
  # `@[OnKeyPress(..., :stopwatch)]` handler matches `event`.
  def handle_key(event : Tui::KeyEvent) : Bool
    dispatch_key_stopwatch(event)
  end

  # Positions the view's widgets within `rect` (called on resize/screen switch).
  def layout(rect : Tui::Rect) : Nil
    @view.layout(rect, @stopwatches, @active_index)
  end

  # Pushes the current state to the view for rendering (called every frame).
  def tick(rect : Tui::Rect, show_millis : Bool) : Nil
    @view.refresh(@stopwatches, active, rect, show_millis)
  end

  @[OnKeyPress(' ', "start/pause", :stopwatch)]
  private def handle_toggle : Nil
    active.toggle
  end

  @[OnKeyPress('r', "reset", :stopwatch)]
  private def handle_reset : Nil
    active.reset
  end

  @[OnKeyPress('l', "lap", :stopwatch)]
  private def handle_lap : Nil
    active.lap
  end

  @[OnKeyPress('n', "new", :stopwatch)]
  private def create_stopwatch : Nil
    @stopwatches << Stopwatch.new
    @active_index = @stopwatches.size - 1
  end

  @[OnKeyPress('d', "delete", :stopwatch)]
  private def delete_stopwatch : Nil
    return if @stopwatches.size <= 1

    @stopwatches.delete_at(@active_index)
    @active_index = Math.min(@active_index, @stopwatches.size - 1)
  end

  @[OnKeyPress("up", "navigate", :stopwatch)]
  private def move_active_up : Nil
    move_active(-1)
  end

  @[OnKeyPress("down", "navigate", :stopwatch)]
  private def move_active_down : Nil
    move_active(1)
  end

  # Moves the active selection by `delta`, clamped to the list's bounds.
  private def move_active(delta : Int32) : Nil
    @active_index = (@active_index + delta).clamp(0, @stopwatches.size - 1)
  end
end
