require "crystal_tui"

# Vertical position of the gap directly above/below the active slot (where
# `[↑↓]` scroll indicators go, to the right of the active display), or
# `nil` when there's nothing to scroll to in that direction. `active_rect` is
# the active display's own rect, used to vertically center each arrow's cell
# on the gap.
record Cresium::ScrollArrows, up_y : Int32?, down_y : Int32?, active_rect : Tui::Rect
