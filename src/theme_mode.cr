# Color rendering mode for `Theme`, settable from the CLI (`--no-color`, `--tty`).
enum Cresium::Theme::Mode
  # 24-bit RGB colors (default, modern terminals).
  Truecolor

  # 16-color ANSI fallback, for TTY/console compatibility (`--tty`).
  Ansi

  # No color, terminal's default style (`--no-color`).
  None
end
