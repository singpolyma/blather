module Blather
class Stream

  # @private
  class Features
    @@features = {}
    def self.register(ns)
      @@features[ns] = self
    end

    def self.from_namespace(ns)
      @@features[ns]
    end

    def initialize(stream, succeed, fail)
      @stream, @succeed, @fail = stream, succeed, fail
    end

    # Fetures may appear in the XML in any order, but sometimes
    # we might prefer to try some first if present
    FEATURE_SCORES = {
      "urn:ieft:params:xml:ns:xmpp-tls" => 0,
      "urn:ieft:params:xml:ns:xmpp-bind" => 1,
      "urn:ieft:params:xml:ns:xmpp-session" => 1,
      "urn:ietf:params:xml:ns:xmpp-sasl" => 2
    }.freeze

    def receive_data(stanza)
      if @feature
        @feature.receive_data stanza
      else
        @features ||= stanza
        @use_next =
          @features.children
            .map { |el| el.namespaces['xmlns'] }.compact
            .sort { |x, y| FEATURE_SCORES.fetch(x, FEATURE_SCORES.length) <=> FEATURE_SCORES.fetch(y, FEATURE_SCORES.length) }
        next!
      end
    end

    def next!
      bind = @features.at_xpath('ns:bind', ns: 'urn:ietf:params:xml:ns:xmpp-bind')
      session = @features.at_xpath('ns:session', ns: 'urn:ietf:params:xml:ns:xmpp-session')
      if bind && session && @features.children.last != session
        bind.after session
      end

      if !@use_next.empty? && (stanza = @features.at_xpath('ns:*', ns: @use_next.shift))
        if stanza.namespaces['xmlns'] && (klass = self.class.from_namespace(stanza.namespaces['xmlns']))
          @feature = klass.new(
            @stream,
            proc {
              if (klass == Blather::Stream::Register && stanza = feature?(:mechanisms))
                @feature = Blather::Stream::SASL.new @stream, proc { next! }, @fail
                @feature.receive_data stanza
              else
                next!
              end
            },
            (klass == Blather::Stream::SASL && feature?(:register)) ? proc { next! } : @fail
          )
          @feature.receive_data stanza
        else
          next!
        end
      else
        succeed!
      end
    end

    def succeed!
      @succeed.call
    end

    def fail!(msg)
      @fail.call msg
    end

    def feature?(feature)
      @features && @features.children.find { |v| v.element_name == feature.to_s }
    end
  end

end #Stream
end #Blather
