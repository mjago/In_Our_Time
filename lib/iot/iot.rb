require 'nokogiri'
require 'rss'
require 'open-uri'
require 'net/http'
require 'open-uri'
require 'yaml'
require 'fileutils'
require 'colorize'

class InOurTime

  ROOT            = File.expand_path '~/'
  IN_OUR_TIME     = File.join ROOT, '.in_our_time'
  CONFIG          = File.join IN_OUR_TIME, 'config.yml'
  UPDATE_INTERVAL = 604800
  AUDIO_DIRECTORY = 'audio'
  RSS_DIRECTORY   = 'rss'
  PAGE_HEIGHT     = 20
  PAGE_WIDTH      = 80

  class KeyboardEvents

    @arrow = 0

    def reset
      $stdin.flush
    end

    def input
      begin
        system("stty raw -echo")
        str = $stdin.getc
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
    setup
    load_config
    check_remote
    parse_rss
    sort_titles
    run
  end

  def iot_print x, col = @text_colour
    print x.colorize col if @config[:colour]
    print x          unless @config[:colour]
  end

  def iot_puts x, col = @text_colour
    puts x.colorize col if @config[:colour]
    puts x          unless @config[:colour]
  end

  def now
    Time.now.to_i
  end

  def setup
    iot = IN_OUR_TIME
    audio = File.join iot, AUDIO_DIRECTORY
    pages = File.join iot, RSS_DIRECTORY
    Dir.mkdir iot unless Dir.exist? iot
    Dir.mkdir audio unless Dir.exist? audio
    unless Dir.exist? pages
      Dir.mkdir pages
      local_rss.map{|f| FileUtils.touch(File.join pages, f)}
    end
  end

  def update_remote?
    now - @config[:update_interval] > @config[:last_update]
  end

  def new_config
    {:last_update => now - UPDATE_INTERVAL - 1,
     :update_interval => UPDATE_INTERVAL,
     :colour => true,
     :mpg_player => :afplay,
     :sort => :age,
     :show_count => true,
     :page_height => PAGE_HEIGHT,
     :page_width  => PAGE_WIDTH,
     :colour_theme => :light_theme,
     :light_theme => {
       :selection_colour =>  {:colour => :magenta, :background => :light_white},
       :count_sel_colour =>  {:colour => :cyan, :background => :light_white},
       :count_colour => :yellow,
       :text_colour => :default,
       :system_colour => :yellow
     },
     :dark_theme => {
       :selection_colour => {:colour => :light_yellow, :background => :light_black},
       :count_sel_colour => {:colur => :blue, :background => :yellow},
       :count_colour => :yellow,
       :text_colour => :default,
       :system_colour => :yellow
     }
    }
  end

  def load_config
    unless File.exist? CONFIG
      save_config new_config
    end
    @config = YAML::load_file(CONFIG)
    @line_count = @config[:page_height]
    theme = @config[:colour_theme]
    @selection_colour = @config[theme][:selection_colour]
    @count_sel_colour = @config[theme][:count_sel_colour]
    @count_colour     = @config[theme][:count_colour]
    @text_colour      = @config[theme][:text_colour]
    @system_colour    = @config[theme][:system_colour]
  end

  def save_config cfg = @config
    File.open(CONFIG, 'w') { |f| f.write cfg.to_yaml}
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
      "culture.rss",
      "history.rss",
      "in_our_time.rss",
      "philosophy.rss",
      "religion.rss",
      "science.rss"
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
    File.join(File.join IN_OUR_TIME, AUDIO_DIRECTORY, temp.downcase)
  end

  def download_audio program, addr
    res = Net::HTTP.get_response(URI.parse(addr))
    case res
    when Net::HTTPOK
      File.open(filename_from_title(program[:title]) , 'wb') do |f|
        iot_print "writing #{filename_from_title(program[:title])}...", @system_colour
        f.print(res.body)
        iot_puts " written.", @system_colour
      end
      program[:have_locally] = true
    else
      iot_puts 'audio download failed. Retrying...', @system_colour
    end
  end

  def have_locally? title
    filename = filename_from_title(title)
    if File.exists?(filename)
      return true
    end
    false
  end

  def rss_files
    local_rss.map{|f| File.join IN_OUR_TIME, RSS_DIRECTORY, f }
  end

  def check_remote
    if update_remote?
      iot_print "checking rss feeds ", @system_colour
      local_rss.length.times do |count|
        iot_print '.', @system_colour
        fetch_uri rss_addresses[count], rss_files[count]
      end
      iot_puts ''
      @config[:last_update] = now
      save_config
    end
  end

  def uniquify_programs
    @programs = @programs.uniq{|pr| pr[:title]}
    unless @programs.uniq.length == @programs.length
      iot_puts "Error ensuring Programs unique!", :red
      exit 1
    end
  end

  def parse_rss
    rss_files.each do |file|
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
        program[:date] = (dates[idx].text)[0..15]
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
    @sorted_titles = @programs.collect { |pr| pr[:title] }
