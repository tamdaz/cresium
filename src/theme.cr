require "crystal_tui"
require "./stopwatch"
require "./timer"

# Application color palette, resolved against the color mode the terminal
# actually supports (`Mode`).
module Cresium::Theme
  # Color rendering mode, settable from the CLI (`--no-color`, `--tty`).
  # Only affects `tui_color` / `style`.
  class_property mode : Mode = Mode::Truecolor

  RUNNING = "#aad94c"
  PAUSED  = "#ffb454"
  ALERT   = "#f07178"
  NEUTRAL = "#e6e1cf"
  MUTED   = "#5c6773"

  # 16-color ANSI equivalent of each palette color, used under `Mode::Ansi`.
  ANSI_FALLBACK = {
    RUNNING => Tui::ANSI::Color::BRIGHT_GREEN,
    PAUSED  => Tui::ANSI::Color::BRIGHT_YELLOW,
    ALERT   => Tui::ANSI::Color::BRIGHT_RED,
    NEUTRAL => Tui::ANSI::Color::BRIGHT_WHITE,
    MUTED   => Tui::ANSI::Color::BRIGHT_BLACK,
  }

  enum Mode
    # 24-bit RGB colors (default, modern terminals).
    Truecolor

    # 16-color ANSI fallback, for TTY/console compatibility (`--tty`).
    Ansi

    # No color, terminal's default style (`--no-color`).
    None
  end

  # Color for a `Stopwatch`'s current state (running, zero, paused).
  def self.stopwatch_color(stopwatch : Stopwatch) : String
    return RUNNING if stopwatch.running?
    return ALERT if stopwatch.zero?

    PAUSED
  end

  # Color for a `Timer`'s current state (editing, expired, running, paused).
  def self.timer_color(timer : Timer, editing : Bool) : String
    return NEUTRAL if editing
    return ALERT if timer.expired?
    return RUNNING if timer.running?

    PAUSED
  end

  # Shortcut for the common case: a `Tui::Style` with only a foreground
  # color from the palette, no background or attributes.
  def self.style(hex : String) : Tui::Style
    Tui::Style.new(fg: tui_color(hex))
  end

  # Converts a palette hex color (e.g. `RUNNING`) to a `Tui::Color`, per `mode`.
  def self.tui_color(hex : String) : Tui::Color
    case mode
    when Mode::None then Tui::Color.default
    when Mode::Ansi then Tui::Color.palette(ANSI_FALLBACK[hex])
    else
      r = hex[1, 2].to_i(16)
      g = hex[3, 2].to_i(16)
      b = hex[5, 2].to_i(16)
      Tui::Color.rgb(r, g, b)
    end
  end
end
