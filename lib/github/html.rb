require 'nokogiri'

module GitHub
  # GitHub HTML processing filters and utilities. This module includes a small
  # framework for defining DOM based content filters and applying them to user
  # provided content.
  #
  # See GitHub::HTML::Filter for information on building filters.
  module HTML
    # Our DOM implementation.
    DocumentFragment = Nokogiri::HTML::DocumentFragment

    # Parse a String into a DocumentFragment object. When a DocumentFragment is
    # provided, return it verbatim.
    def self.parse(document_or_html)
      document_or_html ||= ''
      if document_or_html.is_a?(String)
        DocumentFragment.parse(document_or_html)
      else
        document_or_html
      end
    end

    # Filter implementations
    require 'github/html/filter'
    require 'github/html/autolink_filter'
    require 'github/html/camo_filter'
    require 'github/html/commit_mention_filter'
    require 'github/html/email_reply_filter'
    require 'github/html/emoji_filter'
    require 'github/html/https_filter'
    require 'github/html/image_max_width_filter'
    require 'github/html/issue_mention_filter'
    require 'github/html/markdown_filter'
    require 'github/html/@mention_filter'
    require 'github/html/plain_text_input_filter'
    require 'github/html/sanitization_filter'
    require 'github/html/syntax_highlight_filter'
    require 'github/html/textile_filter'

    # Contruct a pipeline for running multiple HTML filters.
    #
    # filters - Array of Filter objects. Each must respond to call(doc, context)
    #           and return the modified DocumentFragment or a String containing
    #           HTML markup. Filters are performed in the order provided.
    # context - The default context hash. Values specified here may be
    #           overridden by individual pipeline runs.
    class Pipeline
      def initialize(filters, context={})
        @filters = filters.flatten
        @context = context
      end

      # Apply all filters in the pipeline to the given HTML.
      #
      # html    - A String containing HTML or a DocumentFragment object.
      # context - The context hash passed to each filter. See the Filter docs
      #           for more info on possible values. This object may be modified
      #           in place by filters to make extracted information available
      #           to the caller.
      #
      # Returns a DocumentFragment or String containing HTML markup based on the
      # output of the last filter in the pipeline.
      def call(html, context={})
        @context.each { |k, v| context[k] = v if !context.key?(k) }
        @filters.inject(html) { |doc, filter| filter.call(doc, context) }
      end

      # Like call but guarantee the value returned is a DocumentFragment.
      # Pipelines may return a DocumentFragment or a String. Callers that need a
      # DocumentFragment should use this method.
      def to_document(input, context={})
        output = call(input, context)
        GitHub::HTML.parse(output)
      end

      # Like call but guarantee the value returned is a string of HTML markup.
      def to_html(input, context={})
        output = call(input, context)
        if output.respond_to?(:to_html)
          output.to_html
        else
          output.to_s
        end
      end
    end

    # Pipeline providing sanitization and image hijacking but no mention
    # related features.
    SimplePipeline = Pipeline.new [
      SanitizationFilter,
      CamoFilter,
      SyntaxHighlightFilter
    ]

    # Pipeline used for most types of user provided content like comments
    # and issue bodies. Performs sanitization, image hijacking, and various
    # mention links.
    GFMPipeline = Pipeline.new [
      MarkdownFilter,
      SanitizationFilter,
      SyntaxHighlightFilter,
      CamoFilter,
      HttpsFilter,
      MentionFilter,
      IssueMentionFilter,
      CommitMentionFilter,
      EmojiFilter,
      AutolinkFilter
    ]

    # Pipeline used for commit messages. This one is kind of weird because
    # commit messages are treated as preformatted plain text.
    CommitMessagePipeline = Pipeline.new [
      PlainTextInputFilter,
      MentionFilter,
      CommitMentionFilter,
      IssueMentionFilter,
      EmojiFilter,
      AutolinkFilter
    ]

    # Pipeline used for very large commit messages that take too long to
    # generate with a fully featured pipeline.
    LongCommitMessagePipeline = Pipeline.new [PlainTextInputFilter]

    # Pipeline used for email replies.
    EmailPipeline = Pipeline.new [
      EmailReplyFilter,
      MentionFilter,
      IssueMentionFilter,
      CommitMentionFilter,
      EmojiFilter,
      AutolinkFilter
    ]

    # Used to post-process user content for HTML email clients.
    HtmlEmailPipeline = Pipeline.new [
      ImageMaxWidthFilter
    ]

    # Pipeline used for really old comments and maybe other textile content
    # I guess.
    TextilePipeline = Pipeline.new [
      TextileFilter,
      SanitizationFilter
    ], :whitelist => SanitizationFilter::LIMITED

    extend self
  end
end

# XXX nokogiri monkey patches
class Nokogiri::XML::Node
  # Work around an issue with utf-8 encoded data being erroneously converted to
  # ... some other shit when replacing text nodes. See 'utf-8 output 2' in
  # user_content_test.rb for details.
  def replace_with_encoding_fix(replacement)
    if replacement.respond_to?(:to_str)
      replacement = document.fragment("<div>#{replacement}</div>").children.first.children
    end
    replace_without_encoding_fix(replacement)
  end

  alias_method :replace_without_encoding_fix, :replace
  alias_method :replace, :replace_with_encoding_fix

  def swap(replacement)
    replace(replacement)
    self
  end
end
