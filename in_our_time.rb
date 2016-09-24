require 'rss'
require 'nokogiri'
require 'open-uri'
#require 'htmlentities'
require "mongo"
require 'net/http'
require 'open-uri'

CHECK_REMOTE    = false
RELOAD_DATABASE = true
AUDIO_DIRECTORY = 'audio'

class KeyboardEvents
  def input
    begin
      system("stty raw -echo")
      str = STDIN.getc
    #      puts str.inspect
    ensure
      system("stty -raw echo")
    end
    #    puts "str = #{str}"
    case str
    when "l",'L'
      :list
    when ' '
      :page_forward
    when "q",'Q'
      :quit
    when 'p', 'P'
      :previous
    when 'n', 'N'
      :next
    when 'x', 'X'
      :play
    when 'l', 'L'
      :last
    when 'u', 'U'
      :update
    when 't'
      :back_ten
    when 'T'
      :forward_ten
    when 'h'
      :back_one_hundred
    when 'H'
      :forward_one_hundred
    when ' '
      :spacebar
    when '?'
      :help
    else
      :unknown
    end
  end
end


@programs = []
@line_count = 0
@page_length = 20
@selected = 0

def rss_addresses
  [
    "http://www.bbc.co.uk/programmes/b006qykl/episodes/downloads.rss",
    "http://www.bbc.co.uk/programmes/p01drwny/episodes/downloads.rss",
    "http://www.bbc.co.uk/programmes/p01dh5yg/episodes/downloads.rss",
    "http://www.bbc.co.uk/programmes/p01f0vzr/episodes/downloads.rss",
    "http://www.bbc.co.uk/programmes/p01gvqlg/episodes/downloads.rss",
    "http://www.bbc.co.uk/programmes/p01gyd7j/episodes/downloads.rss"
  ]
end

def local_rss
  [
    "pages/culture.rss",
    "pages/history.rss",
    "pages/in_our_time.rss",
    "pages/philosophy.rss",
    "pages/religion.rss",
    "pages/science.rss"
  ]
end

client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'in_our_time')
db = client.database
@collection = client[:programs]

def fetch_uri uri, file
  open(file, "wb") do |f|
    open(uri) do |ur|
      f.write(ur.read)
    end
  end
end

def filename_from_title title
  temp = title.gsub(/[^0-9a-z ]/i, '').gsub(' ', '_').strip + '.mp3'
  File.join('audio', temp.downcase)
end

def download_audio program, addr
  res = Net::HTTP.get_response(URI.parse(addr))
  case res
  when Net::HTTPOK
    File.open( filename_from_title(program[:title]) , 'wb') do |f|
      print "writing #{filename_from_title(program[:title])}..."
      f.print(res.body)
      puts " written."
    end
    true
  else
    puts 'audio download from redirect failed'
  end
end

def have_locally? title
  filename = filename_from_title(title)
  if File.exists?(filename)
    puts "matched #{filename}"
    return true
  end
  false
end

def reload_database
  if RELOAD_DATABASE
    @collection.drop
    result = @collection.insert_many @programs
    p "Inserted #{result.inserted_count} records"
  end
end

def check_remote
  if CHECK_REMOTE
    local_rss.length.times do |count|
      puts 'downloading' + local_rss[count]
      fetch_uri rss_addresses[count], local_rss[count]
    end
  end
end

def uniquify_programs
  @programs = @programs.uniq{|pr| pr[:title]}
  unless @programs.uniq.length == @programs.length
    puts "Error ensuring Programs unique!"
    exit 1
  end
end

def parse_programs
  local_rss.each do |file|
    @doc = Nokogiri::XML(File.open(file))
    titles    = @doc.xpath("//item//title")
    descs     = @doc.xpath("//item//description")
    subtitles = @doc.xpath("//item//itunes:subtitle")
    summarys  = @doc.xpath("//item//itunes:summary")
    durations = @doc.xpath("//item//itunes:duration")
    dates     = @doc.xpath("//item//pubDate")
    links     = @doc.xpath("//item//link")

    0.upto (titles.length - 1) do |idx|
      program = {}
      program[:title] = titles[idx].text
      #    program[:description] = descs[idx]
      program[:subtitle] = subtitles[idx].text
      program[:summary]  = summarys[idx].text
      program[:duration] = durations[idx].text
      program[:date] = dates[idx].text
      program[:link] = links[idx].text
      program[:have_locally] = have_locally?(titles[idx].text)
      @programs << program
    end
  end
  uniquify_programs
end

def select_program title
  @programs.each do |pr|
    if pr[:title].strip == title.strip
      return pr
    end
  end
  nil
end

def sort_titles
  @sorted_titles = []
  @programs.each do |pr|
    @sorted_titles << pr[:title]
  end
  @sorted_titles = @sorted_titles.uniq{|x| x.downcase}
end


#@programs.each do |pr|
#  p pr[:title]
#end
#
#pr = select_program("1848: Year of Revolution")
#unless pr
#  puts "Error! unable to select program"
#  exit 1
#end
#p pr
#system("afplay #{ filename_from_title( pr[:title] ) }")

