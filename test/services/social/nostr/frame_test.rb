require "test_helper"
require "stringio"

class Social::Nostr::FrameTest < ActiveSupport::TestCase
  test "client frames are masked and unmask back to the payload" do
    payload = "🎾 hello"
    frame = Social::Nostr::Frame.encode(payload)

    assert_equal 0x81, frame.getbyte(0)
    assert_equal 0x80 | payload.bytesize, frame.getbyte(1)

    key = frame.byteslice(2, 4)
    unmasked = Social::Nostr::Frame.mask(frame.byteslice(6..), key)
    assert_equal payload, unmasked.force_encoding("UTF-8")
  end

  test "picks the right length encoding for medium and large payloads" do
    medium = Social::Nostr::Frame.encode("x" * 200)
    assert_equal 0x80 | 126, medium.getbyte(1)
    assert_equal 200, medium.byteslice(2, 2).unpack1("n")

    large = Social::Nostr::Frame.encode("x" * 70_000)
    assert_equal 0x80 | 127, large.getbyte(1)
    assert_equal 70_000, large.byteslice(2, 8).unpack1("Q>")
  end

  test "reads an unmasked server frame" do
    payload = %(["OK","abc",true,""])
    server_frame = [ 0x81, payload.bytesize ].pack("C2") + payload

    opcode, body = Social::Nostr::Frame.read(StringIO.new(server_frame), deadline)

    assert_equal :text, opcode
    assert_equal payload, body
  end

  test "returns nil when the stream ends mid-frame" do
    assert_nil Social::Nostr::Frame.read(StringIO.new([ 0x81, 10 ].pack("C2") + "short"), deadline)
  end

  private

  def deadline
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
  end
end
