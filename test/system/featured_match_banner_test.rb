require "application_system_test_case"
require "base64"
require "json"
require "stringio"

class FeaturedMatchBannerTest < ApplicationSystemTestCase
  test "renders active featured match banner on games index" do
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

  test "homepage meta is not overridden by featured match" do
    FeaturedMatch.create!(
      tournament_label: "Roland Garros Final",
      player_left_name: "M. Andreeva",
      player_right_name: "M. Kostyuk",
      starts_at: 1.day.from_now,
      active: true
    )

    visit root_path

    assert_no_selector "title", text: "M. Andreeva vs M. Kostyuk", visible: false
    assert_no_selector "meta[property='og:type'][content='event']", visible: false
    assert_no_selector "script[type='application/ld+json']", visible: false
  end

  test "homepage banner links to event page" do
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

  test "homepage banner does not link surface label to court directly" do
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

  test "homepage without active match does not render banner or JSON-LD" do
    visit root_path

    assert_selector "title", text: "GetCourt", visible: false
    assert_no_selector ".featured-match-banner"
    assert_no_selector "script[type='application/ld+json']", visible: false
  end

  private

  def attach_photo(featured_match, filename)
    featured_match.photos.attach(
      io: StringIO.new(Base64.decode64(SAMPLE_PNG)),
      filename: filename,
      content_type: "image/png"
    )
  end

  SAMPLE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
end
