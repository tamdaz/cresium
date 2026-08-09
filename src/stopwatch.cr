module Cresium
  # Compte le temps écoulé depuis un démarrage, avec pause/reset.
  class Stopwatch
    getter? running = false

    def initialize
      @accumulated = Time::Span.zero
      @started_at = Time.instant
    end

    def start : Nil
      return if @running
      @started_at = Time.instant
      @running = true
    end

    def pause : Nil
      return unless @running
      @accumulated += Time.instant - @started_at
      @running = false
    end

    def toggle : Nil
      @running ? pause : start
    end

    def reset : Nil
      @accumulated = Time::Span.zero
      @started_at = Time.instant
      @running = false
      @laps.clear
    end

    def elapsed : Time::Span
      @running ? @accumulated + (Time.instant - @started_at) : @accumulated
    end

    def zero? : Bool
      !running? && elapsed == Time::Span.zero
    end

    def paused? : Bool
      !running? && !zero?
    end

    getter laps = [] of Time::Span

    def lap : Nil
      laps << elapsed if running?
    end

    def format(with_millis : Bool = true) : String
      Cresium.format_span elapsed, with_millis
    end
  end

  # Décompte depuis une durée fixée à l'armement, avec pause/reset.
  class Timer
    getter? running = false
    getter? armed = false

    def initialize
      @duration = Time::Span.zero
      @accumulated = Time::Span.zero
      @started_at = Time.instant
    end

    def arm(duration : Time::Span) : Nil
      @duration = duration
      @accumulated = Time::Span.zero
      @started_at = Time.instant
      @armed = true
      @running = false
    end

    def start : Nil
      return if @running || !@armed
      @started_at = Time.instant
      @running = true
    end

    def pause : Nil
      return unless @running
      @accumulated += Time.instant - @started_at
      @running = false
    end

    def toggle : Nil
      @running ? pause : start
    end

    def reset : Nil
      @armed = false
      @running = false
      @accumulated = Time::Span.zero
      @duration = Time::Span.zero
    end

    def elapsed : Time::Span
      @running ? @accumulated + (Time.instant - @started_at) : @accumulated
    end

    def remaining : Time::Span
      r = @duration - elapsed
      r.negative? ? Time::Span.zero : r
    end

    def expired? : Bool
      @armed && remaining <= Time::Span.zero
    end

    def paused? : Bool
      armed? && !running? && !expired?
    end

    def format(with_millis : Bool = true) : String
      Cresium.format_span remaining, with_millis
    end
  end

  # Formate une durée en `hh:mm:ss.fff` (ou `mm:ss.fff` si strictement inférieure à 1h).
  # `with_millis: false` omet la partie `.fff` (format compact pour petits terminaux).
  def self.format_span(span : Time::Span, with_millis : Bool = true) : String
    total_seconds = span.total_seconds.to_i
    h = total_seconds // 3600
    m = (total_seconds // 60) % 60
    s = total_seconds % 60

    if with_millis
      ms = span.milliseconds
      h > 0 ? "%02d:%02d:%02d.%03d" % [h, m, s, ms] : "%02d:%02d.%03d" % [m, s, ms]
    else
      h > 0 ? "%02d:%02d:%02d" % [h, m, s] : "%02d:%02d" % [m, s]
    end
  end
end
