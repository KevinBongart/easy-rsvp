module Admin
  class AdminController < ApplicationController
    before_action :raise_if_production

    private

    def raise_if_production
      raise "This page is for debugging purposes only. Do not run in production!" if Rails.env.production?
    end
  end
end
