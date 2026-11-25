# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Event descriptions and guest names are personal. Titles stay readable:
  # every event URL already carries one. Whole-key matches, so keys such as
  # SERVER_NAME or filename stay visible.
  /\Abody\z/, /\Aname\z/
]
