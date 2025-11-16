module ApplicationHelper
  def format_date(date)
    date.strftime("%B %d, %Y")
  end

  def format_time(time)
    time.strftime("%I:%M %p")
  end

  def nearby_courts_link
    link_to 'Find Nearby Courts', searches_path, class: 'btn btn-primary'
  end
end
