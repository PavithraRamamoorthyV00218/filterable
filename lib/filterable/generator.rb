module Filterable
  class Generator
    attr_accessor :model, :filters, :options

    def initialize(model, filters)
      @model = model
      @filters = filters
      @options = filters.last.is_a?(Hash) ? filters.pop : {}
    end

    def generate
      generate_filter unless model.respond_to? :filter
      generate_scopes
    end

    private

    def generate_filter
      model.define_singleton_method(
        :filter, 
        ->(filtering_params) {
          results = where(nil)
          filtering_params.each do |key, value|
            unless results.respond_to?(key)
              if Filterable.configuration.ignore_unknown_filters
                next
              else
                raise UnknownFilter, "Unknown filter received: #{key}"
              end
            end
            next if value.blank? && Filterable.configuration.ignore_empty_values
            results = results.public_send(key, value)
          end
          results
        }
      )
    end

    def generate_scopes
      if options[:custom]
        generate_empty_scopes 
      elsif options[:joins].present?
        generate_joined_model_scopes(filters, options)
      else
        generate_model_scopes(filters)
      end
    end

    def generate_empty_scopes
      prefixes = custom_prefixes
      filters.each do |filter|
        prefixes.each do |prefix|
          model.define_singleton_method(
            "#{prefix}_#{filter}", 
            ->(value) { send(:where, nil) }
          )
        end
      end
    end

    def custom_prefixes
      if options[:prefix].present?
        options[:prefix].is_a?(Array) ? options[:prefix] : [options[:prefix]]
      else
        ['by']
      end
    end

    def generate_joined_model_scopes(filters, options)
      association_name = joined_association_name(options[:joins])
      filters.each do |filter|
        attribute_name = joined_attribute_name(filter, association_name)
        model.define_singleton_method(
          "by_#{filter}",
          ->(value) {
            send(:joins, options[:joins])
              .send(:where, 
                { association_name.to_s.pluralize => { 
                  attribute_name => value } 
                }
              )
          }
        )
        if range_filter?(attribute_name, association_name)
          model.define_singleton_method(
            "from_#{filter}",
            ->(value) {
              send(:joins, options[:joins])
                .send(:where, 
                      "#{association_name.to_s.pluralize}.#{attribute_name} > ?", 
                      value)
            }
          )

          model.define_singleton_method(
            "to_#{filter}",
            ->(value) {
              send(:joins, options[:joins])
                .send(:where, 
                      "#{association_name.to_s.pluralize}.#{attribute_name} < ?", 
                      value)
            }
          )
        end
      end
    end

    def joined_association_name(join_options)
      if join_options.is_a?(Hash) 
        joined_association_name(join_options.values.last) 
      else
        join_options
      end
    end

    def joined_attribute_name(filter, association_name)
      filter.to_s.split("#{association_name}_").last
    end

    def generate_model_scopes(filters)
      filters.each do |filter|
        model.define_singleton_method(
          "by_#{filter}", 
          ->(value) { send(:where, { filter => value }) }
        )
        
        if range_filter?(filter)
          model.define_singleton_method(
            "from_#{filter}", 
            ->(value) { send(:where, "#{filter} > ?", value) }
          )
          model.define_singleton_method(
            "to_#{filter}", 
            ->(value) { send(:where, "#{filter} < ?", value) }
          )
        end
      end
    end

    def range_filter?(filter, model_name = nil)
      model_name ||= model
      [:date, :datetime, :integer].include?(
        model_name.to_s.classify.constantize
          .type_for_attribute(filter.to_s).type
      )
    end
  end
end
