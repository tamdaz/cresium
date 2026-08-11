# Base for a time counter that accumulates elapsed time via start/pause/toggle.
# Subclasses decide what "zero" means and how the counted value is formatted.
abstract class Cresium::Clock
  # True while time is accumulating (not paused, not reset).
  getter? running = false

  # Starts stopped, at zero accumulated time.
  def initialize : Nil
    @accumulated = Time::Span.zero
    @started_at = Time.instant
  end

  # Starts (or resumes) accumulating time. No-op if already running.
  def start : Nil
    return if @running
    @started_at = Time.instant
    @running = true
  end

  # Freezes the accumulated time so far. No-op if already paused.
  def pause : Nil
    return unless @running
    @accumulated += Time.instant - @started_at
    @running = false
  end

  # Switches between `start` and `pause` depending on the current state.
  def toggle : Nil
    @running ? pause : start
  end

  # Total accumulated time, including the running portion if any.
  @[AlwaysInline]
  def elapsed : Time::Span
    @running ? @accumulated + (Time.instant - @started_at) : @accumulated
  end

  # True when stopped with non-zero accumulated time.
  def paused? : Bool
    !running? && !zero?
  end

  # True when the clock is in its initial state (subclass-defined).
  abstract def zero? : Bool

  # Textual `hh:mm:ss[.fff]` representation of the displayed value.
  abstract def format(with_millis : Bool = true) : String
end
