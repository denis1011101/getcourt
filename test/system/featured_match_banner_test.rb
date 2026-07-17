require "application_system_test_case"
require "base64"
require "json"
require "stringio"

class FeaturedMatchBannerTest < ApplicationSystemTestCase
  test "renders active featured match banner on games index" do
    travel_to wallchart_banner_expired_at do
      featured_match = FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_left_flag: "RU",
        player_right_name: "M. Kostyuk",
        player_right_flag: "UA",
        starts_at: 1.day.from_now,
        active: true
      )
      attach_photo(featured_match, "photo1.jpg")
      attach_photo(featured_match, "photo2.jpg")

      visit root_path

      assert_text "Roland Garros Final"
      assert_text "M. Andreeva"
      assert_text "M. Kostyuk"
      assert_selector ".featured-match-banner .countdown"
      assert_selector ".featured-match-banner .photos[data-featured-match-target='photos'] .photo-wrap", count: 2
      assert_selector ".featured-match-banner .photos .photo-main", count: 2
    end
  end

  test "homepage meta is not overridden by featured match" do
    travel_to wallchart_banner_expired_at do
      FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      visit root_path

      assert_text "Roland Garros Final"
      assert_no_selector "title", text: "M. Andreeva vs M. Kostyuk", visible: false
      assert_no_selector "meta[property='og:type'][content='event']", visible: false
      assert_no_selector "script[type='application/ld+json']", visible: false
    end
  end

  test "homepage banner links to event page" do
    travel_to wallchart_banner_expired_at do
      featured_match = FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      visit root_path

      assert_selector "a[href='#{event_path(featured_match)}'] .featured-match-banner"
    end
  end

  test "homepage banner does not link surface label to court directly" do
    travel_to wallchart_banner_expired_at do
      FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        surface_label: "Clay · MyString",
        court: courts(:one),
        active: true
      )

      visit root_path

      assert_selector ".featured-match-banner .surface-tag", text: "Clay · MyString"
      assert_no_selector ".featured-match-banner a.surface-tag--link"
    end
  end

  test "homepage renders wallchart banner instead of featured match while wallchart is active" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL - 1.day do
      featured_match = FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      visit root_path

      assert_selector "a[href='#{event_path(featured_match)}']", text: "Make your final prediction"
      assert_text "Watch the final together"
      assert_no_selector ".featured-match-banner"
      assert_no_selector "a[href^='https://wallchart26.com']"
      assert_no_selector "a[href^='https://yandex.com/maps']"
    end
  end

  test "homepage renders featured match banner after wallchart expires" do
    travel_to wallchart_banner_expired_at do
      FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      visit root_path

      assert_selector ".featured-match-banner", text: "Roland Garros Final"
      assert_no_selector "a[href^='https://wallchart26.com']"
    end
  end

  test "event page renders meta, og:type=website and SportsEvent JSON-LD" do
    featured_match = FeaturedMatch.create!(
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_right_name: "M. Kostyuk",
      starts_at: 1.day.from_now,
      active: true
    )
    attach_photo(featured_match, "photo1.jpg")

    visit event_path(featured_match)

    assert_selector "title", text: "M. Andreeva vs M. Kostyuk", visible: false
    assert_selector "meta[property='og:type'][content='website']", visible: false, count: 1
    assert_selector "meta[property='og:title']", visible: false, count: 1
    og_image = page.find("meta[property='og:image']", visible: false)["content"]
    assert_match %r{/rails/active_storage/representations/}, og_image
    assert_selector "meta[name='twitter:title']", visible: false, count: 1

    json_ld = page.find("script[type='application/ld+json']", visible: false).native.inner_html
    data = JSON.parse(json_ld)
    assert_equal "SportsEvent", data["@type"]
    assert_equal 2, data["competitor"].length
    assert_equal "https://schema.org/EventScheduled", data["eventStatus"]
  end

  test "event page links surface label to court when court is attached" do
    featured_match = FeaturedMatch.create!(
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_right_name: "M. Kostyuk",
      starts_at: 1.day.from_now,
      surface_label: "Clay · MyString",
      court: courts(:one),
      active: true
    )

    visit event_path(featured_match)

    assert_link "Clay · MyString", href: court_path(courts(:one))
  end

  test "event page renders surface label as text without a court" do
    featured_match = FeaturedMatch.create!(
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_right_name: "M. Kostyuk",
      starts_at: 1.day.from_now,
      surface_label: "Clay · Unknown Court",
      active: true
    )

    visit event_path(featured_match)

    assert_selector ".featured-match-banner .surface-tag", text: "Clay · Unknown Court"
    assert_no_link "Clay · Unknown Court"
  end

  test "event page renders fallback about text for a non-featured match" do
    featured_match = FeaturedMatch.create!(
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_right_name: "M. Kostyuk",
      starts_at: 1.day.from_now,
      active: false
    )

    visit event_path(featured_match)

    assert_text "About"
    assert_text "#{featured_match.seo_title} is scheduled for"
    assert_no_text "Before kickoff"
    assert_no_selector "a[href^='https://yandex.com/maps']"
  end

  test "event page renders wallchart promo blocks while wallchart is active" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL - 1.day do
      featured_match = FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      visit event_path(featured_match)

      assert_text "Before kickoff"
      assert_text "Watch the final together"
      assert_selector "a[href='https://wallchart26.com/?utm_source=getcourt&utm_medium=event'][target='_blank'][rel='noopener']", text: "Make your prediction"
      assert_selector "a[href='https://yandex.com/maps/-/CTFs46~-'][target='_blank'][rel='noopener']", text: "Open in Yandex Maps"
    end
  end

  test "event page keeps the venue block after kickoff but hides the prediction cta" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL do
      featured_match = FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: ApplicationHelper::WALLCHART_BANNER_UNTIL,
        active: true
      )

      visit event_path(featured_match)

      assert_text "The predictions are in"
      assert_text "Watch the final together"
      assert_text "Hookah lounge"
      assert_no_text "Before kickoff"
      assert_selector "a[href='https://yandex.com/maps/-/CTFs46~-'][target='_blank'][rel='noopener']"
      assert_no_selector "a[href^='https://wallchart26.com']"
    end
  end

  test "event page does not show wallchart promo for a later active match after the cutoff" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL + 10.days do
      featured_match = FeaturedMatch.create!(
        tournament_label: "US Open Final",
        player_left_name: "C. Alcaraz",
        player_right_name: "J. Sinner",
        starts_at: 5.days.from_now,
        active: true
      )

      visit event_path(featured_match)

      assert_text "About"
      assert_text "#{featured_match.seo_title} is scheduled for"
      assert_no_text "Before kickoff"
      assert_no_text "Watch the final together"
      assert_no_selector "a[href^='https://yandex.com/maps']"
      assert_no_selector "a[href^='https://wallchart26.com']"
    end
  end

  test "event page renders finished result block" do
    featured_match = FeaturedMatch.create!(
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_right_name: "M. Kostyuk",
      starts_at: 1.day.ago,
      status: "finished",
      result: "M. Andreeva won 6-4, 6-4",
      active: true
    )

    visit event_path(featured_match)

    assert_text "Result"
    assert_text "M. Andreeva won 6-4, 6-4"
  end

  test "event page renders linked photo credit" do
    featured_match = FeaturedMatch.create!(
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_right_name: "M. Kostyuk",
      starts_at: 1.day.from_now,
      photo_credit: "WTA Photos",
      photo_credit_url: "https://example.com/photos",
      active: true
    )

    visit event_path(featured_match)

    assert_text "Photo:"
    assert_link "WTA Photos", href: "https://example.com/photos"
  end

  test "homepage without active match does not render banner or JSON-LD" do
    visit root_path

    assert_selector "title", text: "GetCourt", visible: false
    assert_no_selector ".featured-match-banner"
    assert_no_selector "script[type='application/ld+json']", visible: false
  end

  private

  def wallchart_banner_expired_at
    ApplicationHelper::WALLCHART_BANNER_UNTIL + 1.day
  end

  def attach_photo(featured_match, filename)
    featured_match.photos.attach(
      io: StringIO.new(Base64.decode64(SAMPLE_PNG)),
      filename: filename,
      content_type: "image/png"
    )
  end

  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
end
