module DotHelper
  def render_agents_diagram(agents)
    if (command = ENV['USE_GRAPHVIZ_DOT']) &&
       (svg = IO.popen([command, *%w[-Tsvg -q1 -o/dev/stdout /dev/stdin]], 'w+') { |dot|
          dot.print agents_dot(agents, true)
          dot.close_write
          dot.read
        } rescue false)
      svg.html_safe
    else
      tag('img', src: URI('https://chart.googleapis.com/chart').tap { |uri|
            uri.query = URI.encode_www_form(cht: 'gv', chl: agents_dot(agents))
          })
    end
  end

  class DotDrawer
    def initialize(vars = {})
      @dot = ''
      vars.each { |name, value|
        # Import variables as methods
        define_singleton_method(name) { value }
      }
    end

    def to_s
      @dot
    end

    def self.draw(*args, &block)
      drawer = new(*args)
      drawer.instance_exec(&block)
      drawer.to_s
    end

    def raw(string)
      @dot << string
    end

    def escape(string)
      # Backslash escaping seems to work for the backslash itself,
      # though it's not documented in the DOT language docs.
      string.gsub(/[\\"\n]/,
                  "\\" => "\\\\",
                  "\"" => "\\\"",
                  "\n" => "\\n")
    end

    def id(value)
      case string = value.to_s
      when /\A(?!\d)\w+\z/, /\A(?:\.\d+|\d+(?:\.\d*)?)\z/
        raw string
      else
        raw '"'
        raw escape(string)
        raw '"'
      end
    end

    def attr_list(attrs = nil)
      return if attrs.nil?
      attrs = attrs.select { |key, value| value.present? }
      return if attrs.empty?
      raw '['
      attrs.each_with_index { |(key, value), i|
        raw ',' if i > 0
        id key
        raw '='
        id value
      }
      raw ']'
    end

    def node(id, attrs = nil)
      id id
      attr_list attrs
      raw ';'
    end

    def edge(from, to, attrs = nil, op = '->')
      id from
      raw op
      id to
      attr_list attrs
      raw ';'
    end

    def statement(ids, attrs = nil)
      Array(ids).each_with_index { |id, i|
        raw ' ' if i > 0
        id id
      }
      attr_list attrs
      raw ';'
    end

    def block(title, &block)
      raw title
      raw '{'
      block.call
      raw '}'
    end
  end

  private

  def draw(vars = {}, &block)
    DotDrawer.draw(vars, &block)
  end

  def agents_dot(agents, rich = false)
    draw(agents: agents,
         agent_id: ->agent { 'a%d' % agent.id },
         agent_label: ->agent {
           if agent.disabled?
             '%s (Disabled)' % agent.name
           else
             agent.name
           end.gsub(/(.{20}\S*)\s+/) {
             # Fold after every 20+ characters
             $1 + "\n"
           }
         },
         agent_url: ->agent { agent_path(agent.id) },
         rich: rich) {
      @disabled = '#999999'

      def agent_node(agent)
        node(agent_id[agent],
             label: agent_label[agent],
             URL: (agent_url[agent] if rich),
             style: ('rounded,dashed' if agent.disabled?),
             color: (@disabled if agent.disabled?),
             fontcolor: (@disabled if agent.disabled?))
      end

      def agent_edge(agent, receiver)
        edge(agent_id[agent],
             agent_id[receiver],
             style: ('dashed' unless receiver.propagate_immediately),
             color: (@disabled if agent.disabled? || receiver.disabled?))
      end

      block('digraph foo') {
        # statement 'graph', rankdir: 'LR'
        statement 'node',
                  shape: 'box',
                  style: 'rounded',
                  target: '_blank',
                  fontsize: 10,
                  fontname: ('Helvetica' if rich)

        agents.each.with_index { |agent, index|
          agent_node(agent)

          agent.receivers.each { |receiver|
            agent_edge(agent, receiver) if agents.include?(receiver)
          }
        }
      }
    }
  end
end
