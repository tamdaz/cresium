require "./clock"
require "./format_span"

# Counts down from a duration set at setup time, with pause/reset.
class Cresium::Timer < Cresium::Clock
  # True once `set` is called; false after `reset`. `start` is a no-op
  # until set.
  getter? set = false

  def initialize
    super
    @duration = Time::Span.zero
  end

  # Sets the countdown duration and (re)initializes the clock, stopped.
  # Can be called again on an already-set timer to change the duration.
  def set(duration : Time::Span) : Nil
    @duration = duration
    @accumulated = Time::Span.zero
    @started_at = Time.instant
    @set = true
    @running = false
  end

  def start : Nil
    return unless @set
    super
  end

  # Unsets the timer and clears its duration and accumulated time.
  def reset : Nil
    @set = false
    @running = false
    @accumulated = Time::Span.zero
    @duration = Time::Span.zero
  end

  def zero? : Bool
    !set?
  end

  # Time left before expiration, never negative.
  def remaining : Time::Span
    r = @duration - elapsed
    r.negative? ? Time::Span.zero : r
  end

  # True once the countdown has reached zero (requires being set).
  def expired? : Bool
    @set && remaining <= Time::Span.zero
  end

  def paused? : Bool
    set? && !running? && !expired?
  end

  def format(with_millis : Bool = true) : String
    Cresium.format_span remaining, with_millis
  end
end
