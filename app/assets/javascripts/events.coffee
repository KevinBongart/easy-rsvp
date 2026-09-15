# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

document.addEventListener "turbolinks:load", ->
  $('#rsvp-again').click ->
    $('#new_rsvp').removeClass('d-none')
    $('#rsvp-again').toggle()
    return false
