require 'rails_helper'

RSpec.describe 'Image upload ownership', type: :request do
  def start_editor
    get root_path
    editor = Nokogiri::HTML(response.body).at_css('trix-editor')
    editor['data-upload-token']
  end

  def upload_image(token)
    post image_uploads_path(format: :json), params: {
      image_upload: { image: uploaded_image, token: token }
    }
    expect(response).to have_http_status(:ok)
    [ImageUpload.order(:id).last, response.parsed_body.fetch('url')]
  end

  def create_event(token:, body:)
    post events_path, params: {
      image_upload_token: token,
      event: { title: 'Upload ownership', date: '2026-10-10', body: body }
    }
  end

  it 'assigns a referenced editor upload to the newly saved event' do
    token = start_editor
    upload, url = upload_image(token)
    expect(upload.upload_session_digest).to eq(ImageUpload.digest_token(token))
    expect(upload.upload_session_digest).not_to eq(token)

    create_event(token: token, body: %(<figure><img src="#{url}"></figure>))

    expect(response).to redirect_to(event_admin_path(Event.last, Event.last.admin_token))
    expect(upload.reload).to have_attributes(event_id: Event.last.id, upload_session_digest: nil)
  end

  it 'does not assign an upload removed from the editor before save' do
    token = start_editor
    upload, = upload_image(token)

    create_event(token: token, body: '<div>No image remains.</div>')

    expect(upload.reload.event_id).to be_nil
    expect(upload.upload_session_digest).to be_present
  end

  it 'keeps the same capability through validation errors and claims on retry' do
    token = start_editor
    upload, url = upload_image(token)

    post events_path, params: {
      image_upload_token: token,
      event: { title: '', date: '2026-10-10', body: %(<img src="#{url}">) }
    }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('trix-editor')['data-upload-token']).to eq(token)
    expect(upload.reload.event_id).to be_nil

    create_event(token: token, body: %(<img src="#{url}">))
    expect(upload.reload.event).to eq(Event.last)
  end

  it 'does not let another open editor claim an upload' do
    first_token = start_editor
    upload, url = upload_image(first_token)
    second_token = start_editor

    create_event(token: second_token, body: %(<img src="#{url}">))

    expect(upload.reload.event_id).to be_nil
  end

  it 'does not claim an upload after its 24-hour window' do
    token = start_editor
    upload, url = upload_image(token)

    travel 24.hours + 1.second do
      create_event(token: token, body: %(<img src="#{url}">))
      expect(upload.reload.event_id).to be_nil
      expect(ImageUpload.abandoned).to include(upload)
    end
  end

  it 'retires a capability after a successful save' do
    token = start_editor
    create_event(token: token, body: '')

    expect do
      post image_uploads_path(format: :json), params: {
        image_upload: { image: uploaded_image, token: token }
      }
    end.not_to change(ImageUpload, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'assigns a newly referenced upload when an organizer saves an edit' do
    event = create(:event)
    get edit_event_admin_path(event, event.admin_token)
    token = Nokogiri::HTML(response.body).at_css('trix-editor')['data-upload-token']
    upload, url = upload_image(token)

    patch event_admin_path(event, event.admin_token), params: {
      image_upload_token: token,
      event: { title: event.title, date: event.date, body: %(<img src="#{url}">) }
    }

    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
    expect(upload.reload.event).to eq(event)
  end
end
