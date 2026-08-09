require "./clock"
require "./format_span"

# Counts elapsed time since start, with pause/reset and lap recording.
class Cresium::Stopwatch < Cresium::Clock
  # Timestamps recorded by `lap`, in chronological order.
  getter laps = [] of Time::Span

  # Resets the clock to zero and clears recorded laps.
  def reset : Nil
    @accumulated = Time::Span.zero
    @started_at = Time.instant
    @running = false
    @laps.clear
  end

  def zero? : Bool
    !running? && elapsed == Time::Span.zero
  end

  # Records `elapsed` into `laps`. No-op if not running.
  def lap : Nil
    laps << elapsed if running?
  end

  def format(with_millis : Bool = true) : String
    Cresium.format_span elapsed, with_millis
  end
end
