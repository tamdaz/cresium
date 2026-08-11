require "crystal_tui"

# Stacks multiple widgets (stopwatch, timer) where only one is `visible` at
# a time; renders only visible children, sorted by `z_index`.
class Cresium::Screen < Tui::Widget
  def initialize(id : String? = nil) : Nil
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