#    @sorted_titles = @sorted_titles.uniq{|x| x.downcase}
    @sorted_titles = @sorted_titles.sort unless @config[:sort] == :age
  end

  def date
    @programs.map {|pr| return pr[:date] if pr[:title] == @playing}
  end

  def pre_delay
    x = DateTime.strptime("Mon, 20 Jun 2016", '%a, %d %b %Y')
    y = DateTime.strptime(date, '%a, %d %b %Y')
    y < x ? '410' : '435'
  end

  def player_cmd
    case @config[:mpg_player]
    when :mpg123
      "mpg123 -qk#{pre_delay}"
    else
      "afplay"
    end
  end

  def kill_cmd
    "killall " +
      case @config[:mpg_player]
      when :mpg123
        "mpg123"
      else
        "afplay"
      end
  end

  def run_program prg
    unless prg[:have_locally]
      retries = 0
      iot_puts "fetching #{prg[:title]}", @system_colour
      10.times do
        res = Net::HTTP.get_response(URI.parse(prg[:link]))
        case res
        when Net::HTTPFound
          iot_puts 'redirecting...', @system_colour
          @doc = Nokogiri::XML(res.body)
          redirect = @doc.css("body p a").text
          break if download_audio(prg, redirect)
          sleep 2
        else
          iot_puts 'Error! Expected to be redirected!', :red
          exit 1
        end
        retries += 1
      end
      if retries >= 10
        iot_puts "Max retries downloading #{prg[:title]}", :red
        exit 1
      end
    end
    @play = Thread.new do
      @playing = prg[:title]
      system player_cmd + ' ' +
             filename_from_title(@playing)
      @playing = nil
    end
  end

  def print_playing_maybe
    iot_puts ''
    if @playing
      iot_puts "Playing '#{@playing}'", @selection_colour
    elsif @started.nil?
      @started = true
      iot_puts "? or h for instructions", @text_colour
    else
      iot_puts ''
    end
  end

  def kill_audio
    if @playing
      system kill_cmd if @play
      @play.kill if @play
      @playing = nil
    end
  end

  def idx_format idx
    sprintf("%03d", idx + 1)
  end

  def show_count_maybe idx
    if have_locally?(@sorted_titles[idx])
      iot_print idx_format(idx), @count_sel_colour  if @config[:show_count]
    else
      iot_print idx_format(idx), @count_colour if @config[:show_count]
    end
    iot_print ' '
  end

  def draw_page
    if @line_count <= @sorted_titles.length
      @line_count.upto(@line_count + @config[:page_height] - 1) do |idx|
        if idx < @sorted_titles.length
          iot_print "> " if(idx == @selected) unless @config[:colour]
          show_count_maybe idx
          iot_puts @sorted_titles[idx], @selection_colour if (idx == @selected)
          iot_puts @sorted_titles[idx], @text_colour         unless(idx == @selected)
        end
      end
    else
      @line_count = 0
      0.upto(@config[:page_height] - 1) do |idx|
        iot_print "> ", @selection_colour if(idx == @selected)
        show_count_maybe(idx) unless @sorted_titles[idx].nil?
        iot_puts @sorted_titles[idx], @text_colour unless @sorted_titles[idx].nil?
      end
    end
    @line_count += @config[:page_height]
    print_playing_maybe
  end

  def display_list action
    system 'clear'
    case action
    when :draw_page
      draw_page
    when :previous_page
      if @line_count > 0
        @line_count -= (@config[:page_height] * 2)
      else
        @line_count = @sorted_titles.length
        @selected = @line_count
      end
      draw_page
    when :same_page
      @line_count -= @config[:page_height]
      draw_page
    end
  end

  def help
    unless @help
      system 'clear'
      iot_puts " In Our Time Player (Help)       "
      iot_puts "                                 "
      iot_puts " Next      - N (down arrow)      "
      iot_puts " Previous  - P (up arrow)        "
      iot_puts " Next Page -    (SPACE)          "
      iot_puts " Play      - X (return)          "
      iot_puts " Stop      - S                   "
      iot_puts " List      - L                   "
      iot_puts " Info      - I                   "
      iot_puts " Help      - H                   "
      iot_puts " Quit      - Q                   "
      iot_puts "  TL;DR                          "
      iot_puts "Select: up/down arrows           "
      iot_puts "Play:   enter                    "
      iot_puts "Config: ~/.in_our_time/config.yml"
      18.upto(@config[:page_height] - 1) {iot_puts ''}
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
    pages = [[],[]]
    page, top, bottom = 0, 0, @config[:page_width]
    loop do
      if(bottom >= info.length)
        pages[page] << info[top..-1].strip
        break
      end
      loop do
        break unless info[top] == ' '
        top += 1 ; bottom += 1
      end
      loop do
        if idx = info[top..bottom].index("\n")
          pages[page] << info[top..top + idx]
          page,bottom,top = 1,top + idx + @config[:page_width] + 1, top + idx + 1
          next
        else
          break if (info[bottom] == ' ')
          bottom -= 1
        end
      end
      pages[page] << info[top..bottom]
      bottom, top = bottom + @config[:page_width], bottom
    end
    pages
  end

  def info
    if @info.nil?
      prg = select_program @sorted_titles[@selected]
      system 'clear'
      iot_puts ''
      justify(prg[:subtitle].gsub(/\s+/, ' '))[0].map{|x| iot_puts x}
      iot_puts ''
      iot_puts "Date Broadcast: #{prg[:date]}"
      iot_puts "Duration:       #{prg[:duration].to_i/60} mins"
      iot_puts "Availability:   " +
               (prg[:have_locally] ? "Downloaded" : "Requires Download")
      @info = 1
    elsif @info == 1
      prg = select_program @sorted_titles[@selected]
      info = prg[:summary].gsub(/\s+/, ' ')
      system 'clear'
      iot_puts ''
      justify(reformat(info))[0].map{|x| iot_puts x}
      @info = 2
    elsif @info == 2
      prg = select_program @sorted_titles[@selected]
      info = prg[:summary].gsub(/\s+/, ' ')
      system 'clear'
      iot_puts ''
      justify(reformat(info))[1].map{|x| iot_puts x}
      @info = -1
    else
      display_list :same_page
      @info = nil
    end
  end

  def run
    action = :unknown
    display_list :same_page
    key = KeyboardEvents.new
    loop do
      unless action == :unknown
        key.reset
      end

      ip = key.input
      @info = nil unless ip == :info
      @help = nil unless ip == :help

      action =
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
          if @selected >= @line_count -
             @config[:page_height]
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
    end
  end
end

InOurTime.new if __FILE__ == $0
