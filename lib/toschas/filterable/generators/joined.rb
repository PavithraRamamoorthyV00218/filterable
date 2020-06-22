module Generators
  class Joined < Base
    def generate
      filters.each do |filter|
        field = joined_field(filter)
        generate_joined_filter(filter, field, relation_name, options[:joins])
        if table_loaded? && range_filter?(field)
          generate_range_filter(filter, field, relation_name, options[:joins])
        end
      end
    end

    private

    #def relation
      #relation_name.to_s.classify.constantize
    #end

    def generate_joined_filter(filter, field, relation_name, join_options)
      #binding.pry
      model.define_singleton_method(
        "by_#{filter}",
        ->(value) {
          send(:joins, join_options)
          .send(:where, 
                { relation_name.to_s.pluralize => { 
            field => value } 
          }
               )
        }
      )
    end

    def generate_range_filter(filter, field, relation_name, join_options)
      define_range_filter(:from, filter, field, relation_name, join_options)
      define_range_filter(:to, filter, field, relation_name, join_options)
    end

    def define_range_filter(prefix, filter, field, relation_name, join_options)
      operand = prefix == :from ? '>' : '<'

      model.define_singleton_method(
        "#{prefix}_#{filter}",
        ->(value) {
          send(:joins, join_options)
          .send(:where, 
                "#{relation_name.to_s.pluralize}.#{field} #{operand} ?", 
          value)
        }
      )
    end


    def extract_relations(join_options)
      if join_options.is_a?(Hash)
        join_options.flat_map{|k, v| [k, *extract_relations(v)]}
      else
        [join_options]
      end
    end

    def relations
      @relations ||= extract_relations(options[:joins])
    end

    def constantize_relations
      previous = nil
      relations.map! do |rel|
        if previous.nil?
          parent_model_name = model
        else
          parent_model_name = previous.to_s.classify.constantize
        end
        rel = parent_model_name.reflect_on_association(rel).options[:class_name].constantize.table_name if parent_model_name.reflect_on_association(rel).options[:class_name].present?
        previous = rel
      end
      relations
    end

    def relation_name
      @relation_name ||= constantize_relations.last
    end

    def joined_field(filter)
      filter.to_s.split("#{relation_name}_").last
    end

    def range_filter?(filter)
      range_types.include?(
        relation_name.to_s.classify.constantize
        .type_for_attribute(filter.to_s).type
      )
    end
  end
end
