require 'rails_helper'

describe "event creation" do
  it "works" do
    visit '/'

    fill_in 'What are you planning?', with: "Batman's surprise birthday"

    select '2020', from: 'event_date_1i'
    select 'April', from: 'event_date_2i'
    select '7', from: 'event_date_3i'

    click_button "Create your event, for free!"

    expect(page).to have_content "Batman's surprise birthday // Tuesday, Apr 07 2020"
  end
end
