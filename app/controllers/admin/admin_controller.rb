module Admin
  class AdminController < ApplicationController
    http_basic_authenticate_with name: ENV["ADMIN_USER"], password: ENV["ADMIN_PASSWORD"]
  end
end
