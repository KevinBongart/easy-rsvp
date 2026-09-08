require 'rails_helper'

RSpec.describe 'Event management forms', type: :system do
  it 'shows validation errors and preserves a submitted description' do
    visit root_path
    click_button 'Create your event, for free!'
    expect(page).to have_content("can't be blank")
    expect(page).to have_field('What are you planning?')
  end

  it 'edits an event and hides other guests names on its public page' do
    event = create(:event)
    create(:rsvp, event: event, name: 'Private guest')
    visit event_admin_path(event, event.admin_token)
    click_link 'Edit', match: :first
    fill_in 'Title', with: 'Renamed garden party'
    uncheck 'Let guests see the names of other guests'
    click_button 'Update Event'
    expect(page).to have_content('Your event was updated.')
    expect(page).to have_content('Renamed garden party')
    expect(page).to have_content('Private guest')
    click_link 'public-link'
    expect(page).to have_content('Guest names are hidden')
    expect(page).to have_no_content('Private guest')
  end

  it 'preserves a valid event when an edit is invalid' do
    event = create(:event, title: 'Keep this title')
    visit edit_event_admin_path(event, event.admin_token)
    fill_in 'Title', with: ''
    click_button 'Update Event'
    expect(page).to have_content("can't be blank")
    expect(event.reload.title).to eq('Keep this title')
  end

  it 'shows RSVP validation feedback without creating a guest' do
    event = create(:event)
    visit event_path(event)
    click_button 'Yes'
    expect(page).to have_content('Please add your name to your RSVP')
    expect(event.rsvps).to be_empty
  end
end
