require "option_parser"
require "crystal_tui"
require "./digits"
require "./stopwatch"
require "./theme"
require "./widget/digit_display"
require "./widget/lap_grid"
require "./widget/help_overlay"

module Cresium
  VERSION = "0.1.0"
  GIT_SHA = {{ `git rev-parse --short HEAD`.chomp.stringify }}

  class Screen < Tui::Widget
    def initialize(id : String? = nil)
      super(id)
    end

    def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
      return unless visible?

      @children.sort_by(&.z_index).each do |child|
        next unless child.visible?

        if child_clip = clip.intersect(child.render_rect)
          child.render(buffer, child_clip)
        end
      end
    end
  end

  class App < Tui::App
    LAP_COMPACT_WIDTH_THRESHOLD = 80
    TIMER_DIGITS                =  6
    TIMER_LAST_DIGIT            = TIMER_DIGITS - 1

    @timer_cursor_pos : Int32

    def initialize(@show_millis : Bool = true, @show_message : Bool = true)
      super()
      @stopwatches = [Stopwatch.new] of Stopwatch
      @active_stopwatch_index = 0
      @stopwatch_scroll_offset = 0

      @timers = [Timer.new] of Timer
      @active_timer_index = 0
      @timer_scroll_offset = 0

      @timer_buffer = "0" * TIMER_DIGITS
      @timer_cursor_pos = TIMER_LAST_DIGIT
      @timer_cursor_active = false
      @timer_editing = true
      @timer_history = [] of Time::Span
      @tick_count = 0
      @current_screen = :stopwatch

      @stopwatch_displays = [DigitDisplay.new] of DigitDisplay
      @stopwatch_slots = [nil] of Int32?
      @stopwatch_laps = LapGrid.new
      @stopwatch_status = Tui::Label.new(text: "", align: Tui::Label::Align::Left)

      @timer_displays = [DigitDisplay.new] of DigitDisplay
      @timer_slots = [nil] of Int32?
      @timer_history_label = Tui::Label.new(text: "")
      @timer_status = Tui::Label.new(text: "", align: Tui::Label::Align::Left)

      @stopwatch_screen = Screen.new
      @timer_screen = Screen.new
      @timer_screen.visible = false

      @help_overlay = HelpOverlay.new

      update_timer_status
      @stopwatch_status.text = " Chronomètre — [space] start/pause  [r] reset  [l] lap  [n] nouveau  [d] supprimer  [↑↓] naviguer  [tab] minuteur  [q] quitter" if @show_message

      spawn_tick
    end

    def compose : Array(Tui::Widget)
      @stopwatch_laps.z_index = 1
      @stopwatch_status.z_index = 1
      @stopwatch_screen.add_child(@stopwatch_displays.first)
      @stopwatch_screen.add_child(@stopwatch_laps)
      @stopwatch_screen.add_child(@stopwatch_status)

      @timer_history_label.z_index = 1
      @timer_status.z_index = 1
      @timer_screen.add_child(@timer_displays.first)
      @timer_screen.add_child(@timer_history_label)
      @timer_screen.add_child(@timer_status)

      @help_overlay.z_index = 100

      [@stopwatch_screen, @timer_screen, @help_overlay] of Tui::Widget
    end

    private def active_stopwatch : Stopwatch
      @stopwatches[@active_stopwatch_index]
    end

    private def active_timer : Timer
      @timers[@active_timer_index]
    end

    private def compact_laps? : Bool
      @rect.width < LAP_COMPACT_WIDTH_THRESHOLD
    end

    # Le format avec millisecondes (`mm:ss.fff`, 90 colonnes) ne tient pas dans
    # un terminal VGA standard 80x25 — bascule automatiquement en `mm:ss` dès
    # que la largeur manque, en plus du `--no-ms` explicite.
    private def show_millis? : Bool
      @show_millis && @rect.width >= 90
    end

    # Donne tout le rect de l'app aux deux écrans (superposés, un seul visible à la fois).
    private def layout_children : Nil
      @children.each { |child| child.rect = @rect }
      @stopwatch_slots, @stopwatch_scroll_offset = layout_stack(
        @stopwatch_displays, @stopwatches.size, @active_stopwatch_index, @stopwatch_scroll_offset,
        @stopwatch_laps, @stopwatch_status, @stopwatch_screen
      )
      @timer_slots, @timer_scroll_offset = layout_stack(
        @timer_displays, @timers.size, @active_timer_index, @timer_scroll_offset,
        @timer_history_label, @timer_status, @timer_screen
      )
    end

    # `side` (laps ou historique) occupe une bande FIXE en haut de l'écran.
    # En dessous, une zone de défilement affiche le display actif toujours
    # centré verticalement ; les displays grisés défilent au-dessus et en
    # dessous de lui selon `scroll_offset` (navigation ↑↓). Retourne le
    # mapping slot -> index de chrono (`nil` pour le slot actif) et le
    # scroll_offset clampé, pour que le refresh sache quoi afficher où.
    private def layout_stack(
      displays : Array(DigitDisplay), count : Int32, active_index : Int32, scroll_offset : Int32,
      side : Tui::Widget, status : Tui::Label, screen : Screen,
    ) : {Array(Int32?), Int32}
      rect = @rect
      side_height = Math.max(0, Math.min(LapGrid::ROWS, rect.height - Digits::HEIGHT - 3))
      side.rect = Tui::Rect.new(rect.x + 2, rect.y + 1, Math.max(0, rect.width - 4), side_height)
      status.rect = Tui::Rect.new(rect.x, rect.bottom - 1, rect.width, 1)

      scroll_top = rect.y + side_height + 2
      scroll_bottom = rect.bottom - 1
      scroll_height = Math.max(0, scroll_bottom - scroll_top)
      slot_height = Digits::HEIGHT + 1
      max_slots = Math.max(1, scroll_height // slot_height)
      active_slot = max_slots // 2

      # Ceux créés avant l'actif restent au-dessus, ceux créés après restent
      # en dessous — l'ordre de création ne doit jamais s'inverser au fil de
      # la navigation.
      earlier = (0...active_index).to_a
      later = ((active_index + 1)...count).to_a

      before_count = Math.min(active_slot, earlier.size)
      max_offset = Math.max(0, earlier.size - before_count)
      offset = scroll_offset.clamp(0, max_offset)

      # Par défaut (offset 0), on affiche les `before_count` chronos les PLUS
      # PROCHES de l'actif (les derniers de `earlier`), pas les plus anciens —
      # naviguer vers le haut (offset croissant) fait remonter progressivement
      # vers les plus anciens.
      before_start = earlier.size - before_count - offset
      before = earlier[before_start, before_count]? || [] of Int32

      after_max = Math.max(0, max_slots - 1 - before.size)
      after = later[0, after_max]? || later

      slots = Array(Int32?).new(before.size, nil)
      before.each_with_index { |sw_index, i| slots[i] = sw_index }
      slots << nil # slot actif
      after.each { |sw_index| slots << sw_index }

      ensure_pool_size(displays, screen, slots.size)

      y = scroll_top + (active_slot - before.size) * slot_height
      slots.each_with_index do |_, i|
        displays[i].visible = true
        displays[i].rect = Tui::Rect.new(rect.x, y, rect.width, Digits::HEIGHT)
        y += slot_height
      end
      (slots.size...displays.size).each { |i| displays[i].visible = false }

      {slots, offset}
    end

    private def ensure_pool_size(displays : Array(DigitDisplay), screen : Screen, needed : Int32) : Nil
      while displays.size < needed
        d = DigitDisplay.new
        screen.add_child(d)
        displays << d
      end
    end

    def on_capture(event : Tui::Event) : Bool
      return super unless event.is_a?(Tui::KeyEvent)

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

    def on_event(event : Tui::Event) : Bool
      return super unless event.is_a?(Tui::KeyEvent)

      handled = @current_screen == :stopwatch ? handle_stopwatch_key(event) : handle_timer_key(event)
      handled || super
    end

    private def toggle_screen : Nil
      if @current_screen == :stopwatch
        @stopwatch_screen.visible = false
        @timer_screen.visible = true
        @current_screen = :timer
      else
        @timer_screen.visible = false
        @stopwatch_screen.visible = true
        @current_screen = :stopwatch
      end
      mark_dirty!
    end

    private def handle_stopwatch_key(event : Tui::KeyEvent) : Bool
      case
      when event.char == ' '      then active_stopwatch.toggle
      when event.char == 'r'      then active_stopwatch.reset
      when event.char == 'l'      then active_stopwatch.lap
      when event.char == 'n'      then create_stopwatch
      when event.char == 'd'      then delete_stopwatch
      when event.matches?("up")   then move_active_stopwatch(-1)
      when event.matches?("down") then move_active_stopwatch(1)
      else                             return false
      end

      true
    end

    private def create_stopwatch : Nil
      @stopwatches << Stopwatch.new
      @active_stopwatch_index = @stopwatches.size - 1
    end

    private def delete_stopwatch : Nil
      return if @stopwatches.size <= 1
      @stopwatches.delete_at(@active_stopwatch_index)
      @active_stopwatch_index = Math.min(@active_stopwatch_index, @stopwatches.size - 1)
    end

    private def move_active_stopwatch(delta : Int32) : Nil
      new_index = (@active_stopwatch_index + delta).clamp(0, @stopwatches.size - 1)
      @active_stopwatch_index = new_index
    end

    private def handle_timer_key(event : Tui::KeyEvent) : Bool
      if @timer_editing
        case
        when (c = event.char) && c.ascii_number?
          if @timer_cursor_active
            @timer_buffer = @timer_buffer.sub(@timer_cursor_pos, c.not_nil!)
            @timer_cursor_pos = Math.min(TIMER_LAST_DIGIT, @timer_cursor_pos + 1)
          else
            @timer_buffer = @timer_buffer[1..] + c.not_nil!
          end
        when event.key == Tui::Key::Backspace
          if @timer_cursor_active
            if @timer_cursor_pos > 0
              @timer_cursor_pos -= 1
              @timer_buffer = @timer_buffer.sub(@timer_cursor_pos, '0')
            end
          else
            @timer_buffer = '0' + @timer_buffer[0..-2]
          end
        when event.key == Tui::Key::Escape
          @timer_buffer = "0" * TIMER_DIGITS
          @timer_cursor_active = false
        when event.matches?("left")
          @timer_cursor_pos = @timer_cursor_active ? Math.max(0, @timer_cursor_pos - 1) : TIMER_LAST_DIGIT
          @timer_cursor_active = true
        when event.matches?("right")
          @timer_cursor_pos = @timer_cursor_active ? Math.min(TIMER_LAST_DIGIT, @timer_cursor_pos + 1) : TIMER_LAST_DIGIT
          @timer_cursor_active = true
        when event.key == Tui::Key::Enter
          hours = @timer_buffer[0..1].to_i
          minutes = @timer_buffer[2..3].to_i
          seconds = @timer_buffer[4..5].to_i
          duration = (hours * 3600 + minutes * 60 + seconds).seconds
          unless duration.zero?
            @timer_history << duration
            @timer_history.shift if @timer_history.size > 3
            active_timer.arm duration
            @timer_editing = false
          end
        when event.char == 'n'
          create_timer
        when event.char == 'd'
          delete_timer
        when event.matches?("up")
          move_active_timer(-1)
        when event.matches?("down")
          move_active_timer(1)
        else
          return false
        end
        update_timer_status
        true
      else
        case
        when event.char == ' '
          active_timer.toggle
        when event.char == 'r'
          active_timer.reset
          @timer_buffer = "0" * TIMER_DIGITS
          @timer_cursor_pos = TIMER_LAST_DIGIT
          @timer_cursor_active = false
          @timer_editing = true
          update_timer_status
        when (c = event.char) && c.ascii_number? && !active_timer.running?
          active_timer.reset
          @timer_buffer = "0" * TIMER_LAST_DIGIT + c.not_nil!.to_s
          @timer_cursor_pos = TIMER_LAST_DIGIT
          @timer_cursor_active = false
          @timer_editing = true
          update_timer_status
        when event.char == 'n'
          create_timer
        when event.char == 'd'
          delete_timer
        when event.matches?("up")
          move_active_timer(-1)
        when event.matches?("down")
          move_active_timer(1)
        else
          return false
        end
        true
      end
    end

    private def create_timer : Nil
      @timers << Timer.new
      @active_timer_index = @timers.size - 1
      @timer_buffer = "0" * TIMER_DIGITS
      @timer_cursor_pos = TIMER_LAST_DIGIT
      @timer_cursor_active = false
      @timer_editing = true
    end

    private def delete_timer : Nil
      return if @timers.size <= 1
      @timers.delete_at(@active_timer_index)
      @active_timer_index = Math.min(@active_timer_index, @timers.size - 1)
      @timer_buffer = "0" * TIMER_DIGITS
      @timer_cursor_pos = TIMER_LAST_DIGIT
      @timer_cursor_active = false
      @timer_editing = !active_timer.armed?
      update_timer_status
    end

    private def move_active_timer(delta : Int32) : Nil
      new_index = (@active_timer_index + delta).clamp(0, @timers.size - 1)
      return if new_index == @active_timer_index
      @active_timer_index = new_index
      @timer_buffer = "0" * TIMER_DIGITS
      @timer_cursor_pos = TIMER_LAST_DIGIT
      @timer_cursor_active = false
      @timer_editing = !active_timer.armed?
      update_timer_status
    end

    private def update_timer_status : Nil
      return unless @show_message

      @timer_status.text = String.build do |io|
        io << " Minuteur — "

        if @timer_editing
          io << "saisie hh:mm:ss puis [enter]  [←→] curseur  [backspace] effacer"
        elsif active_timer.expired?
          io << "Temps écoulé !  [r] nouvelle saisie"
        else
          io << "[space] start/pause  [r] nouvelle saisie"
        end

        io << "  [n] nouveau  [d] supprimer  [↑↓] naviguer  [tab] chronomètre  [q] quitter"
      end
    end

    private def spawn_tick : Nil
      spawn do
        loop do
          sleep 16.milliseconds
          refresh_displays
          mark_dirty!
        end
      end
    end

    # Le curseur de saisie n'apparaît que quand le minuteur actif n'a jamais été armé
    # (jamais pendant une pause avec valeur déjà saisie).
    private def cursor_visible? : Bool
      @timer_editing && !active_timer.armed? && (@tick_count // 30).even?
    end

    private def render_timer_buffer : String
      @timer_buffer.insert(4, ':').insert(2, ':')
    end

    # Index (dans le texte `hh:mm:ss` rendu) du chiffre à surligner en
    # curseur clignotant, ou `nil` si aucun curseur ne doit s'afficher.
    # Décalé d'un `:` par tranche de deux chiffres franchie.
    private def timer_cursor_index : Int32?
      return nil unless cursor_visible?
      @timer_cursor_pos + @timer_cursor_pos // 2
    end

    private def refresh_displays : Nil
      @tick_count += 1

      refresh_stopwatch_stack
      refresh_timer_stack
    end

    private def refresh_stopwatch_stack : Nil
      @stopwatch_slots.each_with_index do |sw_index, slot|
        d = @stopwatch_displays[slot]
        if sw_index && sw_index < @stopwatches.size
          d.text = @stopwatches[sw_index].format
          d.style = Tui::Style.new(fg: Theme.tui_color(Theme::MUTED))
        else
          d.text = active_stopwatch.format(show_millis?)
          d.style = Tui::Style.new(fg: Theme.tui_color(Theme.stopwatch_color(active_stopwatch)))
        end
      end

      @stopwatch_laps.laps = active_stopwatch.laps
      @stopwatch_laps.compact = compact_laps?
      @stopwatch_laps.style = Tui::Style.new(fg: Theme.tui_color(Theme::NEUTRAL))
    end

    private def refresh_timer_stack : Nil
      active_style = Tui::Style.new(fg: Theme.tui_color(
        if active_timer.expired?
          (@tick_count // 30).even? ? Theme::ALERT : Theme::NEUTRAL
        else
          Theme.timer_color(active_timer, @timer_editing)
        end
      ))

      @timer_slots.each_with_index do |tm_index, slot|
        d = @timer_displays[slot]
        if tm_index && tm_index < @timers.size
          d.text = @timers[tm_index].format
          d.style = Tui::Style.new(fg: Theme.tui_color(Theme::MUTED))
          d.cursor_index = nil
        else
          d.text = @timer_editing ? render_timer_buffer : active_timer.format(show_millis?)
          d.style = active_style
          d.cursor_index = @timer_editing ? timer_cursor_index : nil
        end
      end

      @timer_history_label.text = @timer_editing ? @timer_history.reverse.map { |d| Cresium.format_span d, show_millis? }.join("\n") : ""
    end
  end
end

show_millis = true
show_message = true

OptionParser.parse do |parser|
  parser.banner = "Usage: cresium [options]"

  parser.on("--no-ms", "N'affiche pas les millisecondes") { show_millis = false }

  parser.on("-M", "--no-message", "N'affiche pas les raccourcis en bas du TUI") { show_message = false }

  parser.on("-C", "--no-color", "Désactive les couleurs") { Cresium::Theme.mode = Cresium::Theme::Mode::None }

  parser.on("-T", "--tty", "Couleurs en 16 couleurs ANSI (compatibilité TTY/console)") { Cresium::Theme.mode = Cresium::Theme::Mode::Ansi }

  parser.on("-v", "--version", "Affiche la version") do
    puts "version #{Cresium::VERSION} (#{Cresium::GIT_SHA})"
    exit
  end

  parser.on("-h", "--help", "Affiche l'aide") do
    puts parser
    exit
  end

  parser.invalid_option do |flag|
    STDERR.puts "Option invalide : #{flag}"
    STDERR.puts parser
    exit 1
  end
end

Cresium::App.new(show_millis, show_message).run
