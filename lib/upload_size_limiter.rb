class UploadSizeLimiter
  MAXIMUM_REQUEST_SIZE = 11.megabytes
  PATH = %r{\A/image_uploads(?:\.[^/]+)?/?\z}

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"].match?(PATH) && oversized?(env)
      body = '{"image":["request is too large"]}'
      return [413, { "content-type" => "application/json", "content-length" => body.bytesize.to_s }, [body]]
    end

    @app.call(env)
  end

  private

  def oversized?(env)
    env["CONTENT_LENGTH"].to_i > MAXIMUM_REQUEST_SIZE
  end
end
