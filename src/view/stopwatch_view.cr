require "crystal_tui"
require "../layout_config"
require "../screen_controller"
require "../scroll_arrows"
require "../screen"
require "../stack_layout"
require "../stopwatch"
require "../theme"
require "../widget/digit_display"
require "../widget/lap_grid"

# Composite widget for the stopwatch screen: a scrollable stack of
# `DigitDisplay`s (one per stopwatch, the active one centered), a lap grid
# above it, and a status line below.
class Cresium::StopwatchView
  include StackLayout
  include ScreenView

  getter screen : Screen
  getter status : Tui::Label

  @arrows : ScrollArrows?

  # Creates the widgets, unattached to a `Screen` until `build` is called.
  def initialize(show_message : Bool) : Nil
    @displays = [DigitDisplay.new] of DigitDisplay
    @slots = [nil] of Int32?
    @laps = LapGrid.new
    @status = Tui::Label.new(text: "", align: Tui::Label::Align::Left)
    @scroll_up = DigitDisplay.new
    @scroll_down = DigitDisplay.new
    @arrows = nil
    @scroll_offset = 0

    @status.text_wrap = Tui::Label::TextWrap::Wrap
    @status.text = " Stopwatch — [space] start/pause  [r] reset  [l] lap  [n] new  [d] delete  [↑↓] navigate  [tab] timer  [q] quit" if show_message

    @screen = Screen.new
  end

  # Wires the initial widgets into `screen`; called once from `App#compose`.
  def build : Nil
    @laps.z_index = 1
    @status.z_index = 1
    @scroll_up.z_index = 1
    @scroll_down.z_index = 1

    [@displays.first, @laps, @status, @scroll_up, @scroll_down].each do |screen|
      @screen.add_child(screen)
    end
  end

  # Shows or hides the whole screen (used when switching to/from the timer
  # screen, or hiding both when the terminal is too small).
  def visible=(value : Bool) : Nil
    @screen.visible = value
  end

  # Positions the display stack, lap grid, and status line within `rect`.
  def layout(rect : Tui::Rect, stopwatches : Array(Stopwatch), active_index : Int32) : Nil
    active = stopwatches[active_index]
    large = LayoutConfig.large_digits?(rect)

    @slots, @scroll_offset, @arrows = layout_stack(
      rect, large,
      @displays, stopwatches.size, active_index, @scroll_offset,
      @laps, !active.laps.empty?, @status, @screen
    )
  end

  # Updates the displayed text/styles/laps/scroll arrows from the current
  # state; called every frame by `StopwatchController#tick`.
  def refresh(stopwatches : Array(Stopwatch), active : Stopwatch, rect : Tui::Rect, show_millis_flag : Bool) : Nil
    show_millis = LayoutConfig.show_millis?(rect, show_millis_flag)
    active_text = active.format(show_millis)

    @slots.each_with_index do |sw_index, slot|
      d = @displays[slot]

      if sw_index && sw_index < stopwatches.size
        d.text = stopwatches[sw_index].format(show_millis)
        d.style = Theme.style(Theme::MUTED)
      else
        d.text = active_text
        d.style = Theme.style(Theme.stopwatch_color(active))
      end
    end

    @laps.laps = active.laps
    @laps.compact = LayoutConfig.compact_laps?(rect)
    @laps.style = Theme.style(Theme::NEUTRAL)

    refresh_scroll_arrows(@arrows, @scroll_up, @scroll_down, active_text, LayoutConfig.large_digits?(rect))
  end
end
