require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "should get contacts" do
    get contacts_url
    assert_response :success
  end

  test "should get mission" do
    get mission_url
    assert_response :success
  end

  # pages_nav partial: each page shows links to all others but not itself
  {
    contacts:              -> { contacts_path },
    mission:               -> { mission_path },
    partnership:           -> { partnership_path },
    ntrp_level_guide:      -> { ntrp_level_guide_path },
    tennis_formats_rules:  -> { tennis_formats_and_rules_path },
  }.each do |page, path_proc|
    test "#{page} renders pages_nav without self-link" do
      get instance_exec(&path_proc)
      assert_response :success

      all_paths = [
        contacts_path, mission_path, partnership_path,
        ntrp_level_guide_path, tennis_formats_and_rules_path, coaches_path
      ]
      current_path = instance_exec(&path_proc)

      (all_paths - [ current_path ]).each do |other|
        assert_select "a[href='#{other}']", minimum: 1
      end

      # self-link must not appear inside the nav div
      assert_select "div.mt-6 a[href='#{current_path}']", count: 0
    end
  end
end
