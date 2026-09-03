require "test_helper"

class Telegram::ApiDownloadFileTest < ActiveSupport::TestCase
  GET_FILE = { "ok" => true, "result" => { "file_path" => "photos/file_1.jpg" } }.freeze

  # Временный файл создаётся до запроса, а наружу при неудаче не уходит:
  # убрать его после себя может только сам download_file.
  test "a broken connection leaves no temporary file behind" do
    created = capture_tempfiles do
      stub_singleton(Net::HTTP, :start, ->(*, **, &_block) { raise Errno::ECONNRESET }) do
        assert_nil Telegram::Api.download_file("abc")
      end
    end

    assert_equal 1, created.size
    assert created.first.closed?
    assert_nil created.first.path
  end

  test "a non-success response leaves no temporary file behind" do
    response = Net::HTTPNotFound.new("1.1", "404", "Not Found")
    http = Object.new
    http.define_singleton_method(:request) { |_request, &block| block.call(response) }

    created = capture_tempfiles do
      stub_singleton(Net::HTTP, :start, ->(*, **, &block) { block.call(http) }) do
        assert_nil Telegram::Api.download_file("abc")
      end
    end

    assert_equal 1, created.size
    assert created.first.closed?
    assert_nil created.first.path
  end

  test "no file is created when Telegram gives no path" do
    created = capture_tempfiles do
      stub_singleton(Telegram::Api, :post, ->(*) { { "ok" => false } }) do
        assert_nil Telegram::Api.download_file("abc")
      end
    end

    assert_empty created
  end

  private

  def capture_tempfiles
    created = []
    original = Tempfile.method(:new)

    stub_singleton(Telegram::Api, :post, ->(*) { GET_FILE }) do
      stub_singleton(Tempfile, :new, ->(*args, **kw) { original.call(*args, **kw).tap { |file| created << file } }) do
        yield
      end
    end

    created
  end
end
