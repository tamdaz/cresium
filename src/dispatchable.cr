require "crystal_tui"
require "./on_key_press"

# Generates one `dispatch_key_<group>(event) : Bool` per distinct `group`
# used by `@[OnKeyPress]` in the including class. Each dispatcher calls the
# first matching handler; a handler returning `false` counts as unhandled.
module Cresium::Dispatchable
  macro included
    macro finished
      # A method may carry multiple @[OnKeyPress] (e.g. shared across two
      # groups) — `annotations` (plural) is required to collect them all;
      # `annotation` would only return the first one.
      \{% pairs = [] of Nil %}
      \{% for m in @type.methods %}
        \{% for ann in m.annotations(OnKeyPress) %}
          \{% pairs << {m, ann} %}
        \{% end %}
      \{% end %}
      \{% groups = pairs.map { |p| p[1][2] }.uniq %}
      \{% for group in groups %}
        private def dispatch_key_\{{group.id}}(event : Tui::KeyEvent) : Bool
          \{% group_pairs = pairs.select { |p| p[1][2] == group } %}
          \{% for pair in group_pairs %}
            \{% method = pair[0] %}
            \{% key = pair[1][0] %}
            \{% if key.is_a?(CharLiteral) %}
              if event.char == \{{key}}
                return \{{method.name}} != false
              end
            \{% elsif key.is_a?(SymbolLiteral) && key.id == "digit" %}
              if (c = event.char) && c.ascii_number?
                return \{{method.name}}(c) != false
              end
            \{% elsif key.is_a?(Path) %}
              if event.key == \{{key}}
                return \{{method.name}} != false
              end
            \{% else %}
              if event.matches?(\{{key}})
                return \{{method.name}} != false
              end
            \{% end %}
          \{% end %}
          false
        end
      \{% end %}
    end
  end
end
