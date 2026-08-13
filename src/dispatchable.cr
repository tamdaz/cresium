require "crystal_tui"
require "./on_key_press"

# Generates, in the including class:
#
# * one `dispatch_key_<group>(event) : Bool` per distinct group referenced by
#   an `@[OnKeyPress]` annotation — each calls the first matching handler (in
#   source order), and a handler returning `false` counts as unhandled;
# * a `KEY_BINDINGS` constant, an `Array({String, String, Array(Symbol)})` of
#   `{key, description, groups}` triples describing every binding, in source
#   order, deduplicated on `{key, description}` (a binding shared by several
#   groups appears once, with all its groups merged) — consumed by
#   `Cresium::HelpOverlay` instead of restating each description by hand.
module Cresium::Dispatchable
  macro included
    macro finished
      define_key_dispatchers
    end
  end

  # Called from `macro finished` so that `@type.methods` sees handlers
  # defined after `include Dispatchable`.
  macro define_key_dispatchers
    # A method may carry multiple @[OnKeyPress] (e.g. shared across two
    # groups) — `annotations` (plural) is required to collect them all;
    # `annotation` would only return the first one.
    {% bindings = [] of Nil %}
    {% for m in @type.methods %}
      {% for ann in m.annotations(OnKeyPress) %}
        {% if !ann[2].is_a?(SymbolLiteral) && !ann[2].is_a?(ArrayLiteral) %}
          {% ann.raise "OnKeyPress group must be a symbol or an array of symbols, got #{ann[2]}" %}
        {% end %}

        {% groups = ann[2].is_a?(ArrayLiteral) ? ann[2] : [ann[2]] %}
        {% bindings << {m, ann[0], ann[1], groups} %}
      {% end %}
    {% end %}

    # ameba:disable Naming/BlockParameterName
    {% all_groups = bindings.map { |b| b[3] }.reduce([] of Nil) { |acc, g| acc + g }.uniq %}

    {% for group in all_groups %}
      private def dispatch_key_{{group.id}}(event : Tui::KeyEvent) : Bool
        {% for binding in bindings %}
          {% if binding[3].includes?(group) %}
            {% method = binding[0] %}
            {% key = binding[1] %}

            {% if key.is_a?(CharLiteral) %}
              if event.char == {{key}}
                return {{method.name}} != false
              end
            {% elsif key.is_a?(SymbolLiteral) && key.id == "digit" %}
              if (c = event.char) && c.ascii_number?
                return {{method.name}}(c) != false
              end
            {% elsif key.is_a?(Path) %}
              if event.key == {{key}}
                return {{method.name}} != false
              end
            {% else %}
              if event.matches?({{key}})
                return {{method.name}} != false
              end
            {% end %}
          {% end %}
        {% end %}
        false
      end
    {% end %}

    # Deduplicated on {key, description}: a binding declared for several
    # groups yields one entry carrying every group it belongs to.
    {% entries = [] of Nil %}
    {% for binding in bindings %}
      {% key = binding[1] %}

      {% if key.is_a?(CharLiteral) && key == ' ' %}
        {% label = "space" %}
      {% elsif key.is_a?(Path) %}
        {% label = key.names.last.downcase.stringify %}
      {% else %}
        {% label = key.id.stringify %}
      {% end %}

      {% description = binding[2] %}
      {% existing = entries.find { |e| e[0] == label && e[1] == description } %}

      {% if existing %}
        {% existing[2] = (existing[2] + binding[3]).uniq %}
      {% else %}
        {% entries << [label, description, binding[3]] %}
      {% end %}
    {% end %}

    KEY_BINDINGS = [
      {% for entry in entries %}
        { {{entry[0]}}, {{entry[1]}}, [{{entry[2].splat}}] of Symbol },
      {% end %}
    ] of {String, String, Array(Symbol)}
  end
end
