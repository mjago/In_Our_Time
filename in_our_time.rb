require 'rss'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'open-uri'

class InOurTime

  CHECK_REMOTE    = false
  AUDIO_DIRECTORY = 'audio'

  class KeyboardEvents

    @arrow = 0

    def input
      begin
        system("stty raw -echo")
        str = STDIN.getc
      ensure
        system("stty -raw echo")
      end

      case @arrow
      when 1
        if str == "["
          @arrow = 2
        else
          @arrow = 0
        end

      when 2
        return :previous     if str == "A"
        return :next         if str == "B"
        return :page_forward if str == "C"
        @arrow = 0
      end

      case str
      when "\e"
        @arrow = 1
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
      when 's', 'S'
        :stop
      when 'x', 'X', "\r"
        :play
      when 'i', 'I'
        :info
      when '?', 'h'
        :help
      else
        :unknown
      end
      sleep 0.05
    end
  end

  def initialize
    @programs = []
    @page_length = 20
    @line_count =  @page_length
    @selected = 0
    @playing = nil
    @play = nil
    @help = nil

    check_remote
    parse_programs
    sort_titles
    run
  end

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
      return true
    end
    false
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
    @play = Thread.new do
      @playing = prg[:title]
      system "afplay #{filename_from_title(@playing)}"
      @playing = nil
    end
  end

#  @programs.each do |pr|
#    url = pr[:link]
#    unless pr[:have_locally] && false
#      5.times do
#        res = Net::HTTP.get_response(URI.parse(url))
#        case res
#        when Net::HTTPFound
#          puts "fetching #{pr[:title]}"
#          puts 'redirecting...'
#          @doc = Nokogiri::XML(res.body)
#          redirect = @doc.css("body p a").text
#          exit if download_audio(pr, redirect)
#          sleep 2
#        else
#          puts 'Error! Expected to be redirected!'
#          exit 1
#        end
#      end
#      puts "Max retries downloading #{pr[:title]}"
#    end
#  end

  def print_playing_maybe
    puts
    if @playing
      puts "Playing '#{@playing}'"
    else
      puts
    end
  end

  def kill_audio
    if @playing
      system 'killall afplay' if @play
      @play.kill if @play
      @playing = nil
    end
  end

  def draw_page
    if @line_count <= @sorted_titles.length
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
    print_playing_maybe
  end

  def display_list action
    system 'clear'
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

  def help
    unless @help
      system 'clear'
      puts
      puts "    In Our Time Player       "
      puts
      puts " next      - N (down arrow)  "
      puts " previous  - P (up arrow)    "
      puts " next page -   (right arrow) "
      puts " next page -   (space)       "
      puts " play      - X (return)      "
      puts " stop      - S               "
      puts " list      - L               "
      puts " help      - H               "
      puts " quit      - Q               "
      12.upto(@page_length - 1) do
        puts
      end
      print_playing_maybe
      @help = true
    else
      display_list :same_page
      @help = nil
    end
  end

  def info
    if @info.nil?
      system 'clear'
      puts
      prg = select_program @sorted_titles[@selected]
      puts prg[:subtitle].gsub("\n", ' ').gsub('  ', ' ')
      puts
      puts "Date Broadcast: #{prg[:date][0..16]}"
      puts "Duration:       #{prg[:duration].to_i/60} mins"
      puts "Availability:   " + (prg[:have_locally] ? "Downloaded" : "Requires Download")
      @info = 1
    elsif @info == 1
      system 'clear'
      puts
      prg = select_program @sorted_titles[@selected]
      puts prg[:summary].gsub("\n", ' ').gsub('  ', ' ')
      @info = -1
    else
      display_list :same_page
      @info = nil
    end
  end

  def run
    display_list :same_page
    key = KeyboardEvents.new
    loop do

      ip = key.input

      @info = nil unless ip == :info
      @help = nil unless ip == :help

      case ip
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
        kill_audio
        title = @sorted_titles[@selected]
        pr = select_program title
        run_program pr
        display_list :same_page
      when :stop
        kill_audio
      when :info
        info
      when :help
        help
      when :quit
        kill_audio
        exit 0
      end
      sleep 0.001
    end
  end
end

InOurTime.new if __FILE__ == $0
