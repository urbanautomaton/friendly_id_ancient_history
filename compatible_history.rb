module FriendlyId

=begin

== CompatibleHistory: Avoiding 404's When Slugs Change (the old way)

FriendlyId's {FriendlyId::CompatibleHistory CompatibleHistory} module adds the
ability to store a log of a model's slugs, so that when its friendly id
changes, it's still possible to perform finds by the old id. It does this using
the old-style schema from FriendlyId version 3.x.

The primary use case for this is avoiding broken URLs.

=== Setup

In order to use this module it is assumed that you already have a `slugs` table
created with a migration similar to:

    class CreateSlugs < ActiveRecord::Migration
      def self.up
        create_table :slugs do |t|
          t.string :name
          t.integer :sluggable_id
          t.integer :sequence, :null => false, :default => 1
          t.string :sluggable_type, :limit => 40
          t.string :scope
          t.datetime :created_at
        end
        add_index :slugs, :sluggable_id
        add_index :slugs, [:name, :sluggable_type, :sequence, :scope], :name => "index_slugs_on_n_s_s_and_s", :unique => true
      end

      def self.down
        drop_table :slugs
      end
    end

=== Considerations

This module is incompatible with the +:scoped+ module.

Because recording slug history requires creating additional database records,
this module has an impact on the performance of the associated model's +create+
method.

=== Example

    class Post < ActiveRecord::Base
      extend FriendlyId
      friendly_id :title, :use => :compatible_history
    end

    class PostsController < ApplicationController

      before_filter :find_post

      ...

      def find_post
        @post = Post.find params[:id]

        # If an old id or a numeric id was used to find the record, then
        # the request path will not match the post_path, and we should do
        # a 301 redirect that uses the current friendly id.
        if request.path != post_path(@post)
          return redirect_to @post, :status => :moved_permanently
        end
      end
    end
=end
  module CompatibleHistory

    # Configures the model instance to use the History add-on.
    def self.included(model_class)
      model_class.instance_eval do
        raise "FriendlyId::CompatibleHistory is incompatible with FriendlyId::Scoped" if self < Scoped
        @friendly_id_config.use :slugged
        has_many :slugs, :as => :sluggable, :dependent => :destroy,
          :class_name => CompatibleSlug.to_s, :order => "#{CompatibleSlug.quoted_table_name}.id DESC"
        after_save :create_slug
        relation_class.send :include, FinderMethods
        friendly_id_config.slug_generator_class.send :include, SlugGenerator
      end
    end

    private

    def create_slug
      return unless friendly_id
      return if slugs.first && slugs.first.slug == friendly_id
      # Allow reversion back to a previously used slug
      relation = slugs.with_slug(friendly_id, self.class.friendly_id_config.sequence_separator)
      result = relation.select("id").lock(true).all
      relation.delete_all unless result.empty?
      slugs.create! do |record|
        record.slug = friendly_id
      end
    end

    # Adds a finder that explictly uses slugs from the slug table.
    module FinderMethods

      # Search for a record in the slugs table using the specified slug.
      def find_one(id)
        return super(id) if id.unfriendly_id?
        where(@klass.friendly_id_config.query_field => id).first or
        with_old_friendly_id(id) {|x| find_one_without_friendly_id(x)} or
        find_one_without_friendly_id(id)
      end

      # Search for a record in the slugs table using the specified slug.
      def exists?(id = false)
        return super if id.unfriendly_id?
        exists_without_friendly_id?(@klass.friendly_id_config.query_field => id) or
        with_old_friendly_id(id) {|x| exists_without_friendly_id?(x)} or
        exists_without_friendly_id?(id)
      end

      private

      # Accepts a slug, and yields a corresponding sluggable_id into the block.
      def with_old_friendly_id(slug, &block)
        scope = CompatibleSlug.where(:sluggable_type => @klass.base_class.to_s)
        scope = scope.with_slug(slug, @klass.friendly_id_config.sequence_separator)
        sluggable_id = scope.select(:sluggable_id).map(&:sluggable_id).first
        yield sluggable_id if sluggable_id
      end
    end

    # This module overrides {FriendlyId::SlugGenerator#conflicts} to consider
    # all historic slugs for that model.
    module SlugGenerator

      private

      def direct_conflicts
        scope = CompatibleSlug.where(:name => normalized, :sequence => 1)
        scope = scope.where(:sluggable_type => sluggable_class.to_s)
        scope_excluding_sluggable(scope)
      end

      def conflicts
        scope = CompatibleSlug.where(:name => normalized)
        scope = scope.where(:sluggable_type => sluggable_class.to_s)
        scope = scope.order("sequence DESC")
        scope_excluding_sluggable(scope)
      end

      def scope_excluding_sluggable(scope)
        if sluggable.new_record?
          scope
        else
          scope.where("sluggable_id <> ?", sluggable_primary_key)
        end
      end
    end
  end
end
