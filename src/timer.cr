require "./clock"
require "./format_span"

# Counts down from a duration set at setup time, with pause/reset.
class Cresium::Timer < Cresium::Clock
  # True once `set` is called; false after `reset`. `start` is a no-op
  # until set.
  getter? set = false

  # Starts unset (`zero?` true), with no duration.
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

  # No-op until `set` has been called (unlike `Clock#start`).
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

  # True when the timer has no duration set yet.
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

  # True when set, stopped, and not yet expired.
  def paused? : Bool
    set? && !running? && !expired?
  end

  # Time remaining as `hh:mm:ss[.fff]`.
  def format(with_millis : Bool = true) : String
    Cresium.format_span remaining, with_millis
  end
end
