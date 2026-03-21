# frozen_string_literal: true

module AsyncGraph
  module GraphValidation
    def validate!
      return self if @validated

      errors = validation_errors
      raise ValidationError, errors.uniq.join("; ") unless errors.empty?

      @validated = true
      self
    end

    private

    def validation_errors
      [].tap do |errors|
        add_entry_validation_errors(errors)
        add_edge_validation_errors(errors)
        add_join_validation_errors(errors)
      end.uniq
    end

    def add_entry_validation_errors(errors)
      errors << "Entry point is not set" unless @entry
      return unless @entry && !@nodes.key?(@entry)

      errors << "Entry point #{@entry} is not defined"
    end

    def add_edge_validation_errors(errors)
      @edges.each do |from, edges|
        errors << "Edge source #{from} is not defined" unless @nodes.key?(from)
        add_edge_target_validation_errors(errors, edges)
      end
    end

    def add_edge_target_validation_errors(errors, edges)
      edges.each do |edge|
        next if edge.to == FINISH || @nodes.key?(edge.to)

        errors << "Edge target #{edge.to} is not defined"
      end
    end

    def add_join_validation_errors(errors)
      @join_expects.each do |target, sources|
        errors << "Join target #{target} is not defined" unless @nodes.key?(target)
        sources.each do |source|
          errors << "Join source #{source} for #{target} is not defined" unless @nodes.key?(source)
        end
      end
    end

    def invalidate_validation!
      @validated = false
    end

    def validate_join_sources!(target, sources)
      target = target.to_sym
      raise ValidationError, "Join target #{target} requires at least one source" if sources.empty?

      duplicates = sources.group_by(&:itself).filter_map { |source, items| source if items.size > 1 }
      return if duplicates.empty?

      raise ValidationError, "Join target #{target} has duplicate sources: #{duplicates.join(', ')}"
    end

    def validate_known_node!(node, context:)
      raise ValidationError, "#{context} is not set" unless node
      return if @nodes.key?(node)

      raise ValidationError, "#{context} #{node} is not defined"
    end

    def validate_destination!(node, context:)
      return if node == FINISH

      validate_known_node!(node, context:)
    end
  end
end
