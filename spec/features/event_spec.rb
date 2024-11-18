require 'rails_helper'

describe 'event creation' do
  it 'works' do
    visit '/'

    fill_in 'What are you planning?', with: "Batman's surprise birthday"

    select Date.today.year, from: 'event_date_1i'
    select 'April', from: 'event_date_2i'
    select '7', from: 'event_date_3i'

    click_button 'Create your event, for free!'

    expect(page).to have_content "Batman's surprise birthday // "
    expect(page).to have_content "Apr 07 #{Date.today.year}"

    # Temporarily disabled
    # fill_in 'Your email address:', with: 'alfred@wayne-enterprises.com'
    # click_button 'Receive the admin link'
    # expect(page).to have_content 'The admin link has been sent to alfred@wayne-enterprises.com'

    click_link 'public-link'

    fill_in 'Your name', with: 'Alfred'
    click_button 'Yes'

    fill_in 'Your name', with: 'Robin'
    click_button 'Yes'

    fill_in 'Your name', with: 'Lucius'
    click_button 'Yes'

    fill_in 'Your name', with: 'Poison Ivy'
    click_button 'Maybe'

    fill_in 'Your name', with: 'Mr. Freeze (too hot)'
    click_button 'No'

    expect(page).to have_content 'Alfred [x] Robin [x] Lucius [x]'

    expect(page).to have_content 'Yes (3)'
    expect(page).to have_content 'Maybe (1)'
    expect(page).to have_content 'No (1)'
  end

  it 'can be unpublished' do
    visit '/'
    fill_in 'What are you planning?', with: "Batman's surprise birthday"
    click_button 'Create your event, for free!'
    admin_path = current_path

    expect(page).to have_content "Batman's surprise birthday"

    click_link 'public-link'

    expect(page).to have_content "Batman's surprise birthday"

    visit(admin_path) # Back to admin page
    click_button 'click here'

    expect(page).to have_content "Your event is now unpublished."

    click_link 'public-link'

    expect(current_path).to eq ('/')
    expect(page).to have_content "This event is no longer viewable."

    visit(admin_path) # Back to admin page
    click_button 'Click here to publish it'

    expect(page).to have_content "Your event is now live."

    click_link 'public-link'

    expect(page).to have_content "Batman's surprise birthday"
  end
end
