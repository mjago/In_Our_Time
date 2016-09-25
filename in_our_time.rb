require 'rss'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'open-uri'

class InOurTime
  CHECK_REMOTE    = false
  AUDIO_DIRECTORY = 'audio'
  PAGE_LENGTH     = 20
  PAGE_WIDTH      = 80

  class KeyboardEvents

    @arrow = 0

    def input
      sleep 0.001
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
        return :previous     if str == "D"
        @arrow = 0
      end

      case str
      when "\e"
        @arrow = 1
      when "l",'L'
        :list
      when ' '
        :page_forward
      when "q",'Q', "\u0003", "\u0004"
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
    end
  end

  def initialize
    @programs, @selected = [], 0
    @line_count = PAGE_LENGTH
    check_remote
    parse_programs
    sort_titles
    run
  end

  def rss_addresses
    host = 'http://www.bbc.co.uk/programmes'
    [ "/b006qykl/episodes/downloads.rss",
      "/p01drwny/episodes/downloads.rss",
      "/p01dh5yg/episodes/downloads.rss",
      "/p01f0vzr/episodes/downloads.rss",
      "/p01gvqlg/episodes/downloads.rss",
      "/p01gyd7j/episodes/downloads.rss"
    ].collect{|page| host + page}
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
      puts 'audio download from redirect failed. Retrying...'
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
        puts "checking rss #{count}"
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
    elsif @started.nil?
      @started = true
      puts "? or h for instructions"
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
      @line_count.upto(@line_count + PAGE_LENGTH - 1) do |idx|
        if idx < @sorted_titles.length
          print "> " if(idx == @selected)
          print "#{idx + 1}. "
          puts @sorted_titles[idx]
        end
      end
    else
      @line_count = 0
      0.upto(PAGE_LENGTH - 1) do |idx|
        print "> " if(idx == @selected)
        print "#{idx + 1}. "     unless @sorted_titles[idx].nil?
        puts @sorted_titles[idx] unless @sorted_titles[idx].nil?
      end
    end
    @line_count += PAGE_LENGTH
    print_playing_maybe
  end

  def display_list action
    system 'clear'
    case action
    when :draw_page
      draw_page
    when :previous_page
      if @line_count > 0
        @line_count -= (PAGE_LENGTH * 2)
      else
        @line_count = @sorted_titles.length
        @selected = @line_count
      end
      draw_page
    when :same_page
      @line_count -= PAGE_LENGTH
      draw_page
    end
  end

  def help
    unless @help
      system 'clear'
      puts
      puts " In Our Time Player (Help)   "
      puts
      puts " Next      - N (down arrow)  "
      puts " Previous  - P (up arrow)    "
      puts " Next Page -   (right arrow) "
      puts " Next Page -   (space)       "
      puts " Play      - X (return)      "
      puts " Stop      - S               "
      puts " List      - L               "
      puts " Info      - I               "
      puts " Help      - H               "
      puts " Quit      - Q               "
      puts
      puts " tl;dr:                      "
      puts
      puts "  Select: up/down arrows     "
      puts "  Play:   enter              "
      18.upto(PAGE_LENGTH - 1) {puts}
      print_playing_maybe
      @help = true
    else
      display_list :same_page
      @help = nil
    end
  end

  def reformat info
    info.gsub('With ', "\nWith ")
      .gsub('With: ', "\nWith: ")
      .gsub('Producer', "- Producer")
  end

  def justify info
    collect, top, bottom = [], 0, PAGE_WIDTH
    loop do
      if(bottom >= info.length)
        collect << info[top..-1].strip
        break
      end
      loop do
        break unless info[top] == ' '
        top += 1 ; bottom += 1
      end
      loop do
        if idx = info[top..bottom].index("\n")
          collect << info[top..top + idx]
          bottom, top = top + idx + PAGE_WIDTH + 1, top + idx + 1
          next
        else
          break if (info[bottom] == ' ')
          bottom -= 1
        end
      end
      collect << info[top..bottom]
      bottom, top = bottom + PAGE_WIDTH, bottom
    end
    collect
  end

  def info
    if @info.nil?
      system 'clear'
      puts
      prg = select_program @sorted_titles[@selected]
      puts justify(prg[:subtitle].gsub(/\s+/, ' '))
      puts
      puts "Date Broadcast: #{prg[:date][0..16]}"
      puts "Duration:       #{prg[:duration].to_i/60} mins"
      puts "Availability:   " + (prg[:have_locally] ? "Downloaded" : "Requires Download")
      @info = 1
    elsif @info == 1
      system 'clear'
      puts
      prg = select_program @sorted_titles[@selected]
      info = prg[:summary].gsub(/\s+/, ' ')
      puts justify(reformat(info))
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
        if @selected >= @line_count - PAGE_LENGTH
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
