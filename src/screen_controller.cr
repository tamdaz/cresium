require "crystal_tui"
require "./screen"

# Common interface implemented by `StopwatchView` and `TimerView` — lets
# `ScreenController` (and `App`) treat both screens' views uniformly.
module Cresium::ScreenView
  abstract def screen : Screen
  abstract def build : Nil
  abstract def visible=(value : Bool) : Nil
end

# Common interface implemented by `StopwatchController` and `TimerController`
# — lets `App` treat its two screens uniformly instead of duplicating each
# call site.
module Cresium::ScreenController
  abstract def handle_key(event : Tui::KeyEvent) : Bool
  abstract def layout(rect : Tui::Rect) : Nil
  abstract def tick(rect : Tui::Rect, show_millis : Bool) : Nil
  abstract def view : ScreenView
end
