require "test_helper"

class CourtsControllerTest < ActionDispatch::IntegrationTest
  # ---- basic access -------------------------------------------------------

  test "index is accessible without authentication" do
    get courts_url
    assert_response :success
  end

  test "show renders approved court without authentication" do
    courts(:one).update!(moderation_status: "approved")

    get court_url(courts(:one))
    assert_response :success
  end

  test "show redirects guest away from pending court" do
    courts(:one).update!(moderation_status: "pending")

    get court_url(courts(:one))
    assert_redirected_to courts_path
  end

  # ---- moderation filter --------------------------------------------------

  test "index only shows approved courts to guests" do
    approved = Court.create!(name: "Open Court",    moderation_status: "approved", approved_at: Time.current)
    pending  = Court.create!(name: "Pending Court", moderation_status: "pending")

    get courts_url

    assert_includes     assigns(:courts), approved
    assert_not_includes assigns(:courts), pending
  end

  # ---- pagination ---------------------------------------------------------

  test "index assigns @pagy" do
    get courts_url

    assert_not_nil assigns(:pagy)
  end

  test "index shows at most 12 courts per page" do
    13.times { |i| Court.create!(name: "Paged Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url

    assert_response :success
    assert assigns(:courts).size <= 12
  end

  test "index page 2 returns the overflow record" do
    13.times { |i| Court.create!(name: "Paged Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url, params: { page: 2 }

    assert_response :success
    assert_equal 1, assigns(:courts).size
  end

  test "index first page contains 12 courts when 13 exist" do
    13.times { |i| Court.create!(name: "Sized Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url

    assert_equal 12, assigns(:courts).size
  end

  test "pagy reports correct total count" do
    13.times { |i| Court.create!(name: "Total Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url

    assert_equal 13, assigns(:pagy).count
  end

  test "pagy reports 2 pages when 13 courts exist" do
    13.times { |i| Court.create!(name: "Pages Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url

    assert_equal 2, assigns(:pagy).pages
  end

  # ---- city filter --------------------------------------------------------

  test "index filters by params[:city] when provided" do
    moscow = Court.create!(name: "Moscow Court", city_name: "Moscow", moderation_status: "approved", approved_at: Time.current)
    kazan  = Court.create!(name: "Kazan Court",  city_name: "Kazan",  moderation_status: "approved", approved_at: Time.current)

    get courts_url, params: { city: "Moscow" }

    assert_includes     assigns(:courts), moscow
    assert_not_includes assigns(:courts), kazan
  end

  test "city filter excludes courts from other cities" do
    other = Court.create!(name: "Other Court", city_name: "Kazan", moderation_status: "approved", approved_at: Time.current)

    get courts_url, params: { city: "Moscow" }

    assert_not_includes assigns(:courts), other
  end

  test "city filter still paginates" do
    created_ids = []
    13.times do |i|
      created_ids << Court.create!(name: "Moscow Court #{i}", city_name: "Moscow", moderation_status: "approved", approved_at: Time.current).id
    end

    get courts_url, params: { city: "Moscow" }

    assert_response :success
    assert_not_nil assigns(:pagy)
    assert assigns(:courts).all? { |court| court.city_name == "Moscow" }
  ensure
    Court.where(id: created_ids).delete_all if created_ids
  end

  # ---- city-first ordering for signed-in user ----------------------------

  test "same-city court appears before other-city court for signed-in user" do
    user_email = "courts_city_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.update_column(:city_name, "Kazan")

    other = Court.create!(name: "Other City Court", city_name: "Moscow", moderation_status: "approved", approved_at: Time.current)
    local = Court.create!(name: "Local City Court", city_name: "Kazan",  moderation_status: "approved", approved_at: Time.current)

    get courts_url

    courts = assigns(:courts)
    assert courts.index(local) < courts.index(other),
           "Same-city court should appear before other-city court"
  ensure
    local&.destroy
    other&.destroy
    user&.destroy
  end
end
