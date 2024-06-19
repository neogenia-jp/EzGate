# frozen_string_literal: true

class Redirect
  attr_reader :dest, :status

  def initialize(dest, status = 301)
    dest = "https://#{dest}" unless dest.start_with? 'http'
    dest = dest.chop if dest.end_with? '/'
    @dest = dest
    @status = status
  end

  def check
  end

  def to_s
    "return #{@status} #{@dest}$request_uri;"
  end
end
