require 'intercom_export/model/intercom_admin'
require 'intercom_export/model/intercom_user'
require 'intercom_export/model/intercom_conversation'

require 'nokogiri'

module IntercomExport
  module Differ
    class IntercomZendesk
      def diff(intercom_source, zendesk_destination)
        case intercom_source
        when Model::IntercomUser, Model::IntercomAdmin
          diff_user(intercom_source, zendesk_destination)
        when Model::IntercomConversation
          diff_ticket(intercom_source, zendesk_destination)
        end
      end

      private

      def diff_user(intercom_user, zendesk_user)
        if zendesk_user
          [reference(intercom_user, zendesk_user)]
        else
          [import_user(intercom_user)]
        end
      end

      def diff_ticket(intercom_conversation, zendesk_ticket)
        if zendesk_ticket
          []
        else
          [import_ticket(intercom_conversation)]
        end
      end

      def reference(intercom_source, zendesk_destination)
        { name: :reference, details: zendesk_destination.id, reference: intercom_source.reference }
      end

      def import_user(intercom_user)
        {
          name: :import_user,
          details: {
            external_id: intercom_user.reference.value,
            name: intercom_user.name || intercom_user.email,
            email: intercom_user.email
          },
          reference: intercom_user.reference
        }
      end

      def import_ticket(intercom_conversation)
        {
          name: :import_ticket,
          details: {
            external_id: intercom_conversation.reference.value,
            tags: intercom_conversation.tags,
            status: intercom_conversation.open ? 'pending' : 'solved',
            requester_id: intercom_conversation.user,
            assignee_id: intercom_conversation.assignee,
            subject: strip_html(intercom_conversation.conversation_message.fetch(:subject)),
            comments: [
              author_id: intercom_conversation.user,
              html_body: intercom_conversation.conversation_message.fetch(:body),
              created_at: time(intercom_conversation.created_at)
            ] + intercom_conversation.conversation_parts.map { |part|
              {
                author_id: part.fetch(:author),
                value: html_to_ascii(part.fetch(:body)),
                public: part.fetch(:part_type) != 'note',
                created_at: time(part.fetch(:created_at))
              }
            },
            created_at: time(intercom_conversation.created_at),
            updated_at: time(intercom_conversation.updated_at)
          }
        }
      end

      def time(posix)
        Time.at(posix).strftime('%Y-%m-%dT%H:%M:%SZ')
      end

      def strip_html(html_string)
        Nokogiri::HTML(html_string).text
      end

      def html_to_ascii(html_string)
        node = Nokogiri::HTML(html_string)
        blocks = %w[p div address]                          # els to put newlines after
        swaps  = { 'br' => "\n", 'hr' => "\n#{'-'*70}\n" }  # content to swap out
        dup = node.dup                                      # don't munge the original

        # Get rid of superfluous whitespace in the source
        dup.xpath('.//text()').each { |t| t.content = t.text.gsub(/\s+/, ' ') }

        # Swap out the swaps
        dup.css(swaps.keys.join(',')).each { |n| n.replace(swaps[n.name]) }

        # Slap a couple newlines after each block level element
        dup.css(blocks.join(',')).each { |n| n.after("\n\n") }

        # Return the modified text content
        dup.text.strip
      end
    end
  end
end
