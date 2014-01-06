module FriendlyId
  # A FriendlyId v3.x slug stored in an external table.
  #
  # @see FriendlyId::CompatibleHistory
  class CompatibleSlug < ActiveRecord::Base
    self.table_name = "slugs"
    belongs_to :sluggable, :polymorphic => true

    def self.with_slug(slug, separator)
      name, sequence = name_and_sequence_from_slug(slug, separator)
      where(:name => name, :sequence => sequence)
    end

    def to_param
      slug
    end

    def slug
      return unless name
      sequence == 1 ? name : "#{name}#{separator}#{sequence}"
    end

    def slug=(new_slug)
      self.name, self.sequence = self.class.name_and_sequence_from_slug(new_slug, separator)
    end

    private

    def self.name_and_sequence_from_slug(slug, separator)
      name, sequence = slug.split(separator)
      sequence ||= 1
      [name, sequence.to_i]
    end

    def separator
      sluggable_type.constantize.friendly_id_config.sequence_separator
    end
  end
end
