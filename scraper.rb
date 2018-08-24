#!/bin/env ruby
# encoding: utf-8

require 'colorize'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'pry'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def json_from(url)
  url = "/api/v1/#{url}/?limit=200" unless url.include?("/")
  url = URI.join('https://kansanmuisti.fi', url) unless url.start_with? 'http'
  doc = JSON.parse(open(url).read, symbolize_names: true)
  if doc[:meta][:next]
    return doc[:objects] + json_from(doc[:meta][:next])
  else
    return doc[:objects] 
  end
end

def gender_from(str)
  return unless str
  return 'male' if str == 'm'
  return 'female' if str == 'f'
  raise "unknown gender: #{str}"
end

terms = json_from('term').sort_by { |t| t[:begin] }.each_with_index do |t, i|
  t[:id] = i+1
  t[:name] = "Eduskunta #{i+1}"
  t[:identifier__km] = t.delete(:display_name).strip
  t[:start_date] = t.delete :begin
  t[:end_date] = t.delete :end
  t[:end_date] = '2015-03-14' if t[:identifier__km] == '2011'
  t.delete :resource_uri
  t.delete :visible
end
ScraperWiki.save_sqlite([:id], terms, 'terms')

parties = json_from('party')
json_from('member').each do |member|
  data = { 
    id: member[:origin_id],
    name: member[:print_name],
    sort_name: member[:name],
    family_name: member[:surname],
    given_name: member[:given_names],
    birth_date: member[:birth_date],
    area: member[:district_name],
    email: member[:email],
    phone: member[:phone],
    photo: member[:photo],
    gender: gender_from(member[:gender]),
    homepage: member[:homepage_link],
    wikipedia: member[:wikipedia_link],
    identifier__kansanmuisti: member[:id],
    identifier__eduskunta: member[:origin_id],
    source: member[:info_link],
  }
  data[:photo] = URI.join('https://kansanmuisti.fi', data[:photo]).to_s unless data[:photo].to_s.empty?

  member[:party_associations].each do |pa|
    party_start = pa[:begin] 
    party_end   = pa[:end] || '2015-03-14'
    terms.find_all { |term| party_start < term[:end_date] && party_end > term[:start_date] }.each do |term|
      overlap = [party_start, party_end, term[:start_date], term[:end_date]].sort[1,2]
      membership = { 
        term: term[:id],
        start_date: overlap.first,
        end_date: overlap.last,
        party_id: pa[:party],
        party: parties.find(->{ { name: pa[:party] }}) { |p| p[:abbreviation] == pa[:party] }[:name],
      }
      row = data.merge(membership)
      ScraperWiki.save_sqlite([:id, :term, :start_date], row)
    end

  end

end
