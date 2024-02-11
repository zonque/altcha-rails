# frozen_string_literal: true
require "rails/generators/active_record"

module Altcha
  module Generators
    class InstallGenerator < ActiveRecord::Generators::Base
      desc "Installs Altcha for Rails and generates a model, a controller and a route"
      argument :name, type: :string, default: "Altcha"

      source_root File.expand_path("templates", __dir__)

      def create_model
        copy_file "models/altcha_solution.rb", "app/models/altcha_solution.rb"
      end

      def create_controller
        copy_file "controllers/altcha_controller.rb", "app/controllers/altcha_controller.rb"
      end

      def create_initializer
        copy_file "initializers/altcha.rb", "config/initializers/altcha.rb"
      end

      def setup_routes
        route  "get '/altcha', to: 'altcha#new'"
      end

      def create_migrations
        migration_template "migrations/create_altcha_solutions.rb.erb", "db/migrate/create_altcha_solutions.rb"
      end
    end
  end
end
