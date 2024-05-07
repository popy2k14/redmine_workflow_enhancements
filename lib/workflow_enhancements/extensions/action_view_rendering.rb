module WorkflowEnhancements
  module Extensions
    module ActionViewRendering
      module LookupContext
        module ViewPaths
          def find_all_templates(name, partial = false, locals = {})
            prefixes.collect do |prefix|
              view_paths.collect do |resolver|
                temp_args = *args_for_lookup(name, [prefix], partial, locals, {})
                temp_args[1] = temp_args[1][0]
                resolver.find_all(*temp_args)
              end
            end.flatten!
          end
        end
      end
    end
  end
end

module ActionView
  class LookupContext
    module ViewPaths
      def find_all_templates(name, partial = false, locals = {})
        prefixes.collect do |prefix|
          view_paths.collect do |resolver|
            temp_args = *args_for_lookup(name, [prefix], partial, locals, {})
            temp_args[1] = temp_args[1][0]
            resolver.find_all(*temp_args)
          end
        end.flatten!
      end
    end
  end
end

# wrap the action rendering for ActiveScaffold views
module WorkflowEnhancements #:nodoc:
  module RenderingHelper
    #
    # Adds two rendering options.
    #
    # ==render :super
    #
    # This syntax skips all template overrides and goes directly to the provided ActiveScaffold templates.
    # Useful if you want to wrap an existing template. Just call super!
    #
    # ==render :active_scaffold => #{controller.to_s}, options = {}+
    #
    # Lets you embed an ActiveScaffold by referencing the controller where it's configured.
    #
    # You may specify options[:constraints] for the embedded scaffold. These constraints have three effects:
    #   * the scaffold's only displays records matching the constraint
    #   * all new records created will be assigned the constrained values
    #   * constrained columns will be hidden (they're pretty boring at this point)
    #
    # You may also specify options[:conditions] for the embedded scaffold. These only do 1/3 of what
    # constraints do (they only limit search results). Any format accepted by ActiveRecord::Base.find is valid.
    #
    # Defining options[:label] lets you completely customize the list title for the embedded scaffold.
    #
    # options[:xhr] force to load embedded scaffold with AJAX even when render_component gem is installed.
    #
    def render(*args, &block)
      if args.first == :super
        last_view = view_stack.last || {:view => instance_variable_get(:@virtual_path).split('/').last}
        options = args[1] || {}
        options[:locals] ||= {}
        options[:locals].reverse_merge!(last_view[:locals] || {})
        if last_view[:templates].nil?
          last_view[:templates] = lookup_context.find_all_templates(last_view[:view], last_view[:partial], options[:locals].keys)
          last_view[:templates].shift
        end
        options[:template] = last_view[:templates].shift
        view_stack << last_view
        result = super options
        view_stack.pop
        result
      else
        options = args.first
        if options.is_a?(Hash)
          current_view = {:view => options[:partial], :partial => true} if options[:partial]
          current_view = {:view => options[:template], :partial => false} if current_view.nil? && options[:template]
          current_view[:locals] = options[:locals] if !current_view.nil? && options[:locals]
          view_stack << current_view if current_view.present?
        end
        result = super(*args, &block)
        view_stack.pop if current_view.present?
        result
      end
    end

    def view_stack
      @_view_stack ||= []
    end

    private

    def options_for_render_super(options)
      options ||= {}
      options[:locals] ||= {}
      if view_stack.last
        options[:locals] = view_stack.last[:locals].merge!(options[:locals]) if view_stack.last[:locals]
        options[:object] ||= view_stack.last[:object] if view_stack.last[:object]
      end

      parts = @virtual_path.split('/')
      options[:template] = parts.pop
      prefix = parts.join('/')
      # if prefix is active_scaffold_overrides we must try to render with this prefix in following paths
      if prefix != 'active_scaffold_overrides'
        options[:prefixes] = lookup_context.prefixes.drop((lookup_context.prefixes.find_index(prefix) || -1) + 1)
      else
        options[:prefixes] = ['active_scaffold_overrides']
        update_view_paths
      end
      options
    end

    def update_view_paths
      last_view_path =
        if @lookup_context # rails 6
          File.expand_path(File.dirname(File.dirname(@lookup_context.last_template.short_identifier.to_s)), Rails.root)
        else
          File.expand_path(File.dirname(File.dirname(lookup_context.last_template.inspect)), Rails.root)
        end
      new_view_paths = view_paths.drop(view_paths.find_index { |path| path.to_s == last_view_path } + 1)
      if @lookup_context # rails 6
        if respond_to? :build_lookup_context # rails 6.0
          build_lookup_context(new_view_paths)
        else # rails 6.1
          @lookup_context = ActionView::LookupContext.new(new_view_paths)
        end
      else
        lookup_context.view_paths = new_view_paths
      end
    end

    def remote_controller_config(controller_path)
      # attempt to retrieve the active_scaffold_config by constantizing the controller path
      "#{controller_path}_controller".camelize.constantize.active_scaffold_config
    rescue NameError
      # if we couldn't determine the controller config by instantiating the
      # controller class, parse the ActiveRecord model name from the
      # controller path, which might be a namespaced controller (e.g., 'admin/admins')
      model = controller_path.to_s.sub(%r{.*/}, '').singularize
      active_scaffold_config_for(model)
    end

    def render_embedded(options)
      require 'digest/md5'

      remote_controller = options[:active_scaffold]
      # It is important that the EID hash remains short as to not contribute
      # to a large session size and thus a possible cookie overflow exception
      # when using rails CookieStore or EncryptedCookieStore. For example,
      # when rendering many embedded scaffolds with constraints or conditions
      # on a single page.
      eid = Digest::MD5.hexdigest(params[:controller] + options.to_s)
      eid_info = {loading: true}
      eid_info[:constraints] = options[:constraints] if options[:constraints]
      eid_info[:conditions] = options[:conditions] if options[:conditions]
      eid_info[:label] = options[:label] if options[:label]
      options[:params] ||= {}
      options[:params].merge! :eid => eid, :embedded => eid_info

      id = "as_#{eid}-embedded"
      url_options = {controller: remote_controller.to_s, action: 'index', id: nil}.merge(options[:params])

      if controller.respond_to?(:render_component_into_view, true) && !options[:xhr]
        controller.send(:render_component_into_view, url_options)
      else
        url = url_for(url_options)
        content_tag(:div, :id => id, :class => 'active-scaffold-component', :data => {:refresh => url}) do
          content_tag(:div, :class => 'active-scaffold-header') do
            content_tag(:h2) do
              label = options[:label] || remote_controller_config(remote_controller).list.label
              link_to(label, url, remote: true, class: 'load-embedded', data: {error_msg: as_(:error_500)}) <<
                loading_indicator_tag(url_options)
            end
          end
        end
      end
    end
  end
end

module ActionView
  LookupContext.class_eval do
    prepend WorkflowEnhancements::Extensions::ActionViewRendering::LookupContext
  end

  module Helpers
    Base.class_eval do
      include WorkflowEnhancements::RenderingHelper
    end

    if Gem.loaded_specs['rails'].version.segments.first >= 6
      RenderingHelper.class_eval do
        # override the render method to use our @lookup_context instead of the
        # memoized @_lookup_context
        def render(options = {}, locals = {}, &block)
          case options
          when Hash
            in_rendering_context(options) do |_|
              # previously set view paths and lookup context are lost here
              # if you use view_renderer, so instead create a new renderer
              # with our context
              temp_renderer = ActionView::Renderer.new(@lookup_context)
              if block_given?
                temp_renderer.render_partial(self, options.merge(partial: options[:layout]), &block)
              else
                temp_renderer.render(self, options)
              end
            end
          else
            view_renderer.render_partial(self, partial: options, locals: locals, &block)
          end
        end
      end
    end
  end
end