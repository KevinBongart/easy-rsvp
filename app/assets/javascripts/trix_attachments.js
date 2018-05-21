document.addEventListener("turbolinks:load", function() {
  Trix.config.attachments.preview.caption = {
    name: false,
    size: false
  };

  function uploadAttachment(attachment) {
    var csrfToken = $('meta[name="csrf-token"]').attr('content');
    var file = attachment.file;
    var form = new FormData;
    var endpoint = "/image_uploads";
    form.append("Content-Type", file.type);
    form.append("image_upload[image]", file);

    xhr = new XMLHttpRequest;
    xhr.open("POST", endpoint, true);
    xhr.setRequestHeader("X-CSRF-Token", csrfToken);

    xhr.upload.onprogress = function(event) {
      var progress = event.loaded / event.total * 100;
      return attachment.setUploadProgress(progress);
    };

    xhr.onload = function() {
      if (this.status >= 200 && this.status < 300) {
        var data = JSON.parse(this.responseText);
        return attachment.setAttributes({
          url: data.url,
          href: data.url
        });
      }
    };

    return xhr.send(form);
  };

  document.addEventListener("trix-attachment-add", function(event) {
    var attachment = event.attachment;
    if (attachment.file) {
      return uploadAttachment(attachment);
    }
  });
});