def run_program prg
  unless prg[:have_locally]
    retries = 0
    10.times do
      puts "retries = #{retries}"
      res = Net::HTTP.get_response(URI.parse(prg[:link]))
      case res
      when Net::HTTPFound
        puts "fetching #{prg[:title]}"
        puts 'redirecting...'
        @doc = Nokogiri::XML(res.body)
        redirect = @doc.css("body p a").text
        break if download_audio(prg, redirect)
        sleep 2
      else
        puts 'Error! Expected to be redirected!'
        exit 1
      end
      retries += 1
    end
    if retries >= 10
      puts "Max retries downloading #{prg[:title]}"
      exit 1
    end
  end
  system "afplay #{filename_from_title(prg[:title])}"
end

@programs.each do |pr|
  url = pr[:link]
  unless pr[:have_locally] && false
    5.times do
      res = Net::HTTP.get_response(URI.parse(url))
      case res
      when Net::HTTPFound
        puts "fetching #{pr[:title]}"
        puts 'redirecting...'
        @doc = Nokogiri::XML(res.body)
        redirect = @doc.css("body p a").text
        exit if download_audio(pr, redirect)
        sleep 2
      else
        puts 'Error! Expected to be redirected!'
        exit 1
      end
    end
    puts "Max retries downloading #{pr[:title]}"
  end
end

def draw_page
  if @line_count <=
     @sorted_titles.length
    @line_count.upto(@line_count + @page_length - 1) do |idx|
      if idx < @sorted_titles.length
        print "> " if(idx == @selected)
        print "#{idx + 1}. "
        puts @sorted_titles[idx]
      end
    end
  else
    @line_count = 0
    0.upto(@page_length - 1) do |idx|
      print "> " if(idx == @selected)
      print "#{idx + 1}. "     unless @sorted_titles[idx].nil?
      puts @sorted_titles[idx] unless @sorted_titles[idx].nil?
    end
  end
  @line_count += @page_length
end

def display_list(action)
  system('clear')
  case action
  when :draw_page
    draw_page
  when :previous_page
    if @line_count > 0
      @line_count -= (@page_length * 2)
    else
      @line_count = @sorted_titles.length
      @selected = @line_count
    end
    draw_page
  when :same_page
    @line_count -= @page_length
    draw_page
  end
end

def run
  key = KeyboardEvents.new
  #  post = @last_post
  loop do
    case key.input
    when :list
      @line_count = 0
      @selected = 0
      display_list :draw_page
    when :page_forward
      @selected = @line_count
      display_list :draw_page
    when :previous
      @selected -= 1 if @selected > 0
      if @selected >= @line_count - @page_length
        display_list :same_page
      else
        display_list :previous_page
      end
    when :next
      @selected += 1
      if @selected <= @line_count - 1
        display_list :same_page
      else
        display_list :draw_page
      end
    when :play
      puts "@selected = #{@selected}"
      puts "title = #{@sorted_titles[@selected]}"
      puts "title = #{@sorted_titles[@selected]}"
      title = @sorted_titles[@selected]
      pr = select_program title
      puts pr[:title]
      run_program pr
    when :first
    #      post = @first_post
    when :last
    #      post = @last_post
    when :last
    #      post = @last_post
    when :update
    #      update_posts()
    #      post = @last_post
    when :back_ten
    #      post = (post - 10) <= @first_post ? @first_post : post - 10
    when :forward_ten
    #      post = (post + 10) >= @last_post ? @last_post : post + 10
    when :back_one_hundred
    #      post = (post - 100) <= @first_post ? @first_post : post - 100
    when :forward_one_hundred
    #      post = (post + 100) >= @last_post ? @last_post : post + 100
    when :spacebar
    #      unless draw_page
    #        post = post >= @last_post ? @last_post : post + 1
    when :help
    #      help_page()
    when :quit
      exit 0
    else
    end
    sleep 0.001
  end
end

check_remote
parse_programs
reload_database
sort_titles
run
puts "Done."

exit

#@dates, @titles = [], []

# check for local copies

#puts @collection.find( { have_local: true} ).first
#exit

#@titles.sort!
#puts "titles unique? " + (@titles.uniq.length == @titles.length).to_s
##@titles = @titles.uniq
#
#
#puts "titles unique? " + (@titles.uniq.length == @titles.length).to_s
#puts @titles.length.to_s + " titles"
#p @titles
#@titles.map{|x| puts x}

#  @programs.each do |pr|
#  result = @collection.insert_one pr
#  p result
#end

#result = @collection.insert_many @programs
#p "Inserted #{result.inserted_count} records"

#puts @collection.find( { title: 'Dreams' } ).first

#@programs.each do |pr|
#  result = @collection.delete_many( { title: pr[:title] } )
###  p result
#end

#@programs.each do |pr|
#  @dates << Time.parse(pr[:date][0..16])
#  @titles << pr[:title]
#end

#  File.open('redirect.html','w') do |f|
#    f.write(res.body)
#  end
#  puts "Done."
#  exit
#end

#Dir["audio/*"].each do |file|
##  puts file
#  new_file = file.downcase.gsub(' ', '_')
##  puts new_file
#  File.rename( file, new_file )
#  puts "Rename from " + file + " to " + new_file
#end
#
