require "crystal_tui"
require "./stopwatch"

module Cresium::Theme
  class_property mode : Mode = Mode::Truecolor

  RUNNING = "#aad94c"
  PAUSED  = "#ffb454"
  ALERT   = "#f07178"
  NEUTRAL = "#e6e1cf"
  MUTED   = "#5c6773"

  ANSI_FALLBACK = {
    RUNNING => Tui::ANSI::Color::BRIGHT_GREEN,
    PAUSED  => Tui::ANSI::Color::BRIGHT_YELLOW,
    ALERT   => Tui::ANSI::Color::BRIGHT_RED,
    NEUTRAL => Tui::ANSI::Color::BRIGHT_WHITE,
    MUTED   => Tui::ANSI::Color::BRIGHT_BLACK,
  }

  enum Mode
    Truecolor
    Ansi
    None
  end

  def self.stopwatch_color(stopwatch : Stopwatch) : String
    return RUNNING if stopwatch.running?
    return ALERT if stopwatch.zero?
    PAUSED
  end

  def self.timer_color(timer : Timer, editing : Bool) : String
    return NEUTRAL if editing
    return ALERT if timer.expired?
    return RUNNING if timer.running?
    PAUSED
  end

  def self.tui_color(hex : String) : Tui::Color
    case mode
    when Mode::None
      Tui::Color.default
    when Mode::Ansi
      Tui::Color.palette(ANSI_FALLBACK[hex])
    else
      r = hex[1, 2].to_i(16)
      g = hex[3, 2].to_i(16)
      b = hex[5, 2].to_i(16)
      Tui::Color.rgb(r, g, b)
    end
  end
end
