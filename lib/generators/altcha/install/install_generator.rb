# frozen_string_literal: true
require "rails/generators"

module Altcha
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Installs Altcha for Rails and generates a controller and a route"
      argument :name, type: :string, default: "Altcha"

      source_root File.expand_path("templates", __dir__)

      def create_controller
        copy_file "controllers/altcha_controller.rb", "app/controllers/altcha_controller.rb"
      end

      def create_initializer
        copy_file "initializers/altcha.rb", "config/initializers/altcha.rb"
      end

      def setup_routes
        route  "get '/altcha', to: 'altcha#new'"
      end
    end
  end
end
