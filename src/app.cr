require "crystal_tui"
require "./cresium"
require "./stopwatch"
require "./timer"
require "./theme"
require "./layout_config"
require "./controller/stopwatch_controller"
require "./controller/timer_controller"
require "./screen_controller"
require "./widget/help_overlay"

# Cresium TUI application: a stopwatch screen and a timer screen (each
# supporting multiple entries), toggled with `[tab]`, plus a help overlay.
# Routes input to whichever screen's controller is active; owns nothing
# screen-specific itself.
class Cresium::App < Tui::App
  MIN_WIDTH  = LayoutConfig::MIN_WIDTH
  MIN_HEIGHT = LayoutConfig::MIN_HEIGHT

  # `show_millis` and `show_message` mirror the `--no-ms` and `--no-message`
  # CLI flags (inverted — see `cli.cr`).
  def initialize(@show_millis : Bool = true, show_message : Bool = true) : Nil
    super()
    # `Tui::App#initialize` reads the terminal size but only assigns it to
    # `@rect` on `run`/`mount_headless` — without this, `@rect` stays
    # `Rect.zero` (and `too_small?` always true) until the app is mounted,
    # breaking direct `on_event`/`on_capture` calls (e.g. from specs). The
    # fallback size used without a real TTY (`Terminal.size` → 80x24) is
    # itself below `MIN_HEIGHT`, so fall back further to a comfortable
    # default in that case — `run`/`check_resize` overwrite `@rect` with the
    # real size once the app is actually mounted on a terminal.
    width, height = Tui::Terminal.size
    width, height = 120, 30 if width < MIN_WIDTH || height < MIN_HEIGHT
    @rect = Tui::Rect.new(0, 0, width, height)

    @stopwatch_controller = StopwatchController.new(show_message)
    @timer_controller = TimerController.new(show_message)
    @screens = [@stopwatch_controller, @timer_controller] of ScreenController
    @current_index = 0
    @timer_controller.view.visible = false

    @help_overlay = HelpOverlay.new

    @too_small_label = Tui::Label.new(
      text: "", align: Tui::Label::Align::Center, style: Theme.style(Theme::ALERT)
    )
    @too_small_label.text_wrap = Tui::Label::TextWrap::Wrap
    @too_small_label.visible = false

    spawn_tick
  end

  # Builds the widget tree: both screens (stacked, one hidden), the help
  # overlay, and the too-small message, all on top of each other via z-index.
  def compose : Array(Tui::Widget)
    @screens.each(&.view.build)

    @help_overlay.z_index = 100
    @too_small_label.z_index = 200

    [@stopwatch_controller.view.screen, @timer_controller.view.screen, @help_overlay, @too_small_label] of Tui::Widget
  end

  # Exposed for `spec/key_dispatch_spec.cr` and external callers; the state
  # itself belongs to the controllers.
  def stopwatches : Array(Stopwatch)
    @stopwatch_controller.stopwatches
  end

  def active_stopwatch : Stopwatch
    @stopwatch_controller.active
  end

  def timers : Array(Timer)
    @timer_controller.timers
  end

  def active_timer : Timer
    @timer_controller.active
  end

  def timer_buffer : String
    @timer_controller.input.buffer
  end

  def timer_editing? : Bool
    @timer_controller.editing?
  end

  # Whether the current terminal size is below `MIN_WIDTH`/`MIN_HEIGHT`.
  private def too_small? : Bool
    LayoutConfig.too_small?(@rect)
  end

  # Gives the app's full rect to both screens (stacked, only one visible).
  private def layout_children : Nil
    @children.each(&.rect=(@rect))

    if too_small?
      @screens.each(&.view.visible=(false))
      @help_overlay.visible = false
      @too_small_label.text = "Terminal too small (#{@rect.width}x#{@rect.height})\n" \
                              "Resize to at least #{MIN_WIDTH}x#{MIN_HEIGHT}"
      too_small_label_lines = 2
      @too_small_label.rect = Tui::Rect.new(
        @rect.x, @rect.y + (@rect.height - too_small_label_lines) // 2, @rect.width, too_small_label_lines
      )
      @too_small_label.visible = true
      return
    end

    @too_small_label.visible = false
    # ameba:disable Naming/BlockParameterName
    @screens.each_with_index { |s, i| s.view.visible = i == @current_index }
    @screens.each(&.layout(@rect))
  end

  # App-wide keys that must win over whichever screen is active: `?` and
  # `[escape]` for the help overlay, `[tab]` to switch screens. Everything
  # else falls through to the base class (which handles `[q]`/quit).
  def on_capture(event : Tui::Event) : Bool
    return super unless event.is_a?(Tui::KeyEvent)

    return super if too_small?

    if event.char == '?' || (@help_overlay.visible? && event.matches?("escape"))
      @help_overlay.toggle
      return true
    end

    return true if @help_overlay.visible?

    if event.matches?("tab")
      toggle_screen
      return true
    end

    super
  end

  # Routes the key to whichever screen's controller is currently active.
  def on_event(event : Tui::Event) : Bool
    return super unless event.is_a?(Tui::KeyEvent)
    return super if too_small?

    handled = @screens[@current_index].handle_key(event)
    handled || super
  end

  # Swaps which screen (stopwatch/timer) is visible and active for input.
  private def toggle_screen : Nil
    @screens[@current_index].view.visible = false
    @current_index = 1 - @current_index
    @screens[@current_index].view.visible = true

    mark_dirty!
  end

  # Background fiber driving the ~60fps render loop: refreshes both
  # controllers' views and asks the framework to redraw.
  private def spawn_tick : Nil
    spawn do
      loop do
        sleep 16.milliseconds
        @screens.each(&.tick(@rect, @show_millis))
        mark_dirty!
      end
    end
  end
end
