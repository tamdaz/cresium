require "crystal_tui"

# Terminal-size-dependent display rules, shared by `App` and the screen
# views. Pure predicates over a `Tui::Rect` — no state of its own.
module Cresium::LayoutConfig
  # VGA text mode (80x25) is the smallest resolution we support.
  MIN_WIDTH  = 80
  MIN_HEIGHT = 25

  # Terminal size at/above which digits switch to `Digits::LARGE_GLYPHS`.
  LARGE_MIN_WIDTH  = 120
  LARGE_MIN_HEIGHT =  40

  LAP_COMPACT_WIDTH_THRESHOLD = 80

  # The millisecond format (`mm:ss.fff`, 90 columns) doesn't fit an 80x25
  # VGA terminal — auto-switches to `mm:ss` when width is too narrow, on
  # top of the explicit `--no-ms` flag.
  MILLIS_MIN_WIDTH = 40

  # True when `rect` is below the minimum supported terminal size.
  def self.too_small?(rect : Tui::Rect) : Bool
    rect.width < MIN_WIDTH || rect.height < MIN_HEIGHT
  end

  # True when `rect` is big enough to use the large digit glyphs.
  def self.large_digits?(rect : Tui::Rect) : Bool
    rect.width >= LARGE_MIN_WIDTH && rect.height >= LARGE_MIN_HEIGHT
  end

  # True when `rect` is too narrow to show lap times at full width.
  def self.compact_laps?(rect : Tui::Rect) : Bool
    rect.width < LAP_COMPACT_WIDTH_THRESHOLD
  end

  # Whether milliseconds should actually be shown: `flag` (the `--no-ms`
  # setting) AND enough width to fit them.
  def self.show_millis?(rect : Tui::Rect, flag : Bool) : Bool
    flag && rect.width >= MILLIS_MIN_WIDTH
  end
end
