require "crystal_tui"
require "../digits"
require "../theme"

# Overlay modal d'aide : logo CRESIUM en ASCII art + liste des raccourcis
# clavier fusionnant chronomètre et minuteur. Se dessine par-dessus les
# deux écrans, centré dans le rect qui lui est donné (celui de l'App).
class Cresium::HelpOverlay < Tui::Widget
  PADDING_X = 3
  PADDING_Y = 1

  SHORTCUTS = [
    {"?", "afficher / masquer cette aide"},
    {"tab", "changer chronomètre / minuteur"},
    {"space", "start / pause"},
    {"r", "reset / nouvelle saisie"},
    {"l", "lap (chronomètre)"},
    {"hh:mm:ss + enter", "armer le minuteur"},
    {"←→", "déplacer le curseur de saisie (minuteur)"},
    {"backspace", "effacer un chiffre (minuteur)"},
    {"n", "nouveau"},
    {"d", "supprimer"},
    {"↑↓", "naviguer"},
    {"q", "quitter"},
  ]

  def initialize(id : String? = nil)
    super(id)
    @visible = false
  end

  def toggle : Nil
    @visible = !@visible
    mark_dirty!
  end

  def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
    return unless visible?
    return if @rect.empty?

    logo = Cresium::Letters.render("CRESIUM")
    logo_width = logo.first.size
    key_col_width = SHORTCUTS.max_of { |k, _| k.size }
    lines_width = SHORTCUTS.max_of { |k, desc| key_col_width + 2 + desc.size }
    content_width = Math.max(logo_width, lines_width)

    box_width = content_width + PADDING_X * 2
    box_height = logo.size + 1 + SHORTCUTS.size + PADDING_Y * 2

    box_x = @rect.x + (@rect.width - box_width) // 2
    box_y = @rect.y + (@rect.height - box_height) // 2

    border_style = Tui::Style.new(fg: Theme.tui_color(Theme::MUTED))
    title_style = Tui::Style.new(fg: Theme.tui_color(Theme::RUNNING))
    text_style = Tui::Style.new(fg: Theme.tui_color(Theme::NEUTRAL))
    key_style = Tui::Style.new(fg: Theme.tui_color(Theme::PAUSED))

    fill_box(buffer, clip, box_x, box_y, box_width, box_height, text_style)
    buffer.draw_box(box_x, box_y, box_width, box_height, border_style, Tui::BorderStyle::Round)

    logo_x = box_x + (box_width - logo_width) // 2
    logo.each_with_index do |line, row|
      draw_clipped(buffer, clip, logo_x, box_y + PADDING_Y + row, line, title_style)
    end

    text_x = box_x + PADDING_X
    SHORTCUTS.each_with_index do |(key, desc), i|
      y = box_y + PADDING_Y + logo.size + 1 + i
      draw_clipped(buffer, clip, text_x, y, key.rjust(key_col_width), key_style)
      draw_clipped(buffer, clip, text_x + key_col_width + 2, y, desc, text_style)
    end
  end

  private def fill_box(buffer : Tui::Buffer, clip : Tui::Rect, x : Int32, y : Int32, w : Int32, h : Int32, style : Tui::Style) : Nil
    h.times do |dy|
      w.times do |dx|
        next unless clip.contains?(x + dx, y + dy)
        buffer.set(x + dx, y + dy, ' ', style)
      end
    end
  end

  private def draw_clipped(buffer : Tui::Buffer, clip : Tui::Rect, x : Int32, y : Int32, text : String, style : Tui::Style) : Nil
    return unless y >= clip.y && y < clip.y + clip.height
    text.each_char_with_index do |char, i|
      px = x + i
      next unless clip.contains?(px, y)
      buffer.set(px, y, char, style)
    end
  end
end
