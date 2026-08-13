module Cresium
  # Formats a duration as `hh:mm:ss.fff` (or `mm:ss.fff` if under an hour).
  # `with_millis: false` omits the `.fff` part, for narrow terminals.
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
