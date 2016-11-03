require 'rss'
require 'open-uri'
require 'net/http'
require 'open-uri'
require 'yaml'
require 'fileutils'
require 'colorize'
require 'oga'
require 'pty'
require 'io/console'

class InOurTime

  ROOT            = File.expand_path '~/'
  HERE            = File.dirname(__FILE__)
  CONFIG_DIR      = '.in_our_time'
  CONFIG_NAME     = 'config.yml'
  IN_OUR_TIME     = File.join ROOT, CONFIG_DIR
  VERSION         = File.join HERE, '..','..','VERSION'
  DEFAULT_CONFIG  = File.join HERE, '..','..',CONFIG_NAME
  CONFIG          = File.join IN_OUR_TIME,CONFIG_NAME
  UPDATE_INTERVAL = 604800
  AUDIO_DIRECTORY = 'audio'
  RSS_DIRECTORY   = 'rss'
  PAGE_HEIGHT     = 20
  PAGE_WIDTH      = 80

  class KeyboardEvents

    def initialize
      @mode = :normal
      @event = :no_event
      run
    end

    def reset
      STDIN.flush
    end

    def ke_events
      sleep 0.001
    end

    def read
      ret_val = @event
    #  reset
      @event = :no_event
      ret_val
    end

    def run
      Thread.new do
        loop do
          str = ''
          loop do
            str = STDIN.getch
            if str == "\e"
              @mode = :escape
            else
              case @mode
              when :escape
                @mode =
                  str == "[" ? :escape_2 : :normal
              when :escape_2
                @event = :previous     if str == "A"
                @event = :next         if str == "B"
                @event = :page_forward if str == "C"
                @event = :previous     if str == "D"
                @mode  = :normal

              else
                break if @event == :no_event
              end
            end
            ke_events
          end
          match_event str
          ke_events
        end
      end
    end

    def match_event str
      case str
      when "\e"
        @mode = :escape
      when "l",'L'
        @event = :list
      when "u",'U'
        @event = :update
      when ' '
        @event = :page_forward
      when "q",'Q', "\u0003", "\u0004"
        @event = :quit
      when 'p', 'P'
        @event = :pause
      when 'f', 'F'
        @event = :forward
      when 'r', 'R'
        @event = :rewind
      when 's', 'S'
        @event = :sort
      when 'x', 'X', "\r"
        @event = :play
      when 'i', 'I'
        @event = :info
      when '?', 'h'
        @event = :help
      else
        @event = :no_event
      end
    end
  end

  class Tic
    def initialize
      @flag = false
      run
    end

    def run
      Thread.new do
        loop do
          sleep 1
          @flag = true
        end
      end
    end

    def toc
      ret_val = @flag
      @flag = false
      ret_val
    end
  end

  def initialize
    @programs = []
    @selected = 0
    setup
    load_config
    load_version
    load_help_maybe
    display_version
    check_remote
    parse_rss
    sort_titles
    version_display_wait
    run
  end

  def do_events
    sleep 0.003
    sleep 0.1
  end

  def quit code = 0
    system("stty -raw echo")
    exit code
  end

  def version_display_wait
    do_events while Time.now - @start_time < 1
  end

  def iot_print x, col = @text_colour
    STDOUT.print x.colorize col if @config[:colour]
    STDOUT.print x          unless @config[:colour]
  end

  def iot_puts x = '', col = @text_colour
    iot_print x, col
    iot_print "\n\r"
  end

  def now
    Time.now.to_i
  end

  def setup
    @start_time = Time.now
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

  def display_version
    clear
    iot_print("Loading ", @system_colour) unless ARGV[0] == '-v' || ARGV[0] == '--version'
    iot_puts "In Our Time Player (#{@version})", @system_colour
    quit if ARGV[0] == '-v' || ARGV[0] == '--version'
  end

  def load_version
    File.open(VERSION) {|f| @version = f.readline.strip}
  end

  def update_remote?
    now - @config[:update_interval] > @config[:last_update]
  end

  def create_config
    @config = YAML::load_file(DEFAULT_CONFIG)
    save_config
  end

  def do_configs
    theme = @config[:colour_theme]
    @selection_colour = @config[theme][:selection_colour]
    @count_sel_colour = @config[theme][:count_sel_colour]
    @count_colour     = @config[theme][:count_colour]
    @text_colour      = @config[theme][:text_colour]
    @system_colour    = @config[theme][:system_colour]
    rows, cols = $stdout.winsize
    while(rows % 10 != 0) ; rows -=1 ; end
    while(cols % 10 != 0) ; cols -=1 ; end
    rows = 10 if rows < 10
    cols = 20 if cols < 20
    @config[:page_height] = rows if(@config[:page_height] == :auto)
    @config[:page_width]  = cols if(@config[:page_width]  == :auto)
    @line_count = @config[:page_height]
    @sort = @config[:sort]
  end

  def load_config
    create_config unless File.exist? CONFIG
    @config = YAML::load_file(CONFIG)
    do_configs
  end

  def save_config
    File.open(CONFIG, 'w') { |f| f.write @config.to_yaml}
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
    File.join IN_OUR_TIME, AUDIO_DIRECTORY, temp.downcase
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
      iot_puts 'Download failed. Retrying...', @system_colour
    end
  end

  def have_locally? title
    filename = filename_from_title(title)
    File.exists?(filename) ? true : false
  end

  def rss_files
    local_rss.map{|f| File.join IN_OUR_TIME, RSS_DIRECTORY, f }
  end

  def update
    clear
    iot_print "Checking rss feeds ", @system_colour
    local_rss.length.times do |count|
      iot_print '.', @system_colour
      fetch_uri rss_addresses[count], rss_files[count]
    end
    iot_puts
    @config[:last_update] = now
    save_config
  end

  def check_remote
    update if update_remote?
  end

  def uniquify_programs
    @programs = @programs.uniq{|pr| pr[:title]}
    unless @programs.uniq.length == @programs.length
      print_error_and_delay "Error ensuring Programs unique!"
      quit 1
    end
  end

  def parse_rss
    rss_files.each do |file|
      @doc = Oga.parse_xml(File.open(file))
      titles    = @doc.xpath('rss/channel/item/title')
      subtitles = @doc.xpath('rss/channel/item/itunes:subtitle')
      summarys  = @doc.xpath('rss/channel/item/itunes:summary')
      durations = @doc.xpath('rss/channel/item/itunes:duration')
      dates     = @doc.xpath('rss/channel/item/pubDate')
      links     = @doc.xpath('rss/channel/item/link')

      0.upto (titles.length - 1) do |idx|
        program = {}
        program[:title] = titles[idx].text
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
    @programs.map{|pr| return pr if(pr[:title].strip == title.strip)}
    nil
  end

  def sort_titles
    @sorted_titles = []
    @sorted_titles = @programs.collect { |pr| pr[:title] }
    @sorted_titles.sort! unless @sort == :age
  end

  def sort_selected title
    @sorted_titles.each_with_index do |st, idx|
      if st == title
        selected = idx
        idx += 1
        while idx % @config[:page_height] != 0
          idx += 1
        end
        return selected, idx
      end
    end
  end

  def sort
    title = @sorted_titles[@selected]
    @sort = @sort == :age ? :alphabet : :age
    sort_titles
    @selected, @line_count = sort_selected(title)
    redraw
  end

  def redraw
    display_list :same_page
  end

  def date
    @programs.map {|pr| return pr[:date] if pr[:title] == @playing}
  end

  def pre_delay
    x = DateTime.strptime("Mon, 20 Jun 2016", '%a, %d %b %Y')
    y = DateTime.strptime(date, '%a, %d %b %Y')
    if y < x
      return '410' unless @playing == 'Abelard and Heloise'
      '0' if @playing == 'Abelard and Heloise'
    else
      '435'
    end
  end

  def player_cmd
    case @config[:mpg_player]
    when :mpg123
      "mpg123 --remote-err -Cqk#{pre_delay}"
    else
      "afplay"
    end
  end

  def clear
    system 'clear' or system 'cls'
  end

  def print_error_and_delay message
    iot_puts message, :red
    sleep 2
  end

  def run_program prg
    unless prg[:have_locally]
      retries = 0
      clear
      iot_puts "Fetching #{prg[:title]}", @system_colour
      10.times do
        begin
          res = Net::HTTP.get_response(URI.parse(prg[:link]))
        rescue SocketError => e
          print_error_and_delay "Error: Failed to connect to Internet! (#{e.class})"
          @no_play = true
          break
        end
        case res
        when Net::HTTPFound
          iot_puts 'redirecting...', @system_colour
          @doc = Oga.parse_xml(res.body)
          redirect = @doc.css("body p a").text
          break if download_audio(prg, redirect)
          sleep 2
        else
          print_error_and_delay 'Error! Failed to be redirected!'
          @no_play = true
          break
        end
        retries += 1
      end
      if retries >= 10
        print_error_and_delay "Max retries downloading #{prg[:title]}"
        @no_play = true
      end
    end
    unless @no_play
      @playing = prg[:title]
      window_title prg[:title]
      @cmd = player_cmd + ' ' + filename_from_title(@playing)
      @messages = []
      @p_out, @p_in, @pid = PTY.spawn(@cmd)
    end
    @no_play = nil
  end

  def window_title title = ''
    STDOUT.puts "\"\033]0;#{title}\007"
  end

  def reset
    @pid = nil
    @playing = nil
    @paused = nil
    window_title
    redraw
  end

  def write_player str
    begin
      @p_in.puts str
    rescue Errno::EIO
      reset
    end
  end

  def pause
    if control_play?
      @paused  = @paused ? false : true
      write_player " "
      redraw
    end
  end

  def control_play?
    @playing && (@config[:mpg_player] == :mpg123)
  end

  def forward
     write_player ":" if control_play?
  end

  def rewind
     write_player ";" if control_play?
  end

  def print_playing_maybe
    if @playing
      iot_print("Playing: ", @count_colour) unless @paused
      iot_print("Paused: ", @count_colour) if @paused
      iot_puts @playing, @selection_colour
    elsif @started.nil?
      @started = true
      iot_print "? or h for instructions", @text_colour
      iot_print "", :white
    end
  end

  def kill_audio
    if @playing
      @playing = nil
      if @pid.is_a? Fixnum
        Process.kill('QUIT', @pid)
        sleep 0.2
        reset
      end
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
          iot_puts @sorted_titles[idx], @text_colour   unless(idx == @selected)
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
    clear
    case action
    when :next_page
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

  def load_help_maybe
    if ARGV[0] == '-h' || ARGV[0] == '--help' || ARGV[0] == '-?'
      help
      quit
    end
  end

  def help_screen
    []                                     <<
      " In Our Time Player (#{@version})"  <<
      "                                 "  <<
      " Play/Stop     - X or Enter      "  <<
      " Previous/Next - Down / Up       "  <<
      " Next Page     - SPACE           "  <<
      " Sort          - S               "  <<
      " List Top      - L               "  <<
      " Update        - U               "  <<
      " Info          - I               "  <<
      " Help          - H               "  <<
      " Quit          - Q               "  <<
      "                                 "  <<
      " mpg123 Controls:                "  <<
      "  Pause/Resume - P               "  <<
      "  Forward Skip - F               "  <<
      "  Reverse Skip - R               "  <<
      "                                 "  <<
      "Config: #{CONFIG}                "
  end

  def print_help
    iot_puts help_screen.map{|x|x.rstrip}.join("\n\r"), @system_colour
  end

  def help
    unless @help
      clear
      print_help
      print_playing_maybe
      @help = true
    else
      redraw
      @help = nil
    end
  end

  def reformat info
    ['With','Guests','Producer','Contributors'].map do | x|
      [' ', ':'].map do |y|
        [x, x.upcase].map do |z|
          info.gsub!(z + y, "\n" + z + y)
        end
      end
    end
    info
  end

  def top_space info
    info.length - info.lstrip.length
  end

  def bottom_space? bottom
    bottom == ' '
  end

  def last_line? info, top
    info[top..-1].length < @config[:page_width]
  end

  def justify info
    pages = [[],[]]
    page = 0
    top = 0
    bottom = @config[:page_width]
    loop do
      shift = top_space info[top..bottom]
      top = top + shift
      bottom = bottom + shift
      loop do
        if idx = info[top..bottom].index("\n")
          pages[page] << info[top..top + idx]
          page = 1
          bottom = top + idx + @config[:page_width] + 1
          top = top + idx + 1
        else
          break if bottom_space? info[bottom]
          bottom -= 1
        end
      end
      if last_line? info, top
        pages[page] << info[top..-1].strip
        break
      end
      pages[page] << info[top..bottom]
      bottom = bottom + @config[:page_width]
      top = bottom
    end
    pages
  end

  def print_subtitle prg
    clear
    justify(prg[:subtitle].gsub(/\s+/, ' '))[0].map{|x| iot_puts x}
    print_program_details prg
    @info = 1
    @page_count = 1
  end

  def print_program_details prg
    iot_puts "\nDate Broadcast: #{prg[:date]}"
    iot_puts "Duration:       #{prg[:duration].to_i/60} mins"
    iot_puts "Availability:   " +
             (prg[:have_locally] ? "Downloaded" : "Requires Download")
  end

  def print_info prg
    info = prg[:summary].gsub(/\s+/, ' ')
    clear
    count = 1
    justify(reformat(info))[0].each do |x|
      if (count > (@page_count - 1) * @config[:page_height]) &&
         (count <= @page_count * @config[:page_height])
        iot_puts x
      end
      count += 1
    end
    if count <= @page_count * @config[:page_height] + 1
      @info = justify(reformat(info))[1] == [] ? -1 : 2
    else
      @page_count += 1
    end
  end

  def print_guests prg
    info = prg[:summary].gsub(/\s+/, ' ')
    clear
    justify(reformat(info))[1].map{|x| iot_puts x}
    @info = -1
  end

  def info
    case @info
    when nil
      prg = select_program @sorted_titles[@selected]
      print_subtitle prg
    when 1
      prg = select_program @sorted_titles[@selected]
      print_info prg
    when 2
      prg = select_program @sorted_titles[@selected]
      print_guests prg
    else
      redraw
      @info = nil
    end
  end

  def check_process
    if(@playing && @pid.is_a?(Fixnum))
      begin
        write_player( "\e")
        if @pid.is_a? Fixnum
          Process.kill 0, @pid
        end
      rescue Errno::ESRCH
        reset
      end
    else
      @pid = nil
    end
  end

  def do_action ip
    case ip
    when :pause, :forward, :rewind
      self.send ip
    when :list
      @line_count = 0
      @selected = 0
      display_list :next_page
    when :page_forward
      @selected = @line_count
      display_list :next_page
    when :previous
      @selected -= 1 if @selected > 0
      if @selected >= @line_count -
         @config[:page_height]
        redraw
      else
        display_list :previous_page
      end
    when :next
      @selected += 1
      if @selected <= @line_count - 1
        redraw
      else
        display_list :next_page
      end
    when :play
      if @playing
        kill_audio
      else
        kill_audio
        title = @sorted_titles[@selected]
        pr = select_program title
        run_program pr
        redraw
      end
    when :sort
      sort
    when :update
      update
      parse_rss
      sort_titles
      @line_count = 0
      @selected = 0
      display_list :next_page
    when :info
      info
    when :help
      help
    when :quit
      kill_audio
      quit
    end
  end

  def reset_info_maybe ip
    @info = nil unless ip == :info
    @help = nil unless ip == :help
  end

  def run
    ip = ''
    action = :unknown
    @tic = Tic.new
    @key = KeyboardEvents.new
    redraw

    loop do
      @key.reset
      loop do
        ip = @key.read
        break unless ip == :no_event
        check_process if @tic.toc
        do_events
      end
      reset_info_maybe ip
      do_action ip
      do_events
    end
  end
end

InOurTime.new if __FILE__ == $0
