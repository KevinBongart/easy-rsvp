(function() {
  document.addEventListener("turbolinks:load", function() {
    Trix.config.attachments.preview.caption = { name: false, size: false };
  });

  function uploadAttachment(attachment, editor) {
    var form = new FormData();
    form.append("image_upload[image]", attachment.file);

    var xhr = new XMLHttpRequest();
    xhr.open("POST", "/image_uploads", true);
    xhr.setRequestHeader("X-CSRF-Token", document.querySelector('meta[name="csrf-token"]').content);
    xhr.timeout = 30000;

    function clearError() {
      var error = editor.parentNode.querySelector('.trix-upload-error');
      if (error) error.remove();
    }

    function failUpload() {
      clearError();
      attachment.remove();
      var error = document.createElement('div');
      error.className = 'alert alert-danger trix-upload-error';
      error.setAttribute('role', 'alert');
      error.textContent = 'Image upload failed. Please try again with a PNG, JPEG, GIF, or WebP image (10 MB maximum).';
      editor.insertAdjacentElement('afterend', error);
    }

    xhr.upload.onprogress = function(event) {
      if (event.lengthComputable) attachment.setUploadProgress(event.loaded / event.total * 100);
    };

    xhr.onload = function() {
      if (this.status < 200 || this.status >= 300) return failUpload();
      try {
        var data = JSON.parse(this.responseText);
        if (typeof data.url !== 'string' || !data.url) return failUpload();
        attachment.setAttributes({ url: data.url, href: data.url });
        clearError();
      } catch (error) {
        failUpload();
      }
    };
    xhr.onerror = failUpload;
    xhr.ontimeout = failUpload;
    xhr.onabort = failUpload;
    xhr.send(form);
  }

  // Document listeners survive Turbolinks visits; register the handler once.
  document.addEventListener("trix-attachment-add", function(event) {
    if (event.attachment.file) uploadAttachment(event.attachment, event.target);
  });
})();
