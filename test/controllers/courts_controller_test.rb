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

  # ---- seo ----------------------------------------------------------------

  test "paginated index canonicalizes and hreflangs to itself, not to the first page" do
    get courts_url(host: "getcourt.co", page: 2)

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/courts?page=2']", count: 1
    assert_select "link[rel='alternate'][hreflang='ru'][href='https://ru.getcourt.co/courts?page=2']", count: 1
    assert_select "link[rel='alternate'][hreflang='x-default'][href='https://getcourt.co/courts?page=2']", count: 1
  end

  test "first page keeps a clean canonical without the page parameter" do
    get courts_url(host: "getcourt.co", page: 1)

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/courts']", count: 1
  end

  test "court page ignores a stray page parameter in its canonical" do
    courts(:one).update!(moderation_status: "approved")

    get court_url(courts(:one), host: "getcourt.co", page: 2)

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/courts/#{courts(:one).id}']", count: 1
  end

  test "filtered index does not canonicalize to another page of the unfiltered list" do
    get courts_url(host: "getcourt.co", city: "Moscow", page: 2)

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/courts']", count: 1
  end

  test "court page survives a non-scalar page parameter" do
    courts(:one).update!(moderation_status: "approved")

    get "/courts/#{courts(:one).id}?page[]=2", headers: { "HOST" => "getcourt.co" }

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/courts/#{courts(:one).id}']", count: 1
  end

  test "language switcher links are nofollow" do
    get courts_url(host: "getcourt.co")

    assert_response :success
    assert_select "a[rel='nofollow'][href^='/locale/']", minimum: 3
    assert_select "a[href^='/locale/']:not([rel='nofollow'])", count: 0
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

  test "results summary shows total courts count instead of current page size" do
    initial_count = Court.approved.count
    13.times { |i| Court.create!(name: "Paged Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url

    assert_response :success
    assert_select "[data-testid='results-summary']", text: /#{initial_count + 13} courts available/
  end

  test "index page 2 returns the overflow record" do
    initial_count = Court.approved.count
    13.times { |i| Court.create!(name: "Paged Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url, params: { page: 2 }

    assert_response :success
    assert_equal initial_count + 1, assigns(:courts).size
  end

  test "index first page contains 12 courts when 13 exist" do
    13.times { |i| Court.create!(name: "Sized Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url

    assert_equal 12, assigns(:courts).size
  end

  test "pagy reports correct total count" do
    initial_count = Court.approved.count
    13.times { |i| Court.create!(name: "Total Court #{i}", moderation_status: "approved", approved_at: Time.current) }

    get courts_url

    assert_equal initial_count + 13, assigns(:pagy).count
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

  test "country filter shows the country name and still accepts the country code as a slug" do
    city_ids = []
    city_ids << City.create!(name: "Almaty", country_code: "KZ", population: 2_000_000).id
    court = Court.create!(name: "Almaty Court #{SecureRandom.hex(4)}", city_name: "Almaty", moderation_status: "approved")

    get courts_url, params: { country: "KZ" }
    assert_redirected_to courts_browse_path(country_slug: "kazakhstan")

    follow_redirect!
    assert_match "Kazakhstan", @response.body
    assert_includes @controller.instance_variable_get(:@courts), court

    # links minted before Kazakhstan had a name still resolve
    get courts_browse_url(country_slug: "kz")
    assert_redirected_to courts_browse_path(country_slug: "kazakhstan")
  ensure
    court&.destroy
    City.where(id: city_ids).delete_all
  end

  test "index country filter shows full country name in summary and filters courts" do
    city_ids = []
    city_ids << City.create!(name: "Kitzbuhel", country_code: "AT", population: 8_000).id
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    austrian_court = Court.create!(name: "Kitz Court", city_name: "Kitzbuhel", moderation_status: "approved", approved_at: Time.current)
    russian_court = Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)

    get courts_url, params: { country: "AT" }

    assert_redirected_to courts_browse_path(country_slug: "austria")

    get courts_browse_url(country_slug: "austria")

    assert_response :success
    assert_includes assigns(:courts), austrian_court
    assert_not_includes assigns(:courts), russian_court
    assert_select "[data-testid='results-summary']", text: /Austria/
  ensure
    austrian_court&.destroy
    russian_court&.destroy
    City.where(id: city_ids).delete_all if city_ids
  end

  test "country to city mapping prefers the most populous matching city on courts index" do
    city_ids = []
    city_ids << City.create!(name: "Minsk", country_code: "BY", population: 1_742_124).id
    city_ids << City.create!(name: "Minsk", country_code: "RU", population: 0).id
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    minsk_court = Court.create!(name: "Minsk Court", city_name: "Minsk", moderation_status: "approved", approved_at: Time.current)
    ekb_court = Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)

    get courts_url, params: { country: "RU" }

    assert_redirected_to courts_browse_path(country_slug: "russia")

    get courts_browse_url(country_slug: "russia")

    assert_response :success
    assert_not_includes assigns(:cities), "Minsk"
    assert_includes assigns(:courts), ekb_court
    assert_not_includes assigns(:courts), minsk_court
  ensure
    minsk_court&.destroy
    ekb_court&.destroy
    City.where(id: city_ids).delete_all if city_ids
  end

  test "index renders location filters stimulus payload for client-side city updates" do
    city_ids = []
    city_ids << City.create!(name: "Kitzbuhel", country_code: "AT", population: 8_000).id
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    Court.create!(name: "Kitz Court", city_name: "Kitzbuhel", moderation_status: "approved", approved_at: Time.current)
    Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)

    get courts_url

    assert_response :success
    assert_includes response.body, 'data-controller="location-filters"'
    assert_includes response.body, "Kitzbuhel"
    assert_includes response.body, "Yekaterinburg"
  ensure
    Court.where(name: [ "Kitz Court", "Ekb Court" ]).delete_all
    City.where(id: city_ids).delete_all if city_ids
  end

  test "index redirects city filters to canonical slug path" do
    city_ids = []
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)

    get courts_url, params: { country: "RU", city: "Yekaterinburg" }

    assert_redirected_to courts_browse_path(country_slug: "russia", city_slug: "yekaterinburg")
  ensure
    Court.where(name: "Ekb Court").delete_all
    City.where(id: city_ids).delete_all if city_ids
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

  test "city alias Ekaterinburg matches court with city_name Yekaterinburg" do
    user_email = "ekb_alias_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    user = User.find_by!(email: user_email)
    user.update_column(:city_name, "Ekaterinburg")

    other = Court.create!(name: "Moscow Court",       city_name: "Moscow",        moderation_status: "approved", approved_at: Time.current)
    local = Court.create!(name: "Yekaterinburg Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)

    get courts_url

    courts = assigns(:courts)
    assert courts.index(local) < courts.index(other),
           "Yekaterinburg court should appear before Moscow court for user with city Ekaterinburg"
  ensure
    local&.destroy
    other&.destroy
    user&.destroy
  end

  # ---- free court filter --------------------------------------------------

  test "free filter shows only free courts" do
    free_court  = Court.create!(name: "Free Court",  moderation_status: "approved", approved_at: Time.current, free: true)
    paid_court  = Court.create!(name: "Paid Court",  moderation_status: "approved", approved_at: Time.current, free: false)

    get courts_url, params: { free: "1" }

    courts = assigns(:courts)
    assert_includes courts, free_court
    assert_not_includes courts, paid_court
  ensure
    free_court&.destroy
    paid_court&.destroy
  end

  test "outdoor filter shows only outdoor courts" do
    outdoor_court = Court.create!(name: "Outdoor Court", moderation_status: "approved", approved_at: Time.current, outdoor: true)
    indoor_court = Court.create!(name: "Indoor Only Court", moderation_status: "approved", approved_at: Time.current, outdoor: false)

    get courts_url, params: { outdoor: "1" }

    courts = assigns(:courts)
    assert_includes courts, outdoor_court
    assert_not_includes courts, indoor_court
  ensure
    outdoor_court&.destroy
    indoor_court&.destroy
  end

  test "indoor filter shows only indoor courts" do
    indoor_court = Court.create!(name: "Indoor Court", moderation_status: "approved", approved_at: Time.current, indoor: true)
    outdoor_court = Court.create!(name: "Outdoor Only Court", moderation_status: "approved", approved_at: Time.current, indoor: false)

    get courts_url, params: { indoor: "1" }

    courts = assigns(:courts)
    assert_includes courts, indoor_court
    assert_not_includes courts, outdoor_court
  ensure
    indoor_court&.destroy
    outdoor_court&.destroy
  end

  test "sport filter shows only courts of given sport" do
    tennis_court = Court.create!(name: "Tennis Court", sport: "Tennis", moderation_status: "approved", approved_at: Time.current)
    padel_court = Court.create!(name: "Padel Court", sport: "Padel", moderation_status: "approved", approved_at: Time.current)

    get courts_url, params: { sport: "Tennis" }

    courts = assigns(:courts)
    assert_includes courts, tennis_court
    assert_not_includes courts, padel_court
  ensure
    tennis_court&.destroy
    padel_court&.destroy
  end

  test "sport filter combines with free filter" do
    free_tennis = Court.create!(name: "Free Tennis", sport: "Tennis", free: true, moderation_status: "approved", approved_at: Time.current)
    paid_tennis = Court.create!(name: "Paid Tennis", sport: "Tennis", free: false, moderation_status: "approved", approved_at: Time.current)
    free_padel = Court.create!(name: "Free Padel", sport: "Padel", free: true, moderation_status: "approved", approved_at: Time.current)

    get courts_url, params: { sport: "Tennis", free: "1" }
    follow_redirect! if response.redirect?

    courts = assigns(:courts)
    assert_includes courts, free_tennis
    assert_not_includes courts, paid_tennis
    assert_not_includes courts, free_padel
  ensure
    free_tennis&.destroy
    paid_tennis&.destroy
    free_padel&.destroy
  end

  test "without free filter all courts are shown" do
    free_court  = Court.create!(name: "Free Court2", moderation_status: "approved", approved_at: Time.current, free: true)
    paid_court  = Court.create!(name: "Paid Court2", moderation_status: "approved", approved_at: Time.current, free: false)

    get courts_url

    courts = assigns(:courts)
    assert_includes courts, free_court
    assert_includes courts, paid_court
  ensure
    free_court&.destroy
    paid_court&.destroy
  end

  test "free attribute is saved on create" do
    user_email = "free_create_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }

    post courts_url, params: { court: { name: "My Free Court", free: "1" } }

    court = Court.find_by(name: "My Free Court")
    assert court&.free?, "Court should be free"
  ensure
    Court.where(name: "My Free Court").destroy_all
    User.find_by(email: user_email)&.destroy
  end

  test "outdoor and indoor attributes are saved on create" do
    user_email = "court_flags_create_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }

    post courts_url, params: { court: { name: "My Mixed Court", outdoor: "1", indoor: "1" } }

    court = Court.find_by(name: "My Mixed Court")
    assert court&.outdoor?, "Court should be outdoor"
    assert court&.indoor?, "Court should be indoor"
  ensure
    Court.where(name: "My Mixed Court").destroy_all
    User.find_by(email: user_email)&.destroy
  end

  # ---- authorization on edit/update/destroy --------------------------------

  test "non-owner cannot update a court" do
    owner_email = "owner_#{SecureRandom.hex(4)}@example.com"
    other_email = "other_#{SecureRandom.hex(4)}@example.com"

    post session_url, params: { email: owner_email }
    owner = User.find_by!(email: owner_email)
    court = Court.create!(name: "Owner Court", moderation_status: "approved", approved_at: Time.current, user: owner)

    post session_url, params: { email: other_email }
    patch court_url(court), params: { court: { name: "Hacked Name" } }

    assert_response :forbidden
    assert_equal "Owner Court", court.reload.name
  ensure
    court&.destroy
    User.find_by(email: owner_email)&.destroy
    User.find_by(email: other_email)&.destroy
  end

  test "owner can update their court" do
    owner_email = "owner2_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: owner_email }
    owner = User.find_by!(email: owner_email)
    court = Court.create!(name: "My Court", moderation_status: "approved", approved_at: Time.current, user: owner)

    patch court_url(court), params: { court: { name: "Updated Court" } }

    assert_response :redirect
    assert_equal "Updated Court", court.reload.name
  ensure
    court&.destroy
    User.find_by(email: owner_email)&.destroy
  end

  test "non-owner cannot edit a court" do
    owner_email = "owner3_#{SecureRandom.hex(4)}@example.com"
    other_email = "other3_#{SecureRandom.hex(4)}@example.com"

    post session_url, params: { email: owner_email }
    owner = User.find_by!(email: owner_email)
    court = Court.create!(name: "Another Court", moderation_status: "approved", approved_at: Time.current, user: owner)

    post session_url, params: { email: other_email }
    get edit_court_url(court)

    assert_response :forbidden
  ensure
    court&.destroy
    User.find_by(email: owner_email)&.destroy
    User.find_by(email: other_email)&.destroy
  end

  test "user_id cannot be changed via mass assignment on update" do
    owner_email = "owner4_#{SecureRandom.hex(4)}@example.com"
    other_email = "other4_#{SecureRandom.hex(4)}@example.com"

    post session_url, params: { email: other_email }
    other = User.find_by!(email: other_email)

    post session_url, params: { email: owner_email }
    owner = User.find_by!(email: owner_email)
    court = Court.create!(name: "Owned Court", moderation_status: "approved", approved_at: Time.current, user: owner)

    patch court_url(court), params: { court: { name: "Updated", user_id: other.id } }

    assert_response :redirect
    assert_equal owner.id, court.reload.user_id, "user_id must not change via params"
  ensure
    court&.destroy
    User.find_by(email: owner_email)&.destroy
    User.find_by(email: other_email)&.destroy
  end

  test "admin can update another user's court" do
    owner_email = "owner5_#{SecureRandom.hex(4)}@example.com"
    admin_email = "admin5_#{SecureRandom.hex(4)}@example.com"

    post session_url, params: { email: owner_email }
    owner = User.find_by!(email: owner_email)
    court = Court.create!(name: "Other Court", moderation_status: "approved", approved_at: Time.current, user: owner)

    post session_url, params: { email: admin_email }
    User.find_by!(email: admin_email).update_column(:admin, true)

    patch court_url(court), params: { court: { name: "Admin Edited" } }

    assert_response :redirect
    assert_equal "Admin Edited", court.reload.name
  ensure
    court&.destroy
    User.find_by(email: owner_email)&.destroy
    User.find_by(email: admin_email)&.destroy
  end
end
