require 'rss'
require 'nokogiri'
require 'open-uri'
require 'htmlentities'
require "mongo"
require 'net/http'
require 'open-uri'

DOWNLOAD = false

def fetch_uri uri, file
  open(file, "wb") do |f|
    open(uri) do |ur|
      f.write(ur.read)
    end
  end
end

#class TextHandler < Nokogiri::XML::SAX::Document
#  def initialize
#    @chunks = []
#  end
#
#  attr_reader :chunks
#
#  def cdata_block(string)
#    characters(string)
#  end
#
#  def characters(string)
#    @chunks << string.strip if string.strip != ""
#  end
#end

#def stringify obj
#  th = TextHandler.new
#  parser = Nokogiri::HTML::SAX::Parser.new(th)
#  parser.parse obj.to_s
#  puts "chunks size = #{th.chunks.length}"
#  th.chunks
#end

@programs = []

@addresses = [
  "http://www.bbc.co.uk/programmes/b006qykl/episodes/downloads.rss",
  "http://www.bbc.co.uk/programmes/p01drwny/episodes/downloads.rss",
  "http://www.bbc.co.uk/programmes/p01dh5yg/episodes/downloads.rss",
  "http://www.bbc.co.uk/programmes/p01f0vzr/episodes/downloads.rss",
  "http://www.bbc.co.uk/programmes/p01gvqlg/episodes/downloads.rss",
  "http://www.bbc.co.uk/programmes/p01gyd7j/episodes/downloads.rss"
]

@files = [
  "pages/culture.rss",
  "pages/history.rss",
  "pages/in_our_time.rss",
  "pages/philosophy.rss",
  "pages/religion.rss",
  "pages/science.rss"
]

if DOWNLOAD
  @files.length.times do |count|
    puts 'downloading' + @files[count]
    fetch_uri @addresses[count], @files[count]
  end
end

@files.each do |file|
  @doc = Nokogiri::XML(File.open(file))

  titles    = @doc.xpath("//item//title")
  descs     = @doc.xpath("//item//description")
  subtitles = @doc.xpath("//item//itunes:subtitle")
  summarys  = @doc.xpath("//item//itunes:summary")
  durations = @doc.xpath("//item//itunes:duration")
  dates     = @doc.xpath("//item//pubDate")
  links     = @doc.xpath("//item//link")

#  descs.map{|f| puts "#{f.text} \n\n"}
#  exit

#  if file == "pages/culture.rss"
#    puts @doc.xpath("//item//title")          .length
#    puts @doc.xpath("//item//description")    .length
#    puts @doc.xpath("//item//itunes:subtitle").length
#    puts @doc.xpath("//item//itunes:summary") .length
#    puts @doc.xpath("//item//itunes:duration").length
#    puts @doc.xpath("//item//pubDate")        .length
#    puts @doc.xpath("//item//link")           .length
#    puts titles    .length
#    puts descs     .length
#    puts subtitles .length
#    puts summarys  .length
#    puts durations .length
#    puts dates     .length
#    puts links     .length
#    exit
#  end

  0.upto (titles.length - 1) do |idx|
    program = {}
    program[:title] = titles[idx].text
#    program[:description] = descs[idx]
    program[:subtitle] = subtitles[idx].text
    program[:summary]  = summarys[idx].text
    program[:duration] = durations[idx].text
    program[:date] = dates[idx].text
    program[:link] = links[idx].text
    @programs << program
  end
end

puts @programs.length.to_s + " programs"
puts "programs unique? " + (@programs.uniq.length == @programs.length).to_s
puts "uniquify (by title)..."

@programs = @programs.uniq{|pr| pr[:title]}
puts "programs unique? " + (@programs.uniq.length == @programs.length).to_s
puts @programs.length.to_s + " programs"
puts
@dates, @titles = [], []

#@titles.sort!
#puts "titles unique? " + (@titles.uniq.length == @titles.length).to_s
##@titles = @titles.uniq
#
#
#puts "titles unique? " + (@titles.uniq.length == @titles.length).to_s
#puts @titles.length.to_s + " titles"
#p @titles
#@titles.map{|x| puts x}

client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'in_our_time')
db = client.database

collection = client[:programs]

#collection.drop

#@programs.each do |pr|
#  result = collection.insert_one pr
#  p result
#end

#result = collection.insert_many @programs
#p "Inserted #{result.inserted_count} records"

#puts collection.find( { title: 'Dreams' } ).first

#@programs.each do |pr|
#  result = collection.delete_many( { title: pr[:title] } )
###  p result
#end

#@programs.each do |pr|
#  @dates << Time.parse(pr[:date][0..16])
#  @titles << pr[:title]
#end

@programs.each do |pr|
  p pr[:title]
end

puts
redirect = ''
@programs.each do |pr|
  if pr[:title] == 'Grand Unified Theory'
    puts pr[:link]
    url = pr[:link]
    res = Net::HTTP.get_response(URI.parse(url))
    puts "link response = #{ res.body }"

    @doc = Nokogiri::XML(res.body)
    redirect = @doc.css("body p a").text
    puts
    puts "redirect = #{redirect}"
    puts
    red = Net::HTTP.get_response(URI.parse(redirect))
#    puts "red = #{red.body}"
    title = pr[:title].gsub(' ', '_') + '.mp3'
    title = File.join('audio', title.downcase)
    File.open(title,'wb') do |f|
      f.print(red.body)
      puts "written #{title}"
    end
  end
end

puts "Done."
exit

#  File.open('redirect.html','w') do |f|
#    f.write(res.body)
#  end
#  puts "Done."
#  exit
#end

# url = "http://aod-pod-uk-live.edgesuite.net/mpg_mp3_med/2c97899356ff3f2a015751621c0d457b--audio--IOT-ZenosParadoxes-220916_mpg_mp3_med.mp3?__gda__=1474658642_9624064e8c8aca016652dea21dc86463"
