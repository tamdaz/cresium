# Marks a method as the handler for a key.
#
# * `key` — a `Char` literal, the symbol `:digit`, a `Tui::Key` constant, or
#   a key name string (`"up"`).
# * `description` — human-readable label, surfaced through
#   `Cresium::Dispatchable::KEY_BINDINGS` (consumed by `HelpOverlay`).
# * `groups` — a single symbol (`:stopwatch`) or an array of symbols
#   (`[:timer_editing, :timer_running]`); one dispatcher is generated per
#   distinct group.
#
# See `Cresium::Dispatchable` for how `groups` and the return value are used.
annotation OnKeyPress; end
