require "option_parser"
require "./app"

# CLI entry point, kept separate from class definitions (`app.cr` etc.) so
# those stay `require`-able without side effects (tests).
show_millis = true
show_message = true

OptionParser.parse do |parser|
  parser.banner = "Usage: cresium [options]"

  parser.on("--no-ms", "Don't show milliseconds") { show_millis = false }

  parser.on("-M", "--no-message", "Don't show the shortcut bar at the bottom") do
    show_message = false
  end

  parser.on("-C", "--no-color", "Disable colors") do
    Cresium::Theme.mode = Cresium::Theme::Mode::None
  end

  parser.on("-T", "--tty", "16-color ANSI mode (TTY/console compatibility)") do
    Cresium::Theme.mode = Cresium::Theme::Mode::Ansi
  end

  parser.on("-v", "--version", "Show the version") do
    puts "version #{Cresium::VERSION} (#{Cresium::GIT_SHA})"
    exit
  end

  parser.on("-h", "--help", "Show help") do
    puts parser
    exit
  end

  parser.invalid_option do |flag|
    STDERR.puts "Invalid option: #{flag}"
    STDERR.puts parser
    exit 1
  end
end

Cresium::App.new(show_millis, show_message).run
